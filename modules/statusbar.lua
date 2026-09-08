-- Bottom status bar: CPU / memory / network rate / disk / battery.
--
-- ── WHY THE METRICS ARE COLLECTED THE WAY THEY ARE ───────────────────────────
-- This module used to shell out to `top -l 1` for the CPU figure. Measured, that
-- one command costs 196ms of CPU, and at a 5s refresh that is 4.2% of a core
-- burned continuously, 24/7 -- an order of magnitude more than anything else in
-- this config. Worse, it was also WRONG: `top -l 1` reports its single sample
-- over a window that includes top's own startup, so the cost of measuring got
-- counted as load. Three consecutive runs read 16.2% / 20.2% / 21.6% while
-- `top -l 2` (second sample) and a ps-based diff both said ~8%. The bar was
-- displaying roughly double the real number.
--
-- CPU and memory now come from hs.host, in-process, with no fork and no
-- blocking. The remaining shell call is only what hs has no API for: interface
-- byte counters (hs.network exposes configuration, not traffic) and df. Measured
-- 208.8ms -> 9.1ms per refresh, i.e. 4.18% -> 0.18% of one core.
--
-- ── PAUSE MODEL ──────────────────────────────────────────────────────────────
-- Follows modules/wallpaper/init.lua's pauseReasons set rather than a boolean,
-- for the reason documented there: a flag accumulated from paired enter/exit
-- events desynchronises the first time macOS drops half of a pair. All
-- sleep-ish events share ONE key that any wake event clears.
--
-- There is deliberately NO idle pause here, unlike countdown_chyron. For a
-- status bar "no input for a while" does not mean "not being looked at" --
-- watching a video is idle, and the network rate is exactly what someone would
-- be watching it for.

local M = {}

local barCanvas = nil
local refreshTimer = nil
-- Mouse dodge: hide the bar while the cursor is over it, restore once it leaves.
local mouseWatcher = nil
local screenWatcher = nil
local caffeinateWatcher = nil
local barFrame = nil
local hiddenByMouse = false
-- Network counters are cumulative; we cache the previous sample to derive a rate.
local prevRx, prevTx, prevTime = nil, nil, nil
-- CPU ticks are cumulative since boot; same deal, cache and difference them.
local prevCpuActive, prevCpuIdle = nil, nil
local pauseReasons = {}

-- Status Bar Configuration (Bottom, full width, floating)
local BAR_HEIGHT = 20
local FONT_SIZE = 14
local BACKGROUND_ALPHA = 0.55
local REFRESH_INTERVAL = 5
-- Gap inserted between each metric segment; widen/narrow to taste.
local SEPARATOR = "                 "

-- Only the metrics hs.host has no API for. Output: "disk|rxBytes txBytes".
--
-- df is in the SLOW variant only. Disk usage does not move at network-rate
-- speed, and running it every 5s meant three processes per refresh (df, route,
-- netstat) instead of two -- 17,280 df invocations a day to watch a number that
-- changes by a percentage point an hour at most. The fast variant leaves the
-- disk field empty, and render() then keeps showing the last reading.
local METRICS_SCRIPT_FAST = [[
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net=$(netstat -ibn -I "$iface" | awk 'NR==2 {print $7" "$10}')
printf '%s|%s\n' "" "$net"
]]

local METRICS_SCRIPT_FULL = [[
disk=$(df -k /System/Volumes/Data | awk 'NR==2 {gsub("%","",$5); print $5}')
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net=$(netstat -ibn -I "$iface" | awk 'NR==2 {print $7" "$10}')
printf '%s|%s\n' "$disk" "$net"
]]

-- Refresh the disk figure every this-many refreshes (12 x 5s = once a minute).
local DISK_EVERY = 12
local refreshCount = 0
local lastDisk = nil
local lastText = nil

local function log(fmt, ...)
    print(string.format("[statusbar] " .. fmt, ...))
end

local function isPaused()
    return next(pauseReasons) ~= nil
end

local function reasonsString()
    local keys = {}
    for k in pairs(pauseReasons) do keys[#keys + 1] = k end
    table.sort(keys)
    return #keys > 0 and table.concat(keys, ",") or "none"
end

-- System-wide CPU load as a percentage, differenced against the previous
-- refresh so it describes the whole interval rather than an instant. Returns
-- nil on the first call, when there is no baseline to difference against.
local function cpuPercent()
    local ok, ticks = pcall(hs.host.cpuUsageTicks)
    if not ok or type(ticks) ~= "table" or type(ticks.overall) ~= "table" then
        return nil
    end
    local active, idle = ticks.overall.active, ticks.overall.idle
    if type(active) ~= "number" or type(idle) ~= "number" then return nil end

    local pct = nil
    if prevCpuActive then
        local dActive = active - prevCpuActive
        local dIdle = idle - prevCpuIdle
        local total = dActive + dIdle
        -- Both deltas must be non-negative, not just dActive: on a counter
        -- reset a negative dIdle against a positive dActive still leaves
        -- total > 0 and would yield a bogus percentage above 100.
        if total > 0 and dActive >= 0 and dIdle >= 0 then
            pct = dActive / total * 100
        end
    end
    prevCpuActive, prevCpuIdle = active, idle
    return pct
end

-- Memory footprint as a percentage of physical RAM. Mirrors what `vm_stat` +
-- sysctl used to compute: active + wired + compressor-occupied pages.
-- NOTE: the compressor term is pagesUsedByVMCompressor (pages currently holding
-- compressed data), NOT pagesCompressed, which is a cumulative since-boot
-- counter and would read far above 100%.
local function memPercent()
    local ok, vm = pcall(hs.host.vmStat)
    if not ok or type(vm) ~= "table" then return nil end
    local pageSize, memSize = vm.pageSize, vm.memSize
    local active, wired = vm.pagesActive, vm.pagesWiredDown
    local compressor = vm.pagesUsedByVMCompressor
    if type(pageSize) ~= "number" or type(memSize) ~= "number" or memSize <= 0
        or type(active) ~= "number" or type(wired) ~= "number"
        or type(compressor) ~= "number" then
        log("vmStat missing an expected key; memory will read as --")
        return nil
    end
    return (active + wired + compressor) * pageSize * 100 / memSize
end

local function formatRate(bps)
    if bps >= 1024 * 1024 then return string.format("%.1fM/s", bps / 1024 / 1024) end
    if bps >= 1024 then return string.format("%.0fK/s", bps / 1024) end
    return string.format("%.0fB/s", bps)
end

local function createCanvas()
    local f = hs.screen.mainScreen():fullFrame()
    barFrame = {x = f.x, y = f.y + f.h - BAR_HEIGHT, w = f.w, h = BAR_HEIGHT}
    barCanvas = hs.canvas.new(barFrame)
    barCanvas:level(hs.canvas.windowLevels.floating)
    barCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    barCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0, alpha = BACKGROUND_ALPHA}
    }
    barCanvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFont",
        textSize = FONT_SIZE,
        textColor = {white = 1, alpha = 0.9},
        textAlignment = "center",
        frame = {x = "0%", y = "12%", w = "100%", h = "88%"}
    }
    barCanvas:show()
end

local function updateCanvasFrame()
    if not barCanvas then return end
    local f = hs.screen.mainScreen():fullFrame()
    local expectedFrame = {x = f.x, y = f.y + f.h - BAR_HEIGHT, w = f.w, h = BAR_HEIGHT}
    if not barFrame or barFrame.x ~= expectedFrame.x or barFrame.y ~= expectedFrame.y or barFrame.w ~= expectedFrame.w or barFrame.h ~= expectedFrame.h then
        barFrame = expectedFrame
        barCanvas:frame(barFrame)
    end
end

local function render(stdOut)
    -- Positional match, NOT gmatch("[^|]+"): gmatch skips empty fields, so a
    -- df that produced nothing ("|1000 2000") would slide the net counters into
    -- the disk slot and break both readings instead of just the disk one.
    local diskField, netField = stdOut:match("^([^|]*)|([^\n]*)")

    -- CPU and memory come from hs.host, not from the shell. Both can answer nil
    -- (no baseline yet, or an unexpected vmStat shape), and "--" is the honest
    -- display for that -- the old code fell back to 0, which is a real reading.
    local cpu = cpuPercent()
    local mem = memPercent()
    -- Empty on a fast refresh, which is most of them: carry the last reading
    -- rather than blanking a figure that is still true.
    local disk = tonumber(diskField) or lastDisk
    lastDisk = disk
    local rx, tx = (netField or ""):match("(%d+)%s+(%d+)")
    rx, tx = tonumber(rx), tonumber(tx)

    local now = hs.timer.secondsSinceEpoch()
    local downRate, upRate = 0, 0
    if rx and prevRx and prevTime then
        local dt = now - prevTime
        -- Guard against counter resets (interface change) producing negatives.
        if dt > 0 and rx >= prevRx and tx >= prevTx then
            downRate = (rx - prevRx) / dt
            upRate = (tx - prevTx) / dt
        end
    end
    prevRx, prevTx, prevTime = rx, tx, now

    local battery = hs.battery.percentage()
    local batText = battery and string.format("%d%%", math.floor(battery + 0.5)) or "--"
    local batPrefix = hs.battery.isCharging() and "⚡ " or ""

    local function pct(v, label)
        return v and string.format("%s %d%%", label, math.floor(v + 0.5))
            or (label .. " --")
    end

    local segments = {
        pct(cpu, "CPU"),
        pct(mem, "MEM"),
        string.format("↓ %s  ↑ %s", formatRate(downRate), formatRate(upRate)),
        pct(disk, "SSD"),
        string.format("%sBAT %s", batPrefix, batText),
    }
    local text = table.concat(segments, SEPARATOR)

    if not barCanvas then
        createCanvas()
        lastText = nil
    else
        updateCanvasFrame()
    end
    -- Assigning to a canvas element attribute invalidates the layer whether or
    -- not the value differs, so an unchanged bar was still repainting every 5s.
    if text ~= lastText then
        barCanvas[2].text = text
        lastText = text
    end
end

local function runUpdate()
    if isPaused() then return end
    refreshCount = refreshCount + 1
    local script = (refreshCount % DISK_EVERY == 1) and METRICS_SCRIPT_FULL or METRICS_SCRIPT_FAST
    hs.task.new("/bin/sh", function(_, stdOut)
        render(stdOut or "")
    end, {"-c", script}):start()
end

-- Single owner of the refresh timer, rebuilt from the pause set so no caller
-- has to reason about whether it is currently running.
local function applyTiming()
    if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
    if isPaused() then return end
    refreshTimer = hs.timer.doEvery(REFRESH_INTERVAL, runUpdate)
end

local function setReason(reason, active)
    local before = pauseReasons[reason] and true or false
    local after = active and true or false
    if before == after then return end

    pauseReasons[reason] = after or nil
    log("setReason %s=%s -> paused=%s reasons={%s}",
        reason, tostring(after), tostring(isPaused()), reasonsString())

    if isPaused() then
        -- Drop the cached baselines: on resume the first sample would otherwise
        -- report the average rate across the whole sleep, presented as a
        -- current rate. Better to show "--" for one refresh than a lie.
        prevRx, prevTx, prevTime = nil, nil, nil
        prevCpuActive, prevCpuIdle = nil, nil
    end
    applyTiming()
    if not isPaused() then runUpdate() end
end

-- This is the highest-frequency callback in the whole config -- every mouse
-- movement event on the system enters it -- so it does as little as possible.
-- It used to call hs.mouse.absolutePosition() for a position the event was
-- already carrying, buying a second round trip per event for nothing, and it
-- tested both axes when the bar spans the full screen width and only y can
-- ever rule a point out.
local function startMouseWatcher()
    mouseWatcher = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function(event)
        if not (barCanvas and barFrame) then return false end
        local p = event:location()
        local over = p.y >= barFrame.y and p.y <= barFrame.y + barFrame.h
            and p.x >= barFrame.x and p.x <= barFrame.x + barFrame.w
        if over and not hiddenByMouse then
            hiddenByMouse = true
            barCanvas:hide()
        elseif not over and hiddenByMouse then
            hiddenByMouse = false
            barCanvas:show()
        end
        return false
    end)
    mouseWatcher:start()
end

-- One shared "sleep" key that any wake event clears, rather than one key per
-- cause. Tracking the five separately would let a partner event macOS did not
-- deliver (screensaverDidStop is the unreliable one) pin the bar off until the
-- next config reload; sharing a key fails toward "keep refreshing" instead.
-- screensDidSleep is the event that matters most here: the display can sleep
-- while the system stays awake, and the bar was refreshing regardless.
local SLEEP_EVENTS, WAKE_EVENTS
do
    local w = hs.caffeinate.watcher
    SLEEP_EVENTS = {
        [w.systemWillSleep] = true,
        [w.screensDidSleep] = true,
        [w.screensDidLock] = true,
        [w.screensaverDidStart] = true,
        [w.sessionDidResignActive] = true,
    }
    WAKE_EVENTS = {
        [w.systemDidWake] = true,
        [w.screensDidWake] = true,
        [w.screensDidUnlock] = true,
        [w.screensaverDidStop] = true,
        [w.sessionDidBecomeActive] = true,
    }
end

function M.start()
    -- Full teardown first. The previous version stopped only refreshTimer and
    -- screenWatcher, leaking mouseWatcher and the canvas if start() ever ran
    -- twice; adding a fourth watcher below made that worth fixing rather than
    -- extending. Matches wallpaper/init.lua and countdown_chyron.lua.
    M.stop()

    createCanvas()
    startMouseWatcher()

    screenWatcher = hs.screen.watcher.new(function()
        updateCanvasFrame()
    end)
    screenWatcher:start()

    caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        if SLEEP_EVENTS[event] then
            setReason("sleep", true)
        elseif WAKE_EVENTS[event] then
            setReason("sleep", false)
        end
    end)
    caffeinateWatcher:start()

    runUpdate()
    applyTiming()
    log("started refresh=%ds", REFRESH_INTERVAL)
end

function M.stop()
    if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
    if mouseWatcher then mouseWatcher:stop(); mouseWatcher = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
    if caffeinateWatcher then caffeinateWatcher:stop(); caffeinateWatcher = nil end
    if barCanvas then barCanvas:delete(); barCanvas = nil end
    barFrame, hiddenByMouse = nil, false
    prevRx, prevTx, prevTime = nil, nil, nil
    prevCpuActive, prevCpuIdle = nil, nil
    refreshCount, lastDisk, lastText = 0, nil, nil
    pauseReasons = {}
end

return M

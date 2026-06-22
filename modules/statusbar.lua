local M = {}

local barCanvas = nil
local refreshTimer = nil
-- Mouse dodge: hide the bar while the cursor is over it, restore once it leaves.
local mouseWatcher = nil
local barFrame = nil
local hiddenByMouse = false
-- Network counters are cumulative; we cache the previous sample to derive a rate.
local prevRx, prevTx, prevTime = nil, nil, nil

-- Status Bar Configuration (Bottom, full width, floating)
local BAR_HEIGHT = 20
local FONT_SIZE = 14
local BACKGROUND_ALPHA = 0.55
local REFRESH_INTERVAL = 5
-- Gap inserted between each metric segment; widen/narrow to taste.
local SEPARATOR = "                 "

-- One shell pass collects every metric so we spawn a single task per refresh.
-- Output: "cpu|mem|disk|rxBytes txBytes" (battery comes from hs.battery in Lua).
local METRICS_SCRIPT = [[
cpu=$(top -l 1 | awk '/CPU usage/ {gsub("%","",$7); print 100-$7}')
psize=$(sysctl -n hw.pagesize)
total=$(sysctl -n hw.memsize)
vm=$(vm_stat)
active=$(printf '%s\n' "$vm" | awk '/Pages active/ {gsub("\\.","",$3); print $3}')
wired=$(printf '%s\n' "$vm" | awk '/Pages wired down/ {gsub("\\.","",$4); print $4}')
comp=$(printf '%s\n' "$vm" | awk '/occupied by compressor/ {gsub("\\.","",$5); print $5}')
mem=$(( (active + wired + comp) * psize * 100 / total ))
disk=$(df -k /System/Volumes/Data | awk 'NR==2 {gsub("%","",$5); print $5}')
iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
net=$(netstat -ibn -I "$iface" | awk 'NR==2 {print $7" "$10}')
printf '%s|%s|%s|%s\n' "$cpu" "$mem" "$disk" "$net"
]]

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

local function render(stdOut)
    local fields = {}
    for part in stdOut:gmatch("[^|]+") do fields[#fields + 1] = part end

    local cpu = tonumber(fields[1]) or 0
    local mem = tonumber(fields[2]) or 0
    local disk = tonumber(fields[3]) or 0
    local rx, tx = (fields[4] or ""):match("(%d+)%s+(%d+)")
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

    local segments = {
        string.format("CPU %d%%", math.floor(cpu + 0.5)),
        string.format("MEM %d%%", mem),
        string.format("↓ %s  ↑ %s", formatRate(downRate), formatRate(upRate)),
        string.format("SSD %d%%", disk),
        string.format("%sBAT %s", batPrefix, batText),
    }
    local text = table.concat(segments, SEPARATOR)

    if not barCanvas then createCanvas() end
    barCanvas[2].text = text
end

local function runUpdate()
    hs.task.new("/bin/sh", function(_, stdOut)
        render(stdOut or "")
    end, {"-c", METRICS_SCRIPT}):start()
end

local function startMouseWatcher()
    mouseWatcher = hs.eventtap.new({hs.eventtap.event.types.mouseMoved}, function()
        if not (barCanvas and barFrame) then return false end
        local p = hs.mouse.absolutePosition()
        local over = p.x >= barFrame.x and p.x <= barFrame.x + barFrame.w
            and p.y >= barFrame.y and p.y <= barFrame.y + barFrame.h
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

function M.start()
    if refreshTimer then refreshTimer:stop() end
    createCanvas()
    runUpdate()
    refreshTimer = hs.timer.doEvery(REFRESH_INTERVAL, runUpdate)
    startMouseWatcher()
end

function M.stop()
    if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
    if mouseWatcher then mouseWatcher:stop(); mouseWatcher = nil end
    if barCanvas then barCanvas:delete(); barCanvas = nil end
    barFrame, hiddenByMouse = nil, false
    prevRx, prevTx, prevTime = nil, nil, nil
end

return M

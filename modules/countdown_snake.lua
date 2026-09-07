-- Countdown snake overlay: a wandering snake whose body glyphs spell the time
-- remaining until TARGET, drawn on a click-through full-screen canvas.
-- Toggle with alt+cmd+D.
--
-- ── POWER MODEL ──────────────────────────────────────────────────────────────
-- A full-screen overlay that animates is the most expensive thing in this
-- config: every frame dirties a Retina-sized layer and stops the display from
-- settling to a low refresh rate. So the module is built around NOT drawing:
--
--   * ONE timer, not three. Wake-up count matters more than the work done in
--     each wake-up -- a CPU poked 12x a second never reaches a deep idle state
--     -- and hs.timer has no coalescing/tolerance knob to soften that, so the
--     only lever is fewer timers. The mouse check and the once-a-second clock
--     update ride on the move tick.
--   * The tick interval is DERIVED from the current pause set on every state
--     change, never nudged from the outside.
--   * "Hard" pause reasons (sleep) stop the timer outright, because an event
--     will wake us. "Soft" ones (idle, mouse) only slow it down, because
--     noticing that they have cleared requires polling.
--   * render() mutates the canvas elements in place instead of rebuilding them.
--
-- ── WHY pauseReasons AND NOT A BOOLEAN ───────────────────────────────────────
-- Taken deliberately from modules/wallpaper/init.lua, which documents the bug
-- that motivated it: a flag accumulated from paired enter/exit events
-- desynchronises the first time macOS drops half of a pair, and a stuck flag
-- held that wallpaper paused for over two hours. The same trap is here --
-- screensDidSleep and screensaverDidStart both have wake partners macOS does
-- not reliably deliver -- so all sleep-ish events share ONE reason key that ANY
-- wake event clears, backed by an idle-time watchdog. Both choices fail toward
-- "keep drawing": wasting some battery is recoverable, an overlay frozen until
-- the next config reload looks broken.
--
-- Anything that can be QUERIED is never stored: canvas visibility comes from
-- canvas:isShowing(), power source from hs.battery.powerSource(), user presence
-- from hs.host.idleTime(). State that is re-read cannot desynchronise.

local M = {}

-- ==================== 低耗能可調整參數 (Low-Power Configuration) ====================
local SHOW_FOOD = false             -- 是否顯示食物紅點 (false 亦可節省尋路運算)
-- 省電的主要槓桿是「沒人在用就完全停」(IDLE_PAUSE_SECONDS)，不是降低幀率：
-- 有人在看時給滿 ≈6FPS，一離開就停到 0.2 次喚醒/秒。所以兩種電源的間隔幾乎
-- 相同，電池只略降。想恢復明顯的「電池降幀」把 MOVE_INTERVAL_BATTERY 調大即可。
local MOVE_INTERVAL_AC = 0.16       -- 接電時的移動間隔（秒；0.16s≈6FPS）
local MOVE_INTERVAL_BATTERY = 0.17  -- 電池供電時的移動間隔（秒）
local IDLE_PAUSE_SECONDS = 25       -- 無操作超過這麼久就停止動畫（沒人在看）
local IDLE_POLL_INTERVAL = 5        -- idle 暫停期間的偵測間隔（秒）
local MOUSE_POLL_INTERVAL = 0.3     -- 游標壓在蛇身上、變暗暫停期間的偵測間隔（秒）
local MOUSE_CHECK_EVERY = 2         -- 正常執行時每 N 個 tick 才檢查一次游標
local WATCHDOG_INTERVAL = 30        -- sleep 暫停期間的保險偵測間隔（秒）
local TEXT_ALPHA = 0.50             -- 蛇身數字透明度
local HEAD_ALPHA = 0.75             -- 蛇頭數字透明度
local DIMMED_ALPHA = 0.15           -- 游標碰到蛇時整體變暗的透明度
local FONT_SIZE = 22                -- 數字字型大小
local GRID_STEP = 19                -- 蛇身節點間距
-- ====================================================================================

local TARGET = {year = 2068, month = 9, day = 29, hour = 0, min = 0, sec = 0}

-- Resolved once at load: os.time(table) runs mktime AND writes the normalised
-- fields back into the table, and the answer is a constant.
local TARGET_EPOCH = os.time(TARGET)

-- Derived drawing constants, hoisted out of the per-frame path.
local GLYPH_BOX = FONT_SIZE * 1.5
local GLYPH_OFFSET = FONT_SIZE / 2
local HEAD_COLOR = {red = 0.3, green = 1, blue = 0.5, alpha = HEAD_ALPHA}
local BODY_COLOR = {white = 1, alpha = TEXT_ALPHA}

-- Element index of the first snake glyph. The food circle, when enabled, owns
-- index 1 so that glyph indices stay fixed for the life of the canvas.
local BODY_OFFSET = SHOW_FOOD and 1 or 0

-- The four candidate steps, allocated once. getValidDirections() used to build
-- this table plus a result table on every frame; both are now reused, and dir
-- may alias an entry here, so these tables are never mutated.
local DIRECTIONS = {
    {x = 1, y = 0},
    {x = -1, y = 0},
    {x = 0, y = 1},
    {x = 0, y = -1},
}

-- Live objects
local canvas
local tickTimer          -- the single move/mouse/clock timer
local watchdogTimer      -- only alive while sleep-paused
local caffeinateWatcher
local batteryWatcher
local screenWatcher
local toggleHotkey

-- State
local pauseReasons = {}  -- reason(string) -> true; any entry => animation paused
local screenFrame
local gridMaxX, gridMaxY -- inclusive walkable grid bounds, from the screen size
local dir = {x = 1, y = 0}
local snakeHead = {x = 20, y = 15}
local snakeBody = {}
local targetFood = nil
local cachedCountdownStr = ""
local builtLength = 0    -- glyph count the canvas elements were built for
local lastText = ""      -- glyphs currently assigned to those elements
local tickIndex = 0
local lastClockEpoch = 0

-- Scratch buffers reused every frame so the render/step path allocates nothing.
local frameBuf = {x = 0, y = 0, w = GLYPH_BOX, h = GLYPH_BOX}
local centerBuf = {x = 0, y = 0}
local validDirs = {}

local function log(fmt, ...)
    print(string.format("[countdown_snake] " .. fmt, ...))
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

-- Map a numeric hs.caffeinate.watcher event back to its constant name, so log
-- lines read "screensDidSleep" instead of an opaque integer.
local function caffeinateEventName(event)
    for name, value in pairs(hs.caffeinate.watcher) do
        if type(value) == "number" and value == event then return name end
    end
    return "unknown(" .. tostring(event) .. ")"
end

local function countdownString()
    local remaining = math.max(0, TARGET_EPOCH - os.time())
    local days = math.floor(remaining / 86400)
    remaining = remaining % 86400
    local hours = math.floor(remaining / 3600)
    remaining = remaining % 3600
    local minutes = math.floor(remaining / 60)
    local seconds = remaining % 60
    return string.format("%d:%02d:%02d:%02d", days, hours, minutes, seconds)
end

local function initSnakeBody()
    cachedCountdownStr = countdownString()
    snakeBody = {}
    local startX, startY = 30, 20
    dir = DIRECTIONS[1]
    for i = 1, #cachedCountdownStr do
        snakeBody[i] = {x = startX - (i - 1), y = startY}
    end
    snakeHead = snakeBody[1]
end

-- ── Timing ───────────────────────────────────────────────────────────────────

-- Soft pause reasons need only enough tick rate to notice they have cleared;
-- everything else runs at the configured move interval for the current power
-- source. Both the reason set and the power source are read here rather than
-- cached, so this cannot answer with a stale value.
local function resolveInterval()
    if pauseReasons.idle then return IDLE_POLL_INTERVAL end
    if pauseReasons.mouse then return MOUSE_POLL_INTERVAL end
    if hs.battery.powerSource() == "Battery Power" then return MOVE_INTERVAL_BATTERY end
    return MOVE_INTERVAL_AC
end

-- Forward declarations: applyTiming() and tick() call each other's neighbours,
-- so both names must exist as locals before either body is written.
local tick
local setReason

-- Single owner of every timer in this module. Called on any state change and
-- always rebuilds from scratch, so no caller has to reason about which timers
-- are currently running.
local function applyTiming()
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if watchdogTimer then watchdogTimer:stop(); watchdogTimer = nil end

    -- Hidden by alt+cmd+D, or torn down: nothing to animate and nothing to poll.
    if not canvas or not canvas:isShowing() then return end

    if pauseReasons.sleep then
        -- Backstop for a wake event macOS never delivered. Recent user input
        -- proves the machine is awake and in use, whatever the event stream
        -- said. Costs one wake-up per 30s, and only while sleep-paused.
        watchdogTimer = hs.timer.doEvery(WATCHDOG_INTERVAL, function()
            if hs.host.idleTime() < WATCHDOG_INTERVAL then
                log("watchdog: user input while sleep-paused, clearing sleep")
                setReason("sleep", false)
            end
        end)
        return
    end

    tickTimer = hs.timer.doEvery(resolveInterval(), tick)
end

-- Reflect the current pause set onto the canvas and the timers.
local function applyPause()
    if canvas then
        canvas:alpha(pauseReasons.mouse and DIMMED_ALPHA or 1)
    end
    applyTiming()
end

-- Deliberate deviation from wallpaper/init.lua, which logs every setReason call:
-- the "mouse" reason here flips whenever the cursor crosses the snake, and
-- logging that at tick rate would itself be a measurable I/O cost. Only real
-- transitions are logged, which is still every change of state.
function setReason(reason, active)
    local before = pauseReasons[reason] and true or false
    local after = active and true or false
    if before == after then return end

    pauseReasons[reason] = after or nil
    log("setReason %s=%s -> paused=%s reasons={%s} interval=%.2fs",
        reason, tostring(after), tostring(isPaused()), reasonsString(), resolveInterval())
    applyPause()
end

-- ── Geometry ─────────────────────────────────────────────────────────────────

-- Re-derived on start and on any display/resolution change. The grid bounds
-- used to be two divisions recomputed inside getValidDirections() on every
-- frame, even though they only change when the screen does.
local function refreshScreenGeometry()
    screenFrame = hs.screen.mainScreen():fullFrame()
    gridMaxX = math.floor(screenFrame.w / GRID_STEP) - 3
    gridMaxY = math.floor(screenFrame.h / GRID_STEP) - 3
    if canvas then canvas:frame(screenFrame) end

    -- A shrunken display can leave the snake outside the walkable box, where
    -- every candidate step is invalid and it would sit still forever.
    if snakeHead and (snakeHead.x > gridMaxX or snakeHead.y > gridMaxY) then
        log("screen shrank to %dx%d, respawning snake", screenFrame.w, screenFrame.h)
        initSnakeBody()
    end
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

-- Build the element list ONCE per glyph count. The previous version rebuilt
-- ~57 Lua tables (element + frame + color for each glyph) and called
-- replaceElements() on every frame; at 6 FPS that was ~350 short-lived tables a
-- second of pure GC pressure for a picture whose only per-frame change is a
-- handful of x/y pairs. Colors, font and box size never change, so they are
-- written once here and never touched again.
local function buildElements()
    local elements = {}

    if SHOW_FOOD then
        elements[1] = {
            type = "circle",
            action = "fill",
            center = {x = -100, y = -100},   -- offscreen until spawnFood() runs
            radius = 6,
            fillColor = {red = 1, green = 0.3, blue = 0.3, alpha = 0.8},
        }
    end

    for i = 1, #cachedCountdownStr do
        elements[i + BODY_OFFSET] = {
            type = "text",
            text = cachedCountdownStr:sub(i, i),
            frame = {x = 0, y = 0, w = GLYPH_BOX, h = GLYPH_BOX},
            textColor = (i == 1) and HEAD_COLOR or BODY_COLOR,
            textFont = "Menlo-Bold",
            textSize = FONT_SIZE,
            textAlignment = "center",
        }
    end

    canvas:replaceElements(elements)
    builtLength = #cachedCountdownStr
    lastText = cachedCountdownStr
    log("rebuilt %d elements", builtLength)
end

local function render()
    if not canvas or not canvas:isShowing() then return end

    -- Only on start, and on the day the day-count loses a digit.
    if builtLength ~= #cachedCountdownStr then buildElements() end

    local str = cachedCountdownStr

    -- Glyphs: only the characters that actually changed. Ticking the seconds
    -- rewrites one or two of them, not all fourteen.
    if str ~= lastText then
        for i = 1, builtLength do
            local char = str:sub(i, i)
            if char ~= lastText:sub(i, i) then
                canvas:elementAttribute(i + BODY_OFFSET, "text", char)
            end
        end
        lastText = str
    end

    -- Positions: reuse one rect table for all of them. min() is defensive --
    -- stepSnake() keeps #snakeBody equal to builtLength.
    local count = #snakeBody
    if count > builtLength then count = builtLength end
    for i = 1, count do
        local pos = snakeBody[i]
        frameBuf.x = pos.x * GRID_STEP - GLYPH_OFFSET
        frameBuf.y = pos.y * GRID_STEP - GLYPH_OFFSET
        canvas:elementAttribute(i + BODY_OFFSET, "frame", frameBuf)
    end

    if SHOW_FOOD and targetFood then
        centerBuf.x = targetFood.x * GRID_STEP
        centerBuf.y = targetFood.y * GRID_STEP
        canvas:elementAttribute(1, "center", centerBuf)
    end
end

local function createCanvas()
    canvas = hs.canvas.new(screenFrame)
    canvas:level(hs.drawing.windowLevels.overlay)
    canvas:clickActivating(false)
    canvas:behaviorAsLabels({"canJoinAllSpaces", "stationary"})
end

-- ── Movement ─────────────────────────────────────────────────────────────────

local function spawnFood()
    if not SHOW_FOOD then return end
    local maxGridX = math.floor(screenFrame.w / GRID_STEP) - 5
    local maxGridY = math.floor(screenFrame.h / GRID_STEP) - 5
    targetFood = {
        x = math.random(5, math.max(6, maxGridX)),
        y = math.random(5, math.max(6, maxGridY))
    }
end

-- Fills the shared validDirs buffer and returns how many entries are valid.
-- Returning a count instead of a fresh table keeps the step path allocation-free.
local function collectValidDirections(head)
    local n = 0
    for i = 1, 4 do
        local d = DIRECTIONS[i]
        if not (d.x == -dir.x and d.y == -dir.y) then
            local nextX = head.x + d.x
            local nextY = head.y + d.y
            if nextX >= 3 and nextX <= gridMaxX and nextY >= 3 and nextY <= gridMaxY then
                n = n + 1
                validDirs[n] = d
            end
        end
    end
    return n
end

local function stepSnake()
    local count = collectValidDirections(snakeHead)
    if count == 0 then
        dir = {x = -dir.x, y = -dir.y}
        count = collectValidDirections(snakeHead)
    end

    if count > 0 then
        if SHOW_FOOD and targetFood then
            local bestDir = validDirs[1]
            local minDist = 999999
            for i = 1, count do
                local d = validDirs[i]
                local dist = math.abs(snakeHead.x + d.x - targetFood.x)
                           + math.abs(snakeHead.y + d.y - targetFood.y)
                if dist < minDist then
                    minDist = dist
                    bestDir = d
                end
            end
            dir = bestDir
        else
            -- Lightweight wandering direction selection
            local keepsCurrent = false
            for i = 1, count do
                local d = validDirs[i]
                if d.x == dir.x and d.y == dir.y then keepsCurrent = true; break end
            end
            if not keepsCurrent or math.random() < 0.15 then
                dir = validDirs[math.random(count)]
            end
        end
    end

    local nextX = snakeHead.x + dir.x
    local nextY = snakeHead.y + dir.y

    if SHOW_FOOD and targetFood and nextX == targetFood.x and nextY == targetFood.y then
        targetFood = nil
        spawnFood()
    end

    -- Recycle the tail node as the new head: in the steady state this is the
    -- whole step, with no allocation at all.
    local requiredLen = #cachedCountdownStr
    local newHead
    if #snakeBody >= requiredLen and #snakeBody > 1 then
        newHead = table.remove(snakeBody)
        newHead.x, newHead.y = nextX, nextY
    else
        newHead = {x = nextX, y = nextY}
    end
    table.insert(snakeBody, 1, newHead)
    snakeHead = newHead

    -- Keep #snakeBody == #cachedCountdownStr so every glyph has a node. The
    -- countdown only ever loses digits, so the pad branch is a safety net.
    while #snakeBody > requiredLen do
        table.remove(snakeBody)
    end
    while #snakeBody < requiredLen do
        local last = snakeBody[#snakeBody]
        snakeBody[#snakeBody + 1] = {x = last.x, y = last.y}
    end

    render()
end

local function mouseTouchesSnake()
    local mouse = hs.mouse.absolutePosition()
    local mouseGridX = math.floor(mouse.x / GRID_STEP)
    local mouseGridY = math.floor(mouse.y / GRID_STEP)

    local count = #snakeBody
    if count > 20 then count = 20 end
    for i = 1, count do
        local p = snakeBody[i]
        if math.abs(p.x - mouseGridX) <= 2 and math.abs(p.y - mouseGridY) <= 2 then
            return true
        end
    end
    return false
end

-- ── The single tick ──────────────────────────────────────────────────────────

-- Refresh the cached clock string at most once a second, whatever the tick rate.
-- Returns true when the string actually changed.
local function updateClock()
    local nowEpoch = os.time()
    if nowEpoch == lastClockEpoch then return false end
    lastClockEpoch = nowEpoch
    cachedCountdownStr = countdownString()
    return true
end

function tick()
    tickIndex = tickIndex + 1

    -- Cheapest check and the biggest saving, so it runs every tick: idleTime()
    -- is a counter read, and nobody is looking at the screen.
    setReason("idle", hs.host.idleTime() >= IDLE_PAUSE_SECONDS)

    -- Cursor proximity costs an IOKit round-trip. Skipped entirely while idle,
    -- because cursor movement is itself user input: if idleTime() has reached
    -- the threshold the cursor provably has not moved. Otherwise it rides at
    -- half rate, except while it is the reason holding the pause, where it is
    -- the only thing that can clear it.
    if not pauseReasons.idle
        and (pauseReasons.mouse or tickIndex % MOUSE_CHECK_EVERY == 0) then
        setReason("mouse", mouseTouchesSnake())
    end

    -- The clock is kept up even while paused, on a wake-up already being spent.
    -- Being idle is not the same as not looking -- reading a page counts as
    -- idle -- and a visible countdown frozen for minutes at a time reads as a
    -- bug. render() rewrites only the digits that changed, so the cost of this
    -- while paused is one or two glyphs per second and no extra timer.
    local clockChanged = updateClock()

    if isPaused() then
        if clockChanged then render() end
        return
    end

    stepSnake()   -- renders
end

-- ── Watchers ─────────────────────────────────────────────────────────────────

-- Any event meaning "nobody can see the overlay". screensDidSleep is the one
-- that matters most and the one the first version missed: the display can sleep
-- while the system stays awake, and the old code went on redrawing a
-- full-screen canvas onto a dark panel indefinitely.
local SLEEP_EVENTS, WAKE_EVENTS
do
    local w = hs.caffeinate.watcher
    SLEEP_EVENTS = {
        [w.systemWillSleep] = true,
        [w.screensDidSleep] = true,
        [w.screensDidLock] = true,
        [w.screensaverDidStart] = true,
        [w.sessionDidResignActive] = true,   -- fast user switching away
    }
    WAKE_EVENTS = {
        [w.systemDidWake] = true,
        [w.screensDidWake] = true,
        [w.screensDidUnlock] = true,
        [w.screensaverDidStop] = true,
        [w.sessionDidBecomeActive] = true,
    }
end

local function startWatchers()
    -- One shared "sleep" reason that ANY wake event clears. Tracking the five
    -- causes separately would let a missing partner event (macOS does not
    -- reliably emit screensaverDidStop) pin the overlay off until the next
    -- config reload -- the failure documented in wallpaper/init.lua.
    caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        log("caffeinate event=%s idle=%.0fs powerSource=%s reasons={%s}",
            caffeinateEventName(event), hs.host.idleTime(),
            tostring(hs.battery.powerSource()), reasonsString())
        if SLEEP_EVENTS[event] then
            setReason("sleep", true)
        elseif WAKE_EVENTS[event] then
            setReason("sleep", false)
        end
    end)
    caffeinateWatcher:start()

    -- The power source sets no reason of its own; it only changes the tick
    -- interval, which applyTiming() re-derives from a fresh query.
    batteryWatcher = hs.battery.watcher.new(function()
        log("battery watcher fired: powerSource=%s -> interval=%.2fs",
            tostring(hs.battery.powerSource()), resolveInterval())
        applyTiming()
    end)
    batteryWatcher:start()

    screenWatcher = hs.screen.watcher.new(refreshScreenGeometry)
    screenWatcher:start()
end

local function stopWatchers()
    if caffeinateWatcher then caffeinateWatcher:stop(); caffeinateWatcher = nil end
    if batteryWatcher then batteryWatcher:stop(); batteryWatcher = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
end

-- ── Public API ───────────────────────────────────────────────────────────────

function M.toggle()
    -- After M.stop() there is no canvas and no watchers; showing a canvas here
    -- would only produce a frozen snake, so stay off until M.start() runs.
    if not canvas then return end

    if canvas:isShowing() then
        canvas:hide()
        applyTiming()          -- isShowing() is false now, so this kills every timer
        log("hidden")
    else
        canvas:show()
        cachedCountdownStr = countdownString()
        render()
        applyTiming()
        log("shown interval=%.2fs", resolveInterval())
    end
end

function M.start()
    M.stop()   -- idempotent: reload.lua re-runs this on every *.lua save
    math.randomseed(os.time())

    pauseReasons = {}
    tickIndex = 0
    lastClockEpoch = 0
    builtLength = 0
    lastText = ""

    refreshScreenGeometry()
    createCanvas()
    initSnakeBody()
    canvas:show()
    render()   -- builds the elements, since builtLength is 0

    startWatchers()
    toggleHotkey = hs.hotkey.bind({"alt", "cmd"}, "D", M.toggle)
    applyTiming()

    log("started interval=%.2fs powerSource=%s glyphs=%d",
        resolveInterval(), tostring(hs.battery.powerSource()), builtLength)
end

function M.stop()
    -- Each timer and watcher individually. The previous version used
    -- ipairs{moveTimer, mouseTimer, countdownTimer}, which stops at the first
    -- nil hole and silently leaks the rest -- and a timer leaked across a hot
    -- reload doubles this module's power draw with nothing extra on screen.
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if watchdogTimer then watchdogTimer:stop(); watchdogTimer = nil end
    stopWatchers()
    if toggleHotkey then toggleHotkey:delete(); toggleHotkey = nil end
    if canvas then canvas:delete(); canvas = nil end

    pauseReasons = {}
    builtLength = 0
    lastText = ""
    targetFood = nil
end

return M

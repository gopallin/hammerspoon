-- Countdown chyron overlay: a vertical ticker pinned near the right screen
-- edge. The glyphs of the time remaining until TARGET are stacked upright, one
-- per line, and the whole column scrolls bottom-to-top on a click-through
-- canvas. Toggle with alt+cmd+D.
--
-- ── POWER MODEL ──────────────────────────────────────────────────────────────
-- Anything that animates is the most expensive thing in this config: every
-- frame dirties a Retina-sized layer and stops the display from settling to a
-- low refresh rate. So the module is built around NOT drawing:
--
--   * The canvas is a NARROW COLUMN, not the full screen. Its predecessor let
--     the glyphs wander the whole desktop, which forced a screen-sized layer:
--     every frame invalidated ~2 million pixels to move a dozen characters. A
--     chyron lives inside COLUMN_WIDTH x screen-height, roughly 4% of that
--     area, and the compositor's damage rect shrinks with it.
--   * ONE timer, not three. Wake-up count matters more than the work done in
--     each wake-up -- a CPU poked 6x a second never reaches a deep idle state
--     -- and hs.timer has no coalescing/tolerance knob to soften that, so the
--     only lever is fewer timers. The mouse check and the once-a-second clock
--     update ride on the scroll tick.
--   * The tick interval is DERIVED from the current pause set on every state
--     change, never nudged from the outside. Scroll distance per tick is then
--     derived from that interval, so a slower tick moves further and the chyron
--     travels at the same points-per-second whatever the power source.
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
-- 省電的主要槓桿是「沒人在用就完全停」(IDLE_PAUSE_SECONDS)，不是降低幀率：
-- 有人在看時給滿 ≈6FPS，一離開就停到 0.2 次喚醒/秒。所以兩種電源的間隔幾乎
-- 相同，電池只略降。想恢復明顯的「電池降幀」把 MOVE_INTERVAL_BATTERY 調大即可。
local MOVE_INTERVAL_AC = 0.16       -- 接電時的更新間隔（秒；0.16s≈6FPS）
local MOVE_INTERVAL_BATTERY = 0.17  -- 電池供電時的更新間隔（秒）
local IDLE_PAUSE_SECONDS = 25       -- 無操作超過這麼久就停止捲動（沒人在看）
local IDLE_POLL_INTERVAL = 5        -- idle 暫停期間的偵測間隔（秒）
local MOUSE_POLL_INTERVAL = 0.3     -- 游標壓在跑馬燈上、變暗暫停期間的偵測間隔（秒）
local MOUSE_CHECK_EVERY = 2         -- 正常執行時每 N 個 tick 才檢查一次游標
local WATCHDOG_INTERVAL = 30        -- sleep 暫停期間的保險偵測間隔（秒）
local TEXT_ALPHA = 0.50             -- 字身透明度
local LEAD_ALPHA = 0.75             -- 領頭字（最高位數字）透明度
local DIMMED_ALPHA = 0.15           -- 游標碰到跑馬燈時整體變暗的透明度
local FONT_SIZE = 22                -- 數字字型大小
local GLYPH_STEP = 24               -- 上下相鄰字元的間距（點）
-- 「字與右邊框的距離」就只看這一個值：字是靠右對齊到欄位右緣的，而欄位右緣
-- 就貼在「螢幕可用區右緣往左 COLUMN_MARGIN 點」的位置。調大 = 離邊框更遠。
-- 上限參考：keycap.lua 的按鍵框右緣在距離右緣 40 點處，COLUMN_MARGIN 超過
-- 約 27 就會讓數字疊到那個框上。
local COLUMN_MARGIN = 18            -- 數字右緣距離螢幕可用區右緣的距離（點）
local SCROLL_SPEED = 46             -- 捲動速度（點/秒），由下往上
local LOOP_GAP = 120                -- 整串跑完到下一輪自螢幕下方再進場之間的空白（點）
local BOTTOM_INSET = 24             -- 底部留白，避開 modules/statusbar.lua 的 20pt 狀態列
-- ====================================================================================

local TARGET = {year = 2068, month = 9, day = 29, hour = 0, min = 0, sec = 0}

-- Resolved once at load: os.time(table) runs mktime AND writes the normalised
-- fields back into the table, and the answer is a constant.
local TARGET_EPOCH = os.time(TARGET)

-- Derived drawing constants, hoisted out of the per-frame path.
local GLYPH_BOX = FONT_SIZE * 1.5
-- Only has to be wide enough for the widest glyph. It does NOT move the text:
-- the glyphs are right-aligned to the column's right edge, so the gap from the
-- screen edge is COLUMN_MARGIN alone. Widening this grows the column leftwards
-- into transparent space.
local COLUMN_WIDTH = FONT_SIZE * 2
local LEAD_COLOR = {red = 0.3, green = 1, blue = 0.5, alpha = LEAD_ALPHA}
local BODY_COLOR = {white = 1, alpha = TEXT_ALPHA}

-- Live objects
local canvas
local tickTimer          -- the single scroll/mouse/clock timer
local watchdogTimer      -- only alive while sleep-paused
local caffeinateWatcher
local batteryWatcher
local screenWatcher
local toggleHotkey

-- State
local pauseReasons = {}  -- reason(string) -> true; any entry => animation paused
local columnFrame        -- absolute screen rect of the canvas
local trackHeight = 0    -- canvas height; the chyron's travel distance
local leadY = 0          -- canvas-local y of the FIRST glyph's box top
local currentInterval = MOVE_INTERVAL_AC   -- interval the tick timer is running at
local cachedCountdownStr = ""
local builtLength = 0    -- glyph count the canvas elements were built for
local lastText = ""      -- glyphs currently assigned to those elements
local tickIndex = 0
local lastClockEpoch = 0

-- Scratch buffer reused every frame so the render path allocates nothing. Only
-- .y ever changes: the column is a fixed width and every glyph box is square.
local frameBuf = {x = 0, y = 0, w = COLUMN_WIDTH, h = GLYPH_BOX}

local function log(fmt, ...)
    print(string.format("[countdown_chyron] " .. fmt, ...))
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

-- Height of the whole stacked string, lead glyph's top edge to tail glyph's
-- bottom edge. Recomputed rather than cached: it changes on the day the day
-- count loses a digit, and the arithmetic is cheaper than the staleness bug.
local function stringHeight()
    return (#cachedCountdownStr - 1) * GLYPH_STEP + GLYPH_BOX
end

-- Park the string flush with the bottom of the column, fully on screen. Chosen
-- over "start just below the bottom edge" so that toggling the chyron on shows
-- a readable countdown immediately instead of eight seconds of empty column.
local function resetScroll()
    cachedCountdownStr = countdownString()
    leadY = trackHeight - stringHeight()
end

-- ── Timing ───────────────────────────────────────────────────────────────────

-- Soft pause reasons need only enough tick rate to notice they have cleared;
-- everything else runs at the configured interval for the current power source.
-- Both the reason set and the power source are read here rather than cached, so
-- this cannot answer with a stale value.
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
-- are currently running. It is also the only writer of currentInterval, which
-- keeps the scroll speed in points-per-second independent of the tick rate.
local function applyTiming()
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if watchdogTimer then watchdogTimer:stop(); watchdogTimer = nil end

    currentInterval = resolveInterval()

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

    tickTimer = hs.timer.doEvery(currentInterval, tick)
end

-- Reflect the current pause set onto the canvas and the timers.
local function applyPause()
    if canvas then
        canvas:alpha(pauseReasons.mouse and DIMMED_ALPHA or 1)
    end
    applyTiming()
end

-- Deliberate deviation from wallpaper/init.lua, which logs every setReason call:
-- the "mouse" reason here flips whenever the cursor enters the column, and
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

-- Re-derived on start and on any display/resolution change. frame() rather than
-- fullFrame(): a chyron sits at a fixed place for minutes at a time, so it must
-- clear the menu bar and the Dock instead of scrolling underneath them. The
-- extra BOTTOM_INSET clears modules/statusbar.lua's bar, which frame() does not
-- know about because it is an overlay canvas rather than a system bar.
--
-- Anchored to the RIGHT edge: x is derived so that the column's right edge --
-- which the glyphs are aligned to -- lands COLUMN_MARGIN in from the screen's
-- right edge. COLUMN_WIDTH therefore only extends the transparent area
-- leftwards and never shifts the digits.
local function refreshScreenGeometry()
    local f = hs.screen.mainScreen():frame()
    columnFrame = {
        x = f.x + f.w - COLUMN_MARGIN - COLUMN_WIDTH,
        y = f.y,
        w = COLUMN_WIDTH,
        h = math.max(GLYPH_BOX, f.h - BOTTOM_INSET),
    }
    trackHeight = columnFrame.h
    if canvas then canvas:frame(columnFrame) end

    -- A shrunken display can leave the string parked below the new bottom edge,
    -- where it would be invisible for a whole loop before scrolling back in.
    if leadY > trackHeight + LOOP_GAP then
        log("screen shrank to %dx%d, reparking chyron", f.w, f.h)
        resetScroll()
    end
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

-- Build the element list ONCE per glyph count. The previous version rebuilt
-- ~57 Lua tables (element + frame + color for each glyph) and called
-- replaceElements() on every frame; at 6 FPS that was ~350 short-lived tables a
-- second of pure GC pressure for a picture whose only per-frame change is a
-- handful of y values. Colors, font and box size never change, so they are
-- written once here and never touched again.
local function buildElements()
    local elements = {}

    for i = 1, #cachedCountdownStr do
        elements[i] = {
            type = "text",
            text = cachedCountdownStr:sub(i, i),
            frame = {x = 0, y = 0, w = COLUMN_WIDTH, h = GLYPH_BOX},
            textColor = (i == 1) and LEAD_COLOR or BODY_COLOR,
            textFont = "Menlo-Bold",
            textSize = FONT_SIZE,
            -- Right, not centre: it makes COLUMN_MARGIN the single, literal
            -- "distance from the screen edge to the digits" knob. With centring
            -- the real gap was COLUMN_MARGIN plus half the column's slack, so
            -- COLUMN_WIDTH silently moved the text too.
            textAlignment = "right",
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
                canvas:elementAttribute(i, "text", char)
            end
        end
        lastText = str
    end

    -- Positions: one rect table reused for all of them. Glyph 1 leads at the
    -- top of the column, so reading order survives the scroll -- the top of the
    -- string is what crosses the bottom edge first on the way in.
    for i = 1, builtLength do
        frameBuf.y = leadY + (i - 1) * GLYPH_STEP
        canvas:elementAttribute(i, "frame", frameBuf)
    end
end

local function createCanvas()
    canvas = hs.canvas.new(columnFrame)
    canvas:level(hs.drawing.windowLevels.overlay)
    canvas:clickActivating(false)
    canvas:behaviorAsLabels({"canJoinAllSpaces", "stationary"})
end

-- ── Scrolling ────────────────────────────────────────────────────────────────

-- Advance by points-per-second x seconds-per-tick rather than a fixed number of
-- points, so switching to battery power slows the wake-ups without also slowing
-- the chyron down to a visibly different speed.
local function stepChyron()
    leadY = leadY - SCROLL_SPEED * currentInterval

    -- Whole string has cleared the top edge: re-enter from below the bottom one.
    if leadY + stringHeight() < 0 then
        leadY = trackHeight + LOOP_GAP
    end

    render()
end

-- Horizontally this uses the whole column, including the transparent slack to
-- the left of the right-aligned digits, so the chyron yields a little before
-- the cursor actually touches a glyph. Vertically it is exact: for most of a
-- loop the column is empty, and there is nothing to get out of the way of.
local function mouseOverChyron()
    if not columnFrame then return false end
    local mouse = hs.mouse.absolutePosition()

    local localX = mouse.x - columnFrame.x
    if localX < 0 or localX > COLUMN_WIDTH then return false end

    local localY = mouse.y - columnFrame.y
    return localY >= leadY and localY <= leadY + stringHeight()
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
        setReason("mouse", mouseOverChyron())
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

    stepChyron()   -- renders
end

-- ── Watchers ─────────────────────────────────────────────────────────────────

-- Any event meaning "nobody can see the overlay". screensDidSleep is the one
-- that matters most and the one the first version missed: the display can sleep
-- while the system stays awake, and the old code went on redrawing a canvas
-- onto a dark panel indefinitely.
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
    -- would only produce a frozen chyron, so stay off until M.start() runs.
    if not canvas then return end

    if canvas:isShowing() then
        canvas:hide()
        applyTiming()          -- isShowing() is false now, so this kills every timer
        log("hidden")
    else
        canvas:show()
        resetScroll()          -- start readable rather than mid-loop offscreen
        render()
        applyTiming()
        log("shown interval=%.2fs", resolveInterval())
    end
end

function M.start()
    M.stop()   -- idempotent: reload.lua re-runs this on every *.lua save

    pauseReasons = {}
    tickIndex = 0
    lastClockEpoch = 0
    builtLength = 0
    lastText = ""

    refreshScreenGeometry()
    createCanvas()
    resetScroll()
    canvas:show()
    render()   -- builds the elements, since builtLength is 0

    startWatchers()
    toggleHotkey = hs.hotkey.bind({"alt", "cmd"}, "D", M.toggle)
    applyTiming()

    log("started interval=%.2fs powerSource=%s glyphs=%d column=%dx%d",
        resolveInterval(), tostring(hs.battery.powerSource()), builtLength,
        columnFrame.w, columnFrame.h)
end

function M.stop()
    -- Each timer and watcher individually. An older version used
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
end

return M

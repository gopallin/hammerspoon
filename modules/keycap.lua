local M = {}

local keyCanvas = nil
local charBuffer = {}
local eventTap = nil
local focusChangeTap = nil
local appWatcher = nil
local expireTimer = nil
local isPrivacyMode = false
local notification = require("modules.notification")

-- Keycap Configuration (Bottom-Right)
local FONT_SIZE = 25
local BACKGROUND_ALPHA = 0.3
local CHAR_BUFFER_LENGTH = 8
local CHAR_TTL_SECONDS = 1.5
local EXPIRE_CHECK_INTERVAL = 0.2
local CANVAS_WIDTH = 170
local CANVAS_HEIGHT = 38

-- Backstop only. The cached answer is invalidated the moment anything that can
-- move focus happens (see invalidateProtection), so this is what bounds the
-- damage from a focus change none of those signals caught -- not the normal path.
local AX_PROBE_MAX_AGE = 0.5

-- Special non-printable keys
local specialKeys = {
    [36] = "↩", [48] = "⇥", [49] = "␣", [51] = "⌫", [53] = "⎋",
    [57] = "⇪", [56] = "⇧", [60] = "⇧", [59] = "⌃", [62] = "⌃",
    [63] = "🌐", [123] = "←", [124] = "→", [125] = "↓", [126] = "↑",
}

local structuralSymbols = {
    ["↩"] = true, ["⇥"] = true, ["⌫"] = true, ["⎋"] = true,
    ["←"] = true, ["→"] = true, ["↓"] = true, ["↑"] = true,
    ["⇪"] = true, ["⇧"] = true, ["⌃"] = true, ["⌥"] = true, ["⌘"] = true, ["🌐"] = true
}

local modifierKeyCodes = {
    [54] = true, [55] = true, [56] = true, [57] = true, [58] = true,
    [59] = true, [60] = true, [61] = true, [62] = true, [63] = true,
}

-- Keys that move focus, and therefore change the answer to "is the field I am
-- typing into a secure one". Tab is the important one: tabbing from a username
-- field to a password field is the exact moment the cached answer must not be
-- reused.
local focusChangingKeyCodes = {
    [48] = true,   -- tab
    [36] = true,   -- return
    [76] = true,   -- keypad enter
    [53] = true,   -- escape
}

-- ── PROTECTION PROBE ─────────────────────────────────────────────────────────
-- The accessibility probe below used to run on EVERY keyDown, from inside the
-- event tap callback: one systemElement() round trip plus up to eight
-- attributeValue() calls, each a synchronous IPC to whatever app is frontmost.
-- An app that is busy answers slowly, and a keyDown tap that blocks delays the
-- keystroke reaching the app -- then macOS disables a tap that stays
-- unresponsive, which silently kills this module. modules/mouse.lua already
-- carries a comment about that exact failure mode; this was the same bug on the
-- other side of the config.
--
-- So the expensive part is cached and the cache is invalidated by the things
-- that can actually change the answer: a different app coming forward, a mouse
-- click landing somewhere new, or a focus-moving key. Steady-state typing --
-- thousands of keystrokes into one field -- now costs zero AX calls.
local cachedAxProtected = nil
local cachedAxTime = 0

local function invalidateProtection()
    cachedAxProtected = nil
end

-- Answers "is the focused element a password-ish field". Returns true on ANY
-- failure. Fail-closed is the whole point: this decides whether the next
-- keystroke is painted on screen in plaintext, where a screen recording or a
-- shared display will capture it. The previous version returned false when the
-- pcall failed or the element could not be read, i.e. it showed the characters
-- precisely when it had no idea what was being typed into.
local function probeAxProtected()
    local ok, result = pcall(function()
        local focusedElement = hs.axuielement.systemElement():attributeValue("AXFocusedUIElement")
        if not focusedElement then return nil end

        local role = focusedElement:attributeValue("AXRole")
        local subrole = focusedElement:attributeValue("AXSubrole")
        if role == "AXSecureTextField" or subrole == "AXSecureTextField" then return true end

        local sensitiveKeywords = {"pass", "密碼", "密码", "pw"}
        local attributes = {"AXPlaceholderValue", "AXDescription", "AXTitle", "AXHelp", "AXLabel", "AXIdentifier"}
        for _, attr in ipairs(attributes) do
            local val = focusedElement:attributeValue(attr)
            if type(val) == "string" and val ~= "" then
                local lval = val:lower()
                for _, kw in ipairs(sensitiveKeywords) do
                    if lval:find(kw) then return true end
                end
            end
        end
        return false
    end)

    if not ok then return true end
    -- nil means there was no focused element to inspect -- unknown, not safe.
    if result == nil then return true end
    return result
end

local function isAutoProtected()
    -- Both of these are cheap local reads, so they stay on the hot path and are
    -- never cached: a manual toggle or macOS secure input must take effect on
    -- the very next keystroke.
    if isPrivacyMode or hs.eventtap.isSecureInputEnabled() then return true end

    local now = hs.timer.secondsSinceEpoch()
    if cachedAxProtected == nil or (now - cachedAxTime) > AX_PROBE_MAX_AGE then
        cachedAxProtected = probeAxProtected()
        cachedAxTime = now
    end
    return cachedAxProtected
end

local function resolveKeyText(keyCode, char)
    if specialKeys[keyCode] then return specialKeys[keyCode] end
    if char and #char > 0 and char:match("[%g%s]") then return char end
    local keyName = hs.keycodes.map[keyCode]
    return (type(keyName) == "string" and #keyName > 0) and keyName or ""
end

-- UI: Keycap Canvas
local function createKeyCanvas()
    local screen = hs.screen.mainScreen()
    local f = screen:fullFrame()
    -- f.x/f.y, not 0/0: on a multi-display setup a secondary screen's frame has
    -- a non-zero origin, and ignoring it put the canvas on the wrong display.
    keyCanvas = hs.canvas.new({
        x = f.x + f.w - CANVAS_WIDTH - 40,
        y = f.y + f.h - CANVAS_HEIGHT - 60,
        w = CANVAS_WIDTH, h = CANVAS_HEIGHT
    })
    keyCanvas:level(hs.drawing.windowLevels.overlay)
    keyCanvas[1] =
        {
          type = "rectangle",
          action = "fill",
          fillColor = {white = 0, alpha = BACKGROUND_ALPHA},
          roundedRectRadii = {xRadius = 12, yRadius = 12}
        }

    keyCanvas[2] =
        {
            type = "text",
            text = "",
            textFont = ".AppleSystemUIFont",
            textSize = FONT_SIZE,
            textColor = {white = 1, alpha = 0.7},
            textAlignment = "right",
            frame = {x = "5%", y = "10%", w = "82%", h = "80%"}
        }

    keyCanvas[3] =
        {
            type = "text",
            text = "🔒",
            textSize = 12,
            frame = {x = "88%", y = "30%", w = "10%", h = "40%"},
            textColor = {white = 1, alpha = 0}
        }
end


-- Content
local function getDisplayString(isProtected)
    local pieces = {}
    for i = 1, #charBuffer do
        local item = charBuffer[i]
        local prefix = item.prefix or ""
        local content = item.rawChar or ""
        if isProtected and not structuralSymbols[content] then content = "*" end
        pieces[#pieces + 1] = prefix .. content
    end
    return table.concat(pieces, "  ")
end

-- Display
local function updateDisplay()
    if not keyCanvas then createKeyCanvas() end
    if #charBuffer == 0 then
        if keyCanvas:isShowing() then keyCanvas:hide() end
        return
    end
    local isProtected = isAutoProtected()
    if keyCanvas[3] then keyCanvas[3].textColor.alpha = isProtected and 1 or 0 end
    keyCanvas[2].text = getDisplayString(isProtected)
    if not keyCanvas:isShowing() then keyCanvas:show() end
end

local function pruneExpiredChars()
    local now = hs.timer.secondsSinceEpoch()
    local changed = false
    while #charBuffer > 0 do
        local item = charBuffer[1]
        if (now - item.t) >= CHAR_TTL_SECONDS then
            table.remove(charBuffer, 1)
            changed = true
        else break end
    end
    return changed
end

-- The expiry timer only has work to do while something is on screen, so it only
-- exists then. It used to be created once in M.start() and left running for the
-- life of the session: 5 wake-ups a second, forever, and on an empty buffer
-- pruneExpiredChars() returns immediately, so all five did nothing. That made
-- this module the largest single source of timer wake-ups in the whole config
-- once countdown_chyron learned to pause -- 25x the chyron's idle rate -- and it
-- kept firing with the display asleep. Wake-up count is what keeps a CPU out of
-- its deep idle states, whether or not the callback does any work.
local function stopExpireTimer()
    if expireTimer then expireTimer:stop(); expireTimer = nil end
end

local function syncExpireTimer()
    if #charBuffer > 0 then
        if not expireTimer then
            expireTimer = hs.timer.doEvery(EXPIRE_CHECK_INTERVAL, function()
                if pruneExpiredChars() then updateDisplay() end
                -- Reached empty: nothing left to expire, so stop rather than
                -- keep polling. updateDisplay() has already hidden the canvas.
                if #charBuffer == 0 then stopExpireTimer() end
            end)
        end
    else
        stopExpireTimer()
    end
end

function M.togglePrivacy()
    isPrivacyMode = not isPrivacyMode
    charBuffer = {}

    local msg = isPrivacyMode and "Privacy Mode ON 🔒" or "Privacy Mode OFF"
    notification.showStatus(msg)

    updateDisplay()
    syncExpireTimer()   -- buffer was just cleared, so this stops the timer
end

function M.start()
    M.stop()
    charBuffer = {}
    invalidateProtection()

    eventTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local keyCode = event:getKeyCode()
        local char = event:getCharacters()
        local flags = event:getFlags()
        local prefix = ""
        if not modifierKeyCodes[keyCode] then
            if flags.cmd then prefix = prefix .. "⌘" end
            if flags.alt then prefix = prefix .. "⌥" end
            if flags.ctrl then prefix = prefix .. "⌃" end
            if flags.shift and (keyCode > 50) then prefix = prefix .. "⇧" end
        end
        -- Before the buffer is touched, so the keystroke that MOVED focus is
        -- itself judged against the new field rather than the old one.
        if focusChangingKeyCodes[keyCode] then invalidateProtection() end
        local finalChar = resolveKeyText(keyCode, char)
        if finalChar ~= "" then
            table.insert(charBuffer, { rawChar = finalChar, prefix = prefix, keyCode = keyCode, t = hs.timer.secondsSinceEpoch() })
            while #charBuffer > CHAR_BUFFER_LENGTH do table.remove(charBuffer, 1) end
            pruneExpiredChars()
            updateDisplay()
            syncExpireTimer()   -- buffer is non-empty, so this starts the timer
        end
        return false
    end)
    eventTap:start()

    -- Click-to-focus. Mouse DOWN only -- this is a few events a minute, unlike a
    -- mouseMoved tap -- and the callback does nothing but drop a cached boolean.
    focusChangeTap = hs.eventtap.new(
        {hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown},
        function()
            invalidateProtection()
            return false
        end)
    focusChangeTap:start()

    -- A different app coming forward changes which app AXFocusedUIElement even
    -- refers to, so the cached answer is about the wrong process.
    appWatcher = hs.application.watcher.new(function(_, eventType)
        if eventType == hs.application.watcher.activated then invalidateProtection() end
    end)
    appWatcher:start()
end

function M.stop()
    if eventTap then eventTap:stop(); eventTap = nil end
    if focusChangeTap then focusChangeTap:stop(); focusChangeTap = nil end
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    stopExpireTimer()
    -- nil it too: updateDisplay() recreates the canvas when this is nil, and
    -- leaving a deleted canvas object here meant later calls poked a dead one.
    if keyCanvas then keyCanvas:delete(); keyCanvas = nil end
    charBuffer = {}
    invalidateProtection()
end

return M

local M = {}

local keyCanvas = nil
local charBuffer = {} -- FIFO queue: { text = "...", t = epochSeconds }
local eventTap = nil
local expireTimer = nil
local isPrivacyMode = false

-- Configuration
local FONT_SIZE = 25
local BACKGROUND_ALPHA = 0.3
local CHAR_BUFFER_LENGTH = 8
local CHAR_TTL_SECONDS = 1.5
local EXPIRE_CHECK_INTERVAL = 0.2
local CANVAS_WIDTH = 170
local CANVAS_HEIGHT = 38

-- Special non-printable keys
local specialKeys = {
    [36] = "↩",   -- Return
    [48] = "⇥",   -- Tab
    [49] = "␣",   -- Space
    [51] = "⌫",   -- Backspace
    [53] = "⎋",   -- Escape
    [57] = "⇪",   -- Caps Lock
    [56] = "⇧",   -- Left Shift
    [60] = "⇧",   -- Right Shift
    [59] = "⌃",   -- Left Control
    [62] = "⌃",   -- Right Control
    [63] = "🌐",  -- Globe / Function
    [123] = "←",  -- Left
    [124] = "→",  -- Right
    [125] = "↓",  -- Down
    [126] = "↑",  -- Up
}

local modifierKeyCodes = {
    [54] = true,  -- Right Command
    [55] = true,  -- Left Command
    [56] = true,  -- Left Shift
    [57] = true,  -- Caps Lock
    [58] = true,  -- Left Option
    [59] = true,  -- Left Control
    [60] = true,  -- Right Shift
    [61] = true,  -- Right Option
    [62] = true,  -- Right Control
    [63] = true,  -- Function
}

-- UI
local function createKeyCanvas()
    local screen = hs.screen.mainScreen()
    local f = screen:fullFrame()

    -- Position at bottom-right corner
    local x = f.w - CANVAS_WIDTH - 40
    local y = f.h - CANVAS_HEIGHT - 60

    keyCanvas = hs.canvas.new({x = x, y = y, w = CANVAS_WIDTH, h = CANVAS_HEIGHT})
    keyCanvas:level(hs.drawing.windowLevels.overlay)

    -- Background layer
    keyCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0, alpha = BACKGROUND_ALPHA},
        roundedRectRadii = {xRadius = 12, yRadius = 12},
    }

    -- Text layer (right-aligned for FIFO)
    keyCanvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFont",
        textSize = FONT_SIZE,
        textColor = {white = 1, alpha = 0.7},
        textAlignment = "right",
        frame = {x = "5%", y = "10%", w = "82%", h = "80%"}
    }

    -- Privacy indicator layer
    keyCanvas[3] = {
        type = "text",
        text = "🔒",
        textSize = 12,
        frame = {x = "88%", y = "30%", w = "10%", h = "40%"},
        textColor = {white = 1, alpha = 0}
    }
end

-- Content
local function getDisplayString()
    local pieces = {}
    for i = 1, #charBuffer do
        pieces[#pieces + 1] = charBuffer[i].text
    end
    -- Add spacing between tokens
    local fullStr = table.concat(pieces, "  ")
    -- Mask typed characters when secure mode is on
    if hs.eventtap.isSecureInputEnabled() or isPrivacyMode then
        return fullStr:gsub("[^⌘⌥⌃⇧↩⇥␣⌫⎋←→↓↑%s]", "*")
    end
    return fullStr
end

-- Display
local function updateDisplay()
    if not keyCanvas then createKeyCanvas() end

    if #charBuffer == 0 then
        if keyCanvas:isShowing() then keyCanvas:hide() end
        return
    end

    -- Update privacy icon visibility
    local isProtected = hs.eventtap.isSecureInputEnabled() or isPrivacyMode
    keyCanvas[3].textColor.alpha = isProtected and 1 or 0

    -- Update text content
    keyCanvas[2].text = getDisplayString()

    if not keyCanvas:isShowing() then
        keyCanvas:show()
    end
end

local function pruneExpiredChars()
    local now = hs.timer.secondsSinceEpoch()
    local changed = false
    while #charBuffer > 0 do
        local item = charBuffer[1]
        if (now - item.t) >= CHAR_TTL_SECONDS then
            table.remove(charBuffer, 1)
            changed = true
        else
            break
        end
    end
    return changed
end

function M.togglePrivacy()
    isPrivacyMode = not isPrivacyMode
    charBuffer = {} -- Flush buffer on mode change
    hs.alert.show(isPrivacyMode and "Privacy Mode ON 🔒" or "Privacy Mode OFF")
    updateDisplay()
end

function M.start()
    if eventTap then eventTap:stop() end
    if expireTimer then expireTimer:stop() end

    expireTimer = hs.timer.doEvery(EXPIRE_CHECK_INTERVAL, function()
        if pruneExpiredChars() then
            updateDisplay()
        end
    end)

    -- Capture keyDown events
    eventTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local keyCode = event:getKeyCode()
        local char = event:getCharacters()
        local flags = event:getFlags()

        -- Prefix modifiers for non-modifier keys
        local prefix = ""
        if not modifierKeyCodes[keyCode] then
            if flags.cmd then prefix = prefix .. "⌘" end
            if flags.alt then prefix = prefix .. "⌥" end
            if flags.ctrl then prefix = prefix .. "⌃" end
            if flags.shift and (keyCode > 50) then prefix = prefix .. "⇧" end
        end

        local finalChar = specialKeys[keyCode] or (char and #char > 0 and char or "")

        if finalChar ~= "" then
            table.insert(charBuffer, {
                text = prefix .. finalChar,
                t = hs.timer.secondsSinceEpoch(),
            })

            -- Keep only newest N chars
            while #charBuffer > CHAR_BUFFER_LENGTH do
                table.remove(charBuffer, 1)
            end

            pruneExpiredChars()
            updateDisplay()
        end

        return false -- Do not block keystrokes
    end)
    eventTap:start()

end

function M.stop()
    if eventTap then eventTap:stop() end
    if expireTimer then expireTimer:stop() end
    if keyCanvas then keyCanvas:delete() end
end

return M

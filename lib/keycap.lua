local M = {}

local keyCanvas = nil
local keyTimer = nil
local typedString = ""
local eventTap = nil
local isPrivacyMode = false

-- --- Configuration ---
local DISPLAY_TIMEOUT = 1.5      -- Seconds to wait before hiding the display
local FONT_SIZE = 30            -- Font size
local BACKGROUND_ALPHA = 0.3    -- Background transparency
local MAX_CHARS = 22            -- Characters that fit in the fixed-width box comfortably
local CANVAS_WIDTH = 200        -- Fixed width of the display box
local CANVAS_HEIGHT = 50        -- Fixed height of the display box

-- Special keys mapping
local specialKeys = {
    [36] = "↩",   -- Return
    [48] = "⇥",   -- Tab
    [49] = "␣",   -- Space
    [51] = "⌫",   -- Backspace
    [53] = "⎋",   -- Escape
    [123] = "←",  -- Left
    [124] = "→",  -- Right
    [125] = "↓",  -- Down
    [126] = "↑",  -- Up
}

-- --- Create Canvas ---
local function createKeyCanvas()
    local screen = hs.screen.mainScreen()
    local f = screen:fullFrame()

    local x = f.w - CANVAS_WIDTH - 40   -- 40 pixels from the right
    local y = f.h - CANVAS_HEIGHT - 60  -- 60 pixels from the bottom

    keyCanvas = hs.canvas.new({x = x, y = y, w = CANVAS_WIDTH, h = CANVAS_HEIGHT})
    keyCanvas:level(hs.drawing.windowLevels.overlay)

    -- Background
    keyCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0, alpha = BACKGROUND_ALPHA},
        roundedRectRadii = {xRadius = 10, yRadius = 10},
    }

    -- Text
    keyCanvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFont",
        textSize = FONT_SIZE,
        textColor = {white = 1, alpha = 1},
        textAlignment = "right",
        frame = {x = "5%", y = "15%", w = "82%", h = "70%"}
    }

    -- Privacy Icon (🔒)
    keyCanvas[3] = {
        type = "text",
        text = "🔒",
        textSize = 24,
        frame = {x = "88%", y = "25%", w = "10%", h = "50%"},
        textColor = {white = 1, alpha = 0}
    }
end

-- --- Privacy Check ---
local function shouldMask()
    return hs.eventtap.isSecureInputEnabled() or isPrivacyMode
end

-- --- Display Logic ---
local function updateDisplay()
    local ok, err = pcall(function()
        if not keyCanvas then createKeyCanvas() end

        -- IMMEDIATE PRUNING: Keep only the latest characters in the source string
        -- This ensures no backlog or lag during fast typing
        local rawLen = utf8.len(typedString)
        if rawLen > MAX_CHARS then
            local offset = utf8.offset(typedString, rawLen - MAX_CHARS + 1)
            typedString = string.sub(typedString, offset)
        end

        local displayStr = typedString

        -- Apply Masking if in Privacy Mode
        if shouldMask() then
            displayStr = displayStr:gsub("[^⌘⌥⌃⇧↩⇥␣⌫⎋←→↓↑%s]", "•")
            keyCanvas[3].textColor.alpha = 1
        else
            keyCanvas[3].textColor.alpha = 0
        end

        keyCanvas[2].text = displayStr

        if not keyCanvas:isShowing() then
            keyCanvas:show()
        end

        -- Reset hide timer
        if keyTimer then keyTimer:stop() end
        keyTimer = hs.timer.doAfter(DISPLAY_TIMEOUT, function()
            keyCanvas:hide()
            typedString = ""
        end)
    end)

    if not ok then print("Keycap Error: " .. tostring(err)) end
end

function M.togglePrivacy()
    isPrivacyMode = not isPrivacyMode
    typedString = ""
    hs.alert.show(isPrivacyMode and "Privacy Mode ON 🔒" or "Privacy Mode OFF")
    if keyCanvas then updateDisplay() end
end

function M.start()
    if eventTap then eventTap:stop() end

    eventTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local keyCode = event:getKeyCode()
        local char = event:getCharacters()
        local flags = event:getFlags()

        local prefix = ""
        if flags.cmd then prefix = prefix .. "⌘" end
        if flags.alt then prefix = prefix .. "⌥" end
        if flags.ctrl then prefix = prefix .. "⌃" end
        if flags.shift and (keyCode > 50) then prefix = prefix .. "⇧" end

        local finalChar = specialKeys[keyCode] or (char and #char > 0 and char or "")

        if finalChar ~= "" then
            typedString = typedString .. prefix .. finalChar
            updateDisplay()
        elseif keyCode == 51 then -- Backspace
            local len = utf8.len(typedString)
            if len > 0 then
                local offset = utf8.offset(typedString, -1)
                if offset then
                    typedString = string.sub(typedString, 1, offset - 1)
                end
                updateDisplay()
            end
        end

        return false
    end)
    eventTap:start()

    -- Bind manual toggle hotkey: Option + Cmd + P
    hs.hotkey.bind({"alt", "cmd"}, "P", function()
        M.togglePrivacy()
    end)
end

function M.stop()
    if eventTap then eventTap:stop() end
    if keyCanvas then keyCanvas:delete() end
    if keyTimer then keyTimer:stop() end
end

return M

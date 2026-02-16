local M = {}

local keyCanvas = nil
local keyTimer = nil
local charBuffer = {} -- Table used as a true FIFO buffer
local eventTap = nil
local isPrivacyMode = false 

-- --- Configuration ---
local DISPLAY_TIMEOUT = 1.0     -- Seconds before display hides after typing stops
local FONT_SIZE = 22            -- Increased font size for better readability
local BACKGROUND_ALPHA = 0.3    -- Translucent black background
local MAX_BUFFER = 20           -- Strict character limit for the FIFO queue
local CANVAS_WIDTH = 150        -- Fixed box width
local CANVAS_HEIGHT = 45        -- Fixed box height

-- Mapping for special non-printable keys
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

-- --- UI Creation ---
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

    -- Text layer (Right Aligned for FIFO feel)
    keyCanvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFont",
        textSize = FONT_SIZE,
        textColor = {white = 1, alpha = 1},
        textAlignment = "right",
        frame = {x = "5%", y = "10%", w = "82%", h = "80%"}
    }

    -- Privacy indicator layer
    keyCanvas[3] = {
        type = "text",
        text = "🔒",
        textSize = 24,
        frame = {x = "88%", y = "30%", w = "10%", h = "40%"},
        textColor = {white = 1, alpha = 0}
    }
end

-- --- Content Processing ---
local function getDisplayString()
    local fullStr = table.concat(charBuffer, "")
    -- Auto-mask if system Secure Input is on or manual Privacy Mode is active
    if hs.eventtap.isSecureInputEnabled() or isPrivacyMode then
        -- Mask alphanumeric characters with dots, preserve UI symbols
        return fullStr:gsub("[^⌘⌥⌃⇧↩⇥␣⌫⎋←→↓↑%s]", "•")
    end
    return fullStr
end

-- --- Update Display (FIFO Mechanism) ---
local function updateDisplay()
    if not keyCanvas then createKeyCanvas() end
    
    -- Update Privacy Icon visibility
    local isProtected = hs.eventtap.isSecureInputEnabled() or isPrivacyMode
    keyCanvas[3].textColor.alpha = isProtected and 1 or 0
    
    -- Update text content
    keyCanvas[2].text = getDisplayString()
    
    if not keyCanvas:isShowing() then
        keyCanvas:show()
    end
    
    -- Manage visibility timer
    if keyTimer then keyTimer:stop() end
    keyTimer = hs.timer.doAfter(DISPLAY_TIMEOUT, function()
        keyCanvas:hide()
        charBuffer = {} -- Clear the FIFO buffer when display expires
    end)
end

function M.start()
    if eventTap then eventTap:stop() end

    -- --- Capture Keyboard Events ---
    eventTap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local keyCode = event:getKeyCode()
        local char = event:getCharacters()
        local flags = event:getFlags()

        -- Capture modifier prefixes
        local prefix = ""
        if flags.cmd then prefix = prefix .. "⌘" end
        if flags.alt then prefix = prefix .. "⌥" end
        if flags.ctrl then prefix = prefix .. "⌃" end
        -- Filter shift prefix for simple letter typing
        if flags.shift and (keyCode > 50) then prefix = prefix .. "⇧" end

        local finalChar = specialKeys[keyCode] or (char and #char > 0 and char or "")
        
        if finalChar ~= "" then
            -- FIFO Logic: Add to end
            table.insert(charBuffer, prefix .. finalChar)
            
            -- FIFO Logic: Forcefully remove oldest if buffer exceeds MAX_BUFFER
            -- This provides instant replacement of old characters with new ones
            while #charBuffer > MAX_BUFFER do
                table.remove(charBuffer, 1)
            end
            
            updateDisplay()
        elseif keyCode == 51 then -- Handle Backspace (⌫)
            if #charBuffer > 0 then
                table.remove(charBuffer)
                updateDisplay()
            end
        end

        return false -- Do not block the keystroke from reaching apps
    end)
    eventTap:start()

    -- Manual Privacy Toggle: Option + Cmd + P
    hs.hotkey.bind({"alt", "cmd"}, "P", function()
        isPrivacyMode = not isPrivacyMode
        charBuffer = {} -- Flush buffer on mode change for security
        hs.alert.show(isPrivacyMode and "Privacy Mode ON 🔒" or "Privacy Mode OFF")
        updateDisplay()
    end)
end

function M.stop()
    if eventTap then eventTap:stop() end
    if keyCanvas then keyCanvas:delete() end
    if keyTimer then keyTimer:stop() end
end

return M

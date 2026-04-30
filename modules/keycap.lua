local M = {}

local keyCanvas = nil
local statusCanvas = nil -- New canvas for custom alerts
local statusTimer = nil
local charBuffer = {}
local eventTap = nil
local expireTimer = nil
local isPrivacyMode = false

-- Keycap Configuration (Bottom-Right)
local FONT_SIZE = 25
local BACKGROUND_ALPHA = 0.3
local CHAR_BUFFER_LENGTH = 8
local CHAR_TTL_SECONDS = 1.5
local EXPIRE_CHECK_INTERVAL = 0.2
local CANVAS_WIDTH = 170
local CANVAS_HEIGHT = 38

-- Status Alert Configuration (Top-Right - You can adjust these)
local STATUS_W = 220       -- 固定寬度
local STATUS_H = 50        -- 固定高度
local STATUS_X_OFFSET = 40 -- 距離右邊界的距離
local STATUS_Y_OFFSET = 40 -- 距離上邊界的距離
local STATUS_BG_ALPHA = 0.7
local STATUS_DURATION = 2.0 -- 顯示秒數

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

-- Check for Password Fields
local function isAutoProtected()
    if isPrivacyMode or hs.eventtap.isSecureInputEnabled() then return true end
    local app = hs.application.frontmostApplication()
    if not app then return false end
    local ok, focusedElement = pcall(function()
        return hs.axuielement.systemElement():attributeValue("AXFocusedUIElement")
    end)
    if ok and focusedElement then
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
    end
    return false
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
    keyCanvas = hs.canvas.new({
        x = f.w - CANVAS_WIDTH - 40,
        y = f.h - CANVAS_HEIGHT - 60,
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

-- UI: Custom Status Alert (Top-Right)
local function createStatusCanvas()
    local screen = hs.screen.mainScreen()
    local f = screen:fullFrame()

    -- Calculate position: Top-Right
    local x = f.w - STATUS_W - STATUS_X_OFFSET
    local y = STATUS_Y_OFFSET

    statusCanvas = hs.canvas.new({x = x, y = y, w = STATUS_W, h = STATUS_H})
    statusCanvas:level(hs.drawing.windowLevels.overlay)

    -- Background
    statusCanvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0, alpha = STATUS_BG_ALPHA},
        roundedRectRadii = {xRadius = 10, yRadius = 10},
    }

    -- Text
    statusCanvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFontBold",
        textSize = 18,
        textColor = {white = 1, alpha = 1},
        textAlignment = "center",
        frame = {x = "0%", y = "25%", w = "100%", h = "50%"}
    }
end

local function showCustomStatus(message)
    if not statusCanvas then createStatusCanvas() end
    if statusTimer then statusTimer:stop() end

    statusCanvas[2].text = message
    statusCanvas:show()

    statusTimer = hs.timer.doAfter(STATUS_DURATION, function()
        statusCanvas:hide()
    end)
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

function M.togglePrivacy()
    isPrivacyMode = not isPrivacyMode
    charBuffer = {}

    -- Using custom status instead of hs.alert.show
    local msg = isPrivacyMode and "Privacy Mode ON 🔒" or "Privacy Mode OFF"
    showCustomStatus(msg)

    updateDisplay()
end

function M.start()
    if eventTap then eventTap:stop() end
    if expireTimer then expireTimer:stop() end
    charBuffer = {}
    expireTimer = hs.timer.doEvery(EXPIRE_CHECK_INTERVAL, function()
        if pruneExpiredChars() then updateDisplay() end
    end)
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
        local finalChar = resolveKeyText(keyCode, char)
        if finalChar ~= "" then
            table.insert(charBuffer, { rawChar = finalChar, prefix = prefix, keyCode = keyCode, t = hs.timer.secondsSinceEpoch() })
            while #charBuffer > CHAR_BUFFER_LENGTH do table.remove(charBuffer, 1) end
            pruneExpiredChars()
            updateDisplay()
        end
        return false
    end)
    eventTap:start()
end

function M.stop()
    if eventTap then eventTap:stop() end
    if expireTimer then expireTimer:stop() end
    if keyCanvas then keyCanvas:delete() end
    if statusCanvas then statusCanvas:delete() end
end

return M

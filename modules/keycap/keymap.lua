-- 鍵碼 -> 顯示字元的對照表，以及由事件算出要顯示什麼的純函式。
local M = {}

-- 無法列印的特殊鍵
M.specialKeys = {
    [36] = "↩", [48] = "⇥", [49] = "␣", [51] = "⌫", [53] = "⎋",
    [57] = "⇪", [56] = "⇧", [60] = "⇧", [59] = "⌃", [62] = "⌃",
    [63] = "🌐", [123] = "←", [124] = "→", [125] = "↓", [126] = "↑",
}

-- 遮蔽模式下仍然照常顯示的符號：它們是排版結構，不是輸入內容。
M.structuralSymbols = {
    ["↩"] = true, ["⇥"] = true, ["⌫"] = true, ["⎋"] = true,
    ["←"] = true, ["→"] = true, ["↓"] = true, ["↑"] = true,
    ["⇪"] = true, ["⇧"] = true, ["⌃"] = true, ["⌥"] = true, ["⌘"] = true, ["🌐"] = true,
}

M.modifierKeyCodes = {
    [54] = true, [55] = true, [56] = true, [57] = true, [58] = true,
    [59] = true, [60] = true, [61] = true, [62] = true, [63] = true,
}

-- 會移動焦點、因此會改變「我正在打字的欄位是不是密碼欄」這個答案的鍵。
-- Tab 是最關鍵的一個：從帳號欄 tab 到密碼欄，正是那個不能重用舊答案的瞬間。
M.focusChangingKeyCodes = {
    [48] = true,   -- tab
    [36] = true,   -- return
    [76] = true,   -- keypad enter
    [53] = true,   -- escape
}

-- 修飾鍵前綴，例如 "⌘⇧"。修飾鍵本身被按下時不加前綴。
function M.modifierPrefix(keyCode, flags)
    if M.modifierKeyCodes[keyCode] then return "" end
    local prefix = ""
    if flags.cmd then prefix = prefix .. "⌘" end
    if flags.alt then prefix = prefix .. "⌥" end
    if flags.ctrl then prefix = prefix .. "⌃" end
    if flags.shift and (keyCode > 50) then prefix = prefix .. "⇧" end
    return prefix
end

function M.resolveKeyText(keyCode, char)
    if M.specialKeys[keyCode] then return M.specialKeys[keyCode] end
    if char and #char > 0 and char:match("[%g%s]") then return char end
    local keyName = hs.keycodes.map[keyCode]
    return (type(keyName) == "string" and #keyName > 0) and keyName or ""
end

return M

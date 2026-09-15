-- 模擬捲動：把四個方向包成函式，給 config/keybindings.lua 綁熱鍵。
local config = require("modules.scroll.config")

local scrollWheel = hs.eventtap.scrollWheel

local M = {}

function M.up()
    scrollWheel({ 0, -config.VERTICAL_LINES }, {}, "line")
end

function M.down()
    scrollWheel({ 0, config.VERTICAL_LINES }, {}, "line")
end

function M.left()
    scrollWheel({ config.HORIZONTAL_LINES, 0 }, {}, "line")
end

function M.right()
    scrollWheel({ -config.HORIZONTAL_LINES, 0 }, {}, "line")
end

return M

-- 滑鼠操作：點擊 + 連續移動。實作分別在 click.lua / move.lua，
-- 這裡只把它們接成 config/keybindings.lua 綁熱鍵用的介面。
local click = require("modules.mouse.click")
local move  = require("modules.mouse.move")

local M = {}

function M.mouseClick(button) click.click(button) end
function M.leftClick()        click.click("left") end
function M.rightClick()       click.click("right") end

M.directions = move.directions
function M.startMove(key, dx, dy) move.start(key, dx, dy) end
function M.stopMove(key)          move.stop(key) end

function M.stop()
    move.stopAll()
end

return M

-- 兩段式 3x3 格點游標定位：第一個數字選大格，第二個數字在那一大格裡再選一次。
-- 只按一個數字也可以 -- 等 INPUT_TIMEOUT_SECONDS 後就跳到大格中心。
local config   = require("modules.grid.config")
local position = require("modules.grid.position")

local M = {}

-- State
local firstKey = nil
local keyTimer = nil

local function clearTimer()
    if keyTimer then keyTimer:stop(); keyTimer = nil end
end

function M.handleKey(key)
    local frame = hs.screen.mainScreen():frame()

    if firstKey == nil then
        firstKey = key
        clearTimer()
        keyTimer = hs.timer.doAfter(config.INPUT_TIMEOUT_SECONDS, function()
            position.moveTo(firstKey, frame)
            firstKey = nil
        end)
        return
    end

    clearTimer()
    local firstRect = position.cellRect(firstKey, frame)
    firstKey = nil
    if not firstRect then return end
    position.moveTo(key, firstRect)
end

function M.stop()
    clearTimer()
    firstKey = nil
end

return M

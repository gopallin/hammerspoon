-- 格點 -> 座標的純計算。沒有狀態，只吃 rect 吐 rect / 移動游標。
local config = require("modules.grid.config")

local M = {}

-- rect 內編號 key 那一格的範圍。key 不合法時回傳 nil。
function M.cellRect(key, rect)
    local pos = config.POSITIONS[key]
    if not pos then return nil end
    local w = rect.w / config.DIVISIONS
    local h = rect.h / config.DIVISIONS
    return {
        x = rect.x + pos[1] * w,
        y = rect.y + pos[2] * h,
        w = w,
        h = h,
    }
end

-- 把游標移到 rect 內編號 key 那一格的正中央。
function M.moveTo(key, rect)
    local cell = M.cellRect(key, rect)
    if not cell then return end
    hs.mouse.absolutePosition({
        x = cell.x + cell.w / 2,
        y = cell.y + cell.h / 2,
    })
end

return M

-- 按住方向鍵時的連續移動。每個方向一個 timer，按下開始、放開停止。
local config = require("modules.mouse.config")

local M = {}

-- key(string) -> hs.timer；有值代表該方向正在移動中。
local movingTimers = {}

-- 每個方向每 tick 的位移量（點）。
function M.directions()
    return {
        W = { 0, -config.MOVE_SPEED },
        A = { -config.MOVE_SPEED, 0 },
        S = { 0, config.MOVE_SPEED },
        D = { config.MOVE_SPEED, 0 },
    }
end

function M.start(key, dx, dy)
    if movingTimers[key] then return end
    local startedAt = hs.timer.secondsSinceEpoch()
    movingTimers[key] = hs.timer.doEvery(config.MOVE_INTERVAL, function()
        -- 逾時保險，理由見 config.lua 的 MAX_MOVE_SECONDS。
        if hs.timer.secondsSinceEpoch() - startedAt > config.MAX_MOVE_SECONDS then
            M.stop(key)
            return
        end
        local pt = hs.mouse.absolutePosition()
        hs.mouse.absolutePosition({ x = pt.x + dx, y = pt.y + dy })
    end)
end

function M.stop(key)
    if movingTimers[key] then
        movingTimers[key]:stop()
        movingTimers[key] = nil
    end
end

function M.stopAll()
    for key in pairs(movingTimers) do M.stop(key) end
end

return M

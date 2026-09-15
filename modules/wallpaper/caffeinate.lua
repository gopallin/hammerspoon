-- 把數值型的 hs.caffeinate.watcher 事件代碼還原成常數名稱，讓 log 讀作
-- "systemDidWake" 而不是一個看不出意思的整數。
local M = {}

function M.eventName(event)
    for name, value in pairs(hs.caffeinate.watcher) do
        if type(value) == "number" and value == event then return name end
    end
    return "unknown(" .. tostring(event) .. ")"
end

return M

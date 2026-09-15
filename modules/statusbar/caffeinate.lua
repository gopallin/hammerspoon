-- 睡／醒事件的分類。
--
-- 共用「一個」sleep key，任何 wake 事件都能清掉它，而不是每個成因一個 key。
-- 分開追蹤那五個，只要 macOS 漏送了其中一半（screensaverDidStop 就是那個不可靠的
-- 那一個），就會讓 bar 一路停到下次重載設定為止；共用一個 key 的失效方向是
-- 「繼續刷新」。screensDidSleep 是這裡最重要的那個事件：螢幕可以在系統醒著的
-- 情況下睡著，而 bar 以前照樣在刷新。
local M = {}

local w = hs.caffeinate.watcher

M.SLEEP_EVENTS = {
    [w.systemWillSleep] = true,
    [w.screensDidSleep] = true,
    [w.screensDidLock] = true,
    [w.screensaverDidStart] = true,
    [w.sessionDidResignActive] = true,   -- 快速使用者切換切走
}

M.WAKE_EVENTS = {
    [w.systemDidWake] = true,
    [w.screensDidWake] = true,
    [w.screensDidUnlock] = true,
    [w.screensaverDidStop] = true,
    [w.sessionDidBecomeActive] = true,
}

-- 把數值型的事件代碼還原成常數名稱，讓 log 讀作 "screensDidSleep" 而不是一個
-- 看不出意思的整數。
function M.eventName(event)
    for name, value in pairs(w) do
        if type(value) == "number" and value == event then return name end
    end
    return "unknown(" .. tostring(event) .. ")"
end

return M

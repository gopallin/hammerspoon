-- 睡／醒事件的分類。
--
-- 任何代表「沒有人看得到這個 overlay」的事件。screensDidSleep 是最重要、也是
-- 第一版漏掉的那一個：螢幕可以在系統醒著的情況下睡著，而舊的程式會一直往一片
-- 黑掉的面板上重繪。
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

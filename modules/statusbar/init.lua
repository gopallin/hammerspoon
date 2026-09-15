-- 底部狀態列：CPU / 記憶體 / 網路速率 / 磁碟 / 電池。
-- 這個檔案只有暫停狀態、timer 和 watcher，其餘見：
--   config.lua      可調參數
--   metrics.lua     指標收集與文字組裝
--   bar.lua         畫面
--   caffeinate.lua  睡／醒事件分類
--
-- ── 暫停模型 ─────────────────────────────────────────────────────────────────
-- 跟 modules/wallpaper/init.lua 一樣用 pauseReasons 集合而不是布林值，理由寫在
-- 那裡：從成對的 enter/exit 事件累積出來的旗標，只要 macOS 漏送其中一半就會失步。
-- 所有睡眠類的事件共用「一個」key，任何 wake 事件都能清掉它。
--
-- 這裡刻意「沒有」idle 暫停，跟 countdown_chyron 不同。對狀態列而言「一段時間
-- 沒輸入」不等於「沒人在看」-- 看影片就是 idle，而網路速率正是那時候會想看的東西。
local bar        = require("modules.statusbar.bar")
local caffeinate = require("modules.statusbar.caffeinate")
local config     = require("modules.statusbar.config")
local metrics    = require("modules.statusbar.metrics")

local M = {}

local refreshTimer = nil
local mouseWatcher = nil       -- 游標壓在 bar 上就閃開，離開再顯示
local screenWatcher = nil
local caffeinateWatcher = nil
local hiddenByMouse = false
local pauseReasons = {}

local function log(fmt, ...)
    print(string.format("[statusbar] " .. fmt, ...))
end

local function isPaused()
    return next(pauseReasons) ~= nil
end

local function reasonsString()
    local keys = {}
    for k in pairs(pauseReasons) do keys[#keys + 1] = k end
    table.sort(keys)
    return #keys > 0 and table.concat(keys, ",") or "none"
end

local function render(stdOut)
    if not bar.exists() then
        bar.create()
    else
        bar.refreshFrame()
    end
    bar.setText(metrics.summarize(stdOut))
end

local function runUpdate()
    if isPaused() then return end
    local script = metrics.nextScript()
    hs.task.new("/bin/sh", function(_, stdOut)
        render(stdOut or "")
    end, { "-c", script }):start()
end

-- 刷新 timer 的唯一擁有者，每次都從暫停集合重建，所以沒有任何呼叫端需要去推敲
-- 它現在是不是正在跑。
local function applyTiming()
    if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
    if isPaused() then return end
    refreshTimer = hs.timer.doEvery(config.REFRESH_INTERVAL, runUpdate)
end

local function setReason(reason, active)
    local before = pauseReasons[reason] and true or false
    local after = active and true or false
    if before == after then return end

    pauseReasons[reason] = after or nil
    log("setReason %s=%s -> paused=%s reasons={%s}",
        reason, tostring(after), tostring(isPaused()), reasonsString())

    if isPaused() then metrics.resetBaselines() end
    applyTiming()
    if not isPaused() then runUpdate() end
end

-- 這是整份設定裡觸發頻率最高的 callback -- 系統上每一次滑鼠移動事件都會進來 --
-- 所以它做的事愈少愈好。它以前會呼叫 hs.mouse.absolutePosition() 去要一個事件
-- 本身早就帶著的位置，白白多買一次往返；而且它會測兩個軸，但 bar 橫跨整個螢幕
-- 寬度，只有 y 能排除一個點。
local function startMouseWatcher()
    mouseWatcher = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function(event)
        local over = bar.contains(event:location())
        if over and not hiddenByMouse then
            hiddenByMouse = true
            bar.hide()
        elseif not over and hiddenByMouse then
            hiddenByMouse = false
            bar.show()
        end
        return false
    end)
    mouseWatcher:start()
end

function M.start()
    -- 先完整拆乾淨。舊版只停了 refreshTimer 和 screenWatcher，start() 跑第二次
    -- 就會漏掉 mouseWatcher 和 canvas；再加上第四個 watcher 之後，與其繼續疊，
    -- 不如把它修好。與 wallpaper/init.lua、countdown_chyron/init.lua 一致。
    M.stop()

    bar.create()
    startMouseWatcher()

    screenWatcher = hs.screen.watcher.new(function() bar.refreshFrame() end)
    screenWatcher:start()

    caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        if caffeinate.SLEEP_EVENTS[event] then
            setReason("sleep", true)
        elseif caffeinate.WAKE_EVENTS[event] then
            setReason("sleep", false)
        end
    end)
    caffeinateWatcher:start()

    runUpdate()
    applyTiming()
    log("started refresh=%ds", config.REFRESH_INTERVAL)
end

function M.stop()
    if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
    if mouseWatcher then mouseWatcher:stop(); mouseWatcher = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
    if caffeinateWatcher then caffeinateWatcher:stop(); caffeinateWatcher = nil end
    bar.destroy()
    metrics.reset()
    hiddenByMouse = false
    pauseReasons = {}
end

return M

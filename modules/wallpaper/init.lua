-- 桌面動態桌布：把本地影片播在桌面圖示底下的一張 hs.webview 上，並自動省電暫停。
-- 這個檔案只有暫停狀態與 watcher，其餘見：
--   config.lua      可調參數 + 路徑（含 data/ 的理由）
--   util.lua        檔案／路徑工具
--   page.lua        產生播放器頁面
--   player.lua      webview 本身與播放控制
--   coverage.lua    桌面有沒有被蓋住
--   page.html       前端樣板
local caffeinate = require("modules.wallpaper.caffeinate")
local config     = require("modules.wallpaper.config")
local coverage   = require("modules.wallpaper.coverage")
local player     = require("modules.wallpaper.player")

local M = {}

-- State
local spacesWatcher = nil
local coveredTimer = nil
local appWatcher = nil
local batteryWatcher = nil
local caffeinateWatcher = nil
local screenWatcher = nil
local pauseReasons = {}        -- reason(string) -> true；有任何一項就代表影片暫停

local function isPaused()
    return next(pauseReasons) ~= nil
end

-- 把目前生效的暫停理由排序後用逗號接起來，給 log 用。什麼都沒暫停時是空的。
-- 這讓一行 log 能顯示「整個」理由集合，而不只是剛好翻動 isPaused() 的那一個。
local function reasonsString()
    local keys = {}
    for k in pairs(pauseReasons) do keys[#keys + 1] = k end
    table.sort(keys)
    return #keys > 0 and table.concat(keys, ",") or "none"
end

player.shouldPause = isPaused

local function setReason(reason, active)
    if active then pauseReasons[reason] = true else pauseReasons[reason] = nil end
    -- 「每一次」呼叫都 log（不只是 isPaused() 翻面的時候）：在已經暫停的狀態下
    -- 設定／清除某個理由以前是靜默的，那會讓卡住的理由在 log 裡看不見。
    print(string.format("[wallpaper] setReason %s=%s -> paused=%s reasons={%s}",
        reason, tostring(active), tostring(isPaused()), reasonsString()))
    player.applyPlayback()
end

-- 沒有變化就不出聲，這樣定期重檢才不會把其他暫停理由的 log 淹掉。
local function refreshCoveredReason()
    local active = coverage.isCovered()
    if active ~= (pauseReasons.covered or false) then
        setReason("covered", active)
    end
end

local function startWatchers()
    -- 顯示中的是全螢幕／分割 space -> 暫停（反正 wallpaper 被蓋住了）。
    -- 監看 space 變化而不是視窗事件，也順便修好一個視窗事件從來不會回報的情況：
    -- 切換到一個「已經開著」的全螢幕 app。
    spacesWatcher = hs.spaces.watcher.new(refreshCoveredReason)
    spacesWatcher:start()

    -- 大部分時候，蓋住與讓出桌面的就是切換 app，而且那是事件不是輪詢 --
    -- 所以下面那個 timer 可以維持在它慵懶的間隔，不必為了及時察覺而加快。
    appWatcher = hs.application.watcher.new(function(_, eventType)
        if eventType == hs.application.watcher.activated
            or eventType == hs.application.watcher.deactivated then
            refreshCoveredReason()
        end
    end)
    appWatcher:start()

    -- 漏掉的 space 變化的保險，也是唯一能察覺「在已經最前景的那個 app 裡調整視窗
    -- 大小」的東西：最壞情況下 wallpaper 會在 30 秒內自己修正，而不是一路卡到下次
    -- 重載設定。
    coveredTimer = hs.timer.doEvery(config.FULLSCREEN_RECHECK_INTERVAL, refreshCoveredReason)
    refreshCoveredReason()

    -- 使用電池 -> 暫停。
    batteryWatcher = hs.battery.watcher.new(function()
        local src = hs.battery.powerSource()
        print(string.format("[wallpaper] battery watcher fired: powerSource=%s", tostring(src)))
        setReason("battery", src == "Battery Power")
    end)
    batteryWatcher:start()
    setReason("battery", hs.battery.powerSource() == "Battery Power")

    -- 睡 -> 暫停；醒 -> 恢復並重建（WKWebView 在喚醒後會掉幀）。
    caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        local e = hs.caffeinate.watcher
        -- 「每一個」caffeinate 事件都按名稱 log（包含我們不處理的），這樣在診斷
        -- 卡住的暫停時，漏掉／非預期的 wake 事件才看得見。
        print(string.format("[wallpaper] caffeinate event=%s powerSource=%s reasons={%s}",
            caffeinate.eventName(event), tostring(hs.battery.powerSource()), reasonsString()))
        if event == e.systemWillSleep or event == e.screensDidSleep then
            setReason("sleep", true)
        elseif event == e.systemDidWake or event == e.screensDidWake then
            setReason("sleep", false)
            -- 電源可能在睡眠期間改變（例如整夜插著充電）而不會觸發 battery
            -- watcher，留下一個過期的 "battery" 暫停；喚醒時重讀一次，讓接電時
            -- 能恢復播放。
            setReason("battery", hs.battery.powerSource() == "Battery Power")
            player.rebuild()
        end
    end)
    caffeinateWatcher:start()

    -- 顯示器／解析度改變時重新貼合。
    screenWatcher = hs.screen.watcher.new(function() player.refitToScreen() end)
    screenWatcher:start()
end

local function stopWatchers()
    if spacesWatcher then spacesWatcher:stop(); spacesWatcher = nil end
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    if coveredTimer then coveredTimer:stop(); coveredTimer = nil end
    if batteryWatcher then batteryWatcher:stop(); batteryWatcher = nil end
    if caffeinateWatcher then caffeinateWatcher:stop(); caffeinateWatcher = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
end

function M.start()
    stopWatchers()   -- 跨重載冪等
    pauseReasons = {}
    startWatchers()
    player.show()
end

function M.stop()
    stopWatchers()
    player.hide()
    pauseReasons = {}
end

return M

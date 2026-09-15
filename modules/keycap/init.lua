-- 螢幕上的按鍵顯示：攔 keyDown、推進緩衝區、畫出來，並在偵測到密碼欄時遮蔽。
-- 這個檔案只有 tap / timer / 生命週期，其餘見：
--   config.lua      可調參數
--   keymap.lua      鍵碼對照表
--   buffer.lua      畫面上那幾個字
--   protection.lua  該不該遮蔽（隱私模式 + AX 探測）
--   canvas.lua      畫面
local buffer       = require("modules.keycap.buffer")
local canvas       = require("modules.keycap.canvas")
local config       = require("modules.keycap.config")
local keymap       = require("modules.keycap.keymap")
local notification = require("modules.notification")
local protection   = require("modules.keycap.protection")

local M = {}

local eventTap = nil
local focusChangeTap = nil
local appWatcher = nil
local expireTimer = nil

local function updateDisplay()
    canvas.update(buffer.items(), protection.isProtected())
end

-- 非同步探測是在「觸發它的那次按鍵已經畫完之後」才回來的，所以它需要用回來的
-- 答案重畫一次。
protection.onAnswerChanged = function()
    if buffer.count() > 0 then updateDisplay() end
end

-- 過期 timer 只有在畫面上有東西的時候才有事做，所以也只在那時才存在。它以前是在
-- M.start() 建立一次然後跑滿整個 session：每秒五次喚醒、永遠，而緩衝區空的時候
-- pruneExpired() 立刻返回，所以那五次全都沒做事。在 countdown_chyron 學會暫停之後，
-- 這讓本模組變成整份設定裡最大的 timer 喚醒來源 -- 是 chyron 閒置速率的 25 倍 --
-- 而且螢幕睡著了它還在跑。讓 CPU 進不了深層閒置狀態的是喚醒次數，不是 callback
-- 做了多少事。
local function stopExpireTimer()
    if expireTimer then expireTimer:stop(); expireTimer = nil end
end

local function syncExpireTimer()
    if buffer.count() == 0 then
        stopExpireTimer()
        return
    end
    if expireTimer then return end
    expireTimer = hs.timer.doEvery(config.EXPIRE_CHECK_INTERVAL, function()
        if buffer.pruneExpired() then updateDisplay() end
        -- 清空了：沒有東西會再過期，所以停掉而不是繼續輪詢。
        -- updateDisplay() 已經把 canvas 藏起來了。
        if buffer.count() == 0 then stopExpireTimer() end
    end)
end

function M.cyclePrivacy()
    local mode = protection.cycleMode()
    buffer.clear()

    notification.showStatus(protection.MODE_MESSAGES[mode])

    updateDisplay()
    syncExpireTimer()   -- 緩衝區剛清空，所以這會停掉 timer
end

local function onKeyDown(event)
    local keyCode = event:getKeyCode()
    local prefix = keymap.modifierPrefix(keyCode, event:getFlags())

    -- 在動到緩衝區之前，這樣「移動了焦點的那一次按鍵」本身就是用新欄位、
    -- 而不是舊欄位來判斷的。
    if keymap.focusChangingKeyCodes[keyCode] then protection.invalidate() end

    local char = keymap.resolveKeyText(keyCode, event:getCharacters())
    if char ~= "" then
        buffer.push(char, prefix, keyCode)
        buffer.pruneExpired()
        updateDisplay()
        syncExpireTimer()   -- 緩衝區非空，所以這會啟動 timer
    end
    return false
end

function M.start()
    M.stop()
    buffer.clear()
    protection.invalidate()

    -- 在那個會觸發探測的 tap 存在之前，所以不會有查詢是在 OS 的多秒預設逾時下發出的。
    protection.applyMessagingTimeout()

    eventTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, onKeyDown)
    eventTap:start()

    -- 點擊改變焦點。只收 mouse DOWN -- 這一分鐘只有幾個事件，不像 mouseMoved tap --
    -- 而且 callback 除了丟掉一個快取值之外什麼都不做。
    focusChangeTap = hs.eventtap.new(
        { hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.rightMouseDown },
        function()
            protection.invalidate()
            return false
        end)
    focusChangeTap:start()

    -- 換一個 app 到最前景，會改變 AXFocusedUIElement 指的是「哪個行程」，
    -- 所以快取的答案講的是錯的那個行程。
    appWatcher = hs.application.watcher.new(function(_, eventType)
        if eventType == hs.application.watcher.activated then protection.invalidate() end
    end)
    appWatcher:start()
end

function M.stop()
    if eventTap then eventTap:stop(); eventTap = nil end
    if focusChangeTap then focusChangeTap:stop(); focusChangeTap = nil end
    if appWatcher then appWatcher:stop(); appWatcher = nil end
    stopExpireTimer()
    protection.stop()
    canvas.destroy()
    buffer.clear()
end

return M

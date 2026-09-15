-- 倒數跑馬燈：貼在螢幕右緣的直式跑馬燈。距離 TARGET 的剩餘時間，字元直排堆疊，
-- 整欄由下往上捲，畫在一張點擊穿透的 canvas 上。alt+cmd+D 切換。
--
-- 這個檔案只有「暫停狀態 + 那一個 timer + watcher + 對外 API」，其餘見：
--   config.lua      可調參數 + 目標時刻
--   countdown.lua   倒數字串
--   geometry.lua    尺寸與欄位位置
--   track.lua       跑馬燈目前在哪、顯示什麼
--   canvas.lua      畫面
--   caffeinate.lua  睡／醒事件分類
--
-- ── 耗能模型 ─────────────────────────────────────────────────────────────────
-- 會動的東西是這份設定裡最貴的東西：每一幀都弄髒一張 Retina 尺寸的圖層，並且
-- 讓螢幕無法降到低更新率。所以這個模組是圍繞著「不要畫」設計的：
--
--   * canvas 是一個「窄欄」，不是整個螢幕。它的前身讓字元在整個桌面上遊走，
--     那逼出一張螢幕大小的圖層：每一幀為了移動十幾個字元而讓約兩百萬個像素失效。
--     跑馬燈活在 COLUMN_WIDTH x 螢幕高之內，大約是那個面積的 4%，而合成器的
--     damage rect 也跟著縮小。
--   * 「一個」timer，不是三個。喚醒次數比每次喚醒做多少事更重要 -- 一顆每秒被戳
--     六次的 CPU 永遠到不了深層閒置狀態 -- 而 hs.timer 沒有 coalescing/tolerance
--     旋鈕可以緩和，所以唯一的槓桿是減少 timer 數量。游標檢查和每秒一次的時鐘
--     更新都搭在捲動 tick 上。
--   * tick 間隔是在每次狀態改變時「從當前暫停集合推導」出來的，絕不從外面調整。
--     每 tick 的捲動距離再由那個間隔推導（見 track.step），所以較慢的 tick 會走得
--     較遠，不管電源是什麼，跑馬燈的「點/秒」都一樣。
--   * 「硬」暫停理由（sleep）直接停掉 timer，因為會有事件把我們叫醒。「軟」的
--     （idle、mouse）只是放慢，因為要發現它們已經解除需要輪詢。
--   * canvas.render() 就地改元素，而不是重建它們。
--
-- ── 為什麼是 pauseReasons 而不是布林值 ───────────────────────────────────────
-- 刻意取自 modules/wallpaper/init.lua，那裡記錄了促成這個做法的 bug：從成對的
-- enter/exit 事件累積出來的旗標，只要 macOS 漏送其中一半就會失步，而一個卡住的
-- 旗標曾讓 wallpaper 暫停超過兩小時。同一個陷阱在這裡也有 -- screensDidSleep 和
-- screensaverDidStart 都有 macOS 不保證送達的 wake 夥伴 -- 所以所有睡眠類事件共用
-- 「一個」reason key，任何 wake 事件都能清掉，再加上一個 idle 時間的看門狗。
-- 兩個選擇的失效方向都是「繼續畫」：浪費一點電池是救得回來的，一個凍到下次重載
-- 設定的 overlay 看起來就是壞了。
--
-- 任何「問得到」的東西一律不儲存：canvas 可見性問 canvas、電源問
-- hs.battery.powerSource()、有沒有人在問 hs.host.idleTime()。重新讀取的狀態
-- 不會失步。
local caffeinate = require("modules.countdown_chyron.caffeinate")
local canvas     = require("modules.countdown_chyron.canvas")
local config     = require("modules.countdown_chyron.config")
local track      = require("modules.countdown_chyron.track")

local M = {}

-- Live objects
local tickTimer          -- 唯一那個捲動／游標／時鐘 timer
local watchdogTimer      -- 只在 sleep 暫停期間活著
local caffeinateWatcher
local batteryWatcher
local screenWatcher
local toggleHotkey

-- State
local pauseReasons = {}  -- reason(string) -> true；有任何一項就代表動畫暫停
local currentInterval = config.MOVE_INTERVAL_AC   -- tick timer 目前跑的間隔
local tickIndex = 0

local function log(fmt, ...)
    print(string.format("[countdown_chyron] " .. fmt, ...))
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

-- ── Timing ───────────────────────────────────────────────────────────────────

-- 軟暫停理由只需要足以察覺「它已經解除」的 tick 率；其餘一律用當前電源對應的
-- 設定間隔。理由集合和電源都是在這裡當場讀的而不是快取，所以這個函式不可能用
-- 過期的值回答。
local function resolveInterval()
    if pauseReasons.idle then return config.IDLE_POLL_INTERVAL end
    if pauseReasons.mouse then return config.MOUSE_POLL_INTERVAL end
    if hs.battery.powerSource() == "Battery Power" then return config.MOVE_INTERVAL_BATTERY end
    return config.MOVE_INTERVAL_AC
end

-- 前向宣告：applyTiming() 和 tick() 會呼叫到彼此的鄰居，所以兩個名字都得在任一
-- 個函式主體被寫出來之前就以 local 存在。
local tick
local setReason

-- 這個模組裡每一個 timer 的唯一擁有者。任何狀態改變時被呼叫，而且永遠從頭重建，
-- 所以沒有任何呼叫端需要去推敲現在哪些 timer 正在跑。它也是 currentInterval 的
-- 唯一寫入者，這讓捲動速度（點/秒）與 tick 率無關。
local function applyTiming()
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if watchdogTimer then watchdogTimer:stop(); watchdogTimer = nil end

    currentInterval = resolveInterval()

    -- 被 alt+cmd+D 藏起來，或已經拆掉了：沒有東西要動，也沒有東西要輪詢。
    if not canvas.isShowing() then return end

    if pauseReasons.sleep then
        -- 針對 macOS 從來沒送出的 wake 事件的保險。近期有使用者輸入就證明機器是
        -- 醒著而且有人在用，不管事件流說了什麼。代價是每 30 秒一次喚醒，而且只在
        -- sleep 暫停期間。
        watchdogTimer = hs.timer.doEvery(config.WATCHDOG_INTERVAL, function()
            if hs.host.idleTime() < config.WATCHDOG_INTERVAL then
                log("watchdog: user input while sleep-paused, clearing sleep")
                setReason("sleep", false)
            end
        end)
        return
    end

    tickTimer = hs.timer.doEvery(currentInterval, tick)
end

-- 刻意跟 wallpaper/init.lua 不同，那裡每次 setReason 都會 log：這裡的 "mouse"
-- 理由只要游標進出欄位就會翻面，用 tick 的頻率去 log 它，本身就是一筆量得出來的
-- I/O 成本。這裡只 log 真正的狀態轉換 -- 那仍然是每一次狀態改變。
function setReason(reason, active)
    local before = pauseReasons[reason] and true or false
    local after = active and true or false
    if before == after then return end

    pauseReasons[reason] = after or nil
    log("setReason %s=%s -> paused=%s reasons={%s} interval=%.2fs",
        reason, tostring(after), tostring(isPaused()), reasonsString(), resolveInterval())

    -- 把當前的暫停集合反映到 canvas 和 timer 上。
    canvas.setAlpha(pauseReasons.mouse and config.DIMMED_ALPHA or 1)
    applyTiming()
end

-- ── The single tick ──────────────────────────────────────────────────────────

function tick()
    tickIndex = tickIndex + 1

    -- 最便宜的檢查、也是省最多的那個，所以每個 tick 都跑：idleTime() 是讀一個
    -- 計數器，而且沒有人在看螢幕。
    setReason("idle", hs.host.idleTime() >= config.IDLE_PAUSE_SECONDS)

    -- 游標距離的檢查要花一次 IOKit 往返。idle 期間完全跳過，因為游標移動本身就是
    -- 使用者輸入：如果 idleTime() 已經到閾值，游標就可證明沒有動過。其餘時候以
    -- 半速搭便車，除非它正是那個撐住暫停的理由 -- 那時它是唯一能解除暫停的東西。
    if not pauseReasons.idle
        and (pauseReasons.mouse or tickIndex % config.MOUSE_CHECK_EVERY == 0) then
        setReason("mouse", track.mouseOver())
    end

    -- 時鐘即使在暫停期間也保持走動，搭在一個本來就要花掉的喚醒上。idle 不等於
    -- 沒在看 -- 讀一頁文章就算 idle -- 而一個看得見卻凍住好幾分鐘的倒數看起來
    -- 就是 bug。canvas.render() 只會重寫真的變了的那幾個字，所以暫停期間的成本
    -- 是每秒一兩個字，而且沒有額外的 timer。
    local clockChanged = track.tickClock()

    if isPaused() then
        if clockChanged then track.render() end
        return
    end

    track.step(currentInterval)   -- 內含 render
end

-- ── Watchers ─────────────────────────────────────────────────────────────────

local function startWatchers()
    -- 共用「一個」sleep 理由，任何 wake 事件都能清掉。分開追蹤那五個成因，只要
    -- 有一個夥伴事件缺席（macOS 不保證送出 screensaverDidStop）就會讓 overlay
    -- 一路關到下次重載設定 -- 也就是 wallpaper/init.lua 記錄的那個失效。
    caffeinateWatcher = hs.caffeinate.watcher.new(function(event)
        log("caffeinate event=%s idle=%.0fs powerSource=%s reasons={%s}",
            caffeinate.eventName(event), hs.host.idleTime(),
            tostring(hs.battery.powerSource()), reasonsString())
        if caffeinate.SLEEP_EVENTS[event] then
            setReason("sleep", true)
        elseif caffeinate.WAKE_EVENTS[event] then
            setReason("sleep", false)
        end
    end)
    caffeinateWatcher:start()

    -- 電源不設任何自己的理由；它只改變 tick 間隔，而 applyTiming() 會從一次新鮮的
    -- 查詢重新推導那個間隔。
    batteryWatcher = hs.battery.watcher.new(function()
        log("battery watcher fired: powerSource=%s -> interval=%.2fs",
            tostring(hs.battery.powerSource()), resolveInterval())
        applyTiming()
    end)
    batteryWatcher:start()

    screenWatcher = hs.screen.watcher.new(track.refreshGeometry)
    screenWatcher:start()
end

local function stopWatchers()
    if caffeinateWatcher then caffeinateWatcher:stop(); caffeinateWatcher = nil end
    if batteryWatcher then batteryWatcher:stop(); batteryWatcher = nil end
    if screenWatcher then screenWatcher:stop(); screenWatcher = nil end
end

-- ── Public API ───────────────────────────────────────────────────────────────

function M.toggle()
    -- M.stop() 之後沒有 canvas 也沒有 watcher；這時顯示 canvas 只會得到一個凍住的
    -- 跑馬燈，所以在 M.start() 跑之前就維持關閉。
    if not canvas.exists() then return end

    if canvas.isShowing() then
        canvas.hide()
        applyTiming()          -- isShowing() 現在是 false，所以這會殺掉每一個 timer
        log("hidden")
    else
        canvas.show()
        track.reset()          -- 開起來就讀得到，而不是停在一輪中間的畫面外
        track.render()
        applyTiming()
        log("shown interval=%.2fs", resolveInterval())
    end
end

function M.start()
    M.stop()   -- 冪等：modules/reload 每次存檔都會重跑這個

    pauseReasons = {}
    tickIndex = 0
    track.resetClock()

    track.refreshGeometry()
    canvas.create(track.frame())
    track.reset()
    canvas.show()
    track.render()   -- 順便建立元素

    startWatchers()
    toggleHotkey = hs.hotkey.bind({ "alt", "cmd" }, "D", M.toggle)
    applyTiming()

    log("started interval=%.2fs powerSource=%s glyphs=%d column=%dx%d",
        resolveInterval(), tostring(hs.battery.powerSource()), track.glyphCount(),
        track.frame().w, track.frame().h)
end

function M.stop()
    -- 每個 timer 和 watcher 各別處理。舊版用 ipairs{moveTimer, mouseTimer,
    -- countdownTimer}，那會在第一個 nil 洞停下來並無聲漏掉其餘的 -- 而一個跨越
    -- 熱重載漏掉的 timer，會讓這個模組的耗電加倍，畫面上卻沒有多出任何東西。
    if tickTimer then tickTimer:stop(); tickTimer = nil end
    if watchdogTimer then watchdogTimer:stop(); watchdogTimer = nil end
    stopWatchers()
    if toggleHotkey then toggleHotkey:delete(); toggleHotkey = nil end
    canvas.destroy()

    pauseReasons = {}
end

return M

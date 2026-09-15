-- 「現在該不該遮蔽按鍵」的全部判斷：隱私模式 + macOS secure input +
-- accessibility 探測與它的快取。這個檔案自己持有這些狀態，其他檔案只問結論。
--
-- ── 探測為什麼長這樣 ─────────────────────────────────────────────────────────
-- 下面這支探測以前是「每一次 keyDown 都跑」，而且是從 event tap callback 裡面
-- 跑：一次 systemWideElement() 往返，再加上最多八次 attributeValue()，每一次都
-- 是對當前最前景 app 的同步 IPC。忙碌的 app 回得慢，而 keyDown tap 一旦阻塞就會
-- 延後按鍵送達 app -- 接著 macOS 會停用長時間無回應的 tap，等於無聲地殺掉整個
-- 模組。modules/mouse/click.lua 裡已經有一段註解在講同一個失效模式；這是同一個
-- bug 出現在設定檔的另一側。
--
-- 所以昂貴的部分被快取起來，而讓快取失效的，是那些真的會改變答案的事件：換了
-- 最前景 app、滑鼠點到別的地方、或按下會移動焦點的鍵。穩定打字的情況 -- 對同一
-- 個欄位連打幾千個字 -- 現在的 AX 呼叫次數是零。
--
-- 光是快取答案只解決了一半。快取沒命中時，探測仍然是「從 keyDown callback 裡」
-- 跑的，而 keyDown tap 跑在按鍵送到 app 之前 -- 所以探測花掉的每一毫秒都是輸入
-- 延遲，而且快取正好會在使用者最有感的那一次按鍵上沒命中：焦點剛移動後的第一次。
--
-- spotlight 面板是最壞情況，也是這個問題被發現的地方。那個面板是 Hammerspoon
-- 自己擁有的 webview，所以它開著的時候 Hammerspoon 就「是」最前景 app，而探測
-- 會去問 Hammerspoon 的主執行緒它自己的焦點元件 -- 偏偏那條執行緒正卡在 tap 裡
-- 等這個回覆。在 AX 逾時之前沒有人能回答；等到那時候 macOS 早就放棄這個沒回應的
-- tap（kCGEventTapDisabledByTimeout）並自己把按鍵放行了。那就是「第一個字要等
-- 一秒才出現、第二個字之後就瞬間」的原因 -- 因為那時快取已經熱了。
--
-- 所以現在熱路徑「只」讀快取。沒命中時是為「下一次」按鍵去刷新，而不是阻塞這
-- 一次；而沒命中讀作 unknown，仍然是 fail closed -- 在探測說安全之前字是遮著
-- 的，絕不會先顯示再說。
local config = require("modules.keycap.config")

local M = {}

-- "auto"   -- 相信探測；讀不出焦點狀態就遮蔽（fail closed）
-- "always" -- 一律遮蔽，不管探測說什麼
-- "reveal" -- 焦點狀態 UNKNOWN 時顯示；被明確判定為密碼欄的仍然遮蔽（見 isProtected）
local privacyMode = "auto"

local cachedAnswer = nil     -- "yes" / "no" / "unknown" / nil(無快取)
local cachedTime = 0
local probeInFlight = false
-- 放在 module local 而不是留成匿名的：沒有任何東西參照的 hs.timer 有可能在它
-- 觸發之前就被回收掉。
local probeTimer = nil

-- 每次失效就 +1。焦點移動時已經在飛的探測，回答的是「我們剛離開的那個欄位」的
-- 問題，不能讓它的答案落下來當成新欄位的描述。
local generation = 0

-- 探測答案改變、而畫面已經用舊答案畫過時，由 init.lua 設成重畫函式。
M.onAnswerChanged = nil

function M.invalidate()
    cachedAnswer = nil
    generation = generation + 1
end

-- 回答「焦點元件是不是密碼類欄位」，三種值之一："yes" / "no" / "unknown"。
-- 第三種不是湊數：一個不公布焦點元件的 app 給我們的正是這個，而使用者可以選擇
-- 看穿 unknown（privacyMode == "reveal"）；"yes" 則是證據，無條件遮蔽。
--
-- 用 systemWideElement()，不是 systemElement()：後者根本不是 hs.axuielement 的
-- 函式，所以這個呼叫每次都拋例外、每次都被 pcall 吃掉。在原本 fail-OPEN 的程式
-- 裡那讀作「沒有密碼欄」，探測其實早就死了；7d58136 把同一個例外改成 fail
-- CLOSED，這就是後來每一次按鍵都被遮蔽的原因。這支探測從來沒有真的檢查過任何
-- 東西。
local function probe()
    local ok, result = pcall(function()
        local focused = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
        if not focused then return nil end

        local role = focused:attributeValue("AXRole")
        local subrole = focused:attributeValue("AXSubrole")
        if role == "AXSecureTextField" or subrole == "AXSecureTextField" then return true end

        local sensitiveKeywords = { "pass", "密碼", "密码", "pw" }
        local attributes = { "AXPlaceholderValue", "AXDescription", "AXTitle", "AXHelp", "AXLabel", "AXIdentifier" }
        for _, attr in ipairs(attributes) do
            local val = focused:attributeValue(attr)
            if type(val) == "string" and val ~= "" then
                local lval = val:lower()
                for _, kw in ipairs(sensitiveKeywords) do
                    if lval:find(kw) then return true end
                end
            end
        end
        return false
    end)

    -- AX 錯誤不是「有密碼欄」的證據，一個不公布焦點元件的 app 也不是。
    -- 兩者都算 unknown。
    if not ok then return "unknown" end
    if result == nil then return "unknown" end
    return result and "yes" or "no"
end

-- 把探測丟到 runloop 的下一輪跑，而不是在呼叫端跑。呼叫端通常是 keyDown tap，
-- 它必須「現在」就返回；答案只要來得及重畫就好，晚幾毫秒重畫看不出來。
local function refreshAsync()
    if probeInFlight then return end
    probeInFlight = true
    local myGeneration = generation
    probeTimer = hs.timer.doAfter(0, function()
        probeTimer = nil
        local answer = probe()
        -- 等查詢真的回來才清掉，這樣這個旗標在「有探測正在跑」的整段期間都成立。
        -- 上面那行阻塞時，Hammerspoon 單一 runloop 上也不會有別的東西在跑，所以
        -- 今天這個順序不影響行為 -- 但一個在它所保護的呼叫期間會說謊的旗標，
        -- 距離變成 bug 只差一次重構。
        probeInFlight = false
        -- 問的期間焦點移動了。丟掉：快取已經是 nil，而 nil 是安全的答案。
        if myGeneration ~= generation then return end

        local previous = cachedAnswer
        cachedAnswer = answer
        cachedTime = hs.timer.secondsSinceEpoch()
        -- 畫面上的東西是用「沒命中」畫出來的。只在答案真的改變了什麼的時候才重畫，
        -- 而且這不會遞迴：快取現在是新鮮的，所以 isProtected() 不會再要求刷新。
        if answer ~= previous and M.onAnswerChanged then M.onAnswerChanged() end
    end)
end

function M.isProtected()
    -- 這兩個都是便宜的本地讀取，所以留在熱路徑上而且永不快取：手動切換或 macOS
    -- secure input 必須在「下一次按鍵」就生效。secure input 是 OS 自己在說這是
    -- 密碼欄，所以它的位階高過使用者要求顯示。
    if privacyMode == "always" then return true end
    if hs.eventtap.isSecureInputEnabled() then return true end

    local now = hs.timer.secondsSinceEpoch()
    local fresh = cachedAnswer ~= nil and (now - cachedTime) <= config.AX_PROBE_MAX_AGE
    if not fresh then refreshAsync() end

    -- "yes" 是證據，而它不會因為過期就不再是證據 -- 過期的 "yes" 在刷新飛行途中
    -- 仍然維持遮蔽。只有「新鮮的 no」才被允許顯示任何東西；過期的 no 一律當成
    -- unknown，這比舊版「阻塞按鍵去重問」更嚴格。
    if cachedAnswer == "yes" then return true end
    if fresh and cachedAnswer == "no" then return false end
    -- Unknown：仍然 fail closed，除非使用者明確要求看穿它。那個選擇無法揭露我們
    -- 「有」辨識出來的欄位 -- 上面兩個硬訊號在這裡之前就已經返回了。
    return privacyMode ~= "reveal"
end

-- 三個狀態而不是開／關一對，因為「關」回答不了真正會咬人的情況：一個不公布焦點
-- UI 元件的 app 讀作 unknown，unknown fail closed，然後就沒有任何辦法把按鍵顯示
-- 要回來。"reveal" 就是那個辦法，而它仍然無法揭露探測或 OS 明確判定為安全欄位的
-- 東西。
local NEXT_MODE = { auto = "always", always = "reveal", reveal = "auto" }

M.MODE_MESSAGES = {
    auto   = "Privacy: AUTO",
    always = "Privacy: ALWAYS 🔒",
    reveal = "Privacy: REVEAL 👁",
}

-- 切到下一個模式，回傳新的模式字串。
function M.cycleMode()
    privacyMode = NEXT_MODE[privacyMode] or "auto"
    -- 模式改變了「unknown 代表什麼」，所以已快取的答案是舊的。
    M.invalidate()
    return privacyMode
end

function M.mode()
    return privacyMode
end

-- 在任何可能觸發探測的 tap 存在之前呼叫，這樣就不會有查詢是在 OS 那個以秒計的
-- 預設逾時底下發出的。
function M.applyMessagingTimeout()
    pcall(function()
        hs.axuielement.systemWideElement():setTimeout(config.AX_MESSAGING_TIMEOUT)
    end)
end

function M.stop()
    if probeTimer then probeTimer:stop(); probeTimer = nil end
    probeInFlight = false
    M.invalidate()
end

return M

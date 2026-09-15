-- 面板本身：webview 的生命週期、樣板組裝，以及「目前這個面板是用哪份清單建的」。
--
-- active_* 兩張清單就是 URL handler 的安全邊界：handler 只會把索引解析到這裡，
-- 所以面板關著時送來的偽造 URL 會撞到空表。
local json    = require("hs.json")
local screen  = require("hs.screen")
local webview = require("hs.webview")

local config = require("modules.spotlight.config")
local util   = require("modules.spotlight.util")

local M = {}

local instance = nil
local escHotkey = nil
local focusTimer = nil

-- 目前這個面板是用哪份清單建的。
local activeGhostty = {}
local activeUrls = {}

function M.isOpen()
    return instance ~= nil
end

function M.close()
    if focusTimer then focusTimer:stop(); focusTimer = nil end
    if instance then instance:delete(); instance = nil end
    if escHotkey then escHotkey:delete(); escHotkey = nil end
    activeGhostty = {}
    activeUrls = {}
end

-- 把 URL 事件的參數解析成「面板正在顯示的那份清單」裡的一筆。面板關著、索引不是
-- 數字、或超出範圍時回傳 nil -- 也就是每一個不是本模組發起的請求。
local function resolveIndex(params, list)
    if not instance then return nil end
    if not params or not params.idx then return nil end
    local idx = tonumber(params.idx)
    if not idx or idx < 1 or idx > #list or idx % 1 ~= 0 then return nil end
    return list[idx]
end

function M.resolveUrl(params)     return resolveIndex(params, activeUrls) end
function M.resolveGhostty(params) return resolveIndex(params, activeGhostty) end

local function panelFrame()
    local f = screen.mainScreen():frame()
    local width = math.floor(f.w * config.FRAME.WIDTH_RATIO)
    local height = math.floor(f.h * config.FRAME.HEIGHT_RATIO)
    return {
        x = math.floor(f.x + (f.w - width) / 2),
        y = math.floor(f.y + f.h * config.FRAME.TOP_RATIO),
        w = width,
        h = height,
    }
end

-- 只把頁面需要的欄位挑出來，並附上它必須送回來的索引。網址本身從來不會交給頁面，
-- 所以頁面沒有辦法要求別的東西。
local function slim(items, offset, extraKeys)
    local out = {}
    for i, item in ipairs(items) do
        local entry = {
            idx = offset + i,
            text = item.text,
            subText = item.subText,
            iconUrl = item.iconUrl,
        }
        for _, key in ipairs(extraKeys or {}) do entry[key] = item[key] end
        table.insert(out, entry)
    end
    return out
end

local function buildHtml(safariItems, historyItems, ghosttyItems)
    local html = util.readFile(config.TEMPLATE_PATH)
    if not html then
        return nil, "HTML template not found: " .. config.TEMPLATE_PATH
    end

    local payload = json.encode({
        safari  = slim(safariItems, 0, nil),
        history = slim(historyItems, #safariItems, { "visitCount" }),
        ghostty = slim(ghosttyItems, 0, nil),
    })
    -- payload 是被拼進一個 <script> 區塊裡的，而唯一能提前結束那個區塊的只有字面上的
    -- "</script"。hs.json.encode 背後是 NSJSONSerialization，它剛好會輸出
    -- "<\/script>"，所以今天一個頁面標題還沒辦法逃出去 -- 但那是某個相依套件的實作
    -- 細節，不是保證，而書籤標題是攻擊者可控的輸入。在這裡跳脫，讓這份安全性寫在
    -- 這個檔案裡。
    payload = payload:gsub("</", "<\\/")
    payload = payload:gsub("%%", "%%%%")
    return html:gsub("__DATA__", payload, 1)
end

-- webview 剛建好時，鍵盤焦點不一定會落在搜尋框上，所以再補一次。
local function focusSearchField()
    if not instance then return end
    local w = instance:hswindow()
    if w then
        w:focus()
        pcall(function() w:becomeMain() end)
        pcall(function() w:becomeKey() end)
    end
    pcall(function()
        instance:evaluateJavaScript("document.getElementById('search').focus();")
    end)
end

-- 建立並顯示面板。回傳 true，或 false + 錯誤訊息。
function M.open(safariItems, historyItems, ghosttyItems, onClose)
    -- 先關掉舊面板再組頁面，跟舊版順序一致：組不出來時面板已經是關著的。
    M.close()

    local html, err = buildHtml(safariItems, historyItems, ghosttyItems)
    if not html then return false, err end

    instance = webview.new(panelFrame())

    -- 在 webview 存在「之後」才公布，因為 resolveIndex() 把關閉的面板當成
    -- 「根本沒有清單」。
    activeGhostty = ghosttyItems
    activeUrls = {}
    for _, item in ipairs(safariItems) do activeUrls[#activeUrls + 1] = item end
    for _, item in ipairs(historyItems) do activeUrls[#activeUrls + 1] = item end

    instance:transparent(true)
    instance:shadow(false)
    instance:windowStyle({ "borderless" })
    instance:allowTextEntry(true)
    instance:level(hs.drawing.windowLevels.floating)
    instance:html(html)
    instance:show()
    instance:bringToFront()

    focusSearchField()
    focusTimer = hs.timer.doAfter(0.05, focusSearchField)

    escHotkey = hs.hotkey.bind({}, "escape", onClose)
    return true
end

return M

-- hs.urlevent 的 handler。require 這個檔案就會註冊它們。
--
-- ── 為什麼 handler 收的是索引，不是指令 ──────────────────────────────────────
-- hs.urlevent handler 是一個「公開」入口。任何能打開網址的東西 -- 任何本機行程、
-- 任何網頁、郵件裡的一條連結 -- 都碰得到它們，而 Hammerspoon 分不出 spotlight
-- 頁面的請求和別人的請求。第一版綁的是：
--
--     spotlight-ghostty-run?cmd=<任意字串>
--
-- 然後把那個字串直接打進 Ghostty 再按 Return。那是以登入使用者身分執行、未經
-- 驗證、而且從一個網頁就構得到的任意指令執行。現在 handler 只接受「本模組自己
-- 載入的那份指令清單」的索引，而且面板沒開就拒絕動作，所以一個偽造網址最多只能
-- 執行一條使用者本來就寫在自己設定裡的指令 -- 或者更可能是，什麼都執行不到。
--
-- 同樣的道理適用於 spotlight-safari-open：網址在送進 AppleScript 之前會被檢查
-- 是不是 http(s) 而且不含控制字元。
local browser = require("modules.spotlight.browser")
local ghostty = require("modules.spotlight.ghostty")
local panel   = require("modules.spotlight.panel")

hs.urlevent.bind("spotlight-safari-open", function(_, params)
    local item = panel.resolveUrl(params)
    -- 自由文字搜尋是唯一沒有清單項目可指的情況，所以改帶使用者輸入的文字。
    if not item and panel.isOpen() and params and params.q then
        local url = browser.urlForQuery(params.q)
        if url then item = { url = url } end
    end
    if item and item.url then
        browser.open(item.url)
    end
    panel.close()
end)

hs.urlevent.bind("spotlight-ghostty-run", function(_, params)
    local item = panel.resolveGhostty(params)
    if item and item.command then
        ghostty.run(item.command)
    end
    panel.close()
end)

hs.urlevent.bind("spotlight-close", function()
    panel.close()
end)

-- Spotlight 風格的啟動器：一個 webview，內容是 Safari 書籤／瀏覽紀錄，加上一份
-- Ghostty 指令清單，由頁面送出的 hammerspoon:// URL 事件驅動。
-- 這個檔案只有快取和「打開面板」這一條流程，其餘見：
--   config.lua     可調參數 + 路徑
--   util.lua       檔案／暫存檔工具
--   safari.lua     書籤與瀏覽紀錄
--   ghostty.lua    指令清單與執行
--   browser.lua    開網址 / 查詢字串的解讀
--   panel.lua      webview 生命週期與樣板組裝
--   handlers.lua   hs.urlevent handler（含安全性不變式）
--   page.html      前端頁面
local config  = require("modules.spotlight.config")
local ghostty = require("modules.spotlight.ghostty")
local panel   = require("modules.spotlight.panel")
local safari  = require("modules.spotlight.safari")

require("modules.spotlight.handlers")   -- 註冊 URL handler

local M = {}

local cache = { time = 0, safari = nil, history = nil }

local function cachedSafariData()
    local now = hs.timer.secondsSinceEpoch()
    if cache.safari and (now - cache.time) <= config.CACHE_TTL_SECONDS then
        return cache.safari, cache.history
    end

    local items, err = safari.loadBookmarks()
    if not items then
        -- 書籤有可能因為 sandbox/TCC 而讀不到；沒有它照樣繼續。
        hs.alert.show(err or "Error loading Safari bookmarks", 2)
        items = {}
    end

    cache.safari = items
    cache.history = safari.loadHistory(items)
    cache.time = now
    return cache.safari, cache.history
end

function M.show()
    local safariItems, historyItems = cachedSafariData()
    -- 不快取：這是使用者手動編輯的一個小檔案，而「下次打開就吃到修改」正是重點。
    local ghosttyItems = ghostty.loadCommands()

    local ok, err = panel.open(safariItems, historyItems, ghosttyItems, panel.close)
    if not ok then hs.alert.show(err, 2) end
end

function M.stop()
    panel.close()
end

return M

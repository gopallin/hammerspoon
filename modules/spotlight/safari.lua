-- Safari 資料來源：書籤（Bookmarks.plist）與瀏覽紀錄（History.db 的私有複本）。
local config = require("modules.spotlight.config")
local util   = require("modules.spotlight.util")

local M = {}

local function faviconFor(host)
    if not config.USE_REMOTE_FAVICONS or not host then return nil end
    return "https://www.google.com/s2/favicons?sz=32&domain=" .. host
end

local function collectBookmarks(node, out, folder)
    if type(node) ~= "table" then return end

    if node.WebBookmarkType == "WebBookmarkTypeLeaf" and node.URLString and node.URIDictionary then
        local url = node.URLString
        local host = util.extractHost(url)
        table.insert(out, {
            text = node.URIDictionary.title or node.Title,
            subText = (folder and (folder .. "  •  " .. host)) or host,
            iconUrl = faviconFor(host),
            url = url,
        })
        return
    end

    local currentFolder = folder
    if node.WebBookmarkType == "WebBookmarkTypeFolder" and node.Title then
        currentFolder = folder and (folder .. "/" .. node.Title) or node.Title
    end

    if node.Children then
        for _, child in ipairs(node.Children) do
            collectBookmarks(child, out, currentFolder)
        end
    end
end

-- 回傳 items，或 nil + 錯誤訊息。
function M.loadBookmarks()
    local path = config.BOOKMARKS_PATH
    local data = hs.plist.read(path)

    if not data then
        -- 退路：改讀一份複本，這樣可以繞過活檔案上的鎖。
        local tmpPath = util.tempCopyPath("bookmarks")
        if util.copyFile(path, tmpPath) then
            data = hs.plist.read(tmpPath)
        end
        util.removeDbCopy(tmpPath)
    end

    if not data then
        return nil, ("Safari bookmarks not found or invalid at: " .. path)
    end

    local items = {}
    -- Safari 的 Bookmarks.plist 根節點有一個 'Children' 陣列
    if data.Children then
        for _, child in ipairs(data.Children) do
            collectBookmarks(child, items)
        end
    end
    return items
end

-- Safari history schema：history_items join history_visits。
local SQL = [[
    SELECT
        i.url,
        v.title,
        i.visit_count
    FROM
        history_items i
    JOIN
        history_visits v ON i.id = v.history_item
    ORDER BY
        v.visit_time DESC
    LIMIT %d
]]

-- 已經在書籤裡的網址會被排除，避免清單裡出現兩次。
function M.loadHistory(bookmarkItems)
    local bookmarkUrls = {}
    if bookmarkItems then
        for _, item in ipairs(bookmarkItems) do
            if item.url then bookmarkUrls[item.url] = true end
        end
    end

    local tmpPath = util.tempCopyPath("history")
    if not util.copyFile(config.HISTORY_PATH, tmpPath) then
        util.removeDbCopy(tmpPath)
        return {}
    end

    local db = hs.sqlite3.open(tmpPath)
    if not db then
        util.removeDbCopy(tmpPath)
        return {}
    end

    -- 用 pcall，因為格式錯誤或只複製到一半的資料庫會從 nrows() 拋出例外，
    -- 而那以前會跳過下面的 db:close() 和暫存檔清理。
    local items = {}
    local ok, err = pcall(function()
        for row in db:nrows(string.format(SQL, config.HISTORY_LIMIT)) do
            local host = util.extractHost(row.url)
            table.insert(items, {
                text = (row.title and row.title ~= "") and row.title or host,
                subText = host,
                url = row.url,
                visitCount = row.visit_count or 0,
                iconUrl = faviconFor(host),
            })
        end
    end)
    db:close()
    util.removeDbCopy(tmpPath)
    if not ok then
        print("[spotlight] history query failed: " .. tostring(err))
        return {}
    end

    -- 依網址去重，並排除書籤
    local seen = {}
    local unique = {}
    for _, item in ipairs(items) do
        if not seen[item.url] and not bookmarkUrls[item.url] then
            seen[item.url] = true
            table.insert(unique, item)
        end
    end
    return unique
end

return M

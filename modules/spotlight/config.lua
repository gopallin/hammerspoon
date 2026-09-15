local function expand(path)
    return (path:gsub("^~", os.getenv("HOME") or ""))
end

return {
    -- 書籤與瀏覽紀錄最多這麼久重讀一次。以前每次打開面板都會重讀 plist、整個複製
    -- History.db 再重跑查詢；光那個複製就是 5MB 以上、跑在 Hammerspoon 主 runloop
    -- 上的阻塞式檔案操作，而瀏覽紀錄不會在相隔一秒的兩次熱鍵之間改變。
    CACHE_TTL_SECONDS = 60,

    -- favicon 以前是從 https://www.google.com/s2/favicons?domain=<host> 抓的，
    -- 那等於每次打開面板就把「每一個書籤」和「最近 300 筆瀏覽紀錄」的網域交給
    -- Google。預設關閉；只用樣式表本來就會畫的那個佔位方塊，清單一樣好用。
    USE_REMOTE_FAVICONS = false,

    HISTORY_LIMIT = 300,

    BOOKMARKS_PATH        = expand("~/Library/Safari/Bookmarks.plist"),
    HISTORY_PATH          = expand("~/Library/Safari/History.db"),
    GHOSTTY_COMMANDS_PATH = expand("~/.hammerspoon/modules/spotlight/commands/ghostty_commands.json"),
    TEMPLATE_PATH         = expand("~/.hammerspoon/modules/spotlight/page.html"),

    -- 面板尺寸／位置，都是螢幕可用區的比例。
    FRAME = {
        WIDTH_RATIO  = 0.385,
        HEIGHT_RATIO = 0.25 * 2.5,
        TOP_RATIO    = 0.18,
    },
}

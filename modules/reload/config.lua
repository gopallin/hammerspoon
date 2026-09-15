return {
    WATCH_PATH = os.getenv("HOME") .. "/.hammerspoon/",

    -- ~/.hammerspoon 底下「不是設定」、因此絕對不能觸發 reload 的子目錄：
    --   /data/    產生出來的 wallpaper 頁面 + 影片。wallpaper 每次 start() 都會
    --             往那裡「寫」一個 .html，對它 reload 就是無限迴圈 -- 這正是那個
    --             模組把頁面放在 data/ 底下的原因。
    --   /.git/    git 在任何操作期間都在持續寫檔。
    --   /.claude/ Claude Code 會在授權時改寫 settings.local.json。它是 .json
    --             結尾，所以以前每按一次權限提示就會重啟整份 Hammerspoon 設定。
    IGNORED_DIRS = { "/data/", "/.git/", "/.claude/" },

    WATCHED_EXTENSIONS = { [".lua"] = true, [".html"] = true, [".json"] = true },
}

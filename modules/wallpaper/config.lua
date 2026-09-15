-- WALLPAPER_DIR 為什麼放在 data/ 底下：
--   1. modules/reload 會在 ~/.hammerspoon 底下任何 *.html 寫入時重載整份設定，
--      「除了」路徑含 /data/ 的，所以產生出來的播放器頁面必須住在 data/ 底下，
--      否則它會觸發無盡的重載。
--   2. WKWebView（透過 url()）只會給予它載入的那個頁面「所在目錄」的 file://
--      讀取權限，所以影片必須跟那個產生出來的頁面放在一起。
-- 把影片和產生的頁面一起放在 data/ 底下同時滿足兩者，而且仍然留在專案內
-- （data/ 有被 gitignore，所以影片不會被 commit）。
return {
    WALLPAPER_DIR  = "~/.hammerspoon/data/wallpaper",
    TEMPLATE_PATH  = "~/.hammerspoon/modules/wallpaper/page.html",
    GENERATED_PAGE = "_wallpaper.html",   -- 寫進 WALLPAPER_DIR，跟影片放一起

    EXTENSIONS = { mp4 = true, mov = true, m4v = true, webm = true },

    -- 秒；保險用的定期重檢，見 init.lua 的 startWatchers。
    FULLSCREEN_RECHECK_INTERVAL = 30,

    -- 視窗面積佔螢幕多少比例就算「蓋住桌面」。不用完全相等，因為所謂「最大化」的
    -- 視窗會停在選單列之前，在某些設定下也會停在 Dock 之前。
    COVERED_FRACTION = 0.94,
}

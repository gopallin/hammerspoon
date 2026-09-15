-- 把 page.html 樣板 + 找到的影片，組成放在影片旁邊的播放器頁面。
local config = require("modules.wallpaper.config")
local util   = require("modules.wallpaper.util")

local M = {}

-- 回傳產生出來那個頁面的 file:// URL，失敗回傳 nil。
function M.prepare()
    local dir = util.expandTilde(config.WALLPAPER_DIR)
    util.ensureDir(dir)

    local video = util.findVideo(dir)
    if not video then
        print("[wallpaper] no video (.mp4/.mov/.m4v/.webm) found in " .. dir)
        return nil
    end

    local template = util.readFile(util.expandTilde(config.TEMPLATE_PATH))
    if not template then
        print("[wallpaper] template missing: " .. config.TEMPLATE_PATH)
        return nil
    end

    local html = template:gsub("__VIDEO_SRC__", util.urlEncode(video), 1)
    local pagePath = dir .. "/" .. config.GENERATED_PAGE
    if not util.writeFile(pagePath, html) then
        print("[wallpaper] could not write " .. pagePath)
        return nil
    end

    print("[wallpaper] using video: " .. video)
    return "file://" .. pagePath
end

return M

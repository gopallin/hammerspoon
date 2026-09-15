-- 存檔即重載：監看 ~/.hammerspoon，命中設定檔就 hs.reload()。
local config = require("modules.reload.config")
local filter = require("modules.reload.filter")

local M = {}

local watcher = nil

function M.start()
    M.stop()

    watcher = hs.pathwatcher.new(config.WATCH_PATH, function(files)
        if filter.shouldReload(files) then hs.reload() end
    end)
    watcher:start()

    hs.notify.new({
        title = "Hammerspoon",
        informativeText = "Hammerspoon Setting Reloaded 🚀"
    }):send()
end

function M.stop()
    if watcher then watcher:stop(); watcher = nil end
end

return M

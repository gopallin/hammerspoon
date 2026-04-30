local M = {}
local watcher = nil

function M.start()
  local function reloadConfig(files)
    for _, file in ipairs(files) do
      if file:sub(-4) == ".lua" or file:sub(-5) == ".html" or file:sub(-5) == ".json" then
        hs.reload()
        return
      end
    end
  end

  if watcher then
    watcher:stop()
    watcher = nil
  end
  watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig)
  watcher:start()

  hs.notify.new({
    title = "Hammerspoon",
    informativeText = "Hammerspoon Setting Reloaded 🚀"
  }):send()
end

return M

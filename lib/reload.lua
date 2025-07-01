local M = {}

function M.start()
  local function reloadConfig(files)
    for _, file in ipairs(files) do
      if file:sub(-4) == ".lua" then
        hs.reload()
        return
      end
    end
  end

  local watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig)
  watcher:start()

  hs.notify.new({
    title = "Hammerspoon",
    informativeText = "Hammerspoon Setting Reloaded 🚀"
  }):send()
end

return M

local M = {}

function M.start()
  local function reloadConfig(files)
    for _, file in ipairs(files) do
      if file:sub(-4) == ".lua" then
        -- Add a small delay to prevent rapid reloads if multiple files are saved quickly
        hs.timer.doAfter(0.1, function()
          hs.reload()
          hs.notify.new({
            title = "Hammerspoon",
            informativeText = "Hammerspoon Config Reloaded 🚀"
          }):send()
        end)
        return
      end
    end
  end

  local watcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig)
  watcher:start()
end

return M
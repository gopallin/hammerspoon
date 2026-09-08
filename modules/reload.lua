local M = {}
local watcher = nil

-- Subtrees under ~/.hammerspoon that are not config, and must never trigger a
-- reload:
--   /data/    generated wallpaper page + videos. wallpaper/init.lua WRITES a
--             .html in there on every start, so reloading on it is an infinite
--             loop -- this is why that module keeps its page under data/.
--   /.git/    git writes constantly during any operation.
--   /.claude/ Claude Code rewrites settings.local.json as permissions are
--             granted. It ends in .json, so every permission prompt used to
--             restart the entire Hammerspoon config mid-session.
local IGNORED_DIRS = { "/data/", "/.git/", "/.claude/" }

local WATCHED_EXTENSIONS = { [".lua"] = true, [".html"] = true, [".json"] = true }

local function isIgnored(path)
  for _, dir in ipairs(IGNORED_DIRS) do
    if path:find(dir, 1, true) then return true end
  end
  return false
end

-- Matched against the BASENAME. Against the full path, a dotted directory such
-- as ~/.hammerspoon would be the last dot in strings like "/x/.lua/notes", and
-- reasoning about whether that can collide is harder than just not asking.
local function isConfigFile(path)
  local name = path:match("([^/]+)$") or path
  return WATCHED_EXTENSIONS[name:match("(%.[^.]+)$") or ""] or false
end

function M.start()
  local function reloadConfig(files)
    for _, file in ipairs(files) do
      if not isIgnored(file) and isConfigFile(file) then
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

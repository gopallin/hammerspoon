-- 「這次檔案異動該不該重載設定」的純判斷。沒有狀態。
local config = require("modules.reload.config")

local M = {}

local function isIgnored(path)
    for _, dir in ipairs(config.IGNORED_DIRS) do
        if path:find(dir, 1, true) then return true end
    end
    return false
end

-- 比對「檔名」而不是完整路徑：對完整路徑來說，像 ~/.hammerspoon 這種帶點的
-- 目錄會讓 "/x/.lua/notes" 這類字串的最後一個點落在目錄名上，而要推敲那會不會
-- 撞在一起，比乾脆不要問還難。
local function isConfigFile(path)
    local name = path:match("([^/]+)$") or path
    return config.WATCHED_EXTENSIONS[name:match("(%.[^.]+)$") or ""] or false
end

function M.shouldReload(files)
    for _, file in ipairs(files) do
        if not isIgnored(file) and isConfigFile(file) then return true end
    end
    return false
end

return M

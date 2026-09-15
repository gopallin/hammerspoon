-- 檔案與路徑的小工具。沒有狀態。
local fs = require("hs.fs")
local config = require("modules.wallpaper.config")

local M = {}

function M.expandTilde(path)
    return (path:gsub("^~", os.getenv("HOME") or ""))
end

-- mkdir -p：建立 path 以及所有缺少的上層目錄（WALLPAPER_DIR 是多層的）。
function M.ensureDir(path)
    if not path or path == "" or fs.attributes(path, "mode") == "directory" then return end
    M.ensureDir(path:match("(.*)/[^/]+$"))
    fs.mkdir(path)
end

function M.readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

function M.writeFile(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

-- 把純檔名做 percent-encode，讓空白／unicode 能活著放進 <source src>。
function M.urlEncode(str)
    return (str:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- dir 底下第一支影片（依字母序），沒有就回傳 nil。只看該層，不遞迴。
function M.findVideo(dir)
    if fs.attributes(dir, "mode") ~= "directory" then return nil end
    local names = {}
    for name in fs.dir(dir) do
        local ext = name:match("%.([^.]+)$")
        if ext and config.EXTENSIONS[ext:lower()] then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names[1]
end

return M

-- 檔案、暫存檔與 URL 的小工具。沒有狀態。
local M = {}

function M.readFile(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

-- SQLite 會在它打開的那個檔案旁邊建立 <db>-shm 和 <db>-wal。只對資料庫路徑呼叫
-- os.remove() 會讓那兩個每次打開都留下來：這個問題被發現時，/tmp 裡已經累積了
-- 114 個檔案、1.8MB。每一條離開路徑都要走這裡。
function M.removeDbCopy(path)
    if not path then return end
    os.remove(path)
    os.remove(path .. "-shm")
    os.remove(path .. "-wal")
end

-- 複製一份私有的，讓 SQLite 永遠不會碰到 Safari 的活資料庫。用純 Lua io 而不是
-- os.execute("cp")：os.execute 會 fork 一個 shell，並在整趟往返期間阻塞主 runloop，
-- 而那個 shell 在這裡什麼也沒買到。
function M.copyFile(src, dst)
    local input = io.open(src, "rb")
    if not input then return false end
    local output = io.open(dst, "wb")
    if not output then input:close(); return false end

    local ok = true
    while true do
        local chunk = input:read(1024 * 1024)
        if not chunk then break end
        if not output:write(chunk) then ok = false; break end
    end

    input:close()
    output:close()
    if not ok then M.removeDbCopy(dst) end
    return ok
end

-- 固定檔名，放在 TMPDIR 底下 -- 在 macOS 上那是一個每使用者專屬的目錄（mode 700），
-- 而不是 os.tmpname() 給的那個全世界可寫的 /tmp。刻意用固定而不是唯一的名字：
-- 一個登入 session 只會有一個 Hammerspoon，所以沒有人可以撞名，而固定的名字代表
-- 崩潰留下的孤兒複本會在下次打開時被覆寫，而不是累積 -- 舊做法就是這樣堆到 114 個的。
function M.tempCopyPath(tag)
    local dir = os.getenv("TMPDIR") or "/tmp"
    if dir:sub(-1) ~= "/" then dir = dir .. "/" end
    return dir .. "hs-spotlight-" .. tag
end

function M.extractHost(url)
    if not url then return nil end
    return url:match("^%w+://([^/]+)") or url
end

return M

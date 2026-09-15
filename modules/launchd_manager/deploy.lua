-- 把 config.lua 裡的排程寫進 ~/Library/LaunchAgents 並用 launchctl 載入，
-- 順便清掉已經從設定裡移除的舊排程。
local schedules = require("modules.launchd_manager.config")
local plist     = require("modules.launchd_manager.plist")

local M = {}

-- 給 /bin/sh 用的單引號包裝。hs.execute() 是把字串交給 shell 的，而下面的路徑是
-- 用 $HOME 組出來的 -- 在清理那一段裡，更是用「從檔案系統上讀到的名字」組出來的，
-- 所以任何一邊出現一個單引號或空白，就足以改變實際執行的東西。包在單引號裡並跳脫
-- 內嵌的單引號，是唯一不需要再對內容多做推敲的形式。
local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function cleanupObsolete(dir)
    local active = {}
    for _, schedule in ipairs(schedules) do
        active[schedule.label .. ".plist"] = true
    end

    for file in hs.fs.dir(dir) do
        if file:sub(1, 9) == "com.user." and file:sub(-6) == ".plist" and not active[file] then
            local path = dir .. "/" .. file
            print("🧹 清理已廢棄排程: " .. file)
            hs.execute("launchctl unload " .. shellQuote(path))
            os.remove(path)
        end
    end
end

-- 寫入並載入一筆排程，成功回傳 true。
local function install(dir, schedule)
    local name = schedule.label .. ".plist"
    local path = dir .. "/" .. name

    local file, err = io.open(path, "w")
    if not file then
        print("❌ 寫入失敗 " .. path .. ": " .. tostring(err))
        return false
    end
    file:write(plist.generate(schedule))
    file:close()

    hs.execute("launchctl unload " .. shellQuote(path))
    local output, status = hs.execute("launchctl load " .. shellQuote(path))
    if not status then
        print("❌ 載入失敗 " .. name .. ": " .. output)
        return false
    end

    print("✅ 部署成功: " .. name)
    return true
end

function M.run()
    local dir = os.getenv("HOME") .. "/Library/LaunchAgents"
    hs.execute("mkdir -p " .. shellQuote(dir))

    cleanupObsolete(dir)

    local successCount = 0
    for _, schedule in ipairs(schedules) do
        if install(dir, schedule) then successCount = successCount + 1 end
    end

    hs.alert.show("Launchd 部署完成: " .. successCount .. "/" .. #schedules)
end

return M

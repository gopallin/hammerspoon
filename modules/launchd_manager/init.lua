local launchd_manager = {}
-- 引入排程資料
local schedules = require("modules.launchd_manager.schedules")

local function generatePlist(config)
    local plist = {}
    table.insert(plist, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(plist, '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
    table.insert(plist, '<plist version="1.0">')
    table.insert(plist, '<dict>')
    
    table.insert(plist, '    <key>Label</key>')
    table.insert(plist, string.format('    <string>%s</string>', config.label))
    
    table.insert(plist, '    <key>ProgramArguments</key>')
    table.insert(plist, '    <array>')
    for _, arg in ipairs(config.programArguments) do
        table.insert(plist, string.format('        <string>%s</string>', arg))
    end
    table.insert(plist, '    </array>')
    
    if config.calendar then
        table.insert(plist, '    <key>StartCalendarInterval</key>')
        table.insert(plist, '    <dict>')
        local keys = {"Weekday", "Hour", "Minute"}
        for _, k in ipairs(keys) do
            if config.calendar[k] then
                table.insert(plist, string.format('        <key>%s</key>', k))
                table.insert(plist, string.format('        <integer>%d</integer>', config.calendar[k]))
            end
        end
        table.insert(plist, '    </dict>')
    end
    
    if config.stdOut then
        table.insert(plist, '    <key>StandardOutPath</key>')
        table.insert(plist, string.format('    <string>%s</string>', config.stdOut))
    end
    
    if config.stdErr then
        table.insert(plist, '    <key>StandardErrorPath</key>')
        table.insert(plist, string.format('    <string>%s</string>', config.stdErr))
    end
    
    table.insert(plist, '</dict>')
    table.insert(plist, '</plist>')
    
    return table.concat(plist, "\n")
end

function launchd_manager.deploy()
    local launchAgentsDir = os.getenv("HOME") .. "/Library/LaunchAgents"
    hs.execute("mkdir -p " .. launchAgentsDir)
    
    local activePlists = {}
    for _, config in ipairs(schedules) do
        activePlists[config.label .. ".plist"] = true
    end
    
    for file in hs.fs.dir(launchAgentsDir) do
        if file:sub(1, 9) == "com.user." and file:sub(-6) == ".plist" then
            if not activePlists[file] then
                local obsoletePath = launchAgentsDir .. "/" .. file
                print("🧹 清理已廢棄排程: " .. file)
                hs.execute("launchctl unload " .. obsoletePath)
                os.remove(obsoletePath)
            end
        end
    end
    
    local successCount = 0
    for _, config in ipairs(schedules) do
        local plistName = config.label .. ".plist"
        local plistPath = launchAgentsDir .. "/" .. plistName
        local plistContent = generatePlist(config)
        
        local file, err = io.open(plistPath, "w")
        if file then
            file:write(plistContent)
            file:close()
            
            hs.execute("launchctl unload " .. plistPath)
            local output, status = hs.execute("launchctl load " .. plistPath)
            
            if status then
                print("✅ 部署成功: " .. plistName)
                successCount = successCount + 1
            else
                print("❌ 載入失敗 " .. plistName .. ": " .. output)
            end
        else
            print("❌ 寫入失敗 " .. plistPath .. ": " .. tostring(err))
        end
    end
    
    hs.alert.show("Launchd 部署完成: " .. successCount .. "/" .. #schedules)
end

function launchd_manager.start()
    _G.deployLaunchd = launchd_manager.deploy
end

return launchd_manager

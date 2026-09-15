-- 由一筆排程設定產生 LaunchAgent 的 plist 內容。純字串組裝。
local M = {}

-- 產生出來的 plist 裡的文字節點來自設定值。沒跳脫的話，一個含有 & 或 < 的路徑
-- 會產生出 launchctl 會靜默拒絕載入的 plist。
local function xmlEscape(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local CALENDAR_KEYS = { "Weekday", "Hour", "Minute" }

function M.generate(schedule)
    local lines = {}
    local function add(fmt, ...)
        lines[#lines + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    add('<?xml version="1.0" encoding="UTF-8"?>')
    add('<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">')
    add('<plist version="1.0">')
    add('<dict>')

    add('    <key>Label</key>')
    add('    <string>%s</string>', xmlEscape(schedule.label))

    add('    <key>ProgramArguments</key>')
    add('    <array>')
    for _, arg in ipairs(schedule.programArguments) do
        add('        <string>%s</string>', xmlEscape(arg))
    end
    add('    </array>')

    if schedule.calendar then
        add('    <key>StartCalendarInterval</key>')
        add('    <dict>')
        for _, k in ipairs(CALENDAR_KEYS) do
            if schedule.calendar[k] then
                add('        <key>%s</key>', k)
                add('        <integer>%d</integer>', schedule.calendar[k])
            end
        end
        add('    </dict>')
    end

    if schedule.stdOut then
        add('    <key>StandardOutPath</key>')
        add('    <string>%s</string>', xmlEscape(schedule.stdOut))
    end

    if schedule.stdErr then
        add('    <key>StandardErrorPath</key>')
        add('    <string>%s</string>', xmlEscape(schedule.stdErr))
    end

    add('</dict>')
    add('</plist>')

    return table.concat(lines, "\n")
end

return M

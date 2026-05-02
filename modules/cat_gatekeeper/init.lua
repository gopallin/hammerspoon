local M = {}

local function expandTilde(path)
    return (path:gsub("^~", os.getenv("HOME") or ""))
end

local scriptPath = expandTilde("~/.hammerspoon/modules/cat_gatekeeper/scripts/cat_gatekeeper.py")
local htmlTemplatePath = expandTilde("~/.hammerspoon/modules/cat_gatekeeper/assets/reminder.html")
local gifPath = expandTilde("~/.hammerspoon/modules/cat_gatekeeper/assets/cat_animation.gif")

local lastActiveApp = nil
local lastActiveTime = hs.timer.secondsSinceEpoch()
local trackingTimer = nil
local reminderWebView = nil
local reminderShown = false
local lastReminderSeconds = 0
local json = require("hs.json")
local notification = require("modules.notification")

local function fileToBase64(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return hs.base64.encode(content)
end

function M.formatSeconds(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    return string.format("%d 小時 %d 分", hours, mins)
end

function M.getStatus()
    local output = hs.execute(string.format("python3 %s status", scriptPath))
    if output == "" then
        return nil
    end

    local status = json.decode(output)
    return status
end

function M.trackApp(bundleId, duration)
    if not bundleId or bundleId == "" then
        return
    end

    hs.execute(string.format("python3 %s track '%s' %d", scriptPath, bundleId, duration))
end

function M.showReminder()
    if reminderShown then
        return
    end

    reminderShown = true
    local status = M.getStatus()

    if not status then
        hs.alert("無法獲取使用狀態")
        return
    end

    -- Get screen info
    local screen = hs.screen.mainScreen()
    local screenFrame = screen:frame()

    -- Read HTML template
    local htmlFile = io.open(htmlTemplatePath, "r")
    if not htmlFile then
        hs.alert("無法讀取提醒模板")
        return
    end
    local htmlContent = htmlFile:read("*a")
    htmlFile:close()

    -- Convert GIF to Base64 data URL
    local gifBase64 = fileToBase64(gifPath)
    local gifDataUrl = gifBase64 and ("data:image/gif;base64," .. gifBase64) or ""

    -- Replace placeholders
    htmlContent = htmlContent:gsub("__CAT_GIF__", gifDataUrl)
    htmlContent = htmlContent:gsub("__TOTAL_TIME__", M.formatSeconds(status.total_seconds))
    htmlContent = htmlContent:gsub("__LIMIT_TIME__", M.formatSeconds(status.limit_seconds))

    -- Create WebView
    reminderWebView = hs.webview.new({
        x = screenFrame.x,
        y = screenFrame.y,
        w = screenFrame.w,
        h = screenFrame.h
    })

    -- Set HTML content
    reminderWebView:html(htmlContent)

    -- Add keyboard handler for ESC key
    local hotkey = hs.hotkey.bind({}, "escape", function()
        M.closeReminder()
    end)

    reminderWebView:show()

    -- Auto-hide after 3 minutes
    hs.timer.doAfter(180, function()
        if reminderShown and reminderWebView then
            M.closeReminder()
        end
    end)
end

function M.closeReminder()
    if reminderWebView then
        reminderWebView:delete()
        reminderWebView = nil
    end
    reminderShown = false
end

function M.trackAndCheck()
    local now = hs.timer.secondsSinceEpoch()
    local currentApp = hs.application.frontmostApplication()

    if not currentApp then
        return
    end

    local bundleId = currentApp:bundleID()

    -- If app changed, record previous app's time
    if bundleId ~= lastActiveApp then
        if lastActiveApp then
            local duration = math.floor(now - lastActiveTime)
            if duration > 0 then
                M.trackApp(lastActiveApp, duration)
            end
        end
        lastActiveApp = bundleId
        lastActiveTime = now
    else
        -- Same app still active, accumulate time every 5 seconds
        local duration = math.floor(now - lastActiveTime)
        if duration >= 5 then
            M.trackApp(bundleId, duration)
            lastActiveTime = now
        end
    end

    -- Check if limit exceeded
    local status = M.getStatus()
    if status and status.exceeded and not reminderShown then
        local limitSeconds = status.limit_seconds
        -- Only show reminder if usage exceeded limit + last reminder threshold
        if status.total_seconds >= lastReminderSeconds + limitSeconds then
            M.showReminder()
            lastReminderSeconds = status.total_seconds
        end
    end
end

function M.start()
    trackingTimer = hs.timer.doEvery(5, function()
        M.trackAndCheck()
    end)

    hs.window.filter.default:subscribe(hs.window.filter.windowFocused, function()
        M.trackAndCheck()
    end)

    notification.showStatus("Cat Gatekeeper 已啟動")
end

function M.stop()
    if trackingTimer then
        trackingTimer:stop()
        trackingTimer = nil
    end

    if reminderWebView then
        reminderWebView:delete()
        reminderWebView = nil
    end

    notification.showStatus("Cat Gatekeeper 已停止")
end

return M

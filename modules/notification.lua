local M = {}

-- Configuration
local NOTIFICATION_W = 220
local NOTIFICATION_H = 60
local NOTIFICATION_X_OFFSET = 40
local NOTIFICATION_Y_OFFSET = 40
local NOTIFICATION_SPACING = 10
local NOTIFICATION_BG_ALPHA = 0.7
local NOTIFICATION_DURATION = 2.0
local MAX_QUEUE_LENGTH = 5

-- State
local notificationQueue = {}

local function createNotificationCanvas(message, yPos)
    local screen = hs.screen.mainScreen()
    local f = screen:fullFrame()

    local x = f.w - NOTIFICATION_W - NOTIFICATION_X_OFFSET
    local y = NOTIFICATION_Y_OFFSET + yPos

    local canvas = hs.canvas.new({x = x, y = y, w = NOTIFICATION_W, h = NOTIFICATION_H})
    canvas:level(hs.drawing.windowLevels.overlay)

    -- Background
    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = {white = 0, alpha = NOTIFICATION_BG_ALPHA},
        roundedRectRadii = {xRadius = 10, yRadius = 10},
    }

    -- Text
    canvas[2] = {
        type = "text",
        text = message,
        textFont = ".AppleSystemUIFontBold",
        textSize = 18,
        textColor = {white = 1, alpha = 1},
        textAlignment = "center",
        frame = {x = "5%", y = "20%", w = "90%", h = "60%"}
    }

    return canvas
end

local function updatePositions()
    local screen = hs.screen.mainScreen()
    local f = screen:fullFrame()

    local yOffset = 0
    for i = #notificationQueue, 1, -1 do
        local notification = notificationQueue[i]
        if notification.canvas then
            local x = f.w - NOTIFICATION_W - NOTIFICATION_X_OFFSET
            local y = NOTIFICATION_Y_OFFSET + yOffset

            if y + NOTIFICATION_H > f.h then
                notification.canvas:hide()
            else
                notification.canvas:frame({x = x, y = y, w = NOTIFICATION_W, h = NOTIFICATION_H})
                notification.canvas:show()
            end
        end
        yOffset = yOffset + NOTIFICATION_H + NOTIFICATION_SPACING
    end
end

local function removeNotification(id)
    for i, notification in ipairs(notificationQueue) do
        if notification.id == id then
            if notification.canvas then
                notification.canvas:delete()
            end
            if notification.timer then
                notification.timer:stop()
            end
            table.remove(notificationQueue, i)
            updatePositions()
            break
        end
    end
end

function M.showStatus(message)
    if not message or message == "" then return end

    if #notificationQueue >= MAX_QUEUE_LENGTH then
        removeNotification(notificationQueue[1].id)
    end

    local id = hs.timer.secondsSinceEpoch()
    local canvas = createNotificationCanvas(message, 0)

    local notification = {
        id = id,
        canvas = canvas,
        timer = nil
    }
    table.insert(notificationQueue, notification)
    updatePositions()

    notification.timer = hs.timer.doAfter(NOTIFICATION_DURATION, function()
        removeNotification(id)
    end)
end

function M.stop()
    for i = #notificationQueue, 1, -1 do
        local notification = notificationQueue[i]
        if notification.timer then
            notification.timer:stop()
        end
        if notification.canvas then
            notification.canvas:delete()
        end
    end
    notificationQueue = {}
end

return M

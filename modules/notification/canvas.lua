-- 通知的畫面：建立單張 canvas，以及把整個佇列重新排版。
-- 這裡不持有佇列，佇列由 init.lua 傳進來。
local config = require("modules.notification.config")

local M = {}

function M.create(message)
    local f = hs.screen.mainScreen():fullFrame()
    local canvas = hs.canvas.new({
        x = f.w - config.WIDTH - config.X_OFFSET,
        y = config.Y_OFFSET,
        w = config.WIDTH,
        h = config.HEIGHT,
    })
    canvas:level(hs.drawing.windowLevels.overlay)

    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 0, alpha = config.BG_ALPHA },
        roundedRectRadii = { xRadius = 10, yRadius = 10 },
    }

    canvas[2] = {
        type = "text",
        text = message,
        textFont = ".AppleSystemUIFontBold",
        textSize = 18,
        textColor = { white = 1, alpha = 1 },
        textAlignment = "center",
        frame = { x = "5%", y = "20%", w = "90%", h = "60%" },
    }

    return canvas
end

-- 由新到舊由上往下疊；排到超出螢幕底部的就先藏起來。
function M.layout(queue)
    local f = hs.screen.mainScreen():fullFrame()
    local x = f.w - config.WIDTH - config.X_OFFSET

    local yOffset = 0
    for i = #queue, 1, -1 do
        local canvas = queue[i].canvas
        if canvas then
            local y = config.Y_OFFSET + yOffset
            if y + config.HEIGHT > f.h then
                canvas:hide()
            else
                canvas:frame({ x = x, y = y, w = config.WIDTH, h = config.HEIGHT })
                canvas:show()
            end
        end
        yOffset = yOffset + config.HEIGHT + config.SPACING
    end
end

return M

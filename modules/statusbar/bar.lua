-- 螢幕底部那條 bar 本身：建立、跟著螢幕變動調整、換字、命中測試。
local config = require("modules.statusbar.config")

local M = {}

local canvas = nil
local frame = nil
local lastText = nil

local function expectedFrame()
    local f = hs.screen.mainScreen():fullFrame()
    return { x = f.x, y = f.y + f.h - config.BAR_HEIGHT, w = f.w, h = config.BAR_HEIGHT }
end

function M.create()
    frame = expectedFrame()
    canvas = hs.canvas.new(frame)
    canvas:level(hs.canvas.windowLevels.floating)
    canvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 0, alpha = config.BACKGROUND_ALPHA },
    }
    canvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFont",
        textSize = config.FONT_SIZE,
        textColor = { white = 1, alpha = 0.9 },
        textAlignment = "center",
        frame = { x = "0%", y = "12%", w = "100%", h = "88%" },
    }
    lastText = nil
    canvas:show()
end

function M.exists()
    return canvas ~= nil
end

function M.refreshFrame()
    if not canvas then return end
    local want = expectedFrame()
    if not frame or frame.x ~= want.x or frame.y ~= want.y
        or frame.w ~= want.w or frame.h ~= want.h then
        frame = want
        canvas:frame(frame)
    end
end

function M.setText(text)
    if not canvas then return end
    -- 對 canvas 元素屬性賦值會讓圖層失效，不管值有沒有變 --
    -- 所以沒有變化的 bar 以前仍然每 5 秒重繪一次。
    if text ~= lastText then
        canvas[2].text = text
        lastText = text
    end
end

-- 點是否落在 bar 上。bar 橫跨整個螢幕寬度，先判 y 就能排掉絕大多數的點。
function M.contains(point)
    if not (canvas and frame) then return false end
    return point.y >= frame.y and point.y <= frame.y + frame.h
        and point.x >= frame.x and point.x <= frame.x + frame.w
end

function M.hide()
    if canvas then canvas:hide() end
end

function M.show()
    if canvas then canvas:show() end
end

function M.destroy()
    if canvas then canvas:delete(); canvas = nil end
    frame, lastText = nil, nil
end

return M

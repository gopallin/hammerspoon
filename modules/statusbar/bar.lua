-- 螢幕底部那條 bar 本身：建立、跟著螢幕變動調整、換字、命中測試。
local config = require("modules.statusbar.config")

local M = {}

local canvas = nil
local frame = nil
local lastText = nil

-- canvas 的 text 元素只認得 textColor，沒有描邊屬性；要描邊就得自己組一個
-- hs.styledtext，這時 textFont/textSize/textColor 會被忽略，全部改由這裡指定。
--
-- 字畫兩層，是為了讓外框「只往外長」。strokeWidth 的描邊以字形輪廓為中心，往
-- 兩邊各長一半 -- 往內那一半會吃掉白色內裡，所以單層描邊加粗到看得見的程度，
-- 字就開始變瘦、糊成一團。底層先畫一個描邊＋填色都是黑的「胖版」字，上層再蓋
-- 原尺寸的白字把往內那半補回去，白色就完全不受 TEXT_STROKE_WIDTH 影響。
local function styled(text, attrs)
    local a = {
        font = { name = ".AppleSystemUIFont", size = config.FONT_SIZE },
        paragraphStyle = { alignment = "center" },
    }
    for k, v in pairs(attrs) do a[k] = v end
    return hs.styledtext.new(text, a)
end

local function outlineLayer(text)
    return styled(text, {
        color = config.TEXT_STROKE_COLOR,
        strokeColor = config.TEXT_STROKE_COLOR,
        strokeWidth = -config.TEXT_STROKE_WIDTH,
    })
end

-- 不透明，不是 0.9 -- 底下是黑色的胖版字，只要透一點點黑就會把字染灰。
local function fillLayer(text)
    return styled(text, { color = { white = 1, alpha = 1 } })
end

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
    -- 兩層共用同一個 frame，字才會剛好疊在一起；後面的索引畫在上面。
    local textFrame = { x = "0%", y = "12%", w = "100%", h = "88%" }
    canvas[2] = { type = "text", text = outlineLayer(""), frame = textFrame }
    canvas[3] = { type = "text", text = fillLayer(""), frame = textFrame }
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
        canvas[2].text = outlineLayer(text)
        canvas[3].text = fillLayer(text)
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

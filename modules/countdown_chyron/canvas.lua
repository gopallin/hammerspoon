-- 跑馬燈的畫面：建立 canvas、建立字元元素、每幀更新。
local config   = require("modules.countdown_chyron.config")
local geometry = require("modules.countdown_chyron.geometry")

local M = {}

local canvas = nil
local builtLength = 0    -- 目前這組元素是為幾個字建的
local lastText = ""      -- 目前指派在那些元素上的字

local LEAD_COLOR = { red = 0.3, green = 1, blue = 0.5, alpha = config.LEAD_ALPHA }
local BODY_COLOR = { white = 1, alpha = config.TEXT_ALPHA }

local function log(fmt, ...)
    print(string.format("[countdown_chyron] " .. fmt, ...))
end

function M.create(rect)
    canvas = hs.canvas.new(rect)
    canvas:level(hs.drawing.windowLevels.overlay)
    canvas:clickActivating(false)
    canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    builtLength = 0
    lastText = ""
end

function M.exists()   return canvas ~= nil end
function M.isShowing() return canvas ~= nil and canvas:isShowing() end
function M.show()     if canvas then canvas:show() end end
function M.hide()     if canvas then canvas:hide() end end
function M.setFrame(rect) if canvas then canvas:frame(rect) end end
function M.setAlpha(a)    if canvas then canvas:alpha(a) end end

function M.destroy()
    if canvas then canvas:delete(); canvas = nil end
    builtLength = 0
    lastText = ""
end

-- 每個字數只建「一次」元素清單。舊版每幀重建約 57 張 Lua table（每個字一個元素
-- 加 frame 加 color）並呼叫 replaceElements()；在 6 FPS 下，那是每秒約 350 張
-- 短命 table 的純 GC 壓力，而這張圖每幀真正會變的只有少數幾個 y 值。顏色、字型和
-- 字框大小永遠不變，所以在這裡寫一次就再也不碰。
local function buildElements(text)
    local elements = {}
    for i = 1, #text do
        elements[i] = {
            type = "text",
            text = text:sub(i, i),
            -- 一次排好，放在它在整串字中的位移上。之後整個欄位是用 canvas
            -- transformation 去捲的，所以這些永遠不會再變 -- 見 M.render()。
            frame = {
                x = 0,
                y = (i - 1) * config.GLYPH_STEP,
                w = geometry.COLUMN_WIDTH,
                h = geometry.GLYPH_BOX,
            },
            textColor = (i == 1) and LEAD_COLOR or BODY_COLOR,
            textFont = "Menlo-Bold",
            textSize = config.FONT_SIZE,
            -- 靠右，不是置中：這讓 COLUMN_MARGIN 成為那個字面意義上「螢幕邊緣到
            -- 數字的距離」旋鈕。置中的話真正的間距會是 COLUMN_MARGIN 加上欄位
            -- 寬鬆處的一半，於是 COLUMN_WIDTH 也會偷偷把字移動。
            textAlignment = "right",
        }
    end

    canvas:replaceElements(elements)
    builtLength = #text
    lastText = text
    log("rebuilt %d elements", builtLength)
end

-- text = 要顯示的倒數字串；leadY = 領頭字上緣在 canvas 座標系的 y。
function M.render(text, leadY)
    if not M.isShowing() then return end

    -- 只有啟動時，以及天數少掉一位數的那一天才會發生。
    if builtLength ~= #text then buildElements(text) end

    -- 字：只改真的變了的那幾個。秒數往前跳只會改寫其中一兩個，不是全部十四個。
    if text ~= lastText then
        for i = 1, builtLength do
            local char = text:sub(i, i)
            if char ~= lastText:sub(i, i) then
                canvas:elementAttribute(i, "text", char)
            end
        end
        lastText = text
    end

    -- 位置：「一次」canvas 層級的平移，而不是每個字寫一次 frame。字在建立時就已經
    -- 坐在它於整串字中的位移上（見 buildElements），所以捲動是欄位的性質，不是
    -- 每個字元的性質。舊版每幀對全部十四個元素各寫一次 frame -- 為了表達一個數字，
    -- 每秒六次、每次十四趟 Lua->ObjC 穿越加十四次元素失效。
    canvas:transformation(hs.canvas.matrix.translate(0, leadY))
end

return M

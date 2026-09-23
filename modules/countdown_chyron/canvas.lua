-- 跑馬燈的畫面：建立 canvas、建立字元元素、每幀更新。
local config   = require("modules.countdown_chyron.config")
local geometry = require("modules.countdown_chyron.geometry")

local M = {}

-- 兩張 canvas，不是一張 -- 理由見下面 setAlpha() 上方那段。
local leadCanvas = nil   -- 只有領頭字（最高位數字）
local bodyCanvas = nil   -- 其餘所有字
local builtLength = 0    -- 目前這組元素是為幾個字建的
local lastText = ""      -- 目前指派在那些元素上的字

-- 不透明。半透明是整張 canvas 的性質，不是顏色的性質 -- 見 M.setAlpha()。
local LEAD_COLOR   = { red = 0.3, green = 1, blue = 0.5 }
local BODY_COLOR   = { white = 1 }
local STROKE_COLOR = config.TEXT_STROKE_COLOR

local function log(fmt, ...)
    print(string.format("[countdown_chyron] " .. fmt, ...))
end

-- canvas 的 text 元素只認得 textColor，沒有描邊屬性；要描邊就得自己組
-- hs.styledtext，這時 textColor/textFont/textSize/textAlignment 全部會被忽略，
-- 所以連靠右對齊都得改走 paragraphStyle。
--
-- 每個字畫兩層，是為了讓外框「只往外長」。strokeWidth 的描邊以字形輪廓為中心，
-- 往兩邊各長一半 -- 往內那一半會吃掉字身，單層描邊加粗到看得見的程度，數字就
-- 開始變瘦。底層先畫一個描邊＋填色都是黑的「胖版」字，上層再蓋原尺寸的彩色字
-- 把往內那半補回去。
local function glyph(char, color, strokeWidth)
    return hs.styledtext.new(char, {
        font = { name = "Menlo-Bold", size = config.FONT_SIZE },
        color = color,
        strokeColor = color,
        strokeWidth = strokeWidth,
        -- 靠右，不是置中：這讓 COLUMN_MARGIN 成為那個字面意義上「螢幕邊緣到
        -- 數字的距離」旋鈕。置中的話真正的間距會是 COLUMN_MARGIN 加上欄位
        -- 寬鬆處的一半，於是 COLUMN_WIDTH 也會偷偷把字移動。
        paragraphStyle = { alignment = "right" },
    })
end

local function outlineGlyph(char)
    return glyph(char, STROKE_COLOR, -config.TEXT_STROKE_WIDTH)
end

local function fillGlyph(char, isLead)
    return glyph(char, isLead and LEAD_COLOR or BODY_COLOR, nil)
end

-- 字框：字靠右對齊到 COLUMN_WIDTH，右邊多出來的 STROKE_PAD 是留給黑邊的，
-- 不算在對齊寬度裡（見 geometry.lua）。
local function glyphBox(slot)
    return {
        x = 0,
        y = slot * config.GLYPH_STEP,
        w = geometry.COLUMN_WIDTH,
        h = geometry.GLYPH_BOX,
    }
end

local function newCanvas(rect, alpha)
    local c = hs.canvas.new(rect)
    c:level(hs.drawing.windowLevels.overlay)
    c:clickActivating(false)
    c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    c:alpha(alpha)
    return c
end

function M.create(rect)
    leadCanvas = newCanvas(rect, config.LEAD_ALPHA)
    bodyCanvas = newCanvas(rect, config.TEXT_ALPHA)
    builtLength = 0
    lastText = ""
end

function M.exists()    return leadCanvas ~= nil end
function M.isShowing() return leadCanvas ~= nil and leadCanvas:isShowing() end

function M.show()
    if leadCanvas then leadCanvas:show(); bodyCanvas:show() end
end

function M.hide()
    if leadCanvas then leadCanvas:hide(); bodyCanvas:hide() end
end

function M.setFrame(rect)
    if leadCanvas then leadCanvas:frame(rect); bodyCanvas:frame(rect) end
end

-- 半透明是「整張 canvas」的性質，不是顏色的性質 -- 這正是有兩張 canvas 的原因。
--
-- 顏色帶 alpha 的話，半透明的字身會蓋不住它底下那層黑色胖版字，字的內緣就留下
-- 一圈灰。要讓外框只往外長，上層必須是不透明的；要讓整個字半透明，那個
-- 半透明就得套在「外框＋字身已經合成完」的結果上，也就是 canvas 層級。
--
-- 一張 canvas 只有一個 alpha，而領頭字和字身本來就要兩種，所以是兩張。傳進來的
-- a 是外部的調光乘數（正常 1、游標碰到時 DIMMED_ALPHA），乘在各自的基準上。
function M.setAlpha(a)
    if leadCanvas then
        leadCanvas:alpha(a * config.LEAD_ALPHA)
        bodyCanvas:alpha(a * config.TEXT_ALPHA)
    end
end

function M.destroy()
    if leadCanvas then leadCanvas:delete(); leadCanvas = nil end
    if bodyCanvas then bodyCanvas:delete(); bodyCanvas = nil end
    builtLength = 0
    lastText = ""
end

-- 每個字數只建「一次」元素清單。舊版每幀重建約 57 張 Lua table（每個字一個元素
-- 加 frame 加 color）並呼叫 replaceElements()；在 6 FPS 下，那是每秒約 350 張
-- 短命 table 的純 GC 壓力，而這張圖每幀真正會變的只有少數幾個 y 值。顏色、字型和
-- 字框大小永遠不變，所以在這裡寫一次就再也不碰。
--
-- 外框和字身在 bodyCanvas 裡是「整批」排的：外框全部排在前面，字身全部排在後面。
-- canvas 依索引順序畫，後面的蓋在前面上 -- 整批排才能保證沒有任何一個字的外框會
-- 蓋到鄰居的字身。GLYPH_BOX 是 33pt 而 GLYPH_STEP 只有 24pt，相鄰字元的方框本來
-- 就是重疊的，所以這件事不是理論上的顧慮。
local function buildElements(text)
    local n = #text

    leadCanvas:replaceElements({
        { type = "text", text = outlineGlyph(text:sub(1, 1)),      frame = glyphBox(0) },
        { type = "text", text = fillGlyph(text:sub(1, 1), true),   frame = glyphBox(0) },
    })

    local body = {}
    for i = 2, n do
        local char = text:sub(i, i)
        local box = glyphBox(i - 1)
        body[i - 1]             = { type = "text", text = outlineGlyph(char),    frame = box }
        body[(n - 1) + (i - 1)] = { type = "text", text = fillGlyph(char, false), frame = box }
    end
    bodyCanvas:replaceElements(body)

    builtLength = n
    lastText = text
    log("rebuilt %d glyphs", builtLength)
end

-- 一個字在它那張 canvas 上的兩個元素索引（外框、字身）。
local function slotsFor(i, n)
    if i == 1 then return leadCanvas, 1, 2 end
    return bodyCanvas, i - 1, (n - 1) + (i - 1)
end

-- text = 要顯示的倒數字串；leadY = 領頭字上緣在 canvas 座標系的 y。
function M.render(text, leadY)
    if not M.isShowing() then return end

    -- 只有啟動時，以及天數少掉一位數的那一天才會發生。
    if builtLength ~= #text then buildElements(text) end

    -- 字：只改真的變了的那幾個。秒數往前跳只會改寫其中一兩個，不是全部十四個。
    -- 現在一個字是兩個元素（外框、字身），但「只改變了的」這件事沒變 -- 每幀仍然
    -- 是個位數次寫入，不是二十八次。
    if text ~= lastText then
        for i = 1, builtLength do
            local char = text:sub(i, i)
            if char ~= lastText:sub(i, i) then
                local c, outline, fill = slotsFor(i, builtLength)
                c:elementAttribute(outline, "text", outlineGlyph(char))
                c:elementAttribute(fill, "text", fillGlyph(char, i == 1))
            end
        end
        lastText = text
    end

    -- 位置：「一次」canvas 層級的平移，而不是每個字寫一次 frame。字在建立時就已經
    -- 坐在它於整串字中的位移上（見 buildElements），所以捲動是欄位的性質，不是
    -- 每個字元的性質。舊版每幀對全部十四個元素各寫一次 frame -- 為了表達一個數字，
    -- 每秒六次、每次十四趟 Lua->ObjC 穿越加十四次元素失效。
    local shift = hs.canvas.matrix.translate(0, leadY)
    leadCanvas:transformation(shift)
    bodyCanvas:transformation(shift)
end

return M

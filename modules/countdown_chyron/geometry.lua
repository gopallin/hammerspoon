-- 由 config 推導出來的尺寸，以及欄位在螢幕上的位置。純計算。
local config = require("modules.countdown_chyron.config")

local M = {}

M.GLYPH_BOX = config.FONT_SIZE * 1.5

-- 只要夠寬放得下最寬的字就好。它「不會」移動文字：字是靠右對齊到欄位右緣的，
-- 所以離螢幕邊緣的距離只由 COLUMN_MARGIN 決定。加寬這個值只是把欄位往左長進
-- 透明區域。
M.COLUMN_WIDTH = config.FONT_SIZE * 2

-- 黑邊往字外長出來的量（點）。描邊以字形輪廓為中心往兩邊各長一半，所以是設定值
-- 的一半。字靠右對齊到欄位右緣，而 canvas 會在自己的邊界把超出的部分切掉 -- 不
-- 把欄位往右多讓出這麼多，數字右側的黑邊就會被削成一條直邊。往左不必讓：欄位
-- 左邊有一大塊寬鬆處。
M.STROKE_PAD = math.ceil(config.FONT_SIZE * config.TEXT_STROKE_WIDTH / 100 / 2)

-- 整串字疊起來的高度，從領頭字的上緣到尾字的下緣。
function M.stringHeight(length)
    return (length - 1) * config.GLYPH_STEP + M.GLYPH_BOX
end

-- 欄位在螢幕上的絕對矩形。用 frame() 而不是 fullFrame()：跑馬燈會在同一個位置
-- 停留好幾分鐘，所以它必須避開選單列和 Dock，而不是從它們底下捲過去。額外的
-- BOTTOM_INSET 是為了避開 modules/statusbar 那條 bar -- frame() 不知道它的存在，
-- 因為它是 overlay canvas 而不是系統列。
--
-- 錨定在「右」緣：x 是反推出來的，讓字對齊的那一邊落在距離螢幕右緣
-- COLUMN_MARGIN 的位置。所以 COLUMN_WIDTH 只會把透明區往左延伸，永遠不會移動
-- 數字。欄位本身比對齊寬度再多 STROKE_PAD，那塊是往右讓給黑邊的 -- x 不動，
-- 所以數字停在原處，只是右邊多了一點不會被切到的餘裕。
function M.columnRect()
    local f = hs.screen.mainScreen():frame()
    return {
        x = f.x + f.w - config.COLUMN_MARGIN - M.COLUMN_WIDTH,
        y = f.y,
        w = M.COLUMN_WIDTH + M.STROKE_PAD,
        h = math.max(M.GLYPH_BOX, f.h - config.BOTTOM_INSET),
    }
end

return M

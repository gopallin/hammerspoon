-- 由 config 推導出來的尺寸，以及欄位在螢幕上的位置。純計算。
local config = require("modules.countdown_chyron.config")

local M = {}

M.GLYPH_BOX = config.FONT_SIZE * 1.5

-- 只要夠寬放得下最寬的字就好。它「不會」移動文字：字是靠右對齊到欄位右緣的，
-- 所以離螢幕邊緣的距離只由 COLUMN_MARGIN 決定。加寬這個值只是把欄位往左長進
-- 透明區域。
M.COLUMN_WIDTH = config.FONT_SIZE * 2

-- 整串字疊起來的高度，從領頭字的上緣到尾字的下緣。
function M.stringHeight(length)
    return (length - 1) * config.GLYPH_STEP + M.GLYPH_BOX
end

-- 欄位在螢幕上的絕對矩形。用 frame() 而不是 fullFrame()：跑馬燈會在同一個位置
-- 停留好幾分鐘，所以它必須避開選單列和 Dock，而不是從它們底下捲過去。額外的
-- BOTTOM_INSET 是為了避開 modules/statusbar 那條 bar -- frame() 不知道它的存在，
-- 因為它是 overlay canvas 而不是系統列。
--
-- 錨定在「右」緣：x 是反推出來的，讓欄位右緣（也就是字對齊的那一邊）落在距離
-- 螢幕右緣 COLUMN_MARGIN 的位置。所以 COLUMN_WIDTH 只會把透明區往左延伸，
-- 永遠不會移動數字。
function M.columnRect()
    local f = hs.screen.mainScreen():frame()
    return {
        x = f.x + f.w - config.COLUMN_MARGIN - M.COLUMN_WIDTH,
        y = f.y,
        w = M.COLUMN_WIDTH,
        h = math.max(M.GLYPH_BOX, f.h - config.BOTTOM_INSET),
    }
end

return M

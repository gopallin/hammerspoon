-- 倒數字串的計算。純時間運算，沒有畫面也沒有狀態。
local config = require("modules.countdown_chyron.config")

local M = {}

-- 載入時算一次：os.time(table) 會跑 mktime 並把正規化後的欄位寫回那張表，
-- 而答案是個常數。
local TARGET_EPOCH = os.time(config.TARGET)

function M.string()
    local remaining = math.max(0, TARGET_EPOCH - os.time())
    local days = math.floor(remaining / 86400)
    remaining = remaining % 86400
    local hours = math.floor(remaining / 3600)
    remaining = remaining % 3600
    local minutes = math.floor(remaining / 60)
    local seconds = remaining % 60
    return string.format("%d:%02d:%02d:%02d", days, hours, minutes, seconds)
end

return M

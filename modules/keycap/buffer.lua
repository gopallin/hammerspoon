-- 畫面上那幾個字的緩衝區。只有 push / 過期清除 / 清空，沒有畫面的事。
local config = require("modules.keycap.config")

local M = {}

-- { rawChar, prefix, keyCode, t } 的陣列，索引小的比較舊。
local items = {}

function M.items()
    return items
end

function M.count()
    return #items
end

function M.clear()
    items = {}
end

function M.push(rawChar, prefix, keyCode)
    table.insert(items, {
        rawChar = rawChar,
        prefix  = prefix,
        keyCode = keyCode,
        t       = hs.timer.secondsSinceEpoch(),
    })
    while #items > config.CHAR_BUFFER_LENGTH do table.remove(items, 1) end
end

-- 清掉已經超過 TTL 的字（一定是從最舊的那端開始）。有清到就回傳 true。
function M.pruneExpired()
    local now = hs.timer.secondsSinceEpoch()
    local changed = false
    while #items > 0 do
        if (now - items[1].t) >= config.CHAR_TTL_SECONDS then
            table.remove(items, 1)
            changed = true
        else
            break
        end
    end
    return changed
end

return M

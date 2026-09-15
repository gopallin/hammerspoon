-- 右上角的浮動通知：佇列 + 生命週期。畫面在 canvas.lua。
local canvas = require("modules.notification.canvas")
local config = require("modules.notification.config")

local M = {}

-- State: { id, canvas, timer } 的陣列，索引小的是比較舊的。
local queue = {}

local function remove(id)
    for i, item in ipairs(queue) do
        if item.id == id then
            if item.canvas then item.canvas:delete() end
            if item.timer then item.timer:stop() end
            table.remove(queue, i)
            canvas.layout(queue)
            return
        end
    end
end

function M.showStatus(message)
    if not message or message == "" then return end

    if #queue >= config.MAX_QUEUE_LENGTH then
        remove(queue[1].id)
    end

    local id = hs.timer.secondsSinceEpoch()
    local item = { id = id, canvas = canvas.create(message), timer = nil }
    table.insert(queue, item)
    canvas.layout(queue)

    item.timer = hs.timer.doAfter(config.DURATION, function() remove(id) end)
end

function M.stop()
    for i = #queue, 1, -1 do
        local item = queue[i]
        if item.timer then item.timer:stop() end
        if item.canvas then item.canvas:delete() end
    end
    queue = {}
end

return M

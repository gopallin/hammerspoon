-- 右下角那個按鍵顯示框。只負責畫，遮不遮蔽由呼叫端決定後傳進來。
local config = require("modules.keycap.config")
local keymap = require("modules.keycap.keymap")

local M = {}

local canvas = nil

local function create()
    local f = hs.screen.mainScreen():fullFrame()
    -- 用 f.x/f.y 而不是 0/0：多螢幕時副螢幕的 frame 原點不是零，忽略它會把
    -- canvas 畫到錯的那面螢幕上。
    canvas = hs.canvas.new({
        x = f.x + f.w - config.CANVAS_WIDTH - 40,
        y = f.y + f.h - config.CANVAS_HEIGHT - 60,
        w = config.CANVAS_WIDTH,
        h = config.CANVAS_HEIGHT,
    })
    canvas:level(hs.drawing.windowLevels.overlay)

    canvas[1] = {
        type = "rectangle",
        action = "fill",
        fillColor = { white = 0, alpha = config.BACKGROUND_ALPHA },
        roundedRectRadii = { xRadius = 12, yRadius = 12 },
    }

    canvas[2] = {
        type = "text",
        text = "",
        textFont = ".AppleSystemUIFont",
        textSize = config.FONT_SIZE,
        textColor = { white = 1, alpha = 0.7 },
        textAlignment = "right",
        frame = { x = "5%", y = "10%", w = "82%", h = "80%" },
    }

    -- 右上角的鎖頭；平常 alpha = 0，遮蔽時才亮起來。
    canvas[3] = {
        type = "text",
        text = "🔒",
        textSize = 12,
        frame = { x = "88%", y = "30%", w = "10%", h = "40%" },
        textColor = { white = 1, alpha = 0 },
    }
end

-- 把緩衝區組成要顯示的字串。遮蔽時內容字元換成 "*"，排版符號照原樣留著。
local function displayString(items, protected)
    local pieces = {}
    for i = 1, #items do
        local item = items[i]
        local content = item.rawChar or ""
        if protected and not keymap.structuralSymbols[content] then content = "*" end
        pieces[#pieces + 1] = (item.prefix or "") .. content
    end
    return table.concat(pieces, "  ")
end

function M.update(items, protected)
    if not canvas then create() end

    if #items == 0 then
        if canvas:isShowing() then canvas:hide() end
        return
    end

    canvas[3].textColor.alpha = protected and 1 or 0
    canvas[2].text = displayString(items, protected)
    if not canvas:isShowing() then canvas:show() end
end

function M.destroy()
    -- 連同變數一起設回 nil：update() 看到 nil 才會重建 canvas，把已刪除的
    -- canvas 物件留在這裡會讓後續呼叫去戳一個死掉的東西。
    if canvas then canvas:delete(); canvas = nil end
end

return M

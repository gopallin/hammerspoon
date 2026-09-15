-- 跑馬燈的「位置與內容」：欄位矩形、領頭字的 y、目前的倒數字串。
-- 這個檔案不管暫停也不管 timer -- 那些在 init.lua；它只回答「現在該畫在哪、
-- 畫什麼」，並在被要求時往前推一格。
local canvas    = require("modules.countdown_chyron.canvas")
local config    = require("modules.countdown_chyron.config")
local countdown = require("modules.countdown_chyron.countdown")
local geometry  = require("modules.countdown_chyron.geometry")

local M = {}

local columnFrame        -- canvas 的絕對螢幕矩形
local trackHeight = 0    -- canvas 高度，也就是跑馬燈的行程距離
local leadY = 0          -- 第一個字的字框上緣在 canvas 座標系的 y
local text = ""          -- 目前快取的倒數字串
local lastClockEpoch = 0

local function log(fmt, ...)
    print(string.format("[countdown_chyron] " .. fmt, ...))
end

local function stringHeight()
    return geometry.stringHeight(#text)
end

function M.frame()   return columnFrame end
function M.text()    return text end
function M.glyphCount() return #text end

-- 把整串字停在欄位底部、完整落在畫面內。比起「從底緣外面開始」，這樣在把跑馬燈
-- 打開的瞬間就能看到讀得出來的倒數，而不是先看八秒的空欄位。
function M.reset()
    text = countdown.string()
    leadY = trackHeight - stringHeight()
end

-- 啟動時，以及任何顯示器／解析度改變時重新推導欄位幾何。
function M.refreshGeometry()
    columnFrame = geometry.columnRect()
    trackHeight = columnFrame.h
    canvas.setFrame(columnFrame)

    -- 螢幕變小時，整串字可能被留在新的底緣之外，那樣它會先隱形一整輪才捲回來。
    if leadY > trackHeight + config.LOOP_GAP then
        log("screen shrank to %dx%d, reparking chyron", columnFrame.w, columnFrame.h)
        M.reset()
    end
end

function M.render()
    canvas.render(text, leadY)
end

-- 不管 tick 率多少，最多每秒刷新一次快取的時鐘字串。字串真的變了才回傳 true。
function M.tickClock()
    local nowEpoch = os.time()
    if nowEpoch == lastClockEpoch then return false end
    lastClockEpoch = nowEpoch
    text = countdown.string()
    return true
end

-- 前進距離是「點/秒 x 秒/tick」而不是固定點數，這樣切到電池電源時放慢的是喚醒
-- 次數，而不會連帶把跑馬燈慢到看得出來。
function M.step(interval)
    leadY = leadY - config.SCROLL_SPEED * interval

    -- 整串字已經離開上緣：從下緣外面重新進場。
    if leadY + stringHeight() < 0 then
        leadY = trackHeight + config.LOOP_GAP
    end

    M.render()
end

-- 水平方向用的是整個欄位，包含靠右數字左邊那塊透明的寬鬆處，所以跑馬燈會在游標
-- 真的碰到字之前就先讓開一點。垂直方向則是精確的：一輪的大部分時間欄位是空的，
-- 那時沒有東西需要讓路。
function M.mouseOver()
    if not columnFrame then return false end
    local mouse = hs.mouse.absolutePosition()

    local localX = mouse.x - columnFrame.x
    if localX < 0 or localX > geometry.COLUMN_WIDTH then return false end

    local localY = mouse.y - columnFrame.y
    return localY >= leadY and localY <= leadY + stringHeight()
end

function M.resetClock()
    lastClockEpoch = 0
end

return M

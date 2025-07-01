local utils = require("lib.utils")

hs.hotkey.bind({"option"}, "F", function()
  utils.mouseClick("left")
end)

hs.hotkey.bind({"option"}, "V", function()
  utils.mouseClick("right")
end)

local moveSpeed = 3
local moveInterval = 0.01
local movingTimers = {}

local function startMouseMove(key, dx, dy)
  if movingTimers[key] then return end
  movingTimers[key] = hs.timer.doEvery(moveInterval, function()
    local pt = hs.mouse.getAbsolutePosition()
    hs.mouse.setAbsolutePosition({x = pt.x + dx, y = pt.y + dy})
  end)
end

local function stopMouseMove(key)
  if movingTimers[key] then
    movingTimers[key]:stop()
    movingTimers[key] = nil
  end
end

local directions = {
  W = {0, -moveSpeed},
  A = {-moveSpeed, 0},
  S = {0, moveSpeed},
  D = {moveSpeed, 0},
}

for key, delta in pairs(directions) do
  hs.hotkey.bind({"option"}, key,
    function() startMouseMove(key, delta[1], delta[2]) end,
    function() stopMouseMove(key) end
  )
end


local utils = require("lib.utils")

local firstKey = nil
local keyTimer = nil
local inputTimeout = 1.0

local function handleKey(key)
  local screen = hs.screen.mainScreen()
  local frame = screen:frame()

  if firstKey == nil then
    firstKey = key
    if keyTimer then keyTimer:stop() end
    keyTimer = hs.timer.doAfter(inputTimeout, function()
      utils.moveToGridPosition(firstKey, frame)
      firstKey = nil
    end)
  else
    if keyTimer then keyTimer:stop() end
    local grid = utils.grid
    local pos = grid[firstKey]
    if not pos then return end
    local firstRect = {
      x = frame.x + pos[1] * frame.w / 3,
      y = frame.y + pos[2] * frame.h / 3,
      w = frame.w / 3,
      h = frame.h / 3,
    }
    utils.moveToGridPosition(key, firstRect)
    firstKey = nil
  end
end

for i = 1, 9 do
  hs.hotkey.bind({"option"}, tostring(i), function()
    handleKey(i)
  end)
end


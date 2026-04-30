local scrollWheel = hs.eventtap.scrollWheel

local M = {}

function M.up()
  scrollWheel({ 0, -10 }, {}, "line")
end

function M.down()
  scrollWheel({ 0, 10 }, {}, "line")
end

function M.left()
  scrollWheel({ 15, 0 }, {}, "line")
end

function M.right()
  scrollWheel({ -15, 0 }, {}, "line")
end

return M

local grid = require("lib.grid")
local mouse = require("lib.mouse")
local scroll = require("lib.scroll")
local edge_bookmarks = require("lib.edge_bookmarks")

for i = 1, 9 do
  hs.hotkey.bind({ "option" }, tostring(i), function()
    grid.handleKey(i)
  end)
end

hs.hotkey.bind({ "option" }, "F", function()
  mouse.leftClick()
end)

hs.hotkey.bind({ "option" }, "V", function()
  mouse.rightClick()
end)

for key, delta in pairs(mouse.directions()) do
  hs.hotkey.bind({ "option" }, key,
    function() mouse.startMove(key, delta[1], delta[2]) end,
    function() mouse.stopMove(key) end
  )
end

hs.hotkey.bind({ "option" }, "J", function() scroll.up() end)
hs.hotkey.bind({ "option" }, "K", function() scroll.down() end)
hs.hotkey.bind({ "option" }, "H", function() scroll.left() end)
hs.hotkey.bind({ "option" }, "L", function() scroll.right() end)

hs.hotkey.bind({ "alt", "cmd" }, "space", function()
  edge_bookmarks.show()
end)

local scrollWheel = hs.eventtap.scrollWheel

hs.hotkey.bind({"option"}, "J", function() scrollWheel({0, -10}, {}, "line") end)
hs.hotkey.bind({"option"}, "K", function() scrollWheel({0, 10}, {}, "line") end)
hs.hotkey.bind({"option"}, "H", function() scrollWheel({15, 0}, {}, "line") end)
hs.hotkey.bind({"option"}, "L", function() scrollWheel({-15, 0}, {}, "line") end)


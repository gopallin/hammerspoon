require("config.keybindings")

require("modules.reload").start()
require("modules.keycap").start()

-- Cat Gatekeeper: Application usage tracker with reminder
local catGatekeeper = require("modules.cat_gatekeeper")
catGatekeeper.start()

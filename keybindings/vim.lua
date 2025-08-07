--
-- keybindings/vim.lua
--
-- Keybindings for system-wide Vim-style modal navigation.
-- Manages mode-specific hotkeys.
--

local vim = {}

-- Load core Vim logic and state management
local vim_core = require("lib.vim_core")

-- Helper function to simulate a key press with optional modifiers
-- @param mods table A table of modifier keys (e.g., {"cmd", "alt"})
-- @param key string The key to simulate (e.g., "left", "v")
local function key_stroke(mods, key)
    hs.eventtap.keyStroke(mods, key, 0)
end

-- Binds the Escape key to return to Normal mode.
-- This is a common action for both Insert and Visual modes.
local function bind_escape_to_normal_mode()
    vim_core.state.active_hotkeys.escape = hs.hotkey.bind({}, "escape", function() vim.change_mode(vim_core.MODES.NORMAL) end)
end

-- Binds the hotkeys specific to Normal mode
local function bind_normal_mode_keys()
    -- Basic navigation (h, j, k, l)
    vim_core.state.active_hotkeys.h = hs.hotkey.bind({}, "h", function() key_stroke({}, "left") end)
    vim_core.state.active_hotkeys.j = hs.hotkey.bind({}, "j", function() key_stroke({}, "down") end)
    vim_core.state.active_hotkeys.k = hs.hotkey.bind({}, "k", function() key_stroke({}, "up") end)
    vim_core.state.active_hotkeys.l = hs.hotkey.bind({}, "l", function() key_stroke({}, "right") end)

    -- Mode transitions
    vim_core.state.active_hotkeys.i = hs.hotkey.bind({}, "i", function() vim.change_mode(vim_core.MODES.INSERT) end) -- Enter Insert mode
    vim_core.state.active_hotkeys.v = hs.hotkey.bind({}, "v", function() vim.change_mode(vim_core.MODES.VISUAL) end) -- Enter Visual mode

    -- Global actions
    vim_core.state.active_hotkeys.p = hs.hotkey.bind({}, "p", function() key_stroke({"cmd"}, "v") end) -- Paste (Cmd+V)

    -- Faster scrolling (Ctrl+d, Ctrl+u)
    vim_core.state.active_hotkeys.d_ctrl = hs.hotkey.bind({"ctrl"}, "d", function() key_stroke({}, "pageDown") end)
    vim_core.state.active_hotkeys.u_ctrl = hs.hotkey.bind({"ctrl"}, "u", function() key_stroke({}, "pageUp") end)
end

-- Binds the hotkeys specific to Visual mode
local function bind_visual_mode_keys()
    -- Text selection (h, j, k, l with Shift)
    vim_core.state.active_hotkeys.h = hs.hotkey.bind({}, "h", function() key_stroke({"shift"}, "left") end)
    vim_core.state.active_hotkeys.j = hs.hotkey.bind({}, "j", function() key_stroke({"shift"}, "down") end)
    vim_core.state.active_hotkeys.k = hs.hotkey.bind({}, "k", function() key_stroke({"shift"}, "up") end)
    vim_core.state.active_hotkeys.l = hs.hotkey.bind({}, "l", function() key_stroke({"shift"}, "right") end)

    -- Yank (copy) selected text and return to Normal mode
    vim_core.state.active_hotkeys.y = hs.hotkey.bind({}, "y", function()
        key_stroke({"cmd"}, "c") -- Simulate Cmd+C to copy
        vim.change_mode(vim_core.MODES.NORMAL) -- Return to Normal mode
    end)

    -- Use the shared function to bind Escape
    bind_escape_to_normal_mode()
end

-- Function to change the current mode of the Vim system
-- This function is called by vim_core and then binds the appropriate hotkeys.
-- @param new_mode string The mode to transition to (e.g., vim_core.MODES.NORMAL, vim_core.MODES.INSERT)
function vim.change_mode(new_mode)
    vim_core.change_mode(new_mode) -- Update the core state and visual indicator

    -- Bind hotkeys based on the new mode
    if new_mode == vim_core.MODES.NORMAL then
        bind_normal_mode_keys()
    elseif new_mode == vim_core.MODES.INSERT then
        -- In Insert mode, only Escape is handled to exit.
        bind_escape_to_normal_mode()
    elseif new_mode == vim_core.MODES.VISUAL then
        bind_visual_mode_keys()
    end
end

-- Initialize the master hotkey for the Vim system
vim_core.init_master_hotkey()

return vim
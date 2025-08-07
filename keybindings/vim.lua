--
-- keybindings/vim.lua
--
-- Core module for system-wide Vim-style modal navigation.
-- Implements the state machine and manages all mode-specific hotkeys.
--

local vim = {}

-- -------------------------------------------------------------------
-- Constants and State Management
-- -------------------------------------------------------------------

-- Define the modes for the Vim-like system
local MODES = {
    NORMAL = "NORMAL",   -- Default mode for navigation and commands
    INSERT = "INSERT",   -- For standard text input, passes keys through
    VISUAL = "VISUAL",   -- For selecting text
    DISABLED = "DISABLED" -- When the Vim system is inactive
}

-- Load our custom UI module for visual feedback
local mode_indicator = require("lib.mode_indicator")

-- Track the current state of the Vim module
local state = {
    mode = MODES.DISABLED, -- Start in DISABLED mode by default
    master_hotkey = nil,     -- The hotkey to toggle the entire system on/off
    active_hotkeys = {}      -- A table to hold currently active mode-specific hotkeys
}

-- -------------------------------------------------------------------
-- Visual Feedback
-- -------------------------------------------------------------------

-- Shows, hides, or updates the on-screen mode indicator
local function update_visual_indicator()
    if state.mode == MODES.DISABLED then
        mode_indicator.hide() -- Hide the indicator when the system is disabled
    else
        mode_indicator.update(state.mode) -- Show or update the indicator with the current mode
    end
end

-- -------------------------------------------------------------------
-- Keybinding Definitions
-- -------------------------------------------------------------------

-- Helper function to simulate a key press with optional modifiers
-- @param mods table A table of modifier keys (e.g., {"cmd", "alt"})
-- @param key string The key to simulate (e.g., "left", "v")
local function key_stroke(mods, key)
    hs.eventtap.keyStroke(mods, key, 0)
end

-- Binds the hotkeys specific to Normal mode
local function bind_normal_mode_keys()
    -- Basic navigation (h, j, k, l)
    state.active_hotkeys.h = hs.hotkey.bind({}, "h", function() key_stroke({}, "left") end)
    state.active_hotkeys.j = hs.hotkey.bind({}, "j", function() key_stroke({}, "down") end)
    state.active_hotkeys.k = hs.hotkey.bind({}, "k", function() key_stroke({}, "up") end)
    state.active_hotkeys.l = hs.hotkey.bind({}, "l", function() key_stroke({}, "right") end)

    -- Mode transitions
    state.active_hotkeys.i = hs.hotkey.bind({}, "i", function() vim.change_mode(MODES.INSERT) end) -- Enter Insert mode
    state.active_hotkeys.v = hs.hotkey.bind({}, "v", function() vim.change_mode(MODES.VISUAL) end) -- Enter Visual mode

    -- Global actions
    state.active_hotkeys.p = hs.hotkey.bind({}, "p", function() key_stroke({"cmd"}, "v") end) -- Paste (Cmd+V)

    -- Faster scrolling (Ctrl+d, Ctrl+u)
    state.active_hotkeys.d_ctrl = hs.hotkey.bind({"ctrl"}, "d", function() key_stroke({}, "pageDown") end)
    state.active_hotkeys.u_ctrl = hs.hotkey.bind({"ctrl"}, "u", function() key_stroke({}, "pageUp") end)
end

-- Binds the hotkeys specific to Visual mode
local function bind_visual_mode_keys()
    -- Text selection (h, j, k, l with Shift)
    state.active_hotkeys.h = hs.hotkey.bind({}, "h", function() key_stroke({"shift"}, "left") end)
    state.active_hotkeys.j = hs.hotkey.bind({}, "j", function() key_stroke({"shift"}, "down") end)
    state.active_hotkeys.k = hs.hotkey.bind({}, "k", function() key_stroke({"shift"}, "up") end)
    state.active_hotkeys.l = hs.hotkey.bind({}, "l", function() key_stroke({"shift"}, "right") end)

    -- Yank (copy) selected text and return to Normal mode
    state.active_hotkeys.y = hs.hotkey.bind({}, "y", function()
        key_stroke({"cmd"}, "c") -- Simulate Cmd+C to copy
        vim.change_mode(MODES.NORMAL) -- Return to Normal mode
    end)

    -- Escape to return to Normal mode from Visual mode
    state.active_hotkeys.escape = hs.hotkey.bind({}, "escape", function() vim.change_mode(MODES.NORMAL) end)
end

-- -------------------------------------------------------------------
-- Core Modal Logic
-- -------------------------------------------------------------------

-- Function to clear all currently active, mode-specific hotkeys
local function clear_active_hotkeys()
    for _, hotkey in pairs(state.active_hotkeys) do
        hotkey:delete() -- Deactivate each hotkey
    end
    state.active_hotkeys = {} -- Clear the table of active hotkeys
end

-- Function to change the current mode of the Vim system
-- @param new_mode string The mode to transition to (e.g., MODES.NORMAL, MODES.INSERT)
function vim.change_mode(new_mode)
    -- Do nothing if trying to change to the current mode
    if state.mode == new_mode then return end

    state.mode = new_mode -- Update the current mode
    clear_active_hotkeys() -- Deactivate hotkeys from the previous mode

    -- Bind hotkeys based on the new mode
    if new_mode == MODES.NORMAL then
        bind_normal_mode_keys()
    elseif new_mode == MODES.INSERT then
        -- In Insert mode, most keys pass through. Only Escape is handled to exit.
        state.active_hotkeys.escape = hs.hotkey.bind({}, "escape", function() vim.change_mode(MODES.NORMAL) end)
    elseif new_mode == MODES.VISUAL then
        bind_visual_mode_keys()
    end

    update_visual_indicator() -- Update the on-screen mode indicator
end

-- -------------------------------------------------------------------
-- System Toggle
-- -------------------------------------------------------------------

-- Toggles the entire Vim system on or off
local function toggle_system()
    if state.mode == MODES.DISABLED then
        vim.change_mode(MODES.NORMAL) -- If disabled, enable and enter NORMAL mode
    else
        vim.change_mode(MODES.DISABLED) -- If enabled, disable the system
    end
end

-- -------------------------------------------------------------------
-- Public API
-- -------------------------------------------------------------------

-- Initializes the Vim module and binds the master hotkey
function vim.init()
    -- Bind the master hotkey (Cmd+Alt+Ctrl+V) to toggle the system.
    -- This uses a complex modifier to minimize conflicts with other applications.
    state.master_hotkey = hs.hotkey.bind({"cmd", "alt", "ctrl"}, "v", toggle_system)
end

-- Start the module when it's loaded
vim.init()

return vim

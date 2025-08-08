--
-- lib/mode_indicator.lua
--
-- Manages the on-screen visual indicator for the current Vim mode.
--

local indicator = {}

-- Load required Hammerspoon modules
local hs_canvas_module = require("hs.canvas")
local hs_styledtext_module = require("hs.styledtext")
local hs_timer_module = require("hs.timer") -- Added for flashing

-- -------------------------------------------------------------------
-- Configuration
-- -------------------------------------------------------------------

local UI_CONFIG = {
    WIDTH = 120,
    HEIGHT = 40,
    PADDING = 15,
    FONT_SIZE = 18,
    BG_COLOR = { hex = "#2c3e50" }, -- Dark Slate Blue
    TEXT_COLOR = { hex = "#ecf0f1" }  -- Light Gray
}

-- -------------------------------------------------------------------
-- Private State
-- -------------------------------------------------------------------

local drawing = nil -- This will hold our hs.canvas object for the indicator
local flash_timer = nil -- Timer for the flashing effect

-- -------------------------------------------------------------------
-- Core Functions
-- -------------------------------------------------------------------

-- Hides and destroys the mode indicator
function indicator.hide()
    if flash_timer then
        flash_timer:stop()
        flash_timer = nil
    end
    if drawing then
        drawing:delete() -- Delete the canvas object
        drawing = nil    -- Clear the reference
    end
end

-- Shows and updates the indicator with the specified mode text
-- @param mode_text string The text to display (e.g., "NORMAL", "INSERT")
function indicator.update(mode_text)
    -- Ensure any previous drawing is cleared before creating a new one
    indicator.hide()

    -- Get the main screen's geometry to position the indicator
    local screen_frame = hs.screen.mainScreen():frame()

    -- Calculate the position for the bottom-right corner of the screen
    local x = screen_frame.x + screen_frame.w - UI_CONFIG.WIDTH - UI_CONFIG.PADDING
    local y = screen_frame.y + screen_frame.h - UI_CONFIG.HEIGHT - UI_CONFIG.PADDING

    -- Create the hs.canvas drawing object
    drawing = hs_canvas_module.new({
        x = x,
        y = y,
        w = UI_CONFIG.WIDTH,
        h = UI_CONFIG.HEIGHT
    })

    -- Define the elements to be drawn on the canvas
    -- Element 1: Background rectangle
    drawing[1] = {
        type = "rectangle",
        fillColor = UI_CONFIG.BG_COLOR,
        frame = {x=0, y=0, w=UI_CONFIG.WIDTH, h=UI_CONFIG.HEIGHT},
        roundedRectRadii = {xRadius = UI_CONFIG.HEIGHT / 4, yRadius = UI_CONFIG.HEIGHT / 4} -- Apply rounded corners
    }

    -- Element 2: Mode text
    local styled_text = hs_styledtext_module.new(mode_text, {
        font = {size = UI_CONFIG.FONT_SIZE},
        color = UI_CONFIG.TEXT_COLOR,
        paragraphStyle = {alignment = "center"}
    })

    drawing[2] = {
        type = "text",
        text = styled_text,
        frame = {x=0, y=0, w=UI_CONFIG.WIDTH, h=UI_CONFIG.HEIGHT}
    }

    -- Show the indicator on screen
    drawing:show()

    -- Create and start a timer to make the indicator flash
    flash_timer = hs_timer_module.new(1, function()
        if drawing then
            if drawing:isVisible() then
                drawing:hide()
            else
                drawing:show()
            end
        end
    end)
    flash_timer:start()
end

return indicator

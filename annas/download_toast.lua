-- Small non-modal message anchored to the bottom-right corner of the screen.
-- Unlike InfoMessage it doesn't take input focus, so the user can keep
-- reading or browsing while a download runs in the background.

local Blitbuffer = require("ffi/blitbuffer")
local CustomPositionContainer = require("ui/widget/container/custompositioncontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local Toast = {}

local current = nil

-- Show `text` in the bottom-right corner. Pass `timeout` in seconds to hide
-- it automatically; leave it nil to keep it until Toast.close() is called.
function Toast.show(text, timeout)
    Toast.close()

    local text_widget = TextWidget:new{
        text = text,
        face = Font:getFace("infofont"),
        max_width = math.floor(Screen:getWidth() * 0.6),
    }
    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Screen:scaleBySize(2),
        radius = Screen:scaleBySize(8),
        padding = Screen:scaleBySize(12),
        margin = Screen:scaleBySize(16),
        text_widget,
    }
    local toast = CustomPositionContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        horizontal_position = 1.0,
        vertical_position = 1.0,
        widget = frame,
    }

    current = toast
    UIManager:show(toast)

    if timeout then
        UIManager:scheduleIn(timeout, function()
            if current == toast then
                Toast.close()
            end
        end)
    end
    return toast
end

function Toast.close()
    if current then
        UIManager:close(current, "ui")
        current = nil
    end
end

return Toast

local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local ProgressbarDialog = require("ui/widget/progressbardialog")
local T = require("annas.gettext")
local logger = require("logger")

local AsyncHelper = {}

function AsyncHelper.run(task_func, on_success, on_error, loading_msg, options)
    options = options or {}
    local timeout_seconds = options.timeout_seconds or 90
    if not loading_msg then
        loading_msg = ProgressbarDialog:new{
            title = T("Please wait…"),
            subtitle = T("Tap anywhere to cancel."),
            modal = true,
        }
        loading_msg:show()
    end

    local closed = false
    local timed_out = false
    local on_close_widget = loading_msg.onCloseWidget
    loading_msg.onCloseWidget = function(widget)
        closed = true
        widget._annas_closed = true
        if on_close_widget then
            return on_close_widget(widget)
        end
    end

    local function fail(message)
        logger.warn("Annas background task:", message)
        if on_error then on_error(message) end
    end

    return Trapper:wrap(function()
        local timeout_action = function()
            timed_out = true

            if not closed then UIManager:close(loading_msg) end
        end
        UIManager:scheduleIn(timeout_seconds, timeout_action)

        local call_ok, completed, result = pcall(function()
            return Trapper:dismissableRunInSubprocess(function()

                local ok, data = pcall(task_func)
                if not ok then
                    return { ok = false, error = tostring(data) }
                end
                return { ok = true, data = data }
            end, loading_msg)
        end)

        UIManager:unschedule(timeout_action)
        local was_dismissed = closed

        loading_msg.dismiss_callback = nil
        if not closed then UIManager:close(loading_msg) end
        loading_msg.onCloseWidget = on_close_widget

        if not call_ok then
            fail(tostring(completed))
        elseif timed_out then
            fail(T("Operation timed out. Please try again."))
        elseif not completed then
            if was_dismissed then

                if options.on_cancel then UIManager:nextTick(options.on_cancel) end
            else
                fail(T("Could not start the background task."))
            end
        elseif type(result) ~= "table" then
            fail(T("The background task ended without a result."))
        elseif not result.ok then
            fail(tostring(result.error))
        elseif type(result.data) == "table" and result.data.error then
            fail(tostring(result.data.error))
        elseif on_success then
            on_success(result.data)
        end
    end)
end

return AsyncHelper

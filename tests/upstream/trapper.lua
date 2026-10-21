local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")
local buffer = require("string.buffer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local _ = require("gettext")

local Trapper = {}

function Trapper:wrap(func)

    local pcalled_func = function()
        UIManager:preventStandby()

        local ok, err = xpcall(func, debug.traceback)
        UIManager:allowStandby()
        if not ok then
            logger.warn("error in wrapped function:", err)
            return false
        end
        return true

    end
    local co = coroutine.create(pcalled_func)
    return coroutine.resume(co)
end

function Trapper:isWrapped()
    if coroutine.running() then
        return true
    end
    return false
end

function Trapper:clear()
    if self:isWrapped() then
        if self.current_widget then
            UIManager:close(self.current_widget)
            UIManager:forceRePaint()
            self.current_widget = nil
        end
    end
end

function Trapper:reset()
    self:clear()

    self.paused_text = nil
    self.paused_continue_text = nil
    self.paused_abort_text = nil
    return true
end

function Trapper:info(text, fast_refresh, skip_dismiss_check)
    local _coroutine = coroutine.running()
    if not _coroutine then
        logger.info("unwrapped info:", text)
        return true
    end

    if self.current_widget and self.current_widget.is_infomessage then

        local go_on = true
        local go_on_func
        if not skip_dismiss_check then
            go_on_func = function() coroutine.resume(_coroutine, true) end

            UIManager:scheduleIn(0.1, go_on_func)

            go_on = coroutine.yield()

        end
        if not go_on then
            UIManager:unschedule(go_on_func)

            local abort_box = ConfirmBox:new{
                text = self.paused_text and self.paused_text or _("Paused"),

                cancel_text = self.paused_continue_text and self.paused_continue_text or _("Continue"),
                ok_text = self.paused_abort_text and self.paused_abort_text or _("Abort"),
                cancel_callback = function()
                    coroutine.resume(_coroutine, true)
                end,
                ok_callback = function()
                    coroutine.resume(_coroutine, false)
                end,

                flush_events_on_show = true,
            }
            UIManager:show(abort_box)

            go_on = coroutine.yield()
            UIManager:close(abort_box)
            if not go_on then
                UIManager:close(self.current_widget)
                UIManager:forceRePaint()
                return false
            end
            if self.current_widget then

                self.current_widget:init()
                UIManager:show(self.current_widget)
            end
            UIManager:forceRePaint()
        end

    end

    if fast_refresh and self.current_widget and self.current_widget.is_infomessage then
        local orig_moved_offset = self.current_widget.movable:getMovedOffset()
        self.current_widget:free()
        self.current_widget.text = text
        self.current_widget:init()
        self.current_widget.movable:setMovedOffset(orig_moved_offset)
        local Screen = require("device").screen
        self.current_widget:paintTo(Screen.bb, 0, 0)
        local d = self.current_widget[1][1].dimen
        Screen.refreshUI(Screen, d.x, d.y, d.w, d.h)
    else

        if self.current_widget then
            UIManager:close(self.current_widget)

        end

        self.current_widget = InfoMessage:new{
            text = text,
            dismiss_callback = function()
                coroutine.resume(_coroutine, false)
            end,
            is_infomessage = true,

            flush_events_on_show = true,
        }
        logger.dbg("Showing InfoMessage:", text)
        UIManager:show(self.current_widget)
        UIManager:forceRePaint()
    end
    return true
end

function Trapper:setPausedText(text, abort_text, continue_text)
    if self:isWrapped() then
        self.paused_text = text
        self.paused_abort_text = abort_text
        self.paused_continue_text = continue_text
    end
end

function Trapper:confirm(text, cancel_text, ok_text)

    local _coroutine = coroutine.running()
    if not _coroutine then
        logger.info("unwrapped confirm, returning true to:", text)
        return true
    end

    if self.current_widget then
        UIManager:close(self.current_widget)

    end

    self.current_widget = ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        cancel_text = cancel_text,
        cancel_callback = function()
            coroutine.resume(_coroutine, false)
        end,
        ok_callback = function()
            coroutine.resume(_coroutine, true)
        end,

        flush_events_on_show = true,
    }
    logger.dbg("Showing ConfirmBox and waiting for answer:", text)
    UIManager:show(self.current_widget)

    local ret = coroutine.yield()
    logger.dbg("ConfirmBox answers", ret)
    return ret
end

function Trapper:dismissablePopen(cmd, trap_widget_or_string)
    local _coroutine = coroutine.running()

    if not _coroutine then
        logger.warn("unwrapped dismissablePopen(), falling back to blocking io.popen()")
        local std_out = io.popen(cmd, "r")
        if std_out then
            local output = std_out:read("*all")
            std_out:close()
            return true, output
        end
        return false
    end

    local trap_widget
    local own_trap_widget = false
    local own_trap_widget_invisible = false
    if type(trap_widget_or_string) == "table" then

        trap_widget = trap_widget_or_string
    else
        if type(trap_widget_or_string) == "string" then

            trap_widget = TrapWidget:new{
                text = trap_widget_or_string,
            }
            UIManager:show(trap_widget)
            UIManager:forceRePaint()
        else

            local resend_event = true
            if trap_widget_or_string == false then
                resend_event = false
            end
            trap_widget = TrapWidget:new{
                text = nil,
                resend_event = resend_event,
            }
            UIManager:show(trap_widget)
            own_trap_widget_invisible = true
        end
        own_trap_widget = true
    end
    trap_widget.dismiss_callback = function()

        coroutine.resume(_coroutine, false)
    end

    local collect_interval_sec = 5
    local check_interval_sec = 0.125
    local check_num = 0

    local completed = false
    local output = nil

    local std_out = io.popen(cmd, "r")
    if std_out then

        while true do

            check_num = check_num + 1
            if check_interval_sec < 1 and check_num % 10 == 0 then
                check_interval_sec = math.min(check_interval_sec * 2, 1)
            end

            local go_on_func = function() coroutine.resume(_coroutine, true) end
            UIManager:scheduleIn(check_interval_sec, go_on_func)
            local go_on = coroutine.yield()
            if not go_on then
                UIManager:unschedule(go_on_func)

                local collect_and_clean
                collect_and_clean = function()
                    if ffiutil.getNonBlockingReadSize(std_out) ~= 0 then
                        std_out:read("*all")
                        std_out:close()
                        logger.dbg("collected cancelled cmd output")
                    else
                        UIManager:scheduleIn(collect_interval_sec, collect_and_clean)
                        logger.dbg("cancelled cmd output not yet collectable")
                    end
                end
                UIManager:scheduleIn(collect_interval_sec, collect_and_clean)
                break
            end

            if ffiutil.getNonBlockingReadSize(std_out) ~= 0 then

                output = std_out:read("*all")
                std_out:close()
                completed = true
                break
            end

        end
    end
    if own_trap_widget then

        UIManager:close(trap_widget)
        if not own_trap_widget_invisible then
            UIManager:forceRePaint()
        end
    end

    return completed, output
end

function Trapper:dismissableRunInSubprocess(task, trap_widget_or_string, task_returns_simple_string)
    local _coroutine = coroutine.running()
    if not _coroutine then
        logger.warn("unwrapped dismissableRunInSubprocess(), falling back to blocking in-process run")
        return true, task()
    end

    local trap_widget
    local own_trap_widget = false
    local own_trap_widget_invisible = false
    if type(trap_widget_or_string) == "table" then

        trap_widget = trap_widget_or_string
    else
        if type(trap_widget_or_string) == "string" then

            trap_widget = TrapWidget:new{
                text = trap_widget_or_string,
            }
            UIManager:show(trap_widget)
            UIManager:forceRePaint()
        else

            local resend_event = true
            if trap_widget_or_string == false then
                resend_event = false
            end
            trap_widget = TrapWidget:new{
                text = nil,
                resend_event = resend_event,
            }
            UIManager:show(trap_widget)
            own_trap_widget_invisible = true
        end
        own_trap_widget = true
    end
    trap_widget.dismiss_callback = function()

        coroutine.resume(_coroutine, false)
    end

    local collect_interval_sec = 5
    local check_interval_sec = 0.125
    local check_num = 0

    local completed = false
    local ret_values

    local pid, parent_read_fd = ffiutil.runInSubProcess(function(pid, child_write_fd)
        local output_str = ""
        if task_returns_simple_string then

            local result = task()
            if type(result) == "string" then
                output_str = result
            elseif result ~= nil then
                logger.warn("returned value from task is not a string:", result)
            end
        else

            local results = table.pack(task())
            local ok, str = pcall(buffer.encode, results)
            if not ok then
                logger.warn("cannot serialize", tostring(results), "->", str)
            else
                output_str = str
            end
        end
        ffiutil.writeToFD(child_write_fd, output_str, true)
    end, true)

    if pid then

        while true do

            check_num = check_num + 1
            if check_interval_sec < 1 and check_num % 10 == 0 then
                check_interval_sec = math.min(check_interval_sec * 2, 1)
            end

            local go_on_func = function() coroutine.resume(_coroutine, true) end
            UIManager:scheduleIn(check_interval_sec, go_on_func)
            local go_on = coroutine.yield()
            if not go_on then
                UIManager:unschedule(go_on_func)

                ffiutil.terminateSubProcess(pid)
                local collect_and_clean
                collect_and_clean = function()
                    if ffiutil.isSubProcessDone(pid) then
                        if parent_read_fd then
                            ffiutil.readAllFromFD(parent_read_fd)
                        end
                        logger.dbg("collected previously dismissed subprocess")
                    else
                        if parent_read_fd and ffiutil.getNonBlockingReadSize(parent_read_fd) ~= 0 then

                            ffiutil.readAllFromFD(parent_read_fd)

                            parent_read_fd = nil
                        end

                        UIManager:scheduleIn(collect_interval_sec, collect_and_clean)
                        logger.dbg("previously dismissed subprocess not yet collectable")
                    end
                end
                UIManager:scheduleIn(collect_interval_sec, collect_and_clean)
                break
            end

            local subprocess_done = ffiutil.isSubProcessDone(pid)
            local stuff_to_read = parent_read_fd and ffiutil.getNonBlockingReadSize(parent_read_fd) ~= 0
            logger.dbg("subprocess_done:", subprocess_done, " stuff_to_read:", stuff_to_read)
            if subprocess_done or stuff_to_read then

                completed = true
                if stuff_to_read then
                    local ret_str = ffiutil.readAllFromFD(parent_read_fd)
                    if task_returns_simple_string then
                        ret_values = ret_str
                    else
                        local ok, t = pcall(buffer.decode, ret_str)
                        if ok and t then
                            ret_values = t
                        else
                            logger.warn("malformed serialized data:", t)
                        end
                    end
                    if not subprocess_done then

                        local collect_and_clean
                        collect_and_clean = function()
                            if ffiutil.isSubProcessDone(pid) then
                                logger.dbg("collected subprocess")
                            else
                                UIManager:scheduleIn(1, collect_and_clean)
                                logger.dbg("subprocess not yet collectable")
                            end
                        end
                        UIManager:scheduleIn(1, collect_and_clean)
                    end
                else
                    ffiutil.readAllFromFD(parent_read_fd)

                end
                break
            end
            logger.dbg("process not yet done, will check again soon")
        end
    end
    if own_trap_widget then

        UIManager:close(trap_widget)
        if not own_trap_widget_invisible then
            UIManager:forceRePaint()
        end
    end

    if ret_values then
        if task_returns_simple_string then
            return completed, ret_values
        else
            return completed, unpack(ret_values, 1, ret_values.n)
        end
    end
    return completed
end

return Trapper

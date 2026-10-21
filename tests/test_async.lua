local h = dofile("tests/headless.lua")
local Container = {}
function Container:extend(fields)
    return setmetatable(fields, {__index = self})
end
function Container:new(fields)
    fields = fields or {}
    fields.key_events, fields.ges_events = {}, {}
    setmetatable(fields, {__index = self})
    if fields.init then fields:init() end
    return fields
end
local screen = {
    getSize = function() return {w = 600, h = 800} end,
    getWidth = function() return 600 end,
    getHeight = function() return 800 end,
    scaleBySize = function(_, n) return n end,
}
package.preload.device = function()
    return {screen = screen, input = {group = {Any = {}}},
        hasKeys = function() return true end, isTouchDevice = function() return true end}
end
for _, name in ipairs{
    "ui/widget/container/inputcontainer", "ui/widget/container/framecontainer",
    "ui/widget/verticalgroup", "ui/widget/textwidget", "ui/geometry", "ui/gesturerange",
} do
    package.preload[name] = function() return Container end
end
package.preload["ui/widget/progresswidget"] = function()
    return Container:extend{setPercentage = function(self, n) self.percentage = n end}
end
package.preload["ffi/blitbuffer"] = function() return {COLOR_BLACK = 0, COLOR_WHITE = 1} end
package.preload["ui/font"] = function() return {getFace = function() return {} end} end
package.preload["ui/size"] = function()
    return {padding = {large = 8}, margin = {tiny = 1}, radius = {window = 2}, border = {window = 1}}
end
package.preload.dbg = function() return {guard = function() end} end
package.preload["ui/time"] = function() return {now = function() return h.now() * 1000000 end} end
package.preload["ui/widget/progressbardialog"] = function()
    return dofile("tests/upstream/progressbardialog.lua")
end
local Trapper = dofile("tests/upstream/trapper.lua")
package.preload["ui/trapper"] = function() return Trapper end
local Async = require("annas.async_helper")
local ffi = require("ffi")
local UI, Ui, test, run_until, native = h.UI, h.Ui, h.test, h.run_until, h.native

test("cancellable tasks use KOReader's native progress dialog", function()
    local message = Ui.showLoadingMessage("Searching", true)
    assert(message.title == "Searching" and message.subtitle == "Tap anywhere to cancel.")
    assert(message.modal and message.onTapClose and message.onAnyKeyPressed)
    assert(not message.progress_bar_visible)
    message:close()
end)

test("native keyboard cancellation stops the background task", function()
    local gate, cancelled = h.gate()
    local message = Ui.showLoadingMessage("Searching", true)
    Async.run(function() gate:wait() end,
        function() error("cancelled task succeeded") end, function(err) error(err) end,
        message, {on_cancel = function() cancelled = true end})
    run_until(function() return gate:waiting() end)
    message:onAnyKeyPressed()
    run_until(function() return cancelled end)
    assert(#h.killed() == 1)
end)

test("default loading dialog is native and closes after success", function()
    local gate, result = h.gate()
    Async.run(function() gate:wait(); return "done" end,
        function(value) result = value end, function(err) error(err) end)
    local message = next(UI.widgets)
    assert(message and message.title == "Please wait…" and message.onTapClose)
    gate:release()
    run_until(function() return result ~= nil end)
    assert(result == "done" and message._annas_closed)
end)

test("slow request yields UI; results survive serialization", function()
    local gate, result, heartbeat = h.gate()
    Async.run(function()
        gate:wait()
        return {{title = "Нейромант", author = "William Gibson", format = "epub"}}
    end, function(value) result = value end, function(err) error(err) end,
        Ui.showLoadingMessage("Searching", true))
    UI:nextTick(function() heartbeat = true end)
    run_until(function() return heartbeat end)
    assert(result == nil, "request completed before the worker was released")
    gate:release()
    run_until(function() return result ~= nil end)
    assert(result[1].title == "Нейромант" and result[1].format == "epub")
end)

test("tap cancels a hung worker without success/error or late result", function()
    local gate, succeeded, failed, cancelled = h.gate()
    local message = Ui.showLoadingMessage("Searching", true)
    Async.run(function() gate:wait(); return "late result" end,
        function() succeeded = true end, function() failed = true end, message,
        {on_cancel = function() cancelled = true end})
    run_until(function() return gate:waiting() end)
    message:onTapClose()
    run_until(function() return cancelled end)
    assert(not succeeded and not failed and #h.killed() == 1)
    assert(message._annas_closed)
end)

test("deadline terminates a hung request and reports timeout", function()
    local gate, failure, success = h.gate()
    Async.run(function() gate:wait() end,
        function() success = true end, function(err) failure = err end,
        Ui.showLoadingMessage("Searching", true), {timeout_seconds = 90})
    run_until(function() return gate:waiting() end)
    UI:advance(90)
    run_until(function() return failure ~= nil end)
    assert(failure:find("timed out", 1, true) and not success and #h.killed() == 1)
end)

test("cancel kills shell and curl/wget-like descendants too", function()
    ffi.cdef[[int open(const char *, int, ...);]]
    local temporary = os.getenv("ANNAS_TEST_TMPDIR")
    local root = temporary and (temporary .. "/descendants") or os.tmpname()
    os.remove(root)
    local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
    assert(os.execute("mkdir -p " .. quote(root)) == 0)
    h.after_each(function() assert(os.execute("rm -rf " .. quote(root)) == 0) end)
    local fifo, ready, marker = root .. "/fifo", root .. "/ready", root .. "/stale"
    assert(os.execute("mkfifo " .. quote(fifo)) == 0)
    local message, cancelled = Ui.showLoadingMessage("Downloading", true)
    Async.run(function()
        local command = "exec 3<> " .. quote(fifo) .. "; printf ready > " .. quote(ready)
            .. "; read signal <&3; printf stale > " .. quote(marker) .. "; printf result"
        local pipe = assert(io.popen(command, "r"))
        local result = pipe:read("*a")
        pipe:close()
        return result
    end, function() error("cancelled task delivered a result") end, function(err) error(err) end,
        message, {on_cancel = function() cancelled = true end})
    run_until(function()
        local file = io.open(ready, "r")
        if not file then return false end
        local contents = file:read("*a")
        file:close()
        return contents == "ready"
    end)
    local flags = 1 + (ffi.os == "OSX" and 4 or 2048)
    local fd = ffi.C.open(fifo, flags)
    assert(fd >= 0, "shell has not opened its synchronization pipe")
    ffi.C.close(fd)
    message:onTapClose()
    run_until(function() return cancelled end)
    run_until(function()
        local current = ffi.C.open(fifo, flags)
        if current >= 0 then ffi.C.close(current); return false end
        assert(ffi.errno() == 6, "unexpected FIFO error")
        return true
    end)
    local file = io.open(marker, "r")
    if file then file:close() end
    assert(file == nil, "descendant command continued after cancellation")
end)

test("child exception is reported and closes loading widget", function()
    local failure
    Async.run(function() error("network failure") end,
        function() error("unexpected success") end, function(err) failure = err end,
        Ui.showLoadingMessage("Searching", true))
    run_until(function() return failure ~= nil end)
    assert(failure:find("network failure", 1, true))
end)

test("download path and filesystem changes reach parent", function()
    local temporary = os.getenv("ANNAS_TEST_TMPDIR")
    local path, result = temporary and (temporary .. "/ebook") or os.tmpname()
    os.remove(path)
    h.after_each(function() os.remove(path); os.remove(path .. ".part") end)
    Async.run(function()
        local file = assert(io.open(path .. ".part", "wb"))
        assert(file:write("ebook-test-bytes"))
        file:close()
        assert(os.rename(path .. ".part", path))
        return path
    end, function(value) result = value end, function(err) error(err) end,
        Ui.showLoadingMessage("Downloading", true), { timeout_seconds = 300 })
    run_until(function() return result ~= nil end)
    local file = assert(io.open(result, "rb"))
    assert(file:read("*a") == "ebook-test-bytes")
    file:close()
    os.remove(path)
end)

test("fork failure is an error, not silent cancellation", function()
    local original = native.runInSubProcess
    native.runInSubProcess = function() return false, "fork failed" end
    local failure
    Async.run(function() error("must not run in UI process") end,
        function() error("unexpected success") end, function(err) failure = err end,
        Ui.showLoadingMessage("Searching", true))
    native.runInSubProcess = original
    assert(failure == "Could not start the background task.")
end)

test("worker exit without data is reported", function()
    local failure
    Async.run(function() ffi.C._exit(1) end,
        function() error("unexpected success") end, function(err) failure = err end,
        Ui.showLoadingMessage("Searching", true))
    run_until(function() return failure ~= nil end)
    assert(failure == "The background task ended without a result.")
end)

test("repeat cancellation and retry do not leak widgets or callbacks", function()
    for i = 1, 3 do
        local gate, cancelled = h.gate()
        local message = Ui.showLoadingMessage("Searching", true)
        Async.run(function() gate:wait() end,
            function() error("unexpected success") end, function(err) error(err) end,
            message, {on_cancel = function() cancelled = true end})
        run_until(function() return gate:waiting() end)
        message:onTapClose()
        run_until(function() return cancelled end)
        assert(message._annas_closed and message.dismiss_callback == nil)
        Ui.closeMessage(message)
    end
    local result
    Async.run(function() return {} end,
        function(value) result = value end, function(err) error(err) end,
        Ui.showLoadingMessage("Searching", true))
    run_until(function() return result ~= nil end)
    assert(type(result) == "table" and #result == 0)
end)

test("structured API errors use error callback", function()
    local failure
    Async.run(function() return {error = "HTTP 503"} end,
        function() error("unexpected success") end, function(err) failure = err end,
        Ui.showLoadingMessage("Searching", true))
    run_until(function() return failure ~= nil end)
    assert(failure == "HTTP 503")
end)

h.run()

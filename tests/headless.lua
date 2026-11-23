local plugin_dir = arg[1] or "."
local selected, listing
for i = 2, #arg do
    if arg[i] == "--case" then selected = arg[i + 1] end
    if arg[i] == "--list" then listing = true end
end
package.path = plugin_dir .. "/?.lua;" .. plugin_dir .. "/?/init.lua;" .. package.path
io.stdout:setvbuf("no")
local ffi = require("ffi")
ffi.cdef[[
struct timespec { long tv_sec; long tv_nsec; };
int clock_gettime(int, struct timespec *);
]]
local function now()
    local ts = ffi.new("struct timespec")
    assert(ffi.C.clock_gettime(ffi.os == "OSX" and 6 or 1, ts) == 0)
    return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) / 1000000000
end
local offset = 0
local function clock() return now() + offset end
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end

local warnings = {}
package.preload.logger = function()
    local function ignore() end
    return { dbg = ignore, info = ignore, err = ignore,
        warn = function(...) warnings[#warnings + 1] = {...} end }
end
package.preload.gettext = function() return function(text) return text end end
package.preload["annas.gettext"] = package.preload.gettext

local UI = { events = {}, widgets = {}, standby = 0 }
function UI:scheduleIn(seconds, fn)
    self.events[#self.events + 1] = { at = clock() + seconds, fn = fn }
end
function UI:advance(seconds) offset = offset + seconds end
function UI:nextTick(fn) self:scheduleIn(0, fn) end
function UI:unschedule(fn)
    for i = #self.events, 1, -1 do
        if self.events[i].fn == fn then table.remove(self.events, i) end
    end
end
function UI:show(widget)
    self.widgets[widget] = true
    if widget.onShow then widget:onShow() end
end
function UI:close(widget)
    if not self.widgets[widget] then return end
    self.widgets[widget] = nil
    if widget.onCloseWidget then widget:onCloseWidget() end
end
function UI:preventStandby() self.standby = self.standby + 1 end
function UI:allowStandby() self.standby = self.standby - 1 end
function UI:forceRePaint() end
function UI:setDirty() end
package.preload["ui/uimanager"] = function() return UI end

local Info = {}
function Info:new(options)
    options.modal = true
    if options.dismissable == nil then options.dismissable = true end
    return setmetatable(options, { __index = self })
end
function Info:onShow()
    if self.timeout then
        self._timeout_func = function() UI:close(self) end
        UI:scheduleIn(self.timeout, self._timeout_func)
    end
end
function Info:onCloseWidget()
    if self._timeout_func then UI:unschedule(self._timeout_func) end
    if self.dismiss_callback then
        self.dismiss_callback()
        if not self.is_infomessage then self.dismiss_callback = nil end
    end
end
package.preload["ui/widget/infomessage"] = function() return Info end
package.preload["ui/widget/trapwidget"] = function() return Info end
for _, name in ipairs{
    "ui/widget/confirmbox", "ui/widget/textviewer", "ui/downloadmgr",
    "ui/widget/inputdialog", "ui/widget/buttondialog", "annas.menu",
    "annas.config", "annas.ota", "util",
} do
    package.preload[name] = function() return {} end
end

local native = dofile("tests/upstream/subprocess.lua")
local spawned, killed = {}, {}
local spawn = native.runInSubProcess
native.runInSubProcess = function(...)
    local pid, fd = spawn(...)
    if pid then
        spawned[#spawned + 1] = pid
        local registry = os.getenv("ANNAS_TEST_PROCESS_LOG")
        if registry then
            local file = assert(io.open(registry, "a"))
            file:write(tostring(pid), "\n")
            file:close()
        end
    end
    return pid, fd
end
local terminate = native.terminateSubProcess
native.terminateSubProcess = function(pid)
    killed[#killed + 1] = pid
    return terminate(pid)
end
package.preload["ffi/util"] = function() return native end
local Ui = require("annas.ui")

local function run_until(predicate, limit)
    local deadline = now() + (limit or 2)
    while not predicate() do
        assert(now() < deadline, "test event loop timed out")
        local selected
        for i, event in ipairs(UI.events) do
            if not selected or event.at < UI.events[selected].at then selected = i end
        end
        if selected and UI.events[selected].at <= clock() then
            local event = table.remove(UI.events, selected)
            event.fn()
        else
            ffi.C.usleep(1000)
        end
    end
end

local cleanups, cases = {}, {}
local function after_each(fn) cleanups[#cleanups + 1] = fn end
local function cleanup()
    local errors = {}
    for _, pid in ipairs(spawned) do
        ffi.C.kill(-pid, 9)
    end
    for _, pid in ipairs(spawned) do
        local ok, err = pcall(run_until, function()
            if native.isSubProcessDone(pid) then return true end
            ffi.C.kill(-pid, 9)
            return false
        end)
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    for i = #cleanups, 1, -1 do
        local ok, err = pcall(cleanups[i])
        if not ok then errors[#errors + 1] = tostring(err) end
    end
    return table.concat(errors, "\n")
end
local function finish()
    for _, pid in ipairs(spawned) do
        run_until(function() return native.isSubProcessDone(pid) end)
    end
    local pending = UI.events
    UI.events = {}
    for _, event in ipairs(pending) do event.fn() end
    assert(#UI.events == 0, "stale timer/callback after completion")
    assert(next(UI.widgets) == nil, "loading widget was left open")
    assert(UI.standby == 0, "standby inhibition leaked")
    for _, warning in ipairs(warnings) do
        assert(warning[1] ~= "error in wrapped function:", tostring(warning[2]))
        assert(not tostring(warning[1]):find("unwrapped", 1, true), "Trapper ran without wrap()")
    end
end
local function gate()
    local ready, release = ffi.new("int[2]"), ffi.new("int[2]")
    assert(ffi.C.pipe(ready) == 0 and ffi.C.pipe(release) == 0)
    local closed, released = false, false
    local g = {}
    function g:wait()
        assert(ffi.C.write(ready[1], "x", 1) == 1)
        local byte = ffi.new("char[1]")
        assert(ffi.C.read(release[0], byte, 1) == 1)
    end
    function g:waiting()
        return (native.getNonBlockingReadSize(tonumber(ready[0])) or 0) > 0
    end
    function g:release()
        assert(not released, "gate released twice")
        assert(ffi.C.write(release[1], "x", 1) == 1)
        released = true
    end
    after_each(function()
        if closed then return end
        closed = true
        ffi.C.close(ready[0]); ffi.C.close(ready[1])
        ffi.C.close(release[0]); ffi.C.close(release[1])
    end)
    return g
end
local function test(name, fn)
    for _, case in ipairs(cases) do assert(case.name ~= name, "duplicate test name: " .. name) end
    cases[#cases + 1] = {name = name, fn = fn}
end
local function run()
    if listing then
        for _, case in ipairs(cases) do print("TEST\t" .. case.name) end
        assert(cleanup() == "")
        return
    end
    assert(selected, "Use python3 tests/run.py, or select one test with --case")
    local found
    for _, case in ipairs(cases) do
        if case.name == selected then found = case; break end
    end
    assert(found, "unknown test: " .. selected)
    local ok, err = xpcall(function() found.fn(); finish() end, debug.traceback)
    local cleanup_error = cleanup()
    if not ok or cleanup_error ~= "" then
        io.stderr:write("FAIL " .. selected .. "\n" .. tostring(err or "") .. "\n" .. cleanup_error .. "\n")
        os.exit(1)
    end
    print("PASS " .. selected)
end
return {UI = UI, Ui = Ui, test = test, run_until = run_until, native = native,
    now = now, warnings = warnings, killed = function() return killed end,
    gate = gate, after_each = after_each, run = run}

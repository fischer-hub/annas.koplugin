local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local ffi = require("ffi")
local CoverCache = require("annas.cover_cache")
local CoverUtils = require("annas.cover_utils")
local logger = require("logger")

local M = {}
M.__index = M
local CONCURRENCY = 2
local JOB_TIMEOUT = 12
local PAGE_TIMEOUT = 40
local TERMINAL = {ready = true, unavailable = true, error = true, timeout = true, cancelled = true}

function M:new() return setmetatable({jobs = {}, states = {}}, self) end

local function reap(pid)
    if ffiutil.isSubProcessDone(pid) then return end
    local collect
    collect = function()
        if not ffiutil.isSubProcessDone(pid) then UIManager:scheduleIn(0.2, collect) end
    end
    UIManager:scheduleIn(0.2, collect)
end

local function close_pipe(job)
    if job.fd then ffi.C.close(job.fd); job.fd = nil end
end

function M:stop(reason)
    if self.poll then UIManager:unschedule(self.poll) end
    if self.deadline then UIManager:unschedule(self.deadline) end
    for _, job in ipairs(self.jobs) do
        UIManager:unschedule(job.timeout)
        ffiutil.terminateSubProcess(job.pid)
        close_pipe(job)
        reap(job.pid)
    end
    for _, state in pairs(self.states) do
        if not TERMINAL[state.stage] then state.stage = reason or "cancelled" end
    end
    self.jobs = {}
    self.pid = nil
end

function M:_consume(job, bytes)
    job.buffer = (job.buffer or "") .. bytes
    local changed = false
    while true do
        local line, rest = job.buffer:match("^([^\n]*)\n(.*)$")
        if not line then break end
        job.buffer = rest
        local stage, received, total = line:match("^(%a+) (%d+) (%d+)$")
        if stage then
            local state = self.states[job.key]
            received, total = tonumber(received), tonumber(total)
            if state.stage ~= stage or state.received ~= received or state.total ~= total then
                state.stage, state.received, state.total = stage, received, total
                changed = true
            end
        end
    end
    return changed
end

function M:_read(job)
    if not job.fd then return false end
    local available = ffiutil.getNonBlockingReadSize(job.fd)
    if not available or available <= 0 then return false end
    local size = math.min(available, 8192)
    local buffer = ffi.new("char[?]", size)
    local count = tonumber(ffi.C.read(job.fd, buffer, size))
    if count > 0 then return self:_consume(job, ffi.string(buffer, count)) end
    return false
end

function M:_finish(job, reason)
    UIManager:unschedule(job.timeout)
    if reason then
        ffiutil.terminateSubProcess(job.pid)
        close_pipe(job)
        reap(job.pid)
    elseif job.fd then
        self:_consume(job, ffiutil.readAllFromFD(job.fd))
        job.fd = nil
    end
    local state = self.states[job.key]
    if CoverCache.get(job.book) then
        state.stage = "ready"
    elseif reason then
        state.stage = reason
    elseif not TERMINAL[state.stage] then
        state.stage = "unavailable"
    end
    for i, active in ipairs(self.jobs) do
        if active == job then table.remove(self.jobs, i); break end
    end
    self.pid = self.jobs[1] and self.jobs[1].pid
end

function M:_fill()
    while #self.jobs < CONCURRENCY and self.next_index <= #self.books do
        local book = self.books[self.next_index]
        self.next_index = self.next_index + 1
        local key = CoverUtils.key(book)
        local pid, fd = ffiutil.runInSubProcess(function(_, output_fd)
            local previous
            local function report(stage, received, total)
                received, total = received or 0, total or 0

                local bucket = total > 0 and math.floor(received * 100 / total) or math.ceil(received / 8192)
                local signature = stage .. ":" .. bucket
                if signature ~= previous then
                    previous = signature
                    ffiutil.writeToFD(output_fd, string.format("%s %d %d\n", stage, received, total))
                end
            end
            local ok, err = pcall(CoverCache.fetch, book, report)
            if not ok then
                logger.dbg("Annas cover fetch failed:", err)
                report("error")
            end
            ffi.C.close(output_fd)
        end, true)
        if pid then
            local job = {book = book, key = key, pid = pid, fd = fd, buffer = ""}
            self.jobs[#self.jobs + 1] = job
            self.states[key].stage = "lookup"
            job.timeout = function()
                if self.states[key] and not TERMINAL[self.states[key].stage] then
                    self:_finish(job, "timeout")
                    self:_fill()
                    if not self.pid then
                        UIManager:unschedule(self.poll)
                        UIManager:unschedule(self.deadline)
                    end
                    self.on_update()
                end
            end
            UIManager:scheduleIn(JOB_TIMEOUT, job.timeout)
        else
            self.states[key].stage = "error"
            self._dirty = true
        end
    end
    self.pid = self.jobs[1] and self.jobs[1].pid
end

function M:start(books, on_update)
    self:stop()
    self.books, self.next_index, self.on_update = books, 1, on_update
    self.states = {}
    for _, book in ipairs(books) do
        local key = CoverUtils.key(book)
        if key then self.states[key] = {stage = "queued", received = 0, total = 0} end
    end
    if #books == 0 then return end
    self:_fill()
    self.poll = function()
        local changed = self._dirty or false
        self._dirty = false
        for i = #self.jobs, 1, -1 do
            local job = self.jobs[i]
            changed = self:_read(job) or changed
            if ffiutil.isSubProcessDone(job.pid) then
                self:_finish(job)
                changed = true
            end
        end
        self:_fill()
        if self.pid then
            UIManager:scheduleIn(0.5, self.poll)
        else
            UIManager:unschedule(self.deadline)

            pcall(CoverCache.prune)
        end
        if changed then on_update() end
    end
    self.deadline = function()
        self:stop("timeout")
        on_update()
    end
    UIManager:scheduleIn(PAGE_TIMEOUT, self.deadline)
    UIManager:scheduleIn(0.5, self.poll)
end

return M

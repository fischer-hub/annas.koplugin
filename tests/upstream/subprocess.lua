local ffi = require("ffi")
ffi.cdef[[
typedef int pid_t;
int pipe(int *);
pid_t fork(void);
void _exit(int);
int setpgid(pid_t, pid_t);
pid_t getpid(void);
int close(int);
int setpriority(int, unsigned int, int);
pid_t waitpid(pid_t, int *, int);
int kill(pid_t, int);
int ioctl(int, unsigned long, ...);
long read(int, void *, unsigned long);
long write(int, const void *, unsigned long);
int usleep(unsigned int);
int fileno(void *);
char *strerror(int);
struct sched_param { int sched_priority; };
int sched_setscheduler(pid_t, int, const struct sched_param *);
enum { PRIO_PROCESS = 0, WNOHANG = 1, SCHED_BATCH = 3 };
]]
ffi.cdef(ffi.os == "OSX" and "enum { FIONREAD = 0x4004667f };" or "enum { FIONREAD = 0x541b };")
local C = ffi.C
local posix = { strerror = function() return ffi.string(C.strerror(ffi.errno())) end }
local logger = require("logger")
local util = {}
local _run_before_fork_funcs, _run_after_fork_parent_funcs, _run_in_subprocess_after_fork_funcs = {}, {}, {}

function util.runInSubProcess(func, with_pipe, double_fork)
    local parent_read_fd, parent_write_fd
    local child_read_fd, child_write_fd
    if with_pipe then
        local pipe = ffi.new('int[2]', {-1, -1})
        if C.pipe(pipe) ~= 0 then
            return false, "failed creating pipe: "..posix.strerror()
        end
        parent_read_fd, child_write_fd = pipe[0], pipe[1]
        if with_pipe == 'bidi' then
            if C.pipe(pipe) ~= 0 then
                return false, "failed creating pipe: "..posix.strerror()
            end
            parent_write_fd, child_read_fd = pipe[1], pipe[0]
        end
    end

    for _, f in pairs(_run_before_fork_funcs) do
        f()
    end
    local pid = C.fork()

    if pid ~= 0 then
        for _, f in pairs(_run_after_fork_parent_funcs) do
            f()
        end
    end
    if pid == 0 then
        for _, f in pairs(_run_in_subprocess_after_fork_funcs) do
            f()
        end
        if double_fork then
            pid = C.fork()
            if pid ~= 0 then

                C._exit((pid < 0) and 1 or 0)
            end

        end

        local ok, err = xpcall(function()

            C.setpgid(0, 0)

            if parent_read_fd then
                C.close(parent_read_fd)
            end
            if parent_write_fd then
                C.close(parent_write_fd)
            end

            if ffi.os == "Linux" then

                local param = ffi.new("struct sched_param")
                C.sched_setscheduler(0, C.SCHED_BATCH, param)
            end

            C.setpriority(C.PRIO_PROCESS, 0, 5)

            pid = C.getpid()
            func(pid, child_write_fd, child_read_fd)
        end, debug.traceback)
        if not ok then
            print("error in subprocess:", err)
        end
        C._exit(0)
    end

    if pid < 0 then
        return false, "fork failed: "..posix.strerror()
    end

    if double_fork then
        local status = ffi.new('int[1]')
        local ret = C.waitpid(pid, status, 0)

        if ret < 0 then
            return false, "double fork failed: "..posix.strerror()
        end
    end

    if child_read_fd then
        C.close(child_read_fd)
    end
    if child_write_fd then
        C.close(child_write_fd)
    end
    return pid, parent_read_fd, parent_write_fd
end

function util.isSubProcessDone(pid, wait)
    local status = ffi.new('int[1]')
    local ret = C.waitpid(pid, status, wait and 0 or C.WNOHANG)

    if ret == pid or ret == -1 then
        return true
    end
    return false
end

function util.terminateSubProcess(pid)
    local done = util.isSubProcessDone(pid)
    if not done then

        C.kill(-pid, 9)

    end
end

function util.getNonBlockingReadSize(fd_or_luafile)
    local fileno
    if type(fd_or_luafile) == "number" then
        fileno = fd_or_luafile
    else
        fileno = C.fileno(fd_or_luafile)
    end
    local available = ffi.new('int[1]')
    local ok = C.ioctl(fileno, C.FIONREAD, available)
    if ok ~= 0 then
        print("C.ioctl(…, FIONREAD, …) failed:", posix.strerror())
        return
    end
    available = tonumber(available[0])
    return available
end

function util.writeToFD(fd, data, close_fd)
    local size = #data
    local ptr = ffi.cast("uint8_t *", data)

    local bytes_written = C.write(fd, ptr, size)

    local success = bytes_written == size
    if close_fd then
        C.close(fd)

    end
    return success
end

function util.readAllFromFD(fd)
    local chunksize = 8192
    local buffer = ffi.new('char[?]', chunksize, {0})
    local data = {}
    while true do

        local bytes_read = tonumber(C.read(fd, ffi.cast('void*', buffer), chunksize))
        if bytes_read < 0 then
            print("readAllFromFD() error: "..posix.strerror())
            break
        elseif bytes_read == 0 then
            break
        else
            table.insert(data, ffi.string(buffer, bytes_read))
        end
    end
    C.close(fd)

    return table.concat(data)
end

return util

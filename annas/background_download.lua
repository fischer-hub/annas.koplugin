-- Runs a book download as a detached shell job (src/download_job.sh), so the
-- KOReader UI thread never waits on the network. The job writes a single
-- status line when it finishes, and this module polls for it from the UI loop.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
require("src.scraper")  -- provides sanitize_name() and libgen_mirror_list()

local BackgroundDownload = {}

local POLL_INTERVAL = 0.5
local JOB_TIMEOUT = 20 * 60
-- The job removes its PID file only after it writes the status file, so a
-- missing PID file with no status means the shell died without reporting.
local STARTUP_GRACE = 3

-- Plugin root (the annas.koplugin directory), derived from this file's path.
local function plugin_root()
    local source = debug.getinfo(1, "S").source
    local dir = source:match("^@(.*/)") or "./"
    return dir .. ".."
end

local function shell_quote(value)
    return "'" .. (tostring(value):gsub("'", "'\\''")) .. "'"
end

local function ensure_dir(path)
    if lfs.attributes(path, "mode") ~= "directory" then
        lfs.mkdir(path)
    end
end

-- Prefer the aria2c binary Rakuyomi ships for Kindle, then common system
-- locations. An empty result makes the job fall back to curl.
local function find_aria2c()
    local candidates = {
        plugin_root() .. "/../rakuyomi.koplugin/aria2c",
        "/usr/bin/aria2c",
        "/usr/local/bin/aria2c",
    }
    for _, path in ipairs(candidates) do
        if lfs.attributes(path, "mode") == "file" then
            return path
        end
    end
    return ""
end

-- aria2c on Kindle has no CA bundle of its own, so hand it KOReader's.
local function find_ca_bundle()
    local candidates = {
        lfs.currentdir() .. "/data/ca-bundle.crt",
        "/etc/ssl/certs/ca-certificates.crt",
    }
    for _, path in ipairs(candidates) do
        if lfs.attributes(path, "mode") == "file" then
            return path
        end
    end
    return ""
end

-- Final file location for a book, matching the naming the plugin has always used.
function BackgroundDownload.targetPath(book, dir)
    return dir .. "/" .. sanitize_name(book.title) .. "_" .. sanitize_name(book.author) .. "." .. book.format
end

local function read_status(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

local function pid_file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function finish(job, on_done, ok, message)
    if job.finished then return end
    job.finished = true
    os.remove(job.status_file)
    os.remove(job.pid_file)
    if on_done then on_done(ok, message) end
end

local function stop(job)
    local f = io.open(job.pid_file, "r")
    if f then
        local pid = f:read("*l")
        f:close()
        if pid and pid:match("^%d+$") then
            os.execute("kill " .. pid)
        end
    end
    os.remove(job.pid_file)
end

-- Start downloading `book` into `dir`. `on_done(ok, message)` runs on the UI
-- loop: with the saved path when ok is true, or with a reason when it is false.
function BackgroundDownload.start(book, dir, on_done)
    local job_dir = DataStorage:getDataDir() .. "/cache/annas-downloads"
    ensure_dir(DataStorage:getDataDir() .. "/cache")
    ensure_dir(job_dir)

    local stamp = book.md5 .. "-" .. tostring(os.time())
    local job = {
        status_file = job_dir .. "/" .. stamp .. ".status",
        pid_file = job_dir .. "/" .. stamp .. ".pid",
        finished = false,
    }

    if not (book.download and string.find(book.download, "lgli", 1, true)) then
        UIManager:scheduleIn(0, function()
            finish(job, on_done, false, "This book is not available on Library Genesis.")
        end)
        return job
    end

    local args = {
        "sh",
        plugin_root() .. "/src/download_job.sh",
        job.status_file,
        job.pid_file,
        BackgroundDownload.targetPath(book, dir),
        book.md5,
        book.format,
        find_aria2c(),
    }
    for _, mirror in ipairs(libgen_mirror_list()) do
        table.insert(args, mirror)
    end

    local quoted = {}
    for i, value in ipairs(args) do
        quoted[i] = shell_quote(value)
    end
    local command = "ANNAS_CA_BUNDLE=" .. shell_quote(find_ca_bundle()) .. " "
        .. table.concat(quoted, " ") .. " >/dev/null 2>&1 &"
    logger.info("Annas:BackgroundDownload - starting job for " .. book.md5)
    os.execute(command)

    local started = os.time()
    local function poll()
        if job.finished then return end
        local line = read_status(job.status_file)
        if line and line:sub(1, 3) == "OK " then
            finish(job, on_done, true, line:sub(4))
        elseif line and line:sub(1, 5) == "FAIL " then
            finish(job, on_done, false, line:sub(6))
        elseif os.time() - started >= STARTUP_GRACE
            and not pid_file_exists(job.pid_file) then
            finish(job, on_done, false, "The download job stopped unexpectedly.")
        elseif os.time() - started > JOB_TIMEOUT then
            stop(job)
            finish(job, on_done, false, "The download timed out.")
        else
            UIManager:scheduleIn(POLL_INTERVAL, poll)
        end
    end
    UIManager:scheduleIn(POLL_INTERVAL, poll)

    return job
end

return BackgroundDownload

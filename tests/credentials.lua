-- Credential loader tests. Run from the plugin root:
--   luajit tests/credentials.lua <tempdir>
--
-- <tempdir> must be an existing, dedicated, writable directory.

local tempdir = arg and arg[1]
assert(tempdir, "usage: luajit tests/credentials.lua <tempdir>")
tempdir = tempdir:gsub("/+$", "") .. "/"

local probe = io.open(tempdir .. ".credentials_test_probe", "w")
assert(probe, "tempdir is not writable or does not exist: " .. tempdir)
probe:close()
os.remove(tempdir .. ".credentials_test_probe")

-- Resolve the plugin root (parent of this script's directory) so the test
-- works from any cwd.
local script_dir = arg[0]:match("^(.*)/[^/]+$") or "."
local plugin_root = script_dir .. "/../"

-- ---------- KOReader environment stubs ----------

local logs = {}
local store = {}

package.preload["util"] = function()
    return { trim = function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end }
end
package.preload["annas.gettext"] = function()
    return function(s) return s end
end
package.preload["logger"] = function()
    return {
        info = function(msg) table.insert(logs, tostring(msg)) end,
        warn = function(msg) table.insert(logs, tostring(msg)) end,
    }
end
package.preload["apps/filemanager/filemanagerutil"] = function()
    return { getDefaultDir = function() return "/nonexistent-default" end }
end

G_reader_settings = {
    readSetting = function(self, key) return store[key] end,
    saveSetting = function(self, key, value) store[key] = value end,
    delSetting = function(self, key) store[key] = nil end,
}

local Config = dofile(plugin_root .. "annas/config.lua")
local KEY = Config.SETTINGS_AA_SECRET_KEY_KEY

-- ---------- helpers ----------

local failures = 0
local function check(cond, name)
    if cond then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name)
    end
end

local function reset()
    for k in pairs(store) do store[k] = nil end
    for i = #logs, 1, -1 do logs[i] = nil end
end

local function write_file(name, body)
    local f = assert(io.open(tempdir .. name, "w"))
    f:write(body)
    f:close()
end

local function remove_file(name)
    os.remove(tempdir .. name)
end

local function remove_fixtures()
    remove_file(Config.CREDENTIALS_FILENAME)
end

local function logs_contain(needle)
    for _, line in ipairs(logs) do
        if line:find(needle, 1, true) then return true end
    end
    return false
end

-- ---------- scenarios ----------

remove_fixtures()

-- 1. First launch: no saved key, valid file present -> imports once.
write_file(Config.CREDENTIALS_FILENAME, 'return { annasSecretKey = "  FILE-KEY  " }')
reset()
Config.loadCredentialsFromFile(tempdir)
check(store[KEY] == "FILE-KEY", "first import stores trimmed file key")
check(Config.getAnnasSecretKey() == "FILE-KEY", "imported key is retrievable")
check(not logs_contain("FILE-KEY"), "import success log does not echo key")

-- 2. User then sets a key via the UI; file must never override it again.
Config.setAnnasSecretKey("UI-KEY")
write_file(Config.CREDENTIALS_FILENAME, 'return { annasSecretKey = "ROTATED-FILE-KEY" }')
Config.loadCredentialsFromFile(tempdir)
Config.loadCredentialsFromFile(tempdir)
check(store[KEY] == "UI-KEY", "UI key survives repeat loader calls")
check(Config.getAnnasSecretKey() == "UI-KEY", "getter returns UI key, not file key")

-- 3. Clearing the key stores a deliberate empty value that must block re-import.
Config.setAnnasSecretKey("")
check(Config.getAnnasSecretKey() == nil, "cleared key reads as unset")
Config.loadCredentialsFromFile(tempdir)
Config.loadCredentialsFromFile(tempdir)
check(store[KEY] == "", "cleared key is not resurrected by credentials file")

-- 4. Syntax error quoting the secret must not leak it into logs.
reset()
write_file(Config.CREDENTIALS_FILENAME, 'return { annasSecretKey = "UNTERMINATED-FAKE-SECRET')
Config.loadCredentialsFromFile(tempdir)
check(store[KEY] == nil, "unterminated file stores no key")
check(not logs_contain("UNTERMINATED-FAKE-SECRET"), "syntax error does not echo secret into logs")

-- 5. A file raising a runtime error containing a secret must not leak it.
reset()
write_file(Config.CREDENTIALS_FILENAME, 'error("RUNTIME-FAKE-SECRET")')
Config.loadCredentialsFromFile(tempdir)
check(store[KEY] == nil, "runtime-error file stores no key")
check(not logs_contain("RUNTIME-FAKE-SECRET"), "runtime error does not echo secret into logs")

-- 6. No credentials file at all: nothing stored, nothing logged.
reset()
remove_fixtures()
Config.loadCredentialsFromFile(tempdir)
check(store[KEY] == nil, "no files means no stored key")
check(#logs == 0, "no files means no log noise")

remove_fixtures()

if failures > 0 then
    print(string.format("%d FAILURES", failures))
    os.exit(1)
end
print("ALL PASS")

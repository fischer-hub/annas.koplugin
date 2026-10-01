-- Api.redactSecrets regression coverage with KOReader/network modules stubbed.
-- Run from the plugin root: luajit tests/redaction.lua
local root = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/../"
local KEY = "FAKE+%/SECRET.KEY"
local configured_key = KEY

package.loaded["annas.config"] = {
    getAnnasSecretKey = function() return configured_key end,
}
package.loaded["annas.gettext"] = function(text) return text end
package.loaded["logger"] = { dbg = function() end, err = function() end }
package.loaded["socketutil"] = {}
package.loaded["socket.http"] = {}
package.loaded["ltn12"] = {}

local Api = assert(loadfile(root .. "annas/api.lua"))()

local function check(label, expected, actual)
    assert(actual == expected,
        label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    print("PASS " .. label)
end

check("configured key",
    "https://annas-archive.example/account/?key=[REDACTED]&x=1",
    Api.redactSecrets("https://annas-archive.example/account/?key=" .. KEY .. "&x=1"))
check("url-encoded configured key",
    "https://annas-archive.example/account/?key=[REDACTED]&x=1",
    Api.redactSecrets("https://annas-archive.example/account/?key=FAKE%2B%25%2FSECRET.KEY&x=1"))
check("url-encoded key in path",
    "https://cdn.example/[REDACTED]/file.epub",
    Api.redactSecrets("https://cdn.example/FAKE%2B%25%2FSECRET.KEY/file.epub"))
check("key in log text",
    "failed request to https://host/path?key=[REDACTED] body: bad",
    Api.redactSecrets("failed request to https://host/path?key=" .. KEY .. " body: bad"))
check("generic key parameter",
    "https://host/path?key=[REDACTED]&x=1",
    Api.redactSecrets("https://host/path?key=other-secret&x=1"))
check("multiple key parameters",
    "https://host/path?key=[REDACTED]&key=[REDACTED]",
    Api.redactSecrets("https://host/path?key=one&key=two"))
check("non-string input", "42", Api.redactSecrets(42))

configured_key = nil
check("no configured key",
    "https://host/path?key=[REDACTED]&x=1",
    Api.redactSecrets("https://host/path?key=other-secret&x=1"))

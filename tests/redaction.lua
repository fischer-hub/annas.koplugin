local root = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/../"
local KEY = "FAKE+%/SECRET.KEY"
local configured_key = KEY
local logs = {}
local function record(message) logs[#logs + 1] = tostring(message) end

package.loaded["annas.config"] = { getAnnasSecretKey = function() return configured_key end }
package.loaded["annas.gettext"] = function(text) return text end
package.loaded["logger"] = { dbg = record, err = record }
package.loaded["socketutil"] = { table_sink = function(parts)
    return function(chunk) if chunk then parts[#parts + 1] = chunk end; return 1 end
end }
local behavior = "success"
package.loaded["socket.http"] = { request = function()
    if behavior == "throw" then error("request rejected for " .. KEY) end
    if behavior == "http_error" then return 1, 403, {}, "403 denied " .. KEY end
    return 1, 200, {}, "OK"
end }

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
check("multiple key parameters",
    "https://host/path?key=[REDACTED]&key=[REDACTED]",
    Api.redactSecrets("https://host/path?key=one&key=two"))
check("non-string input", "42", Api.redactSecrets(42))

local function private(result, label)
    for _, message in ipairs(logs) do
        assert(not message:find(KEY, 1, true), label .. " leaked the configured key")
        assert(not message:find("UNSAVED-QUERY-SECRET", 1, true), label .. " leaked a query credential")
    end
    assert(not tostring(result.error):find(KEY, 1, true), label .. " returned a secret-bearing error")
    logs = {}
    print("PASS " .. label)
end
private(Api.makeHttpRequest({url = "https://cdn.example/" .. KEY .. "/book"}), "signed CDN URL diagnostics")
private(Api.makeHttpRequest({url = "https://archive.example/api?key=UNSAVED-QUERY-SECRET"}), "API query diagnostics")
behavior = "throw"
local result = Api.makeHttpRequest({url = "https://cdn.example/book"})
assert(result.error and result.error:find("request rejected", 1, true), "request failure was hidden")
private(result, "thrown transport failure")
behavior = "http_error"
result = Api.makeHttpRequest({url = "https://cdn.example/book"})
assert(result.status_code == 403 and result.error, "HTTP failure was hidden")
private(result, "HTTP status diagnostics")

configured_key = nil
check("generic key parameter without a configured key",
    "https://host/path?key=[REDACTED]&x=1",
    Api.redactSecrets("https://host/path?key=other-secret&x=1"))
print("ALL PASS")

-- Run from the plugin root: luajit tests/transport.lua
local root = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/../"
local key = "FAKE+%/SECRET.KEY"
local logs = {}
local function record(message) logs[#logs + 1] = tostring(message) end
package.preload["logger"] = function() return { dbg = record, err = record } end
package.preload["annas.gettext"] = function() return function(message) return message end end
package.loaded["annas.config"] = { getAnnasSecretKey = function() return key end }
package.preload["socketutil"] = function()
    return { table_sink = function(parts)
        return function(chunk) if chunk then parts[#parts + 1] = chunk end; return 1 end
    end }
end
local behavior = "success"
package.preload["socket.http"] = function()
    return { request = function()
        if behavior == "throw" then error("request rejected for " .. key) end
        if behavior == "http_error" then return 1, 403, {}, "403 denied " .. key end
        return 1, 200, {}, "OK"
    end }
end
local Api = dofile(root .. "annas/api.lua")
local function private(result, label)
    for _, message in ipairs(logs) do
        assert(not message:find(key, 1, true), label .. " leaked the configured key")
        assert(not message:find("UNSAVED-QUERY-SECRET", 1, true), label .. " leaked a query credential")
    end
    assert(not tostring(result.error):find(key, 1, true), label .. " returned a secret-bearing error")
    logs = {}
    print("PASS " .. label)
end
private(Api.makeHttpRequest({url = "https://cdn.example/" .. key .. "/book"}), "signed CDN URL diagnostics")
private(Api.makeHttpRequest({url = "https://archive.example/api?key=UNSAVED-QUERY-SECRET"}), "API query diagnostics")
behavior = "throw"
local result = Api.makeHttpRequest({url = "https://cdn.example/book"})
assert(result.error and result.error:find("request rejected", 1, true), "request failure was hidden")
private(result, "thrown transport failure")
behavior = "http_error"
result = Api.makeHttpRequest({url = "https://cdn.example/book"})
assert(result.status_code == 403 and result.error, "HTTP failure was hidden")
private(result, "HTTP status diagnostics")
print("ALL PASS")

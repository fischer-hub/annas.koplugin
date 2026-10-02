local directory = assert(arg[1], "a dedicated writable temporary directory is required")
local root = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/../"
local ffi = require("ffi")
ffi.cdef[[ int chdir(const char *path); ]]

local KEY = "FAKE KEY+/1"
local MD5 = "0123456789abcdef0123456789abcdef"

package.loaded["annas.config"] = {
    getAnnasSecretKey = function() return KEY end,
}

local JSON = {
    ['{"error":"Invalid secret key"}'] = { error = "Invalid secret key" },
    ['{"download_url":"https://cdn.example/file"}'] = { download_url = "https://cdn.example/file" },
}
package.preload["json"] = function()
    return { decode = function(text) return JSON[text] or error("not json") end }
end

local requests, respond
package.loaded["annas.api"] = {
    makeHttpRequest = function(options)
        table.insert(requests, options)
        local status, headers, body = respond(options)
        local result = { status_code = status, headers = headers or {}, body = body or "" }
        if status ~= 200 and status ~= 206 then
            result.error = "HTTP Error: " .. tostring(status)
        end
        return result
    end,
}
assert(loadfile(root .. "src/scraper.lua"))("fast-download-test")

check_url = function(url)
    if url:find("cdn.example", 1, true) then
        return "success", "EPUB-BYTES"
    end
    return "http_error", nil, 403
end

-- scraper.lua reads its domain cache from the working directory.
assert(ffi.C.chdir(directory) == 0, "cannot chdir to " .. directory)
local cache = assert(io.open("annas_domains_cache.txt", "w"))
cache:write(os.time() .. "\nannas-archive.example\nannas-archive.gl\nannas-archive.pk\n")
cache:close()

local real_print = print
print = function() end
local function pass(label) real_print("PASS " .. label) end

local function reset(handler)
    requests, respond = {}, handler
end

local function host(options) return options.url:match("^https://([^/]+)") end

local book = { title = "Das Kapital", author = "Marx", format = "EPUB", md5 = MD5 }

reset(function() return 401, {}, '{"error":"Invalid secret key"}' end)
local result = download_book(book, directory)
assert(result:find("^Failed,") and result:find("Invalid secret key", 1, true),
    "API error message was lost: " .. tostring(result))
assert(#requests == 1 and host(requests[1]) == "annas-archive.gl", "a rejected key was sent to more mirrors")
assert(requests[1].url:find("key=", 1, true), "the member key was not sent")
assert(requests[1].redirect == false, "a request carrying the key may follow redirects")
pass("API errors surface their message and stop the mirror loop")

reset(function() return 200, {}, '{"download_url":"https://cdn.example/file"}' end)
result = download_book(book, directory)
local file = assert(io.open(result, "rb"), "fast download did not save a file: " .. tostring(result))
assert(file:read("*a") == "EPUB-BYTES", "saved file has the wrong content")
file:close()
assert(result:sub(-5) == ".EPUB", "saved file has the wrong extension: " .. result)
for _, request in ipairs(requests) do
    assert(host(request) ~= "annas-archive.example", "the key reached an unlisted host")
end
os.remove(result)
pass("fast download saves the file and keeps the key on allowlisted hosts")

os.remove("annas_domains_cache.txt")
real_print("ALL PASS")

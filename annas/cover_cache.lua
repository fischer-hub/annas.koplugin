local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Api = require("annas.api")
local CoverUtils = require("annas.cover_utils")

local M = {}
local EXTENSIONS = {"jpg", "png", "gif", "webp"}
local MAX_BYTES = 1024 * 1024
local MISS_TTL = 300
local CACHE_LIMIT = 160
local directory = DataStorage:getFullDataDir() .. "/cache/annas-covers"

local function prefix(book)
    local key = CoverUtils.key(book)
    return key and (directory .. "/" .. key)
end

function M.get(book)
    local path = prefix(book)
    if not path then return nil end
    for _, ext in ipairs(EXTENSIONS) do
        local file = path .. "." .. ext
        local size = lfs.attributes(file, "size")
        if size and size > 0 then return file end
    end
end

function M.should_fetch(book)
    local path = prefix(book)
    if not path or M.get(book) then return false end
    local modified = lfs.attributes(path .. ".miss", "modification")
    return not modified or os.time() - modified >= MISS_TTL
end

local function request(url, referer, max_bytes, progress)
    local chunks, size = {}, 0
    local total
    local result = Api.makeHttpRequest{
        url = url,
        method = "GET",
        headers = {
            ["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36",
            ["Referer"] = referer or url,
        },
        timeout = {3, 5},
        on_headers = function(headers)
            local length = tonumber(headers["content-length"] or headers["Content-Length"])
            local transfer = headers["transfer-encoding"] or headers["Transfer-Encoding"]
            if length and length > 0 and (not transfer or transfer == "identity") then
                total = length
            end
            if progress then progress(size, total) end
        end,
        sink = function(chunk)
            if chunk then
                size = size + #chunk
                if size > max_bytes then return nil, "cover response too large" end
                chunks[#chunks + 1] = chunk
                if progress then progress(size, total) end
            end
            return 1
        end,
    }
    if result and not result.error and tonumber(result.status_code) == 200 then
        return table.concat(chunks)
    end
end

function M.fetch(book, report)
    if not M.should_fetch(book) then return M.get(book) end
    report = report or function() end
    util.makePath(directory)
    local path = prefix(book)
    local referer = book.cover_page or book.link
    local cover_url = CoverUtils.absolute_url(book.cover_url, book.cover_page or book.link)
    if not cover_url then
        report("lookup")
        for _, page in ipairs{book.cover_page or book.link or "", book.edition_url or "", book.annas_page or ""} do
            if page ~= "" then
                local html = request(page, page, MAX_BYTES)
                cover_url = html and CoverUtils.extract_image(html, page)
                if cover_url then referer = page; break end
            end
        end
    end
    if cover_url then
        report("connecting")
        local bytes = request(cover_url, referer, MAX_BYTES, function(received, total)
            report("download", received, total)
        end)
        local ext = CoverUtils.image_type(bytes)
        if ext then
            local target = path .. "." .. ext
            local temporary = path .. ".part"
            local file = io.open(temporary, "wb")
            if file then
                local ok = file:write(bytes)
                local closed = file:close()
                if ok and closed and os.rename(temporary, target) then
                    os.remove(path .. ".miss")
                    report("ready", #bytes, #bytes)
                    return target
                end
                os.remove(temporary)
            end
        end
    end
    local file = io.open(path .. ".miss", "w")
    if file then file:close() end
    report("unavailable")
end

function M.prune()
    if lfs.attributes(directory, "mode") ~= "directory" then return end
    local files = {}
    for name in lfs.dir(directory) do
        if name:match("^%x+%.[a-z]+$") then
            local full = directory .. "/" .. name
            local attributes = lfs.attributes(full)
            if attributes and attributes.mode == "file" then
                if name:match("%.part$") then
                    os.remove(full)
                else
                    files[#files + 1] = {path = full, modified = attributes.modification}
                end
            end
        end
    end
    table.sort(files, function(a, b) return a.modified > b.modified end)
    for i = CACHE_LIMIT + 1, #files do os.remove(files[i].path) end
end

return M

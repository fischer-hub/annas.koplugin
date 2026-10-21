local M = {}

local function decode(text)
    return (text:gsub("&amp;", "&"):gsub("&#38;", "&"):gsub("&#x26;", "&")
        :gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&apos;", "'"))
end

function M.attributes(tag)
    local attributes = {}
    for key, quote, value in tag:gmatch("([%w_:%-]+)%s*=%s*([\"'])(.-)%2") do
        attributes[key:lower()] = decode(value)
    end
    for key, value in tag:gmatch("([%w_:%-]+)%s*=%s*([^%s\"'=<>`]+)") do
        key = key:lower()
        if not attributes[key] then attributes[key] = decode(value) end
    end
    return attributes
end

function M.absolute_url(value, base)
    if type(value) ~= "string" then return nil end
    value = decode(value):match("^%s*(.-)%s*$")
    if value == "" or value:find("[%z\1-\31]") then return nil end
    if value:match("^https?://[^/]+") then return value:gsub(" ", "%%20") end
    if value:match("^[%w+.-]+:") then return nil end
    local origin = type(base) == "string" and base:match("^(https?://[^/]+)")
    if not origin then return nil end
    if value:sub(1, 2) == "//" then
        return base:match("^(https?:)") .. value
    end
    local url
    if value:sub(1, 1) == "/" then
        url = origin .. value
    else
        local directory = base:gsub("[?#].*$", ""):match("^(https?://.*/)") or (origin .. "/")
        url = directory .. value
    end
    local host, path = url:match("^(https?://[^/]+)(/.*)$")
    if host then
        local tail = path:match("([?#].*)$") or ""
        path = path:gsub("[?#].*$", "")
        local parts = {}
        for part in path:gmatch("[^/]+") do
            if part == ".." then
                table.remove(parts)
            elseif part ~= "." then
                parts[#parts + 1] = part
            end
        end
        url = host .. "/" .. table.concat(parts, "/") .. tail
    end
    return url:gsub(" ", "%%20")
end

local function useful_image(value)
    local lower = value:lower()
    if lower:find("%.svg") then return false end
    for _, word in ipairs{"logo", "favicon", "blank", "spacer", "placeholder", "nocover", "no_cover", "no-cover", "noimage", "avatar", "sprite", "button"} do
        if lower:find(word, 1, true) then return false end
    end
    return true
end

function M.extract_image(html, base)
    if type(html) ~= "string" then return nil end
    local fallback
    for tag in html:gmatch("<[Ii][Mm][Gg]%s[^>]*>") do
        local a = M.attributes(tag)
        local url
        for _, value in ipairs{a["data-src"] or "", a["data-lazy-src"] or "", a.src or "", a.srcset and a.srcset:match("^%s*([^%s,]+)") or ""} do
            local candidate = M.absolute_url(value, base)
            if candidate and useful_image(candidate) then url = candidate; break end
        end
        if url and useful_image(url) then
            if (url .. " " .. (a.class or "") .. " " .. (a.id or "")):lower():find("cover", 1, true) then
                return url
            end
            fallback = fallback or url
        end
    end
    for tag in html:gmatch("<[Mm][Ee][Tt][Aa]%s[^>]*>") do
        local a = M.attributes(tag)
        if a.property == "og:image" or a.name == "twitter:image" then
            local url = M.absolute_url(a.content, base)
            if url and useful_image(url) then return url end
        end
    end
    return fallback
end

function M.extract_anna_page(html, base, md5)
    for tag in html:gmatch("<[Aa]%s[^>]*>") do
        local url = M.absolute_url(M.attributes(tag).href, base)
        local host = url and url:match("^https?://([^/]+)")
        local hash = url and url:match("/md5/(%x+)")
        if host and hash and hash:lower() == md5:lower()
                and (host:match("^annas%-archive%.") or host:match("%.annas%-archive%.")) then
            return url
        end
    end
end

function M.key(book)
    local md5 = type(book) == "table" and book.md5
    if type(md5) == "string" and #md5 == 32 and md5:match("^%x+$") then
        return md5:lower()
    end
end

function M.image_type(bytes)
    if type(bytes) ~= "string" then return nil end
    if bytes:sub(1, 3) == "\255\216\255" then return "jpg" end
    if bytes:sub(1, 8) == "\137PNG\13\10\26\10" then return "png" end
    if bytes:sub(1, 6) == "GIF87a" or bytes:sub(1, 6) == "GIF89a" then return "gif" end
    if bytes:sub(1, 4) == "RIFF" and bytes:sub(9, 12) == "WEBP" then return "webp" end
end

return M

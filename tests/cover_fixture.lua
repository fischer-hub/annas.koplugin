local h = dofile("tests/headless.lua")
local test, UI, run_until = h.test, h.UI, h.run_until
local ffi = require("ffi")
local U = require("annas.cover_utils")
local temporary = os.getenv("ANNAS_TEST_TMPDIR")
local root = temporary and (temporary .. "/covers") or os.tmpname()
os.remove(root)
local directory = root .. "/cache/annas-covers"
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function mkdir(path) assert(os.execute("mkdir -p " .. quote(path)) == 0) end
mkdir(directory)
package.loaded.util.makePath = mkdir
package.preload.datastorage = function() return {getFullDataDir = function() return root end} end
local mtimes = {}
os.time = function() return 1700000000 end
package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, field)
            if path == directory then
                if field == "mode" then return "directory" end
                return {mode = "directory", modification = os.time()}
            end
            local file = io.open(path, "rb")
            if not file then return nil end
            local size = file:seek("end")
            file:close()
            local a = {mode = "file", size = size, modification = mtimes[path] or os.time()}
            return field and a[field] or a
        end,
        dir = function(path)
            local process = assert(io.popen("ls -1 " .. quote(path), "r"))
            local names = {}
            for name in process:lines() do names[#names + 1] = name end
            process:close()
            local i = 0
            return function() i = i + 1; return names[i] end
        end,
    }
end
local responses, calls = {}, {}
package.preload["annas.api"] = function()
    return {makeHttpRequest = function(options)
        calls[#calls + 1] = options.url
        local response = responses[options.url]
        if not response then return {error = "HTTP 404", status_code = 404} end
        local bytes = response.body
        if options.on_headers then
            options.on_headers(response.headers or (response.no_length and {} or {["content-length"] = tostring(#bytes)}))
        end
        if response.gate then response.gate:wait() end
        local chunk_size = response.chunk_size or math.max(1, #bytes)
        for first = 1, #bytes, chunk_size do
            if not options.sink(bytes:sub(first, first + chunk_size - 1)) then return {error = "response too large"} end
            if response.after_chunk then response.after_chunk(first) end
        end
        options.sink(nil)
        return {status_code = 200}
    end}
end
local Cache = require("annas.cover_cache")
local Loader = require("annas.cover_loader")
local png = ("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082")
    :gsub("..", function(hex) return string.char(tonumber(hex, 16)) end)
local function book(n)
    return {md5 = string.format("%032x", n), cover_page = "https://books.test/ads.php?md5=" .. n}
end
local function serve(b, gate)
    local image = "https://books.test/covers/" .. b.md5 .. ".png"
    responses[b.cover_page] = {body = '<img src="/img/logo.png"><img src="' .. image .. '">'}
    responses[image] = {body = png, gate = gate}
    return image
end

local Base = {}
Base.__index = Base
function Base:extend(class) class.__index = class; return setmetatable(class, {__index = self}) end
function Base:new(options)
    local instance = setmetatable(options, self)
    instance:init()
    return instance
end
function Base:init()
    self.page, self.perpage = 1, self.items_per_page
    self:updateItems()
end
function Base:_recalculateDimen() self.item_dimen = {w = 600, h = 120} end
function Base:updateItems()
    self:_recalculateDimen()
    self.updates = (self.updates or 0) + 1
end
function Base:onCloseWidget() self.base_closed = true end
package.loaded["annas.menu"] = Base
for name, kind in pairs{
    ["ui/widget/imagewidget"] = "image",
    ["ui/widget/container/framecontainer"] = "placeholder",
    ["ui/widget/container/centercontainer"] = "center",
    ["ui/widget/textwidget"] = "text",
    ["ui/widget/textboxwidget"] = "text",
} do
    package.preload[name] = function()
        return {new = function(_, options) options.kind = kind; return options end}
    end
end
package.preload["ui/font"] = function() return {getFace = function() return {} end} end
package.preload["ui/geometry"] = function() return {new = function(_, options) return options end} end
package.preload.device = function() return {screen = {scaleBySize = function(_, value) return value end}} end
local CoverMenu = require("annas.cover_menu")

h.after_each(function() assert(os.execute("rm -rf " .. quote(root)) == 0) end)
return {h = h, U = U, mtimes = mtimes, UI = UI, test = test, run_until = run_until, root = root, directory = directory,
    responses = responses, calls = calls, Cache = Cache, Loader = Loader,
    CoverMenu = CoverMenu, book = book, serve = serve, mkdir = mkdir, png = png, quote = quote}

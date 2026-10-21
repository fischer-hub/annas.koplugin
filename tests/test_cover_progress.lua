local c = dofile("tests/cover_fixture.lua")
local test, UI, run_until = c.test, c.UI, c.run_until
local Cache, Loader, Menu = c.Cache, c.Loader, c.CoverMenu
local book, serve, responses = c.book, c.serve, c.responses
local ffi = require("ffi")

test("two covers run concurrently and the faster one is not blocked", function()
    local slow, fast, gate = book(101), book(102), c.h.gate()
    serve(slow, gate)
    serve(fast)
    local loader = Loader:new()
    loader:start({slow, fast}, function() end)
    assert(#loader.jobs == 2)
    run_until(function() return Cache.get(fast) ~= nil end)
    assert(Cache.get(slow) == nil, "second cover waited for first cover")
    gate:release()
    run_until(function() return loader.pid == nil end)
end)

test("pool stays at two workers while queued covers get their turn", function()
    local books = {}
    for n = 103, 108 do
        books[#books + 1] = book(n)
        serve(books[#books])
    end
    local loader = Loader:new()
    loader:start(books, function() assert(#loader.jobs <= 2) end)
    assert(#loader.jobs == 2 and loader.states[books[3].md5].stage == "queued")
    run_until(function() return loader.pid == nil end, 4)
    for _, b in ipairs(books) do assert(Cache.get(b) and loader.states[b.md5].stage == "ready") end
end)

test("single-cover timeout frees its slot without stopping other workers", function()
    local hung, held, next_book = book(109), book(110), book(111)
    local hung_gate, held_gate = c.h.gate(), c.h.gate()
    serve(hung, hung_gate)
    serve(held, held_gate)
    serve(next_book)
    local loader = Loader:new()
    loader:start({hung, held, next_book}, function() end)
    run_until(function() return hung_gate:waiting() and held_gate:waiting() end)
    local deadline = loader.jobs[1].timeout
    UI:unschedule(deadline)
    UI:nextTick(deadline)
    run_until(function() return Cache.get(next_book) ~= nil end)
    assert(loader.states[hung.md5].stage == "timeout")
    assert(not Cache.get(held) and not Cache.get(hung))
    held_gate:release()
    run_until(function() return loader.pid == nil end)
    assert(Cache.get(held))
end)

test("progress pipe carries partial reads and a real percentage", function()
    local b, gate = book(112), c.h.gate()
    local image = serve(b)
    responses[image].body = c.png .. string.rep("x", 4096)
    responses[image].chunk_size = 1024
    responses[image].after_chunk = function(first) if first == 1 then gate:wait() end end
    local loader = Loader:new()
    local mid_progress
    loader:start({b}, function()
        local state = loader.states[b.md5]
        if state.stage == "download" and state.received > 0 and state.received < state.total then
            mid_progress = state.received / state.total
            assert(not Cache.get(b))
        end
    end)
    run_until(function() return mid_progress ~= nil end)
    assert(mid_progress > 0 and mid_progress < 1)
    gate:release()
    run_until(function() return loader.pid == nil end)
    assert(loader.states[b.md5].stage == "ready")
end)

test("unknown total reports received bytes without inventing a percentage", function()
    local b, gate = book(113), c.h.gate()
    local image = serve(b)
    responses[image].body = c.png .. string.rep("x", 4096)
    responses[image].chunk_size = 1024
    responses[image].after_chunk = function(first) if first == 1 then gate:wait() end end
    local loader = Loader:new()
    responses[image].no_length = true
    local menu = setmetatable({_cover_loader = loader}, {__index = Menu})
    local label
    loader:start({b}, function()
        local state = loader.states[b.md5]
        if state.stage == "download" and state.received > 0 then
            label = menu:_coverLabel(b)
            assert(state.total == 0 and not label:find("%%"))
        end
    end)
    run_until(function() return label ~= nil end)
    assert(label:find("KB", 1, true) and not Cache.get(b))
    gate:release()
    run_until(function() return loader.pid == nil end)
    assert(loader.states[b.md5].stage == "ready")
end)

test("status labels distinguish queue, lookup, transfer and failure", function()
    local b = book(114)
    local loader = Loader:new()
    local menu = setmetatable({_cover_loader = loader}, {__index = Menu})
    local state = {stage = "queued", received = 0, total = 0}
    loader.states[b.md5] = state
    assert(menu:_coverLabel(b) == "Queued")
    state.stage = "lookup"; assert(menu:_coverLabel(b) == "Finding cover")
    state.stage = "connecting"; assert(menu:_coverLabel(b) == "Connecting")
    state.stage, state.received, state.total = "download", 50, 100
    assert(menu:_coverLabel(b) == "50%")
    state.received = 100; assert(menu:_coverLabel(b) == "99%")
    state.stage = "ready"; assert(menu:_coverLabel(b) == "100%")
    state.stage = "timeout"; assert(menu:_coverLabel(b) == "Timed out")
    state.stage = "unavailable"; assert(menu:_coverLabel(b) == "No cover")
end)

test("stopping a page cancels both active workers and leaves no callbacks", function()
    local a, b = book(115), book(116)
    local first, second = c.h.gate(), c.h.gate()
    serve(a, first); serve(b, second)
    local loader = Loader:new()
    loader:start({a, b}, function() error("stopped page received an update") end)
    run_until(function() return first:waiting() and second:waiting() end)
    loader:stop()
    assert(#loader.jobs == 0 and loader.pid == nil)
    assert(loader.states[a.md5].stage == "cancelled" and loader.states[b.md5].stage == "cancelled")
end)

test("split and invalid pipe messages cannot corrupt progress", function()
    local b = book(117)
    local loader, job = Loader:new(), {key = b.md5, buffer = ""}
    loader.states[b.md5] = {stage = "queued", received = 0, total = 0}
    assert(not loader:_consume(job, "downlo"))
    assert(loader:_consume(job, "ad 50 100\ninvalid\n"))
    assert(loader.states[b.md5].received == 50 and job.buffer == "")
end)

local fake_http = {}
local response_headers = {["content-length"] = "8"}
local wire_events, request_count = {}, 0
local resets = 0
local socketutil = {
    set_timeout = function() end,
    reset_timeout = function() resets = resets + 1 end,
    table_sink = function(target) return function(chunk) if chunk then target[#target + 1] = chunk end; return 1 end end,
}
local function open()
    return {receivebody = function(_, _, sink)
        wire_events[#wire_events + 1] = "body"
        sink("abcd"); sink("efgh"); sink(nil)
        return 1
    end}
end
fake_http.open = open
fake_http.request = function(request)
    request_count = request_count + 1
    if fake_http.fail then error("connection failed") end
    local connection = fake_http.open()
    connection:receivebody(response_headers, request.sink)
    return 1, 200, response_headers, "HTTP/1.1 200 OK"
end
package.preload.socketutil = function() return socketutil end
package.preload["socket.http"] = function() return fake_http end
local Api = assert(loadfile((arg[1] or ".") .. "/annas/api.lua"))()

test("HTTP headers arrive before bytes, without an extra HEAD request", function()
    local original = fake_http.open
    local before = request_count
    local response = Api.makeHttpRequest{
        url = "https://books.test/cover.png", timeout = {3, 5},
        on_headers = function(headers)
            assert(headers["content-length"] == "8")
            wire_events[#wire_events + 1] = "headers"
        end,
    }
    assert(response.body == "abcdefgh" and wire_events[1] == "headers" and wire_events[2] == "body")
    assert(request_count == before + 1 and fake_http.open == original and resets == 1)
end)

test("HTTP hook and timeout state are restored after a connection error", function()
    local original = fake_http.open
    fake_http.fail = true
    local response = Api.makeHttpRequest{url = "https://books.test/cover.png", timeout = {3, 5}, on_headers = function() end}
    fake_http.fail = false
    assert(response.error and fake_http.open == original and resets == 1)
end)

test("bad headers callback cannot break a successful download", function()
    local original = fake_http.open
    local response = Api.makeHttpRequest{
        url = "https://books.test/cover.png", on_headers = function() error("callback failure") end,
    }
    assert(not response.error and response.body == "abcdefgh" and fake_http.open == original)
end)

c.h.run()

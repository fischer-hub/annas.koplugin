local c = dofile("tests/cover_fixture.lua")
local h, UI, test, run_until = c.h, c.UI, c.test, c.run_until
local U, Cache, Loader, CoverMenu = c.U, c.Cache, c.Loader, c.CoverMenu
local book, serve, responses, calls = c.book, c.serve, c.responses, c.calls
local directory, png, mtimes = c.directory, c.png, c.mtimes

test("cover HTML skips logo and blank images", function()
    assert(U.extract_image('<img src="/img/logo.png"><img src="/fictioncovers/1/book.jpg" width=300>', "https://books.test/ads.php")
        == "https://books.test/fictioncovers/1/book.jpg")
    assert(U.extract_image('<img src="/img/blank.png">', "https://books.test") == nil)
end)

test("lazy, relative and unquoted image URLs", function()
    assert(U.extract_image('<IMG data-src="//cdn.test/covers/a.jpg?a=1&amp;b=2" src="/blank.png">', "https://books.test/search")
        == "https://cdn.test/covers/a.jpg?a=1&b=2")
    assert(U.extract_image('<img src=../covers/a.png>', "https://books.test/details/a") == "https://books.test/covers/a.png")
    assert(U.absolute_url("../../covers/a.png", "https://books.test/details/a") == "https://books.test/covers/a.png")
    assert(U.absolute_url("javascript:alert(1)", "https://books.test") == nil)
    assert(U.absolute_url("data:image/png;base64,AAAA", "https://books.test") == nil)
end)

test("cache keys reject paths and HTML is never treated as an image", function()
    assert(U.key{md5 = "../outside"} == nil)
    assert(U.key{md5 = string.rep("A", 32)} == string.rep("a", 32))
    assert(U.image_type("<html>403 Forbidden</html>") == nil)
    assert(U.image_type(png) == "png")
end)

test("cover fetch saves atomically and reuses cached bytes", function()
    local b = book(1)
    serve(b)
    local before = #calls
    local path = assert(Cache.fetch(b))
    assert(path == directory .. "/" .. b.md5 .. ".png")
    local file = assert(io.open(path, "rb"))
    assert(file:read("*a") == png)
    file:close()
    assert(not io.open(directory .. "/" .. b.md5 .. ".part", "r"))
    assert(#calls == before + 2)
    assert(Cache.fetch(b) == path and #calls == before + 2)
end)

test("direct Anna image URL avoids metadata request", function()
    local b = book(2)
    b.cover_url = serve(b)
    local before = #calls
    assert(Cache.fetch(b))
    assert(#calls == before + 1)
end)

test("edition page is a fallback when download page lacks a cover", function()
    local b = book(3)
    b.edition_url = "https://books.test/edition.php?id=3"
    local image = serve(b)
    responses[b.cover_page] = {body = '<img src="/img/blank.png">'}
    responses[b.edition_url] = {body = '<img src="' .. image .. '">'}
    assert(Cache.fetch(b))
end)

test("missing images are retried after a short negative-cache TTL", function()
    local b = book(4)
    assert(Cache.fetch(b) == nil)
    assert(not Cache.should_fetch(b))
    mtimes[directory .. "/" .. b.md5 .. ".miss"] = os.time() - 301
    assert(Cache.should_fetch(b))
end)

test("Anna exact-file page is used when LibGen has no image", function()
    local b = book(7)
    b.annas_page = "https://en.annas-archive.test/md5/" .. b.md5
    local image = serve(b)
    responses[b.cover_page] = {body = '<img src="/img/blank.png">'}
    responses[b.annas_page] = {body = '<img data-src="' .. image .. '">'}
    assert(Cache.fetch(b))
    local html = '<a href="' .. b.annas_page .. '">Anna</a>'
    assert(U.extract_anna_page(html, "https://libgen.test", b.md5) == b.annas_page)
    assert(U.extract_anna_page(html, "https://libgen.test", string.rep("f", 32)) == nil)
end)

test("HTML response and oversized image do not become cache entries", function()
    for n, bytes in pairs{[5] = "<html>bot check</html>", [6] = png .. string.rep("x", 1024 * 1024)} do
        local b = book(n)
        local image = serve(b)
        responses[image] = {body = bytes}
        assert(Cache.fetch(b) == nil and Cache.get(b) == nil)
    end
end)

test("background covers leave UI interactive and publish completed files", function()
    local b, gate = book(10), h.gate()
    serve(b, gate)
    local loader = Loader:new()
    local heartbeat, updated
    loader:start({b}, function() updated = true end)
    UI:nextTick(function() heartbeat = true end)
    run_until(function() return heartbeat end)
    assert(not Cache.get(b), "cover completed before its response was released")
    gate:release()
    run_until(function() return updated and loader.pid == nil end)
    assert(Cache.get(b))
end)

test("page change cancels old cover worker without stale repaint", function()
    local old, new, gate = book(11), book(12), h.gate()
    serve(old, gate)
    serve(new)
    local loader = Loader:new()
    local stale, updated
    loader:start({old}, function() stale = true end)
    run_until(function() return gate:waiting() end)
    loader:start({new}, function() updated = true end)
    run_until(function() return updated and loader.pid == nil end)
    assert(not stale and Cache.get(new) and not Cache.get(old))
end)

test("closing cover loader removes timers and terminates its worker", function()
    local b, gate = book(13), h.gate()
    serve(b, gate)
    local loader = Loader:new()
    loader:start({b}, function() error("closed menu received a repaint") end)
    run_until(function() return gate:waiting() end)
    loader:stop()
    assert(loader.pid == nil and Cache.get(b) == nil)
end)

test("cover deadline kills stalled metadata/image requests", function()
    local b, gate = book(14), h.gate()
    serve(b, gate)
    local loader = Loader:new()
    loader:start({b}, function() assert(loader.states[b.md5].stage == "timeout") end)
    run_until(function() return gate:waiting() end)
    UI:unschedule(loader.deadline)
    UI:nextTick(loader.deadline)
    run_until(function() return loader.pid == nil end)
    assert(Cache.get(b) == nil)
end)

test("scraper preserves exact-edition cover metadata", function()
    local config = package.loaded["annas.config"]
    config.getSearchOrder = function() return {} end
    config.getSearchLanguages = function() return {} end
    config.getSearchExtensions = function() return {} end
    config.getLibgenTopics = function() return {} end
    config.getLibgenMaxPages = function() return 1 end
    local b = book(20)
    local html = '<title>Library Genesis</title><table><tr><td><a href="edition.php?id=42">A book</a></td><td>An author</td><td>Publisher</td><td>2024</td><td>English</td><td>100</td><td>1 MB</td><td>epub</td><td><a href="ads.php?md5=' .. b.md5 .. '">Get</a></td></tr></table>'
    assert(loadfile((arg[1] or "annas.koplugin") .. "/src/scraper.lua"))("src.scraper")
    local requests = 0
    check_url = function() requests = requests + 1; return "success", html end
    local books = scraper("A book")
    assert(#books == 1 and requests == 1, "search fetched extra pages for covers")
    assert(books[1].edition_url == "https://libgen.gl/edition.php?id=42")
    assert(books[1].cover_page == "https://libgen.gl/ads.php?md5=" .. b.md5)
end)

test("menu shows six rows, adds cached images and retries cancelled pages", function()
    local items = {}
    for n = 30, 37 do
        local b = book(n)
        serve(b)
        items[#items + 1] = {text = "Book " .. n, original_book_data_ref = b}
    end
    local menu = CoverMenu:new{item_table = items}
    assert(menu.perpage == 6 and menu.state_w > 0)
    assert(items[1].state.kind == "placeholder" and items[7].state == nil)
    run_until(function() return items[1].state.kind == "image" end)
    assert(items[1].state.kind == "image" and items[1].state.scale_factor == 0)
    menu.page = 2
    menu:updateItems()
    run_until(function() return items[7].state.kind == "image" end)
    menu.page = 1
    menu:updateItems()
    run_until(function() return items[6].state.kind == "image" and menu._cover_loader.pid == nil end)
    menu:onCloseWidget()
    assert(menu.base_closed)
end)

test("closing results before next tick prevents cover loading", function()
    local b = book(40)
    serve(b)
    local menu = CoverMenu:new{item_table = {{text = "Book", original_book_data_ref = b}}}
    menu:onCloseWidget()
    assert(menu._cover_loader.pid == nil and Cache.get(b) == nil)
end)

h.run()

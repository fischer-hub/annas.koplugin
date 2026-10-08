-- Run from the repository root: luajit tests/download_failure_test.lua
-- Synthetic responses only: no network access or KOReader installation needed.
assert(loadfile("src/scraper.lua"))("download_failure_test")

local original_check_url = check_url
local original_save = save_file_bytes
local original_open, original_remove, original_rename = io.open, os.remove, os.rename
local book = { title = "Test", author = "Author", format = "epub", md5 = "test", download = "lgli" }
local page = '<a href="get.php?md5=test">GET</a>'
local passed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    check_url, save_file_bytes = original_check_url, original_save
    io.open, os.remove, os.rename = original_open, original_remove, original_rename
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS: " .. name)
end

local function forbid_save()
    save_file_bytes = function() error("failed response must not be saved") end
end

test("failed final request falls back to the next mirror", function()
    local calls, saves = {}, 0
    check_url = function(url)
        calls[#calls + 1] = url
        if url:find("ads.php", 1, true) then return "success", page end
        if url:find("libgen.gl", 1, true) then return "network_error", nil, "blocked" end
        return "success", "synthetic ebook"
    end
    save_file_bytes = function(_, bytes)
        assert(bytes == "synthetic ebook")
        saves = saves + 1
        return true, "saved"
    end
    assert(download_book(book, "/downloads") == "/downloads/Test_Author.epub")
    assert(#calls == 4 and calls[3]:find("libgen.li", 1, true))
    assert(saves == 1)
end)

test("failed source page falls back instead of returning early", function()
    local calls = 0
    check_url = function(url)
        calls = calls + 1
        if url:find("libgen.gl", 1, true) then return "network_error", nil end
        if url:find("ads.php", 1, true) then return "success", page end
        return "success", "synthetic ebook"
    end
    save_file_bytes = function() return true, "saved" end
    assert(download_book(book, "/downloads") == "/downloads/Test_Author.epub")
    assert(calls == 3)
end)

test("all final requests failing returns a UI error without saving", function()
    local requests = 0
    check_url = function(url)
        requests = requests + 1
        if url:find("ads.php", 1, true) then return "success", page end
        return "network_error", nil, "blocked"
    end
    forbid_save()
    assert(download_book(book, "/downloads"):find("Failed,", 1, true) == 1)
    assert(requests == 16, "must attempt all eight mirrors")
end)

test("empty or missing successful response is not saved", function()
    local downloads = 0
    check_url = function(url)
        if url:find("ads.php", 1, true) then return "success", page end
        downloads = downloads + 1
        if downloads % 2 == 0 then return "success", "" end
        return "success", nil
    end
    forbid_save()
    assert(download_book(book, "/downloads"):find("Failed,", 1, true) == 1)
    assert(downloads == 8)
end)

test("save failure is returned instead of a success path", function()
    local requests = 0
    check_url = function(url)
        requests = requests + 1
        return "success", url:find("ads.php", 1, true) and page or "synthetic ebook"
    end
    save_file_bytes = function() return nil, "write failed: disk full" end
    assert(download_book(book, "/downloads") == "Failed, write failed: disk full")
    assert(requests == 2, "local write errors should not trigger mirror retries")
end)

test("missing download data never opens a file", function()
    io.open = function() error("must validate before opening") end
    assert(not save_file_bytes("unused", nil))
    assert(not save_file_bytes("unused", ""))
end)

test("open failure is reported", function()
    io.open = function() return nil, "permission denied" end
    local ok, err = save_file_bytes("unused", "data")
    assert(not ok and err == "open failed: permission denied")
end)

for _, stage in ipairs({ "write", "close", "rename" }) do
    test(stage .. " failure cleans up temporary file and preserves destination", function()
        local removed, renamed
        io.open = function(path, mode)
            assert(path == "book.epub.part" and mode == "wb")
            return {
                write = function() if stage == "write" then return nil, "disk full" end return true end,
                close = function() if stage == "close" then return nil, "disk full" end return true end,
            }
        end
        os.remove = function(path) removed = path return true end
        os.rename = function() renamed = true return nil, "permission denied" end
        local ok, err = save_file_bytes("book.epub", "data")
        assert(not ok and err:find(stage .. " failed:", 1, true) == 1)
        assert(removed == "book.epub.part")
        assert((stage == "rename") == (renamed == true))
    end)
end

test("successful binary save replaces destination and leaves no temporary file", function()
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    assert(f:write("previous contents"))
    assert(f:close())
    local bytes = "synthetic\000ebook\255"
    assert(save_file_bytes(path, bytes))
    f = assert(io.open(path, "rb"))
    assert(f:read("*a") == bytes)
    f:close()
    assert(not io.open(path .. ".part", "rb"))
    os.remove(path)
end)

print(string.format("%d tests passed", passed))

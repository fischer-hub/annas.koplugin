local function extract_md5_and_link(line)
    -- Match href="/md5/<md5hash>"
    local link, md5 = line:match('href="(/md5/([a-fA-F0-9]+))"')
    if link and md5 and #md5 == 32 then
        return link, md5
    end
    return nil, nil
end


local function extract_title(line)
    -- Check if line contains an <h3> tag
    if line:find("<h3 class=") then
        -- Extract content between first <h3 ...> and </h3>
        local content = line:match("<h3[^>]*>(.-)</h3>")
        if content then
            -- Trim leading and trailing whitespace
            content = content:match("^%s*(.-)%s*$")
            -- Escape quotes and bullet characters
            content = content:gsub('"', '\\"')
            content = content:gsub("•", "\\u2022")
            return content
        end
    end
    return 'Could not retrieve title.'
end

local function extract_author(line)
    -- Check if line contains a div with class including "italic"
    if line:find('<div class=.*italic') then
        -- Extract content between the first <div ...> and </div>
        local content = line:match('<div[^>]*italic[^>]*>(.-)</div>')
        if content then
            -- Trim leading/trailing whitespace
            content = content:match("^%s*(.-)%s*$")
            -- Escape double quotes
            content = content:gsub('"', '\\"')
            return content
        end
    end
    return 'Could not retrieve author.'
end

local function extract_format(line)
    -- Look for a div with class including text-gray-500 and extract its content
    local content = line:match('class="[^"]-text%-gray%-500[^"]*"%s*>(.-)</div>')
    if content then
        -- Look for something like ".epub," and extract "epub"
        local ext = content:match('%.([a-z0-9]+),')
        if ext then
            return ext
        end
    end
    return 'Could not retrieve format.'
end


local function extract_description(line)
    -- Match div with a class that contains "text-gray-500"
    local desc = line:match('class="[^"]*text%-gray%-500[^"]*".->(.-)</div>')
    if desc then
        -- Trim leading/trailing whitespace
        desc = desc:match("^%s*(.-)%s*$")
        -- Escape quotes
        desc = desc:gsub('"', '\\"')
        -- Wrap in double quotes (optional, to mimic AWK behavior)
        return '"' .. desc .. '"'
    end
    return 'Could not retrieve description.'
end

function check_curl(url, command)
    -- Try to start curl
    local command = string.format('%s "%s"', command, url)
    print('executing command:\n', command)
    local handle, err = io.popen(
        command, "r"
    )
    if not handle then
        return "no_curl", err
    end

    -- Read output
    local output = handle:read("*a")

    -- Close and get exit status
    local ok, reason, code = handle:close()

    if not ok then
        -- curl started, but something failed (non-zero exit code)
        return "network_error", string.format("reason=%s code=%d", reason, code)
    end

    return "success", output
end

function scraper(query)

    local annas_url = "https://annas-archive.li/"
    local page = "1"

    --local http = require("socket/http")

    --local query = 'marx'--io.read()
    if not query then
        query = ''
    end

    print('got query: ', query)

    local encoded_query = string.gsub(query, " ", "+")
    local filters = ""

    local url = string.format("%ssearch?page=%s&q=%s%s", annas_url, page, encoded_query, filters)
    
    local status, data = check_curl(url, "curl -s -S -o - ")

    if status == "no_curl" then
        return "Curl is not installed or not in PATH:" .. data
    elseif status == "network_error" then
        return "Please check connection, Network/HTTP error:" .. data
    elseif status == "success" then
        print("Curl succeeded!")

        local split_pattern = '<div class="h%-%[110px%] flex flex%-col justify%-center ">'
        result_html = split_pattern .. data

        segments = {}

        for segment in result_html:gmatch(split_pattern .. '(.-)(<div class="h%-%[110px%] flex flex%-col justify%-center ">)') do
            table.insert(segments, segment)
        end

        local book_lst = {}
        for i, entry in ipairs(segments) do
            print("\n---- Entry #" .. i .. " ----\n")

            local link, md5 = extract_md5_and_link(entry)
            local book = {}
            book.title = extract_title(entry)
            book.author = extract_author(entry)
            book.format = extract_format(entry)
            book.md5 = md5
            book.link = link
            
            if string.find(entry, "lgli", 1, true) then
                book.download = 'lgli'

                if string.find(entry, "zlib", 1, true) then
                    book.download = book.download .. ' | zlib'
                end
            else
                if string.find(entry, "zlib", 1, true) then
                    book.download = 'zlib'
                end
            end

            print(book.title)
            print(book.download)

            table.insert(book_lst, book)
        end

        return book_lst
    else
        return "Unknown error occured: " .. data
    end
end

function download_book(book)
    lgli_url = "https://libgen.li/"
    print(book.title)

    if not book.download then
        print('no source available')
        return "failed"
    end
    
    if string.find(book.download, 'lgli', 1, true) then
        download_page = lgli_url .. "ads.php?md5=" .. book.md5
        local status, data = check_curl(download_page, "curl -s -L")

        if status == "no_curl" then
            return "Curl is not installed or not in PATH:" .. data
        elseif status == "network_error" then
            return "Please check connection, Network/HTTP error:" .. data
        elseif status == "success" then
            print("Curl succeeded!")
            print(data)
        end
        
    else
        print('book not available on libgen')
    end
end

if ... == nil then
    -- This block runs only if executed directly:
    print("Running as main script")
    local book_lst = scraper('Marx')
    download_book(book_lst[2])

end
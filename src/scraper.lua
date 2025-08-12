local Config = require("zlibrary.config")

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
    local languages = Config.getSearchLanguages()
    local ext = Config.getSearchExtensions()
    local order = Config.getSearchOrder()
    local src = 'lgli'
    --local timeout = Config.getSearchTimeout()
    local filters = ''

    if languages then
        for k, lang in pairs(languages) do
            filters = filters .. "&lang=" .. lang
        end
    end

    if ext then
        for k, e in pairs(ext) do
            filters = filters .. "&ext=" .. string.lower(e)
        end
    end

    if order[1] then
        filters = filters .. "&sort=" .. order[1]
    end

    if src then
        filters = filters .. "&src=" .. src
    end

    print('applying filters: ', filters)

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

        local start_pos = 1

        while true do
            local s, e = result_html:find(split_pattern, start_pos)
            if not s then break end
        
            -- Find the next occurrence of the split_pattern after the current one
            local next_s = result_html:find(split_pattern, e + 1)
        
            -- Extract segment from current start to next start - 1, or end of string if none
            local segment
            if next_s then
                segment = result_html:sub(s, next_s - 1)
                start_pos = next_s
            else
                segment = result_html:sub(s)
                start_pos = #result_html + 1
            end
        
            table.insert(segments, segment)
        end

        local book_lst = {}
        book_count = 0 

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

            local number_str = entry:match(" (%d+%.?%d*)MB, ")
            book.size = number_str .. "MB"

            print(book.title)
            print(book.download)

            table.insert(book_lst, book)
            book_count = book_count + 1
        end

        print("found " .. book_count .. " entries")

        return book_lst
    else
        return "Unknown error occured: " .. data
    end
end

function sanitize_name(name)
    local sanitized = name
    sanitized = sanitized:gsub("[^%w._-]", "_")
    sanitized = sanitized:gsub(" ", "_")
    return sanitized
end

function download_book(book, path)
    local filename = path .. "/" .. sanitize_name(book.title) .. '_'.. sanitize_name(book.author) .. '.' .. book.format
    lgli_url = "https://libgen.li/"
    print(book.title)

    if not book.download then
        print('no source available')
        return "Failed, no download source available [lgli, zlib]."
    end
    
    if string.find(book.download, 'lgli', 1, true) then
        download_page = lgli_url .. "ads.php?md5=" .. book.md5
        local status, data = check_curl(download_page, "curl -s -L")

        if status == "no_curl" then
            return "Failed, curl is not installed or not in PATH:" .. data
        elseif status == "network_error" then
            return "Failed, please check connection, Network/HTTP error:" .. data
        elseif status == "success" then
            print("Curl succeeded!")

            local download_link = data:match('href="([^"]*get%.php[^"]*)"')

            if download_link then
                print("Found link:", download_link)
                local download_url = lgli_url .. download_link
                local curl_command = "curl -# -L -o" .. "\"" .. filename .. "\""

                local status, data = check_curl(download_url, curl_command )
                print('data:\n', data)
                print('status:\n', status)
                print(filename)
                return filename

            else
                print("No matching link found.")
                return 'Failed, could not fetch download link from source page.'
            end

        end
        
    else
        print('book not available on libgen')
        return "Failed, book not available on libgen."
    end
end

if ... == nil then
    -- This block runs only if executed directly:
    print("Running as main script")
    scraper("hello")
    local book_lst = scraper('Marx')
    --download_book(book_lst[2])

end
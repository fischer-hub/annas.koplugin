local Config = require("zlibrary.config")
local Api = require('zlibrary.api')

local function extract_md5_and_link(line)
    -- Match href="/md5/<md5hash>"
    -- href="\/md5\/[a-f0-9]{32}"/
    local md5 = line:match('href="/md5/([a-fA-F0-9]+)"')

    if md5 and #md5 == 32 then
        return md5
    end
    return nil
end


local function extract_title(line)
    -- Check if line contains an <h3> tag
    local content = line:match('<div class="font%-bold text%-violet%-900 line%-clamp%-%[5%]" data%-content="([^"]+)"')

    if content then
        -- Trim leading and trailing whitespace
        content = content:match("^%s*(.-)%s*$")
        -- Escape quotes and bullet characters
        content = content:gsub('"', '\\"')
        content = content:gsub("•", "\\u2022")
        print('Title: ', content)
        return content
    end

    return 'Could not retrieve title.'
end

local function extract_author(line)

    -- Step 1: check if line contains the class combo
    if line:match('<div[^>]*class="[^"]*font%-bold[^"]*text%-amber%-900[^"]*line%-clamp%-%[2%][^"]*"') then
        -- Step 2: try to capture the whole <div ... data-content="...">
        local block = line:match('<div[^>]*class="[^"]*font%-bold[^"]*text%-amber%-900[^"]*line%-clamp%-%[2%][^"]*" data%-content="[^"]+"')

        if block then
            -- Step 3: extract just the data-content value
            local author = block:match('data%-content="([^"]+)"')

            if author then
                print("Author:", author)
                return author
            end
        end
    end

    return 'Could not retrieve author.'
end

local function extract_format(line)

    local div_text = line:match('<div class="text%-gray%-800[^>]*>[^<]+')
    if div_text then
        -- Step 2: extract content after ">"
        local content = div_text:match('>([^<]+)')
        
        if content then
            -- Step 3: split content on " · "
            --local parts = {}
            --for part in content:gmatch("[^ ·]+") do
            --    table.insert(parts, part)
            --end
            
            -- Step 4: check if there are at least 2 parts
            local format = nil
            format = content:match("([A-Z][A-Z]+)")
            if format then
                print('format: ', format)
                return format
            end
        end
    end
    return 'Could not retrieve format.'
end


local function extract_description(line)
    local html = [[ <div class="line-clamp-[2] overflow-hidden break-words text-sm text-gray-600 mt-2 mb-2 leading-[1.3]">description text</div> ]]

    local div_block = line:match('<div[^>]*class="[^"]*line%-clamp%-%[2%][^"]*"[^>]*>(.-)</div>')
    print('desc: ', div_block)

    if div_block then
        local description = div_block
    
        -- Step 2: remove <script> blocks
        description = description:gsub('<script[^>]*>.-</script>', '')
    
        -- Step 3: remove <a> tags
        description = description:gsub('<a[^>]*>.-</a>', '')
    
        -- Step 4: remove all remaining HTML tags
        description = description:gsub('<[^>]->', '')
    
        -- Step 5: remove HTML entities like &nbsp;, &#123;, &amp;, etc.
        description = description:gsub('&[#a-zA-Z0-9]+;', '')
    
        -- Step 6: trim leading/trailing whitespace
        description = description:gsub('^%s+', ''):gsub('%s+$', '')
    
        print("Description:", description)
        return description
    end
    print("Description: Could not retrieve")

    return 'Could not retrieve description.'
end

--[[ function check_url_curl(url, command)
    -- Try to start curl
    local command = string.format('%s --connect-timeout 20 "%s"', command, url)
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
end ]]

function check_url(url)
    local headers = {
        ['Content-Type'] = 'text/html',
        ["User-Agent"] = 'anna/7.81.0',
    }
    if user_id and user_key then
        headers["Cookie"] = string.format("remix_userid=%s; remix_userkey=%s", user_id, user_key)
    end

    local http_result = Api.makeHttpRequest{
        url = url,
        method = "GET",
        headers = headers,
        timeout = 20,
    }

    return "success", http_result.body
end


function scraper(query)

    local aa_exts = {
        [1] = ".se/",
        [2] = ".org/",
        [3] = ".li/",
    }

    local ext_counter = 0

    local annas_url = "https://annas-archive"
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

    ::retry::
    ext_counter = ext_counter + 1
    annas_url = annas_url .. aa_exts[ext_counter]

    local url = string.format("%ssearch?page=%s&q=%s%s", annas_url, page, encoded_query, filters)
    
    local status, data = check_url(url)

    if status == "no_curl" then
        return "Curl is not installed or not in PATH:" .. data
    elseif status == "network_error" then
        if ext_counter < 3 then
            print('Network error on ', annas_url)
            print('Checking different mirror ...')
            goto retry
        end
        return "Please check connection, Network/HTTP error:" .. data
    elseif status == "success" then
        print("Curl succeeded!")

        local ddos_guard_needle = 'der-gray-100<!doctype html><html><head><title>DDoS-Guard</titl'

        if data:find(ddos_guard_needle, 1, true) then
            print("DDoS guard triggered, trying different mirror ...")
            goto retry
        end

        --local split_pattern = '<div class="h%-%[110px%] flex flex%-col justify%-center ">'
        local split_pattern = 'pt-3 pb-3 border-b last:border-b-0 border-gray-100'
        --'flex  pt-3 pb-3 border-b last:border-b-0 border-gray-100'
        
        result_html = split_pattern .. data

        
        segments = {}
        
        local start_pos = 1
        --print(result_html)
        if not result_html then
            print('resulthtml is empty')
        end
        
        while true do
            local s, e = result_html:find(split_pattern, start_pos, true)
            if not s then break end
            
            -- Find the next occurrence of the split_pattern after the current one
            local next_s = result_html:find(split_pattern, e + 1, true)
            
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
            print(string.sub(entry, 1, 100))

            local md5 = extract_md5_and_link(entry)
            local link = nil
            
            if md5 then
                link = annas_url .. 'md5/' .. md5
                print('found link', link )
            else
                print('Couldnt fetch MD5 sum of entry, probs not a valid html segment.')
                goto continue
            end

            local book = {}
            book.title = extract_title(entry)
            book.author = extract_author(entry)
            book.format = extract_format(entry)
            book.description = extract_description(entry)
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

            local number_str = entry:match(" (%d+%.?%d*)MB · ")

            if number_str then
                book.size = number_str .. "MB"
            else
                number_str = 'NA'
            end

            print(book.download)

            table.insert(book_lst, book)
            book_count = book_count + 1
            
            ::continue::
        end

        print("found " .. book_count .. " entries")

        return book_lst
    else
        if ext_counter < 3 then
            print('Unknown error on ', annas_url)
            print('Checking different mirror ...')
            goto retry
        end
    end
    return "Unknown error occured: " .. data
end

function sanitize_name(name)
    local sanitized = name
    sanitized = sanitized:gsub("[^%w._-]", "_")
    sanitized = sanitized:gsub(" ", "_")
    return sanitized
end

function download_book(book, path)

    local lgli_exts = {
        [1] = ".li/",
        [2] = ".is/",
        [3] = ".rs/",
        [4] = ".st/",
    }

    for _, lgli_ext in ipairs(lgli_exts) do
        
        ::continue::

        local filename = path .. "/" .. sanitize_name(book.title) .. '_'.. sanitize_name(book.author) .. '.' .. book.format
        lgli_url = "https://libgen" .. lgli_ext
        print(book.title)

        if not book.download then
            print('no source available')
            return "Failed, no download source available [lgli, zlib]."
        end
        
        if string.find(book.download, 'lgli', 1, true) then
            download_page = lgli_url .. "ads.php?md5=" .. book.md5
            local status, data = check_url(download_page)

            if status == "no_curl" then
                return "Failed, curl is not installed or not in PATH:" .. data
            elseif status == "network_error" then
                return "Failed, please check connection, Network/HTTP error:" .. data
            elseif status == "success" then
                print("Curl succeeded!")

                local download_link = data:match('href="([^"]*get%.php[^"]*)"')

                if download_link then
                    print("Found link:", download_link)    
                    local filename = path .. "/" .. sanitize_name(book.title) .. '_'.. sanitize_name(book.author) .. '.' .. book.format
                    --lgli_url = "https://libgen"
                    print(book.title)
            
                    if not book.download then
                        print('no source available')
                        return "Failed, no download source available [lgli, zlib]."
                    end
                    
                    if string.find(book.download, 'lgli', 1, true) then
                        download_page = lgli_url .. "ads.php?md5=" .. book.md5
                        local status, data = check_url(download_page)
            
                        if status == "no_curl" then
                            return "Failed, curl is not installed or not in PATH:" .. data
                        elseif status == "network_error" then
                            return "Failed, please check connection, Network/HTTP error:" .. data
                        elseif status == "success" then
                            print("Curl succeeded!")
            
                            local download_link = data:match('href="([^"]*get%.php[^"]*)"')
            
                            if download_link then
                                print("Found final link:", download_link)
                                local download_url = lgli_url .. download_link
                                local curl_command = "curl -# -L -o" .. "\"" .. filename .. "\""
            
                                local status, data = check_url(download_url )
                                print('data:\n', data)
                                print('status:\n', status)
                                print(filename)
                                return filename
            
                            else
                                print("No matching link found.")
                                --goto continue
                            end
            
                        end
                        
                    else
                        print('book not available on libgen')
                        --goto continue
                    end

                    local download_url = lgli_url .. download_link
                    local curl_command = "curl -# -L -o" .. "\"" .. filename .. "\""

                    local status, data = check_url(download_url )
                    print('data:\n', data)
                    print('status:\n', status)
                    print(filename)
                    return filename

                else
                    print("No matching link found.")
                    --return 'Failed, could not fetch download link from source page.'
                end

            end
            
        else
            print('book not available on libgen')
            --return "Failed, book not available on libgen."
        end
    end
    
    return 'Failed, could not fetch download link from source page.'
    
end

if ... == nil then
    -- This block runs only if executed directly:
    print("Running as main script")
    scraper("hello")
    local book_lst = scraper('Marx')
    --download_book(book_lst[2])

end
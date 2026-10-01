-- Config/Api depend on KOReader-only modules (util, G_reader_settings, socket.http),
-- so fall back gracefully when this file is run standalone outside the plugin.
local Config_ok, Config = pcall(require, "annas.config")
if not Config_ok then Config = nil end
local Api_ok, Api = pcall(require, "annas.api")
if not Api_ok then Api = nil end

-- Cache configuration
local CACHE_FILE = "annas_domains_cache.txt"
local CACHE_DURATION = 12 * 60 * 60  -- 12 hours in seconds

-- Reads domains from cache
local function read_cache()
    local f = io.open(CACHE_FILE, "r")
    if not f then
        return nil, nil
    end
    
    local timestamp_str = f:read("*l")
    if not timestamp_str then
        f:close()
        return nil, nil
    end
    
    local timestamp = tonumber(timestamp_str)
    if not timestamp then
        f:close()
        return nil, nil
    end
    
    -- Check whether cache is still valid
    if os.time() - timestamp > CACHE_DURATION then
        f:close()
        print("=== Cache expired")
        return nil, nil
    end
    
    local domains = {}
    for line in f:lines() do
        if line and line ~= "" then
            table.insert(domains, line)
        end
    end
    f:close()
    
    if #domains > 0 then
        print("=== Loaded", #domains, "domains from cache")
        return domains, timestamp
    end
    
    return nil, nil
end

-- Writes domains to cache
local function write_cache(domains)
    local f = io.open(CACHE_FILE, "w")
    if not f then
        print("=== Warning: Could not write cache file")
        return false
    end
    
    f:write(os.time() .. "\n")
    for _, domain in ipairs(domains) do
        f:write(domain .. "\n")
    end
    f:close()
    
    print("=== Cached", #domains, "domains")
    return true
end

-- Extracts domains from Wikipedia HTML
local function extract_domains_from_wikipedia(html)
    local domains = {}
    
    -- Search for all annas-archive URLs
    for url in html:gmatch('href="(https://annas%-archive%.[^/"]+)/?"') do
        -- Extract only the domain part
        local domain = url:match("https://(.+)")
        if domain and not domains[domain] then
            domains[domain] = true
            table.insert(domains, domain)
            print("=== Found domain:", domain)
        end
    end
    
    return domains
end

-- Fetches domains from Wikipedia
local function fetch_domains_from_wikipedia()
    print("=== Fetching domains from Wikipedia...")
    
    local wikipedia_url = "https://en.wikipedia.org/wiki/Anna%27s_Archive"
    
    -- Try using different methods
    local status, data = check_url(wikipedia_url)
    
    if status ~= "success" or not data then
        print("=== Failed to fetch Wikipedia page")
        return nil
    end
    
    print("=== Successfully fetched Wikipedia page")
    
    local domains = extract_domains_from_wikipedia(data)
    
    if #domains == 0 then
        print("=== Warning: No domains found in Wikipedia page")
        return nil
    end
    
    print("=== Extracted", #domains, "domains from Wikipedia")
    
    -- Save to cache
    write_cache(domains)
    
    return domains
end

-- Main function to retrieve domains
local function get_annas_archive_domains()
    -- Try loading from cache first
    local cached_domains, cache_time = read_cache()
    if cached_domains then
        local age_hours = math.floor((os.time() - cache_time) / 3600)
        print("=== Using cached domains (age:", age_hours, "hours)")
        return cached_domains
    end

    -- If cache is unavailable, fetch fresh domains from Wikipedia. Deliberately
    -- no hardcoded fallback list here: a static domain name can go stale and
    -- get taken over by someone else long after Anna's Archive stops using
    -- it, so the Wikipedia-sourced list - reflecting whatever mirrors are
    -- actually current - is the only source of truth for what to trust.
    return fetch_domains_from_wikipedia() or {}
end


local function extract_md5_and_link(line)
    -- Extract MD5 hash from href="/md5/<hash>" pattern
    local md5 = line:match('href="/md5/([a-fA-F0-9]+)"')
    if md5 and #md5 == 32 then
        return md5
    end
    return nil
end

local function extract_title(line)
    -- Extract title from data-content attribute and clean it
    local content = line:match('<div class="font%-bold text%-violet%-900 line%-clamp%-%[5%]" data%-content="([^"]+)"')
    if content then
        content = content:match("^%s*(.-)%s*$")  -- trim whitespace
        content = content:gsub('"', '\\"')     -- escape quotes
        content = content:gsub("•", "\\u2022") -- escape bullet points
        print('Title: ', content)
        return content
    end
    return 'Could not retrieve title.'
end

local function extract_author(line)
    -- Extract author from specific div class combination
    if line:match('<div[^>]*class="[^"]*font%-bold[^"]*text%-amber%-900[^"]*line%-clamp%-%[2%][^"]*"') then
        local block = line:match('<div[^>]*class="[^"]*font%-bold[^"]*text%-amber%-900[^"]*line%-clamp%-%[2%][^"]*" data%-content="[^"]+"')
        if block then
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
    -- Extract file format (PDF, EPUB, etc.) from text content
    local div_text = line:match('<div class="text%-gray%-800[^>]*>[^<]+')
    if div_text then
        local content = div_text:match('>([^<]+)')
        if content then
            local format = content:match("([A-Z][A-Z]+)")  -- match uppercase format like PDF, EPUB
            if format then
                print('format: ', format)
                return format
            end
        end
    end
    return 'Could not retrieve format.'
end

local function extract_description(line)
    -- Extract and clean description text from HTML
    local div_block = line:match('<div[^>]*class="[^"]*line%-clamp%-%[2%][^"]*"[^>]*>(.-)</div>')
    print('desc: ', div_block)
    if div_block then
        local description = div_block
        description = description:gsub('<script[^>]*>.-</script>', '')  -- remove scripts
        description = description:gsub('<a[^>]*>.-</a>', '')           -- remove links
        description = description:gsub('<[^>]->', '')                -- remove HTML tags
        description = description:gsub('&[#a-zA-Z0-9]+;', '')          -- remove HTML entities
        description = description:gsub('^%s+', ''):gsub('%s+$', '')  -- trim whitespace
        print("Description:", description)
        return description
    end
    print("Description: Could not retrieve")
    return 'Could not retrieve description.'
end

-- Check if external command (curl/wget) is available
local function command_exists(cmd)
    local handle = io.popen("which " .. cmd .. " 2>/dev/null")
    if not handle then return false end
    local result = handle:read("*a")
    handle:close()
    return result and result ~= ""
end

-- Percent-encode a search query for safe use in a URL query string. Anything
-- outside RFC 3986 unreserved characters is escaped, which also neutralizes
-- shell metacharacters (quotes, backticks, $, ;, &, ...) a query might contain.
local function url_encode(str)
    if not str then return "" end
    str = str:gsub("([^%w%-%_%.%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str:gsub(" ", "+")
end

-- Safely quote a string (URL, file path, ...) for embedding as a single shell
-- argument, regardless of its content. URLs here can come from a user's
-- search query or from a third-party mirror's HTML (download links), so this
-- must not rely on that content already being "safe" by construction.
local function shell_quote(str)
    return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
end

-- Anna's Archive mirrors sit behind anti-bot/WAF checks (DDoS-Guard, Cloudflare)
-- that can 403 requests lacking a convincing browser fingerprint - curl's bare
-- default (literally "curl/8.x") or a truncated User-Agent are both common
-- triggers for a 403 a real browser never sees for the same URL. Every fetch
-- tier below sends this same realistic, complete header set.
local BROWSER_HEADERS = {
    ["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Safari/605.1.15",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    -- No Accept-Encoding here: wget, LuaSocket and KOReader's Api don't
    -- decompress responses, so advertising br/zstd gets them bytes they
    -- can't parse (libgen.la answers with zstd). curl's --compressed flag
    -- already requests only the encodings curl itself can decode.
    ["Accept-Language"] = "en-US,en;q=0.9",
}

-- Build a headers table's worth of curl -H (or wget --header=) flags, so
-- each fetch tier's request-building code doesn't restate every header by hand.
local function curl_header_args(headers)
    local args = {}
    for key, value in pairs(headers) do
        table.insert(args, "-H " .. shell_quote(key .. ": " .. value))
    end
    return table.concat(args, " ")
end

local function wget_header_args(headers)
    local args = {}
    for key, value in pairs(headers) do
        table.insert(args, "--header=" .. shell_quote(key .. ": " .. value))
    end
    return table.concat(args, " ")
end

-- Failure reason categories, from least to most specific/actionable. Every
-- fetch tier reports one of these on failure so scraper() can tell the user
-- something more useful than a single generic "network error":
--   "unavailable" - this fetch method doesn't exist in this environment
--                    (no curl/wget, no LuaSocket, no KOReader Api module)
--   "unreachable" - no HTTP response at all (DNS/connection failure, timeout)
--   "blocked"     - got a real response, but a non-200 status or a
--                    recognized/suspected anti-bot challenge page
local REASON_PRIORITY = { unavailable = 1, unreachable = 2, blocked = 3 }
local function best_reason(a, b)
    if not a then return b end
    if not b then return a end
    if (REASON_PRIORITY[b] or 0) > (REASON_PRIORITY[a] or 0) then
        return b
    end
    return a
end

-- Pure Lua HTTP implementation using LuaSocket (fallback method)
local function fetch_with_lua_socket(url)
    print('=== Trying pure Lua socket for URL:', url)
    
    local socket_ok, socket = pcall(require, "socket")
    local http_ok, http = pcall(require, "socket.http")
    local ltn12_ok, ltn12 = pcall(require, "ltn12")
    
    if not (socket_ok and http_ok and ltn12_ok) then
        print('=== LuaSocket not available')
        return "no_socket", nil, "unavailable"
    end

    -- Every other fetch tier bounds its request (curl --max-time, wget --timeout,
    -- Api's socketutil timeout); without this, a stalled connection here can hang
    -- far longer than the OS default before falling through to the next tier/mirror.
    http.TIMEOUT = 20

    local response_body = {}
    local res, code, response_headers, status = http.request{
        url = url,
        method = "GET",
        headers = BROWSER_HEADERS,
        sink = ltn12.sink.table(response_body),
        redirect = true,
    }
    
    if res and code == 200 then
        local body = table.concat(response_body)
        print('=== LuaSocket succeeded, got', #body, 'bytes')
        return "success", body
    else
        print('=== LuaSocket failed, code:', code, 'status:', status)
        -- A numeric code means we got a real (non-200) HTTP response; anything
        -- else (typically an error message string) means the connection itself
        -- failed before any response arrived.
        return "socket_error", nil, (type(code) == "number") and "blocked" or "unreachable"
    end
end

-- Try external commands (curl/wget) for HTTP requests
local function fetch_with_external_command(url)
    print('=== Trying external command for URL:', url)

    local tried_any = false
    local reason = nil

    -- Try curl first (most reliable)
    if command_exists("curl") then
        tried_any = true
        print('=== Using curl')
        local http_code_marker = "___CURL_HTTP_CODE___:"
        print('curl -L -s --compressed --max-time 20 '
            .. curl_header_args(BROWSER_HEADERS) .. ' '
            .. '-w "' .. http_code_marker .. '%{http_code}" '
            .. shell_quote(url) .. ' 2>&1')
        local handle = io.popen('curl -L -s --compressed --max-time 20 '
            .. curl_header_args(BROWSER_HEADERS) .. ' '
            .. '-w "' .. http_code_marker .. '%{http_code}" '
            .. shell_quote(url) .. ' 2>&1')
        if handle then
            local raw = handle:read("*a")
            local success = handle:close()
            local body, http_code_str = raw:match("^(.*)" .. http_code_marker .. "(%d+)$")
            local result = body or raw
            local http_code = tonumber(http_code_str)
            if success and result and #result > 0 then
                if http_code and http_code ~= 200 then
                    print('=== curl got HTTP', http_code, '- treating as failure, trying next method/mirror')
                    reason = best_reason(reason, "blocked")
                else
                    print('=== curl succeeded, got', #result, 'bytes')
                    return "success", result
                end
            else
                -- curl ran but produced no usable response: connection/DNS/timeout failure.
                reason = best_reason(reason, "unreachable")
            end
        else
            reason = best_reason(reason, "unreachable")
        end
    end

    -- Try wget as fallback
    if command_exists("wget") then
        tried_any = true
        print('=== Using wget')
        local temp_file = os.tmpname()
        local cmd = string.format('wget -q -O %s --timeout=10 %s %s 2>&1',
            shell_quote(temp_file),
            wget_header_args(BROWSER_HEADERS),
            shell_quote(url))
        local handle = io.popen(cmd)
        if handle then
            handle:close()
            local f = io.open(temp_file, "r")
            if f then
                local result = f:read("*a")
                f:close()
                os.remove(temp_file)
                if result and #result > 0 then
                    print('=== wget succeeded, got', #result, 'bytes')
                    return "success", result
                end
            end
        end
        -- wget aborts and writes nothing on an HTTP error status by default, so
        -- reaching here most often means a rejected (blocked) request rather
        -- than total unreachability.
        reason = best_reason(reason, "blocked")
    end

    if not tried_any then
        return "no_external_command", nil, "unavailable"
    end

    return "no_external_command", nil, reason or "unreachable"
end

-- Try KOReader's API with multiple header configurations
local function fetch_with_api(url)
    if not Api then
        print('=== Api.makeHttpRequest not available (running outside KOReader)')
        return "api_unavailable", nil, "unavailable"
    end

    print('=== Trying Api.makeHttpRequest for:', url)

    local reason = nil
    local hostname = url:match("://([^/]+)")

    -- Try progressively richer header configurations for compatibility: some
    -- KOReader network backends are pickier about extra headers than others.
    local full_headers = { ["Host"] = hostname }
    for key, value in pairs(BROWSER_HEADERS) do
        full_headers[key] = value
    end

    local header_configs = {
        { ["User-Agent"] = BROWSER_HEADERS["User-Agent"] }, -- Minimal headers
        BROWSER_HEADERS,                                    -- Standard headers
        full_headers,                                       -- Full headers with hostname
    }

    for i, headers in ipairs(header_configs) do
        print('=== API attempt', i, 'with', #headers, 'headers')

        local success, http_result = pcall(function()
            return Api.makeHttpRequest{
                url = url,
                method = "GET",
                headers = headers,
                timeout = 10,
            }
        end)
        
        if not success then
            print('=== API call threw error:', http_result)
            reason = best_reason(reason, "unreachable")
            goto next_attempt
        end

        if not http_result then
            print('=== API returned nil')
            reason = best_reason(reason, "unreachable")
            goto next_attempt
        end

        if http_result.error then
            print('=== API returned error:', http_result.error)
            -- "HTTP Error: ..." means we got a real (non-200/206) response;
            -- anything else (timeout, connection failure) means we didn't.
            if tostring(http_result.error):find("HTTP Error", 1, true) then
                reason = best_reason(reason, "blocked")
            else
                reason = best_reason(reason, "unreachable")
            end
            goto next_attempt
        end

        local status_code = tonumber(http_result.status_code)
        if status_code == 200 and http_result.body and #http_result.body > 0 then
            print('=== API succeeded with attempt', i, 'got', #http_result.body, 'bytes')
            return "success", http_result.body
        else
            print('=== API attempt', i, 'failed - status:', status_code, 'body exists:', http_result.body ~= nil)
            reason = best_reason(reason, "blocked")
        end

        ::next_attempt::
    end

    return "api_failed", nil, reason or "unreachable"
end

-- Main HTTP request function with three-tier fallback system
function check_url(url)
    print('=== DEBUG: check_url called with:', url)

    local reason = nil

    -- Method 1: Try external commands (curl/wget) - most reliable
    local ext_status, ext_data, ext_reason = fetch_with_external_command(url)
    if ext_status == "success" then
        return "success", ext_data
    end
    reason = best_reason(reason, ext_reason)

    print('=== External command not available, trying alternative methods')

    -- Method 2: Try LuaSocket (pure Lua, no external dependencies)
    local socket_status, socket_data, socket_reason = fetch_with_lua_socket(url)
    if socket_status == "success" then
        return "success", socket_data
    end
    reason = best_reason(reason, socket_reason)

    print('=== LuaSocket not available or failed, trying Api.makeHttpRequest')

    -- Method 3: Try KOReader's API with multiple configurations
    local api_status, api_data, api_reason = fetch_with_api(url)
    if api_status == "success" then
        return "success", api_data
    end
    reason = best_reason(reason, api_reason)

    -- All methods failed
    print('=== ERROR: All HTTP methods failed')
    print('=== Tried: external commands (curl/wget), LuaSocket, Api.makeHttpRequest')

    return "network_error", nil, reason or "unreachable"
end

-- Turn a tally of per-mirror failure reasons into a message that actually
-- says something about what went wrong, instead of a single generic string
-- for every possible cause (blocked, unreachable, or no working HTTP method
-- can all look identical to the caller otherwise).
local function build_search_failure_message(total_attempts, failure_tally)
    local blocked = failure_tally.blocked or 0
    local unreachable = failure_tally.unreachable or 0
    local unavailable = failure_tally.unavailable or 0

    local parts = {}
    if blocked > 0 then table.insert(parts, blocked .. " blocked by DDoS protection") end
    if unreachable > 0 then table.insert(parts, unreachable .. " unreachable") end
    if unavailable > 0 then table.insert(parts, unavailable .. " with no working HTTP method available") end

    local detail = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
    local summary = string.format("Failed after trying %d mirror%s%s.",
        total_attempts, total_attempts == 1 and "" or "s", detail)

    if blocked > 0 and blocked >= unreachable and blocked >= unavailable then
        return summary .. " Anna's Archive is blocking automated requests right now, try again later."
    elseif unreachable > 0 then
        return summary .. " Check internet connection or try again later. Mirrors may be down right now."
    elseif unavailable > 0 then
        return summary .. " No supported HTTP method is available on the device."
    end
    return summary
end

-- Search Anna's Archive (fallback source, see scraper() below)
local function annas_search(query)
    -- Get current Anna's Archive domains from Wikipedia (with caching)
    local aa_domains = get_annas_archive_domains()

    if #aa_domains == 0 then
        return "Could not fetch current AA mirrors from Wikipedia. Check your internet connection and try again."
    end

    print("=== Using", #aa_domains, "Anna's Archive domains")

    local domain_counter = 0
    local protocols = {"https://"}
    local protocol_counter = 0
    local page = "1"

    -- A mirror can serve an unrecognized bot-challenge page (not a known error
    -- status/signature) that just happens to parse into zero book entries.
    -- Retry a couple of other mirrors before accepting that as a genuine
    -- empty result, without cycling through the entire domain list (which
    -- would make a real "no matches" search take much longer than needed).
    local zero_result_retries = 0
    local MAX_ZERO_RESULT_RETRIES = 2

    -- Tracks why each mirror attempt failed, so a total failure can report
    -- something more useful than one generic message for every cause.
    local total_attempts = 0
    local failure_tally = { unavailable = 0, unreachable = 0, blocked = 0 }
    local function tally_failure(reason)
        reason = reason or "unreachable"
        failure_tally[reason] = (failure_tally[reason] or 0) + 1
    end

    -- Give up and report results, favoring an informative failure message
    -- over a bare empty list whenever mirrors were actually seen failing
    -- along the way - otherwise a search that ran into real 403s/blocks
    -- could still end up silently reported as "no results found" if it
    -- happened to also hit the zero-result-retry cap (see below) rather
    -- than exhausting the domain list outright.
    local function give_up(book_lst_or_nil)
        if failure_tally.blocked > 0 or failure_tally.unreachable > 0 or failure_tally.unavailable > 0 then
            return build_search_failure_message(total_attempts, failure_tally)
        end
        return book_lst_or_nil or {}
    end

    if not query then
        query = ''
    end

    print('got query: ', query)

    local encoded_query = url_encode(query)
    local languages = Config and Config.getSearchLanguages() or {}
    local ext = Config and Config.getSearchExtensions() or {}
    local order = Config and Config.getSearchOrder() or {}
    local src = 'lgli'
    local filters = ''

    if languages then
        for _, lang in pairs(languages) do
            filters = filters .. "&lang=" .. lang
        end
    end

    if ext then
        for _, e in pairs(ext) do
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
    domain_counter = domain_counter + 1
    if domain_counter > #aa_domains then
        domain_counter = 1
        protocol_counter = protocol_counter + 1
        if protocol_counter >= #protocols then
            return give_up(nil)
        end
    end

    local annas_url = protocols[protocol_counter + 1] .. aa_domains[domain_counter] .. "/"
    local url = string.format("%ssearch?page=%s&q=%s%s", annas_url, page, encoded_query, filters)

    print('Attempting URL:', url)
    print('Protocol:', protocols[protocol_counter + 1], 'Domain:', aa_domains[domain_counter])

    total_attempts = total_attempts + 1
    local status, data, reason = check_url(url)

    if status == "network_error" or status == "dns_error" then
        tally_failure(reason)
        print('Network/DNS error on ', annas_url)
        print('Checking different mirror ...')
        goto retry
    elseif status == "success" then
        print("=== HTTP request succeeded")

        if not data or data == "" then
            tally_failure("unreachable")
            print('=== ERROR: No data received from server')
            print('=== Retrying with different mirror...')
            goto retry
        end

        print('=== SUCCESS: Received data, length:', #data)
        print('=== First 100 chars:', string.sub(data, 1, 100))

        -- The old needle here ('der-gray-100<!doctype html>...') required that exact
        -- text immediately before the DDoS-Guard page, which a genuine top-level
        -- challenge response (it just starts with <!doctype html>) never has - so
        -- this never actually matched in practice. Match the real page directly.
        if data:find("<title>DDoS-Guard</title>", 1, true) or data:find("/.well-known/ddos-guard/", 1, true) then
            tally_failure("blocked")
            print("=== DDoS-Guard challenge page detected, trying different mirror ...")
            goto retry
        end

        -- Safety net: catch generic server/gateway error pages (e.g. nginx's default
        -- "500 Internal Server Error") regardless of which fetch method served them or
        -- whether it already checked the HTTP status code itself.
        local http_error_code = data:match('<title>%s*(%d%d%d)%s+[^<]*</title>')
        if http_error_code and tonumber(http_error_code) >= 400 then
            tally_failure("blocked")
            print("=== Got HTTP error page (" .. http_error_code .. "), trying different mirror ...")
            goto retry
        end

        -- Split HTML into book entries using consistent pattern
        local split_pattern = 'pt-3 pb-3 border-b last:border-b-0 border-gray-100'
        
        result_html = split_pattern .. data
        
        segments = {}
        
        local start_pos = 1
        
        while true do
            local s, e = result_html:find(split_pattern, start_pos, true)
            if not s then break end
            
            -- Find next occurrence to extract individual segments
            local next_s = result_html:find(split_pattern, e + 1, true)
            
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
            
            local has_lgli = string.find(entry, "lgli", 1, true) ~= nil
            local has_zlib = string.find(entry, "zlib", 1, true) ~= nil
            if has_lgli and has_zlib then
                book.download = 'lgli | zlib'
            elseif has_lgli then
                book.download = 'lgli'
            elseif has_zlib then
                book.download = 'zlib'
            end

            local number_str = entry:match(" (%d+%.?%d*)MB · ")
            if number_str then
                book.size = number_str .. "MB"
            end

            print(book.download)

            table.insert(book_lst, book)
            book_count = book_count + 1
            
            ::continue::
        end

        print("found " .. book_count .. " entries")

        if book_count == 0 and zero_result_retries < MAX_ZERO_RESULT_RETRIES then
            zero_result_retries = zero_result_retries + 1
            tally_failure("blocked")
            print("=== Zero entries parsed (likely an unrecognized bot-challenge page), trying different mirror (" .. zero_result_retries .. "/" .. MAX_ZERO_RESULT_RETRIES .. ") ...")
            goto retry
        end

        return give_up(book_lst)
    else
        tally_failure(reason)
        print('Unknown error on ', annas_url, ': ', status)
        print('Checking different mirror ...')
        goto retry
    end
    return "Unknown error occurred"
end

-- Library Genesis mirrors, used both to search (libgen_search) and to
-- download (download_book, via each mirror's ads.php page).
local LIBGEN_MIRRORS = {
    "libgen.gl",
    "libgen.li",
    "libgen.la",
    "libgen.me",
    "libgen.bz",
    "libgen.vg",
    "libgen.st",
    "libgen.is",
}

-- libgen has no language or format query parameter (it also ignores
-- "lang:"/"ext:" terms in the query), so those filters are applied to the
-- parsed results instead. libgen stores languages as English names, while
-- the plugin's language setting uses ISO codes (Config.SUPPORTED_LANGUAGES).
local LIBGEN_LANGUAGE_NAMES = {
    ar = "Arabic", hy = "Armenian", az = "Azerbaijani", bn = "Bengali",
    zh = "Chinese", ["zh-Hant"] = "Chinese", cs = "Czech", nl = "Dutch", en = "English",
    fr = "French", ka = "Georgian", de = "German", el = "Greek", hi = "Hindi",
    id = "Indonesian", it = "Italian", ja = "Japanese", ko = "Korean",
    ms = "Malay", ps = "Pashto", pl = "Polish", pt = "Portuguese",
    ru = "Russian", sr = "Serbian", sk = "Slovak", es = "Spanish", te = "Telugu", th = "Thai",
    tr = "Turkish", uk = "Ukrainian", ur = "Urdu", vi = "Vietnamese",
}

-- The plugin's sort options mapped to libgen's order/ordermode parameters.
-- libgen has no relevance or random order: "Most Relevant" keeps libgen's
-- default order and "Random" shuffles the parsed results.
local LIBGEN_SORT = {
    newest = { "year", "desc" },
    oldest = { "year", "asc" },
    largest = { "filesize", "desc" },
    smallest = { "filesize", "asc" },
    newest_added = { "time_added", "desc" },
    oldest_added = { "time_added", "asc" },
}

local function strip_tags(html)
    local text = html:gsub("<[^>]->", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    return text
end

-- A results page is a table with one row per file: title, author,
-- publisher, year, language, pages, size, extension, mirror links.
local function parse_libgen_results(html)
    local books = {}
    local row_count = 0
    for row in html:gmatch("<tr>(.-)</tr>") do
        local md5 = row:match("ads%.php%?md5=(%x+)")
        if md5 then
            row_count = row_count + 1
        end
        local cells = {}
        for cell in row:gmatch("<td[^>]*>(.-)</td>") do
            cells[#cells + 1] = cell
        end
        local format = cells[8] and strip_tags(cells[8])
        -- download_book needs an md5 and a format (for the file name)
        if md5 and #md5 == 32 and #cells >= 9 and format then
            -- the first cell also holds the series name and badges; the
            -- title itself is the edition link
            local title = cells[1]:match('href="edition%.php[^"]*">(.-)</a>') or cells[1]
            local pages = strip_tags(cells[6])
            table.insert(books, {
                title = strip_tags(title) or "Unknown Title",
                author = strip_tags(cells[2]) or "Unknown Author",
                publisher = strip_tags(cells[3]),
                year = strip_tags(cells[4]),
                lang = strip_tags(cells[5]),
                pages = pages ~= "0" and pages or nil,
                size = strip_tags(cells[7]),
                format = format:upper(),
                md5 = md5,
                download = "lgli",
            })
        end
    end
    return books, row_count
end

local function filter_libgen_results(books)
    local languages = Config and Config.getSearchLanguages() or {}
    local extensions = Config and Config.getSearchExtensions() or {}
    if #languages == 0 and #extensions == 0 then
        return books
    end

    local wanted_languages = {}
    for _, code in ipairs(languages) do
        -- settings saved by older versions may hold names instead of codes
        table.insert(wanted_languages, (LIBGEN_LANGUAGE_NAMES[code] or code):lower())
    end
    local wanted_formats = {}
    for _, ext in ipairs(extensions) do
        wanted_formats[ext:upper()] = true
    end

    local filtered = {}
    for _, book in ipairs(books) do
        -- libgen may list several languages for one file ("English; German")
        local language_ok = #wanted_languages == 0
        if not language_ok and book.lang then
            local lang = book.lang:lower()
            for _, name in ipairs(wanted_languages) do
                if lang:find(name, 1, true) then
                    language_ok = true
                    break
                end
            end
        end
        local format_ok = #extensions == 0 or wanted_formats[book.format]
        if language_ok and format_ok then
            table.insert(filtered, book)
        end
    end
    return filtered
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(i)
        list[i], list[j] = list[j], list[i]
    end
end

local LIBGEN_PAGE_SIZE = 100
-- when paging through filtered results, stop once this many matches are in
local LIBGEN_ENOUGH_MATCHES = 100

-- Fetch and parse one page of libgen results. Returns the parsed books and
-- the page's raw row count, or nil plus a failure reason.
local function fetch_libgen_page(mirror, path, page)
    local url = "https://" .. mirror .. path .. (page > 1 and ("&page=" .. page) or "")
    print("=== Trying libgen search:", url)
    local status, data, fail_reason = check_url(url)
    if status == "success" and data and data:find("<title>Library Genesis", 1, true) then
        return parse_libgen_results(data)
    end
    -- a "successful" response that isn't a libgen results page is most
    -- likely a block, challenge or error page
    if status == "success" then
        local title = data and data:match("<title>(.-)</title>")
        print("=== libgen mirror returned an unexpected page:", mirror, #(data or ""), "bytes, title:", title or "(none)")
    end
    return nil, fail_reason or "blocked"
end

local function has_search_filters()
    local languages = Config and Config.getSearchLanguages() or {}
    local extensions = Config and Config.getSearchExtensions() or {}
    return #languages > 0 or #extensions > 0
end

-- Search Library Genesis. Mirrors don't all carry the same files, so a
-- mirror with no (matching) results moves on to the next one. libgen can't
-- filter by language or format itself, so with those filters set, each
-- mirror is paged through (up to the user's "max result pages" setting)
-- and the rows are filtered locally. Returns the first non-empty list of
-- books, an empty list if every reachable mirror came up empty, or nil
-- plus a failure reason if no mirror returned a results page at all.
local function libgen_search(query)
    local order = Config and Config.getSearchOrder() or {}
    local params = { "req=" .. url_encode(query or ""), "res=" .. LIBGEN_PAGE_SIZE }
    -- no topics[] parameter means libgen searches every collection
    for _, topic in ipairs(Config and Config.getLibgenTopics and Config.getLibgenTopics() or {}) do
        table.insert(params, "topics%5B%5D=" .. url_encode(topic))
    end
    local sort = LIBGEN_SORT[order[1] or ""]
    if sort then
        table.insert(params, "order=" .. sort[1])
        table.insert(params, "ordermode=" .. sort[2])
    end
    local path = "/index.php?" .. table.concat(params, "&")

    -- without filters, one page of 100 results is plenty
    local max_pages = 1
    if has_search_filters() then
        max_pages = Config and Config.getLibgenMaxPages() or 5
    end

    local reason = nil
    local got_results_page = false
    for _, mirror in ipairs(LIBGEN_MIRRORS) do
        local books = {}
        for page = 1, max_pages do
            local parsed, row_count = fetch_libgen_page(mirror, path, page)
            if not parsed then
                -- keep whatever earlier pages of this mirror already matched
                reason = best_reason(reason, row_count)
                print("=== libgen mirror failed:", mirror, "page", page, reason)
                break
            end
            got_results_page = true
            local matches = filter_libgen_results(parsed)
            for _, book in ipairs(matches) do
                table.insert(books, book)
            end
            print("=== libgen mirror", mirror, "page", page, "parsed", row_count, "rows,", #matches, "matched filters,", #books, "total")
            -- Full pages don't always hold exactly LIBGEN_PAGE_SIZE rows
            -- (a "marx" page 2 had 99, with more pages after it), and the
            -- page has no usable pagination links, so only treat a clearly
            -- short page as the last one. A last page with more rows than
            -- that just costs one extra, empty request.
            if row_count < LIBGEN_PAGE_SIZE / 2 or #books >= LIBGEN_ENOUGH_MATCHES then
                break
            end
        end
        if #books > 0 then
            if order[1] == "random" then
                shuffle(books)
            end
            return books
        end
    end
    if got_results_page then
        return {}
    end
    return nil, reason or "unreachable"
end

-- Search entry point used by main.lua. Library Genesis comes first: its
-- search pages are plain HTML without an anti-bot challenge. Anna's Archive
-- is the fallback when every libgen mirror fails, or when libgen finds
-- nothing (libgen's language/format filtering happens on one page of
-- results, so a filtered search can come up empty where Anna's server-side
-- filters would still find matches).
function scraper(query)
    local books, libgen_reason = libgen_search(query)
    if books and #books > 0 then
        return books
    end

    print("=== libgen search " .. (books and "found no results" or "failed") .. ", falling back to Anna's Archive")
    local annas_result = annas_search(query)
    if type(annas_result) == "table" and #annas_result > 0 then
        return annas_result
    end

    if books then
        -- libgen answered with a genuine empty result; Anna's being blocked
        -- shouldn't turn that into an error
        return books
    end
    if type(annas_result) == "string" then
        return "Library Genesis search failed (every mirror " .. libgen_reason .. "). Anna's Archive fallback: " .. annas_result
    end
    return annas_result
end

function sanitize_name(name)
    local sanitized = name
    sanitized = sanitized:gsub("[^%w._-]", "_")
    sanitized = sanitized:gsub(" ", "_")
    return sanitized
end

-- Save binary data to file
function save_file_bytes(path, bytes)
    local f, err = io.open(path, "wb")  -- open in binary mode
    if not f then 
        return nil, "open failed: "..tostring(err) 
    end

    local ok, werr = f:write(bytes)
    f:close()
    if not ok then 
        return nil, "write failed: "..tostring(werr) 
    end

    return true, "saved file to: " .. path
end

-- Exact official Anna's Archive hosts that may receive the member key: the
-- Wikipedia mirror list can be edited by anyone, so a listed-but-stale or
-- hijacked domain never sees it.
local CREDENTIAL_HOSTS = {
    ["annas-archive.pk"] = true,
    ["annas-archive.gd"] = true,
    ["annas-archive.gl"] = true,
}

-- Try Anna's Archive's member fast-download API; returns the saved filename
-- or nil plus the failure detail.
local function fast_download_book(book, filename)
    local secret_key = Config and Config.getAnnasSecretKey()
    if not secret_key or not book.md5 or not Api then
        return nil
    end

    local json = require("json")
    local detail = "no trusted Anna's Archive mirror is listed"

    for _, domain in ipairs(get_annas_archive_domains()) do
        -- The key goes into this endpoint's URL; only send it to exact known
        -- official Anna hosts, never to stale/retired cache entries.
        if CREDENTIAL_HOSTS[domain] then
            local base_url = "https://" .. domain
            local api_url = string.format(
                "%s/dyn/api/fast_download.json?md5=%s&key=%s",
                base_url,
                url_encode(book.md5),
                url_encode(secret_key)
            )
            print("Trying Anna's Archive fast download API on:", base_url)

            local http_result = Api.makeHttpRequest{
                url = api_url,
                method = "GET",
                headers = {
                    ["Accept"] = "application/json",
                    ["User-Agent"] = BROWSER_HEADERS["User-Agent"],
                },
                -- The URL carries the member key; never follow a redirect and
                -- risk forwarding it to another host.
                redirect = false,
                timeout = { 15, 15 },
            }

            -- Failures arrive as non-2xx statuses with a JSON `error` field
            -- (e.g. 401 "Invalid secret key"), so read the body either way.
            local response = {}
            if http_result.body and http_result.body ~= "" then
                local decoded, value = pcall(json.decode, http_result.body)
                if decoded and type(value) == "table" then
                    response = value
                end
            end

            if response.download_url then
                local status, file_data, dl_reason = check_url(response.download_url)
                if status == "success" then
                    local saved, save_err = save_file_bytes(filename, file_data)
                    if saved then
                        return filename
                    end
                    detail = save_err
                else
                    detail = "download URL fetch failed (" .. tostring(dl_reason) .. ")"
                end
            elseif response.error then
                -- An answer from the API itself (invalid key, no downloads
                -- left, ...): every mirror shares that account state.
                detail = tostring(response.error)
                break
            else
                -- No JSON at all: a challenge page or unreachable mirror.
                detail = http_result.error or "unexpected fast-download API response"
            end
        end
    end

    return nil, detail
end

-- Anna's Archive's fast-download API is tried first when a member key is
-- configured; 'lgli' sources fall back to Library Genesis mirrors.
function download_book(book, path)
    local filename = path .. "/" .. sanitize_name(book.title) .. '_'
        .. sanitize_name(book.author) .. '.' .. book.format
    local fast_result, fast_detail = fast_download_book(book, filename)
    if fast_result then
        return fast_result
    end

    local function failed(message)
        -- Keep the fast-download reason visible when the fallback also fails.
        if fast_detail then
            message = message .. " (fast download: " .. tostring(fast_detail) .. ")"
        end
        return "Failed, " .. message
    end

    -- Try different Library Genesis mirrors
    for _, mirror in ipairs(LIBGEN_MIRRORS) do
        ::continue::

        local lgli_url = "https://" .. mirror .. "/"
        print(book.title)

        if not book.download then
            print('no source available')
            return failed("no download source available [lgli, zlib].")
        end

        -- Check if book is available on Library Genesis
        if string.find(book.download, 'lgli', 1, true) then
            local download_page = lgli_url .. "ads.php?md5=" .. book.md5
            print('download page on lgli: ', download_page)
            local page_status, page_data = check_url(download_page)

            if page_status == "network_error" then
                return failed("please check connection, Network/HTTP error: " .. (page_data or ""))
            elseif page_status == "success" then
                print("Download page fetched successfully!")

                if not page_data then
                    print("No data received from download page")
                    goto continue_download
                end

                -- Extract the actual download link from the page
                local download_link = page_data:match('href="([^"]*get%.php[^"]*)"')

                if download_link then
                    print("Found final link:", download_link)
                    local download_url = lgli_url .. download_link

                    local dl_status, dl_data = check_url(download_url)
                    print('status:\n', dl_status)
                    print(filename)
                    local save_ok, save_msg = save_file_bytes(filename, dl_data)
                    print(save_msg)
                    return filename

                else
                    print("No matching link found.")
                end

            end

        else
            print('book not available on libgen')
        end
        
        ::continue_download::
    end
    
    return failed("could not fetch download link from source page.")
end

-- Main execution block (runs when script is executed directly)
if ... == nil then
    print("Running as main script")
    local book_lst = scraper('Marx')
end

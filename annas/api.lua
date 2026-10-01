local logger = require("logger")
local socketutil = require("socketutil")
local http = require("socket.http")
local T = require("annas.gettext")
local Config = require("annas.config")

local Api = {}

-- Strip credentials from any text (URLs, error and status strings) before it
-- reaches logs or the UI: the configured member key in raw or URL-encoded
-- form, and any ?key= URL parameter whether or not a key is configured.
function Api.redactSecrets(text)
    text = tostring(text)
    local key = Config.getAnnasSecretKey()
    -- Generic key parameters first so a substituted secret cannot make the
    -- second pattern consume trailing log text as part of its value.
    text = text:gsub("([?&]key=)[^&%s]+", "%1[REDACTED]")
    if key then
        -- Raw and URL-encoded forms; the key may appear outside key= params
        -- (e.g. signed CDN paths or POST bodies echoed in error strings).
        text = text:gsub((key:gsub("%W", "%%%1")), "[REDACTED]")
        local encoded = key:gsub("([^%w%-%._~])",
            function(c) return string.format("%%%02X", string.byte(c)) end)
        text = text:gsub((encoded:gsub("%%", "%%%%")), "[REDACTED]")
    end
    return text
end

function Api.makeHttpRequest(options)
    logger.dbg(string.format("Annas:Api.makeHttpRequest - START - URL: %s, Method: %s", Api.redactSecrets(options.url), options.method or "GET"))

    local response_body_table = {}
    local result = { body = nil, status_code = nil, error = nil, headers = nil }

    local sink_to_use = options.sink
    if not sink_to_use then
        response_body_table = {}
        sink_to_use = socketutil.table_sink(response_body_table)
    end

    if options.timeout then
        if type(options.timeout) == "table" then
            socketutil:set_timeout(options.timeout[1], options.timeout[2])
            logger.dbg(string.format("Annas:Api.makeHttpRequest - Setting timeout to %s/%s seconds", options.timeout[1], options.timeout[2]))
        else
            socketutil:set_timeout(options.timeout)
            logger.dbg(string.format("Annas:Api.makeHttpRequest - Setting timeout to %s seconds", options.timeout))
        end
    end

    local request_params = {
        url = options.url,
        method = options.method or "GET",
        headers = options.headers,
        source = options.source,
        sink = sink_to_use,
        -- redirect = false keeps headers (e.g. Set-Cookie) and never forwards them to another host.
        redirect = options.redirect ~= false,
    }

    logger.dbg(string.format("Annas:Api.makeHttpRequest - Request Params: URL: %s, Method: %s, Timeout: %s", Api.redactSecrets(request_params.url), request_params.method, tostring(options.timeout)))

    local req_ok, r_val, r_code, r_headers_tbl, r_status_str = pcall(http.request, request_params)

    if options.timeout then
        socketutil:reset_timeout()
        logger.dbg("Annas:Api.makeHttpRequest - Reset timeout to default")
    end

    logger.dbg(string.format("Annas:Api.makeHttpRequest - pcall result: ok=%s, r_val=%s (type %s), r_code=%s (type %s), r_headers_tbl type=%s, r_status_str=%s",
        tostring(req_ok), Api.redactSecrets(r_val), type(r_val), Api.redactSecrets(r_code), type(r_code), type(r_headers_tbl), Api.redactSecrets(r_status_str)))

    if not req_ok then
        local error_msg = Api.redactSecrets(r_val)
        if string.find(error_msg, "timeout") or
           string.find(error_msg, "wantread") or
           string.find(error_msg, "closed") or
           string.find(error_msg, "connection") or
           string.find(error_msg, "sink timeout") then
            result.error = T("Request timed out - please check your connection and try again")
            r_code = 408
        else
            result.error = T("Network request failed") .. ": " .. error_msg
        end
        logger.err(string.format("Annas:Api.makeHttpRequest - END (pcall error) - Error: %s", result.error))
        return result
    end

    result.status_code = r_code
    result.headers = r_headers_tbl

    if not options.sink then
        result.body = table.concat(response_body_table)
    end

    if type(result.status_code) ~= "number" then
        local status_str = tostring(result.status_code)
        if string.find(status_str, "wantread") or
           string.find(status_str, "timeout") or
           string.find(status_str, "closed") or
           string.find(status_str, "sink timeout") then
            result.error = T("Request timed out - please check your connection and try again")
        else
            result.error = T("Network connection error - please check your internet connection and try again")
        end
        logger.err(string.format("Annas:Api.makeHttpRequest - END (Invalid response code type) - Error: %s", result.error))
        return result
    end

    if result.status_code ~= 200 and result.status_code ~= 206 then
        if not result.error then
            result.error = string.format("%s: %s (%s)", T("HTTP Error"), result.status_code, Api.redactSecrets(r_status_str or T("Unknown Status")))
        end
    end

    logger.dbg(string.format("Annas:Api.makeHttpRequest - END - Status: %s, Headers found: %s, Error: %s",
        result.status_code, tostring(result.headers ~= nil), tostring(result.error)))
    return result
end

return Api

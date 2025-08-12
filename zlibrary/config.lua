local util = require("util")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local T = require("zlibrary.gettext")

local Config = {}

Config.SETTINGS_BASE_URL_KEY = "zlibrary_base_url"
Config.SETTINGS_USERNAME_KEY = "zlibrary_username"
Config.SETTINGS_PASSWORD_KEY = "zlibrary_password"
Config.SETTINGS_USER_ID_KEY = "zlib_user_id"
Config.SETTINGS_USER_KEY_KEY = "zlib_user_key"
Config.SETTINGS_SEARCH_LANGUAGES_KEY = "zlibrary_search_languages"
Config.SETTINGS_SEARCH_EXTENSIONS_KEY = "zlibrary_search_extensions"
Config.SETTINGS_SEARCH_ORDERS_KEY = "zlibrary_search_order"
Config.SETTINGS_DOWNLOAD_DIR_KEY = "zlibrary_download_dir"
Config.SETTINGS_TURN_OFF_WIFI_AFTER_DOWNLOAD_KEY = "zlibrary_turn_off_wifi_after_download"
Config.SETTINGS_TIMEOUT_LOGIN_KEY = "zlibrary_timeout_login"
Config.SETTINGS_TIMEOUT_SEARCH_KEY = "zlibrary_timeout_search"
Config.SETTINGS_TIMEOUT_BOOK_DETAILS_KEY = "zlibrary_timeout_book_details"
Config.SETTINGS_TIMEOUT_RECOMMENDED_KEY = "zlibrary_timeout_recommended"
Config.SETTINGS_TIMEOUT_POPULAR_KEY = "zlibrary_timeout_popular"
Config.SETTINGS_TIMEOUT_DOWNLOAD_KEY = "zlibrary_timeout_download"
Config.SETTINGS_TIMEOUT_COVER_KEY = "zlibrary_timeout_cover"
Config.CREDENTIALS_FILENAME = "zlibrary_credentials.lua"

Config.DEFAULT_DOWNLOAD_DIR_FALLBACK = G_reader_settings:readSetting("home_dir")
             or require("apps/filemanager/filemanagerutil").getDefaultDir()
Config.SEARCH_RESULTS_LIMIT = 30

-- Timeout configuration for different operations (block_timeout, total_timeout)
Config.TIMEOUT_LOGIN = { 10, 15 }        -- Login operations
Config.TIMEOUT_SEARCH = { 15, 15 }       -- Search operations
Config.TIMEOUT_BOOK_DETAILS = { 15, 5 }  -- Book details operations
Config.TIMEOUT_RECOMMENDED = { 30, 15 }  -- Recommended books operations
Config.TIMEOUT_POPULAR = { 30, 15 }      -- Popular books operations
Config.TIMEOUT_DOWNLOAD = { 15, -1 }    -- Book download operations (infinite total timeout if data flows)
Config.TIMEOUT_COVER = { 5, 15 }        -- Cover image operations

function Config.loadCredentialsFromFile(plugin_path)
    local cred_file_path = plugin_path .. Config.CREDENTIALS_FILENAME
    if lfs.attributes(cred_file_path, "mode") == "file" then
        local func, err = loadfile(cred_file_path)
        if func then
            local success, result = pcall(func)
            if success and type(result) == "table" then
                logger.info("Successfully loaded credentials from " .. Config.CREDENTIALS_FILENAME)
                if result.baseUrl then
                    Config.saveSetting(Config.SETTINGS_BASE_URL_KEY, result.baseUrl)
                    logger.info("Overriding Base URL from " .. Config.CREDENTIALS_FILENAME)
                end
                if result.username then
                    Config.saveSetting(Config.SETTINGS_USERNAME_KEY, result.username)
                    logger.info("Overriding Username from " .. Config.CREDENTIALS_FILENAME)
                end
                if result.email then
                    Config.saveSetting(Config.SETTINGS_USERNAME_KEY, result.email)
                    logger.info("Overriding Username from " .. Config.CREDENTIALS_FILENAME)
                end
                if result.password then
                    Config.saveSetting(Config.SETTINGS_PASSWORD_KEY, result.password)
                    logger.info("Overriding Password from " .. Config.CREDENTIALS_FILENAME)
                end
            else
                logger.warn("Failed to execute or get table from " .. Config.CREDENTIALS_FILENAME .. ": " .. tostring(result))
            end
        else
            logger.warn("Failed to load " .. Config.CREDENTIALS_FILENAME .. ": " .. tostring(err))
        end
    else
        logger.info(Config.CREDENTIALS_FILENAME .. " not found. Using UI settings if available.")
    end
end

Config.SUPPORTED_LANGUAGES = {
    { name = "العربية", value = "arabic" },
    { name = "Հայերեն", value = "armenian" },
    { name = "Azərbaycanca", value = "azerbaijani" },
    { name = "বাংলা", value = "bengali" },
    { name = "简体中文", value = "chinese" },
    { name = "Nederlands", value = "dutch" },
    { name = "English", value = "en" },
    { name = "Français", value = "fr" },
    { name = "ქართული", value = "georgian" },
    { name = "Deutsch", value = "de" },
    { name = "Ελληνικά", value = "greek" },
    { name = "हिन्दी", value = "hindi" },
    { name = "Bahasa Indonesia", value = "indonesian" },
    { name = "Italiano", value = "italian" },
    { name = "日本語", value = "japanese" },
    { name = "한국어", value = "korean" },
    { name = "Bahasa Malaysia", value = "malaysian" },
    { name = "پښتو", value = "pashto" },
    { name = "Polski", value = "polish" },
    { name = "Português", value = "portuguese" },
    { name = "Русский", value = "russian" },
    { name = "Српски", value = "serbian" },
    { name = "Español", value = "sp" },
    { name = "తెలుగు", value = "telugu" },
    { name = "ไทย", value = "thai" },
    { name = "繁體中文", value = "traditional chinese" },
    { name = "Türkçe", value = "turkish" },
    { name = "Українська", value = "ukrainian" },
    { name = "اردو", value = "urdu" },
    { name = "Tiếng Việt", value = "vietnamese" },
}

Config.SUPPORTED_EXTENSIONS = {
    { name = "AZW", value = "AZW" },
    { name = "AZW3", value = "AZW3" },
    { name = "CBZ", value = "CBZ" },
    { name = "DJV", value = "DJV" },
    { name = "DJVU", value = "DJVU" },
    { name = "EPUB", value = "EPUB" },
    { name = "FB2", value = "FB2" },
    { name = "LIT", value = "LIT" },
    { name = "MOBI", value = "MOBI" },
    { name = "PDF", value = "PDF" },
    { name = "RTF", value = "RTF" },
    { name = "TXT", value = "TXT" },
}

Config.SUPPORTED_ORDERS = {
    { name = T("Most Relevant"), value = "" },
    { name = T("Newest"), value = "newest" },
    { name = T("Oldest"), value = "oldest" },
    { name = T("Largest"), value = "largest"},
    { name = T("Smallest"), value = "smallest"},
    { name = T("Newest Added"), value = "newest_added"},
    { name = T("Oldest Added"), value = "oldest_added"},
    { name = T("Random"), value = "random"}
}
    --[[ { name = T("Most popular"), value = "popular" },
    { name = T("Best match"), value = "bestmatch" },
    { name = T("Recently added"), value = "date" },
    { name = string.format("%s %s", T("Title"), "(A-Z)"), value = "titleA" },
    { name = string.format("%s %s", T("Title"), "(Z-A)"), value = "title" },
    { name = T("Year"), value = "year" },
    { name = string.format("%s %s", T("File size"), "↓"), value = "filesize" },
    { name = string.format("%s %s", T("File size"), "↑"), value = "filesizeA" }
} ]]

function Config.getBaseUrl()
    local configured_url = Config.getSetting(Config.SETTINGS_BASE_URL_KEY)
    if configured_url == nil or configured_url == "" then
        return nil
    end
    return configured_url
end

function Config.setAndValidateBaseUrl(url_string)
    if not url_string or url_string == "" then
        return false, "Error: URL cannot be empty."
    end

    url_string = util.trim(url_string)

    if not (string.sub(url_string, 1, 8) == "https://" or string.sub(url_string, 1, 7) == "http://") then
        url_string = "https://" .. url_string
    end

    if not string.find(url_string, "%.") then
        return false, "Error: URL must include a valid domain name (e.g., example.com)."
    end

    if string.sub(url_string, -1) == "/" then
        url_string = string.sub(url_string, 1, -2)
    end

    Config.saveSetting(Config.SETTINGS_BASE_URL_KEY, url_string)
    return true, nil
end

function Config.getRpcUrl()
    local base = Config.getBaseUrl()
    if not base then return nil end
    return base .. "/rpc.php"
end

function Config.getSearchUrl(query)
    local base = Config.getBaseUrl()
    if not base then return nil end
    return base .. "/eapi/book/search"
end

function Config.getBookUrl(href)
    if not href then return nil end
    local base = Config.getBaseUrl()
    if not base then return nil end
    if not href:match("^/") then href = "/" .. href end
    return base .. href
end

function Config.getDownloadUrl(download_path)
    if not download_path then return nil end
    local base = Config.getBaseUrl()
    if not base then return nil end
    if not download_path:match("^/") then download_path = "/" .. download_path end
    return base .. download_path
end

function Config.getBookDetailsUrl(book_id, book_hash)
    local base = Config.getBaseUrl()
    if not base or not book_id or not book_hash then return nil end
    return base .. string.format("/eapi/book/%s/%s", book_id, book_hash)
end

function Config.getRecommendedBooksUrl()
    local base = Config.getBaseUrl()
    if not base then return nil end
    return base .. "/eapi/user/book/recommended"
end

function Config.getMostPopularBooksUrl()
    local base = Config.getBaseUrl()
    if not base then return nil end
    return base .. "/eapi/book/most-popular"
end

function Config.getSetting(key, default)
    return G_reader_settings:readSetting(key) or default
end

function Config.saveSetting(key, value)
    if type(value) == "string" then
        G_reader_settings:saveSetting(key, util.trim(value))
    else
        G_reader_settings:saveSetting(key, value)
    end
end

function Config.deleteSetting(key)
    G_reader_settings:delSetting(key)
end

function Config.getCredentials()
    return {
        username = Config.getSetting(Config.SETTINGS_USERNAME_KEY),
        password = Config.getSetting(Config.SETTINGS_PASSWORD_KEY),
    }
end

function Config.getUserSession()
    return {
        user_id = Config.getSetting(Config.SETTINGS_USER_ID_KEY),
        user_key = Config.getSetting(Config.SETTINGS_USER_KEY_KEY),
    }
end

function Config.saveUserSession(user_id, user_key)
    Config.saveSetting(Config.SETTINGS_USER_ID_KEY, user_id)
    Config.saveSetting(Config.SETTINGS_USER_KEY_KEY, user_key)
end

function Config.clearUserSession()
    Config.deleteSetting(Config.SETTINGS_USER_ID_KEY)
    Config.deleteSetting(Config.SETTINGS_USER_KEY_KEY)
end

function Config.getDownloadDir()
    return Config.getSetting(Config.SETTINGS_DOWNLOAD_DIR_KEY, Config.DEFAULT_DOWNLOAD_DIR_FALLBACK)
end

function Config.getSearchLanguages()
    return Config.getSetting(Config.SETTINGS_SEARCH_LANGUAGES_KEY, {})
end

function Config.getSearchExtensions()
    return Config.getSetting(Config.SETTINGS_SEARCH_EXTENSIONS_KEY, {})
end

function Config.getSearchOrder()
    return Config.getSetting(Config.SETTINGS_SEARCH_ORDERS_KEY, {})
end

function Config.getSearchOrderName()
    local search_order_name = T("Default")
    local selected_order = Config.getSearchOrder()
    local search_order = selected_order and selected_order[1]

    if search_order then
        for _, v in ipairs(Config.SUPPORTED_ORDERS) do
            if v.value == search_order then
                search_order_name = v.name
                break
            end
        end
    end
    return search_order_name
end

function Config.getTurnOffWifiAfterDownload()
    return Config.getSetting(Config.SETTINGS_TURN_OFF_WIFI_AFTER_DOWNLOAD_KEY, false)
end

function Config.setTurnOffWifiAfterDownload(turn_off)
    Config.saveSetting(Config.SETTINGS_TURN_OFF_WIFI_AFTER_DOWNLOAD_KEY, turn_off)
end

function Config.isTestModeEnabled()
    return Config.getSetting("zlibrary_test_mode", false)
end

function Config.setTestMode(enabled)
    Config.saveSetting("zlibrary_test_mode", enabled)
end

-- Timeout configuration functions
function Config.getTimeoutConfig(timeout_key, default_timeout)
    local saved_timeout = Config.getSetting(timeout_key)
    if saved_timeout and type(saved_timeout) == "table" and #saved_timeout == 2 then
        return saved_timeout
    end
    return default_timeout
end

function Config.setTimeoutConfig(timeout_key, block_timeout, total_timeout)
    Config.saveSetting(timeout_key, {block_timeout, total_timeout})
end

function Config.getLoginTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_LOGIN_KEY, Config.TIMEOUT_LOGIN)
end

function Config.getSearchTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_SEARCH_KEY, Config.TIMEOUT_SEARCH)
end

function Config.getBookDetailsTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_BOOK_DETAILS_KEY, Config.TIMEOUT_BOOK_DETAILS)
end

function Config.getRecommendedTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_RECOMMENDED_KEY, Config.TIMEOUT_RECOMMENDED)
end

function Config.getPopularTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_POPULAR_KEY, Config.TIMEOUT_POPULAR)
end

function Config.getDownloadTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_DOWNLOAD_KEY, Config.TIMEOUT_DOWNLOAD)
end

function Config.getCoverTimeout()
    return Config.getTimeoutConfig(Config.SETTINGS_TIMEOUT_COVER_KEY, Config.TIMEOUT_COVER)
end

function Config.formatTimeoutForDisplay(timeout_pair)
    local block_timeout = timeout_pair[1]
    local total_timeout = timeout_pair[2]
    
    local total_display = total_timeout == -1 and T("infinite") or (tostring(total_timeout) .. "s")
    return string.format(T("Block: %ds, Total: %s"), block_timeout, total_display)
end

function Config.setLoginTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_LOGIN_KEY, block_timeout, total_timeout)
end

function Config.setSearchTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_SEARCH_KEY, block_timeout, total_timeout)
end

function Config.setBookDetailsTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_BOOK_DETAILS_KEY, block_timeout, total_timeout)
end

function Config.setRecommendedTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_RECOMMENDED_KEY, block_timeout, total_timeout)
end

function Config.setPopularTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_POPULAR_KEY, block_timeout, total_timeout)
end

function Config.setDownloadTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_DOWNLOAD_KEY, block_timeout, total_timeout)
end

function Config.setCoverTimeout(block_timeout, total_timeout)
    Config.setTimeoutConfig(Config.SETTINGS_TIMEOUT_COVER_KEY, block_timeout, total_timeout)
end

return Config

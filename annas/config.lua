local util = require("util")
local T = require("annas.gettext")
local logger = require("logger")

local Config = {}

Config.SETTINGS_SEARCH_LANGUAGES_KEY = "annas_search_languages"
Config.SETTINGS_SEARCH_EXTENSIONS_KEY = "annas_search_extensions"
Config.SETTINGS_SEARCH_ORDERS_KEY = "annas_search_order"
Config.SETTINGS_DOWNLOAD_DIR_KEY = "annas_download_dir"
Config.SETTINGS_TURN_OFF_WIFI_AFTER_DOWNLOAD_KEY = "annas_turn_off_wifi_after_download"
Config.SETTINGS_LIBGEN_MAX_PAGES_KEY = "annas_libgen_max_pages"
Config.SETTINGS_LIBGEN_TOPICS_KEY = "annas_libgen_topics"
Config.SETTINGS_AA_SECRET_KEY_KEY = "annas_archive_secret_key"
Config.CREDENTIALS_FILENAME = "annas_credentials.lua"

-- Library Genesis collections, as libgen's topics[] search parameter.
-- No selection searches all of them (libgen's default).
Config.SUPPORTED_LIBGEN_TOPICS = {
    { name = T("Libgen"), value = "l" },
    { name = T("Comics"), value = "c" },
    { name = T("Fiction"), value = "f" },
    { name = T("Scientific Articles"), value = "a" },
    { name = T("Magazines"), value = "m" },
    { name = T("Fiction RUS"), value = "r" },
    { name = T("Standards"), value = "s" },
}

-- libgen can't filter by language or format itself, so with those filters
-- set the plugin pages through results (100 per page) and filters locally.
Config.LIBGEN_MAX_PAGES_DEFAULT = 5
Config.LIBGEN_MAX_PAGES_MIN = 1
Config.LIBGEN_MAX_PAGES_MAX = 20

Config.DEFAULT_DOWNLOAD_DIR_FALLBACK = G_reader_settings:readSetting("home_dir")
             or require("apps/filemanager/filemanagerutil").getDefaultDir()

-- Anna's Archive uses ISO 639-1 / BCP-47 language codes (see the `lang`
-- query parameter in the search form). Unknown values are silently ignored
-- by the server, which makes the filter appear to do nothing.
Config.SUPPORTED_LANGUAGES = {
    { name = "العربية", value = "ar" },
    { name = "Հայերեն", value = "hy" },
    { name = "Azərbaycanca", value = "az" },
    { name = "বাংলা", value = "bn" },
    { name = "简体中文", value = "zh" },
    { name = "Čeština", value = "cs" },
    { name = "Nederlands", value = "nl" },
    { name = "English", value = "en" },
    { name = "Français", value = "fr" },
    { name = "ქართული", value = "ka" },
    { name = "Deutsch", value = "de" },
    { name = "Ελληνικά", value = "el" },
    { name = "हिन्दी", value = "hi" },
    { name = "Bahasa Indonesia", value = "id" },
    { name = "Italiano", value = "it" },
    { name = "日本語", value = "ja" },
    { name = "한국어", value = "ko" },
    { name = "Bahasa Malaysia", value = "ms" },
    { name = "پښتو", value = "ps" },
    { name = "Polski", value = "pl" },
    { name = "Português", value = "pt" },
    { name = "Русский", value = "ru" },
    { name = "Српски", value = "sr" },
    { name = "Slovenčina", value = "sk" },
    { name = "Español", value = "es" },
    { name = "తెలుగు", value = "te" },
    { name = "ไทย", value = "th" },
    { name = "繁體中文", value = "zh-Hant" },
    { name = "Türkçe", value = "tr" },
    { name = "Українська", value = "uk" },
    { name = "اردو", value = "ur" },
    { name = "Tiếng Việt", value = "vi" },
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

-- Optional bootstrap: a credentials file in the plugin directory supplies the
-- member key. Errors return stable categories only, never raw loadfile/pcall
-- messages (they can quote the source line and leak the secret into logs).
local function loadSecretKey(path)
    local chunk = loadfile(path)
    if not chunk then
        return false, "parse_error"
    end

    local ok, credentials = pcall(chunk)
    if not ok then
        return false, "runtime_error"
    end
    if type(credentials) ~= "table" then
        return false, "not_a_table"
    end

    if type(credentials.annasSecretKey) == "string" and util.trim(credentials.annasSecretKey) ~= "" then
        Config.saveSetting(Config.SETTINGS_AA_SECRET_KEY_KEY, credentials.annasSecretKey)
        return true
    end

    return false, "missing_key"
end

function Config.loadCredentialsFromFile(plugin_path)
    -- One-time import only; an empty string counts as a deliberate clear.
    if G_reader_settings:readSetting(Config.SETTINGS_AA_SECRET_KEY_KEY) ~= nil then
        return
    end
    local path = plugin_path .. Config.CREDENTIALS_FILENAME
    local file = io.open(path, "r")
    if not file then
        return
    end
    file:close()
    local loaded, category = loadSecretKey(path)
    if loaded then
        logger.info("Annas: Loaded secret key from " .. Config.CREDENTIALS_FILENAME)
    else
        logger.warn("Annas: Could not load " .. Config.CREDENTIALS_FILENAME .. ": " .. category)
    end
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

function Config.getLibgenMaxPages()
    local pages = tonumber(Config.getSetting(Config.SETTINGS_LIBGEN_MAX_PAGES_KEY)) or Config.LIBGEN_MAX_PAGES_DEFAULT
    return math.max(Config.LIBGEN_MAX_PAGES_MIN, math.min(Config.LIBGEN_MAX_PAGES_MAX, math.floor(pages)))
end

function Config.setLibgenMaxPages(pages)
    Config.saveSetting(Config.SETTINGS_LIBGEN_MAX_PAGES_KEY, pages)
end

function Config.getLibgenTopics()
    return Config.getSetting(Config.SETTINGS_LIBGEN_TOPICS_KEY, {})
end

function Config.getAnnasSecretKey()
    local key = Config.getSetting(Config.SETTINGS_AA_SECRET_KEY_KEY)
    -- Empty string = deliberately cleared; callers see nil either way.
    if key == "" then
        return nil
    end
    return key
end

function Config.setAnnasSecretKey(key)
    -- Persist clears as "" so the credentials file cannot resurrect the key.
    Config.saveSetting(Config.SETTINGS_AA_SECRET_KEY_KEY, key or "")
end

-- Pre-rename versions stored these under zlibrary_* keys, which collided with
-- the unrelated zlibrary.koplugin's own settings. Copy any value forward to
-- the new annas_* key (once) so users don't silently lose their preferences
-- on update. The old key is deliberately left untouched rather than deleted:
-- since it was shared/colliding, we can't be sure it isn't still in use by
-- that other plugin if it's also installed.
local LEGACY_SETTINGS_KEY_MAP = {
    zlibrary_search_languages = Config.SETTINGS_SEARCH_LANGUAGES_KEY,
    zlibrary_search_extensions = Config.SETTINGS_SEARCH_EXTENSIONS_KEY,
    zlibrary_search_order = Config.SETTINGS_SEARCH_ORDERS_KEY,
    zlibrary_download_dir = Config.SETTINGS_DOWNLOAD_DIR_KEY,
    zlibrary_turn_off_wifi_after_download = Config.SETTINGS_TURN_OFF_WIFI_AFTER_DOWNLOAD_KEY,
}

function Config.migrateLegacySettings()
    for old_key, new_key in pairs(LEGACY_SETTINGS_KEY_MAP) do
        if G_reader_settings:readSetting(new_key) == nil then
            local old_value = G_reader_settings:readSetting(old_key)
            if old_value ~= nil then
                Config.saveSetting(new_key, old_value)
            end
        end
    end
end

return Config

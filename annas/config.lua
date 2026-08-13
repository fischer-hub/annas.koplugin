local util = require("util")
local T = require("annas.gettext")

local Config = {}

Config.SETTINGS_SEARCH_LANGUAGES_KEY = "annas_search_languages"
Config.SETTINGS_SEARCH_EXTENSIONS_KEY = "annas_search_extensions"
Config.SETTINGS_SEARCH_ORDERS_KEY = "annas_search_order"
Config.SETTINGS_DOWNLOAD_DIR_KEY = "annas_download_dir"
Config.SETTINGS_TURN_OFF_WIFI_AFTER_DOWNLOAD_KEY = "annas_turn_off_wifi_after_download"

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

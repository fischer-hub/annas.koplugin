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

return Config

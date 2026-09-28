local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local TextViewer = require("ui/widget/textviewer")
local T = require("annas.gettext")
local DownloadMgr = require("ui/downloadmgr")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local Menu = require("annas.menu")
local util = require("util")
local logger = require("logger")
local Config = require("annas.config")
local Ota = require("annas.ota")
local Ui = {}

local _plugin_instance = nil

function Ui.setPluginInstance(plugin_instance)
    _plugin_instance = plugin_instance
end

local function _showAndTrackDialog(dialog)
    if _plugin_instance and _plugin_instance.dialog_manager then
        return _plugin_instance.dialog_manager:showAndTrackDialog(dialog)
    else
        UIManager:show(dialog)
        return dialog
    end
end

local function _closeAndUntrackDialog(dialog)
    if _plugin_instance and _plugin_instance.dialog_manager then
        _plugin_instance.dialog_manager:closeAndUntrackDialog(dialog)
    else
        if dialog then
            UIManager:close(dialog)
        end
    end
end

local function _colon_concat(a, b)
    return a .. ": " .. b
end

function Ui.colonConcat(a, b)
    return _colon_concat(a, b)
end

function Ui.showInfoMessage(text)
    if _plugin_instance and _plugin_instance.dialog_manager then
        _plugin_instance.dialog_manager:showInfoMessage(text)
    else
        UIManager:show(InfoMessage:new{ text = text })
    end
end

function Ui.showErrorMessage(text)
    if _plugin_instance and _plugin_instance.dialog_manager then
        _plugin_instance.dialog_manager:showErrorMessage(text)
    else
        UIManager:show(InfoMessage:new{ text = text, timeout = 5 })
    end
end

function Ui.showLoadingMessage(text)
    local message = InfoMessage:new{ text = text, timeout = 0 }
    UIManager:show(message)
    return message
end

function Ui.closeMessage(message_widget)
    if message_widget then
        if type(message_widget.close) == "function" then
            message_widget:close()
            -- Ensure complete screen refresh after closing the progress dialog
            -- Use setDirty with "full" to completely redraw the screen area
            UIManager:setDirty("all", "full")
        else
            UIManager:close(message_widget)
        end
    end
end

function Ui.showFullTextDialog(title, full_text)
    local dialog = TextViewer:new{
        title = title,
        text = full_text,
    }
    _showAndTrackDialog(dialog)
end

function Ui.showSimpleMessageDialog(title, text)
    if _plugin_instance and _plugin_instance.dialog_manager then
        _plugin_instance.dialog_manager:showConfirmDialog({
            title = title,
            text = text,
            cancel_text = T("Close"),
            no_ok_button = true,
        })
    else
        local dialog = ConfirmBox:new{
            title = title,
            text = text,
            cancel_text = T("Close"),
            no_ok_button = true,
        }
        UIManager:show(dialog)
    end
end

function Ui.showDownloadDirectoryDialog()
    local current_dir = Config.getSetting(Config.SETTINGS_DOWNLOAD_DIR_KEY)
    DownloadMgr:new{
        title = T("Select Download Directory"),
        onConfirm = function(path)
            if path then
                Config.saveSetting(Config.SETTINGS_DOWNLOAD_DIR_KEY, path)
                Ui.showInfoMessage(string.format(T("Download directory set to: %s"), path))
            else
                Ui.showErrorMessage(T("No directory selected."))
            end
        end,
    }:chooseDir(current_dir)
end

function Ui.showSettingsDialog()

    local full_source_path = debug.getinfo(1, "S").source
    if full_source_path:sub(1,1) == "@" then
        full_source_path = full_source_path:sub(2)
    end
    local foo, _ = util.splitFilePathName(full_source_path):gsub("/+", "/")
    local plugin_path, _ = foo:gsub("/annas/", "")

    dialog = ButtonDialog:new{
        title = T("Settings"),
        input = def_input,
        buttons = {
            {{
            text = T("Set Download Directory"),
            callback = function()
                _closeAndUntrackDialog(dialog)
                Ui.showDownloadDirectoryDialog()
            end,
            }},{{
            text = string.format(T("Max. result pages to filter: %d"), Config.getLibgenMaxPages()),
            callback = function()
                _closeAndUntrackDialog(dialog)
                Ui.showLibgenMaxPagesDialog()
            end,
            }},{{
            text = #Config.getLibgenTopics() == 0 and T("Library Genesis collections: all")
                or string.format(T("Library Genesis collections: %d selected"), #Config.getLibgenTopics()),
            callback = function()
                _closeAndUntrackDialog(dialog)
                Ui.showLibgenTopicsDialog()
            end,
            }},{{
            text = T("Check for Updates"),
            keep_menu_open = false,
            separator = true,
            callback = function()
                _closeAndUntrackDialog(dialog)
                if plugin_path then
                    Ota.startUpdateProcess(plugin_path)
                else
                    logger.err("Annas: Plugin path not available for OTA update.")
                    Ui.showErrorMessage(T("Error: Plugin path not found. Cannot check for updates."))
                end
            end,
            }}
        }
    }
    _showAndTrackDialog(dialog)
end

function Ui.showLibgenMaxPagesDialog()
    local SpinWidget = require("ui/widget/spinwidget")
    local widget = SpinWidget:new{
        title_text = T("Max. result pages to filter"),
        info_text = T("Library Genesis can't filter by language or format itself, so with those filters set, the plugin reads up to this many pages of 100 results and keeps the matches. More pages find more matches for narrow filters, but each page adds about a second."),
        value = Config.getLibgenMaxPages(),
        value_min = Config.LIBGEN_MAX_PAGES_MIN,
        value_max = Config.LIBGEN_MAX_PAGES_MAX,
        default_value = Config.LIBGEN_MAX_PAGES_DEFAULT,
        callback = function(spin)
            Config.setLibgenMaxPages(spin.value)
            Ui.showSettingsDialog()
        end,
    }
    _showAndTrackDialog(widget)
end

local function _showMultiSelectionDialog(parent_ui, title, setting_key, options_list, ok_callback, is_single)
    local selected_values_table = Config.getSetting(setting_key, {})
    local selected_values_set = {}
    for _, value in ipairs(selected_values_table) do
        selected_values_set[value] = true
    end

    local current_selection_state = {}
    for _, option_info in ipairs(options_list) do
        current_selection_state[option_info.value] = selected_values_set[option_info.value] or false
    end

    local menu_items = {}
    local selection_menu

    for i, option_info in ipairs(options_list) do
        local option_value = option_info.value
        menu_items[i] = {
            text = option_info.name,
            mandatory_func = function()
                return current_selection_state[option_value] and "[X]" or "[ ]"
            end,
            callback = function()
                current_selection_state[option_value] = not current_selection_state[option_value]
                selection_menu:updateItems(nil, true)
                -- single select
                if is_single then
                    selection_menu:onClose()
                end
            end,
            keep_menu_open = true,
        }
    end

    selection_menu = Menu:new{
        title = title,
        item_table = menu_items,
        parent = parent_ui,
        show_captions = true,
        onClose = function()
            local ok, err = pcall(function()
                local new_selected_values = {}
                for value, is_selected in pairs(current_selection_state) do
                    if is_selected then table.insert(new_selected_values, value) end
                end
                if is_single and #new_selected_values > 1 then
                    local original_option = selected_values_table[1]
                    for i = #new_selected_values, 1, -1 do
                        if new_selected_values[i] == original_option then
                            table.remove(new_selected_values, i)
                        end
                    end
                end

                table.sort(new_selected_values, function(a, b)
                    local name_a, name_b
                    for _, info in ipairs(options_list) do
                        if info.value == a then name_a = info.name end
                        if info.value == b then name_b = info.name end
                    end
                    return (name_a or "") < (name_b or "")
                end)

                if #new_selected_values > 0 then
                    Config.saveSetting(setting_key, new_selected_values)
                    return #new_selected_values
                else
                    Config.deleteSetting(setting_key)
                end
            end)

            UIManager:close(selection_menu)
            if ok then
                if type(ok_callback) == "function" then
                    ok_callback(err)
                else
                    Ui.showInfoMessage(string.format(T("%d items selected for %s."), err, title))
                end
            else
                logger.err("Annas:Ui._editConfigOptionsDialog - Error during onClose for %s: %s", title, tostring(err))
                Ui.showInfoMessage(string.format(T("Filter cleared for %s."), title))
            end
        end,
    }
    _showAndTrackDialog(selection_menu)
end

local function  _showRadioSelectionDialog(parent_ui, title, setting_key, options_list, ok_callback)
    _showMultiSelectionDialog(parent_ui, title, setting_key, options_list, ok_callback, true)
end

function Ui.showLanguageSelectionDialog(parent_ui)
    _showMultiSelectionDialog(parent_ui, T("Select search languages"), Config.SETTINGS_SEARCH_LANGUAGES_KEY, Config.SUPPORTED_LANGUAGES)
end

function Ui.showExtensionSelectionDialog(parent_ui)
    _showMultiSelectionDialog(parent_ui, T("Select search formats"), Config.SETTINGS_SEARCH_EXTENSIONS_KEY, Config.SUPPORTED_EXTENSIONS)
end

function Ui.showLibgenTopicsDialog(parent_ui)
    _showMultiSelectionDialog(parent_ui, T("Select Library Genesis collections"), Config.SETTINGS_LIBGEN_TOPICS_KEY, Config.SUPPORTED_LIBGEN_TOPICS, function()
        Ui.showSettingsDialog()
    end)
end

function Ui.showOrdersSelectionDialog(parent_ui, ok_callback)
    _showRadioSelectionDialog(parent_ui, T("Select search order"), Config.SETTINGS_SEARCH_ORDERS_KEY, Config.SUPPORTED_ORDERS, ok_callback)
end

function Ui.showSearchDialog(parent_annas, def_input)
    -- save last search input
    if Ui._last_search_input and not def_input then
        def_input = Ui._last_search_input
    end

    local dialog
    local search_order_name = Config.getSearchOrderName()
    
    local selected_languages = Config.getSearchLanguages()
    local selected_extensions = Config.getSearchExtensions()
    
    local lang_text = T("Set languages")
    if #selected_languages > 0 then
        if #selected_languages == 1 then
            lang_text = string.format(T("Language: %s"), selected_languages[1])
        else
            lang_text = string.format(T("Languages (%d)"), #selected_languages)
        end
    end
    
    local format_text = T("Set formats")
    if #selected_extensions > 0 then
        if #selected_extensions == 1 then
            for _, ext_info in ipairs(Config.SUPPORTED_EXTENSIONS) do
                if ext_info.value == selected_extensions[1] then
                    format_text = string.format(T("Format: %s"), ext_info.name)
                    break
                end
            end
        else
            format_text = string.format(T("Formats (%d)"), #selected_extensions)
        end
    end

    dialog = InputDialog:new{
        title = T("Search Annas Archive"),
        input = def_input,
        buttons = {{{
        text = T("Search"),
        callback = function()
            local query = dialog:getInputText()
            _closeAndUntrackDialog(dialog)

            if not query or not query:match("%S") then
                Ui.showErrorMessage(T("Please enter a search term."))
                return
            end
            Ui._last_search_input = query

            local trimmed_query = util.trim(query)
            parent_annas:performSearch(trimmed_query)
        end,
        }},{{
            text = string.format("%s: %s \u{25BC}", T("Sort by"), search_order_name),
            callback = function()
                _closeAndUntrackDialog(dialog)
                Ui.showOrdersSelectionDialog(parent_annas, function(count)
                    Ui.showSearchDialog(parent_annas, def_input)
                end)
            end
        }},{{
            text = lang_text,
            callback = function()
                _closeAndUntrackDialog(dialog)
                _showMultiSelectionDialog(parent_annas, T("Select search languages"), Config.SETTINGS_SEARCH_LANGUAGES_KEY, Config.SUPPORTED_LANGUAGES, function(count)
                    Ui.showSearchDialog(parent_annas, def_input)
                end)
            end
        },{
            text = format_text,
            callback = function()
                _closeAndUntrackDialog(dialog)
                _showMultiSelectionDialog(parent_annas, T("Select search formats"), Config.SETTINGS_SEARCH_EXTENSIONS_KEY, Config.SUPPORTED_EXTENSIONS, function(count)
                    Ui.showSearchDialog(parent_annas, def_input)
                end)
            end
        }},{{
            text = T("Settings"),
            keep_menu_open = true,
            callback = function()
                _closeAndUntrackDialog(dialog)
                Ui.showSettingsDialog()
            end,
        }},{{
            text = T("Cancel"),
            id = "close",
            callback = function() _closeAndUntrackDialog(dialog) end,
        }}}
    }
    _showAndTrackDialog(dialog)
    dialog:onShowKeyboard()
end

function Ui.createBookMenuItem(book_data, parent_annas_instance)
    local year_str = (book_data.year and book_data.year ~= "N/A" and tostring(book_data.year) ~= "0") and (" (" .. book_data.year .. ")") or ""
    local title_for_html = (type(book_data.title) == "string" and book_data.title) or T("Unknown Title")
    local title = util.htmlEntitiesToUtf8(title_for_html)
    local author_for_html = (type(book_data.author) == "string" and book_data.author) or T("Unknown Author")
    local author = util.htmlEntitiesToUtf8(author_for_html)
    local combined_text = string.format("%s by %s%s", title, author, year_str)

    local additional_info_parts = {}

    if book_data.format and book_data.format ~= "N/A" then
        table.insert(additional_info_parts, book_data.format)
    end
    if book_data.size and book_data.size ~= "N/A" then table.insert(additional_info_parts, book_data.size) end
    if book_data.rating and book_data.rating ~= "N/A" then table.insert(additional_info_parts, _colon_concat(T("Rating"), book_data.rating)) end

    if #additional_info_parts > 0 then
        combined_text = combined_text .. " | " .. table.concat(additional_info_parts, " | ")
    end

    return {
        text = combined_text,
        callback = function()
            Ui.showBookDetails(parent_annas_instance, book_data)
        end,
        keep_menu_open = true,
        original_book_data_ref = book_data,
    }
end

function Ui.createSearchResultsMenu(parent_ui_ref, query_string, initial_menu_items)
    local search_order_name = Config.getSearchOrderName()
    local menu = Menu:new{
        title = _colon_concat(T("Search Results"), query_string),
        subtitle = string.format("%s: %s", T("Sort by"), search_order_name),
        item_table = initial_menu_items,
        parent = parent_ui_ref,
        items_per_page = 10,
        show_captions = true,
        is_popout = false,
        is_borderless = true,
        title_bar_fm_style = true,
        multilines_show_more_text = true
    }
    _showAndTrackDialog(menu)
    return menu
end

function Ui.showBookDetails(parent_annas, book)
    local details_menu_items = {}
    local details_menu

    local title_text_for_html = (type(book.title) == "string" and book.title) or ""
    local full_title = util.htmlEntitiesToUtf8(title_text_for_html)
    table.insert(details_menu_items, {
        text = _colon_concat(T("Title"), full_title),
        mandatory = "\u{25B7}",
        callback = function()
            if book.description and book.description ~= "" then
                local desc_for_html = (type(book.description) == "string" and book.description) or ""
                local full_description = util.htmlEntitiesToUtf8(util.trim(desc_for_html))
                full_description = string.gsub(full_description, "<[Bb][Rr]%s*/?>", "\n")
                full_description = string.gsub(full_description, "</[Pp]>", "\n\n")
                full_description = string.gsub(full_description, "<[^>]+>", "")
                full_description = string.gsub(full_description, "(\n\r?%s*){2,}", "\n\n")
                Ui.showFullTextDialog(T("Description"), full_description)
            else
                Ui.showSimpleMessageDialog(T("Full Title"), full_title)
            end
        end,
    })

    local author_text_for_html = (type(book.author) == "string" and book.author) or ""
    local full_author = util.htmlEntitiesToUtf8(author_text_for_html)
    table.insert(details_menu_items, {
        text = string.format("%s: %s", T("Author"), full_author),
        mandatory = "\u{25B7}",
        callback = function()
            Ui.showSearchDialog(parent_annas, full_author)
        end,
    })

    if book.year and book.year ~= "N/A" and tostring(book.year) ~= "0" then table.insert(details_menu_items, { text = _colon_concat(T("Year"), book.year), enabled = false }) end
    if book.lang and book.lang ~= "N/A" then table.insert(details_menu_items, { text = _colon_concat(T("Language"), book.lang), enabled = false }) end

    if book.format and book.format ~= "N/A" then
        if book.download then
            table.insert(details_menu_items, {
                text = string.format(T("Format: %s (tap to download)"), book.format),
                mandatory = "\u{25B7}",
                callback = function()
                    parent_annas:downloadBook(book)
                end,
            })
        else
            table.insert(details_menu_items, { text = string.format(T("Format: %s (Download source unavailable [zlib, lgli])"), book.format), enabled = false })
        end
    elseif book.download then
        table.insert(details_menu_items, {
            text = T("Download Book (Unknown Format)"),
            mandatory = "\u{25B7}",
            callback = function()
                parent_annas:downloadBook(book)
            end,
        })
    end

    if book.size and book.size ~= "N/A" then table.insert(details_menu_items, { text = _colon_concat(T("Size"), book.size), enabled = false }) end
    if book.rating and book.rating ~= "N/A" then table.insert(details_menu_items, { text = _colon_concat(T("Rating"), book.rating), enabled = false }) end
    if book.publisher and book.publisher ~= "" then
        local publisher_for_html = (type(book.publisher) == "string" and book.publisher) or ""
        table.insert(details_menu_items, { text = _colon_concat(T("Publisher"), util.htmlEntitiesToUtf8(publisher_for_html)), enabled = false })
    end
    if book.series and book.series ~= "" then
        local series_for_html = (type(book.series) == "string" and book.series) or ""
        table.insert(details_menu_items, { text = _colon_concat(T("Series"), util.htmlEntitiesToUtf8(series_for_html)), enabled = false })
    end
    if book.pages and book.pages ~= 0 then table.insert(details_menu_items, { text = _colon_concat(T("Pages"), book.pages), enabled = false }) end

    table.insert(details_menu_items, { text = "---" })

    table.insert(details_menu_items, {
        text = T("Back"),
        mandatory = "\u{21A9}",
        callback = function()
            if details_menu then UIManager:close(details_menu) end
        end,
    })

    details_menu = Menu:new{
        title = T("Book Details"),
        item_table = details_menu_items,
        parent = parent_annas.ui,
        show_captions = true,
        multilines_show_more_text = true
    }

    _showAndTrackDialog(details_menu)
end

function Ui.confirmDownload(filename, ok_callback)
    if _plugin_instance and _plugin_instance.dialog_manager then
        _plugin_instance.dialog_manager:showConfirmDialog({
            text = string.format(T("Download \"%s\"?"), filename),
            ok_text = T("Download"),
            ok_callback = ok_callback,
            cancel_text = T("Cancel")
        })
    else
        local dialog = ConfirmBox:new{
            text = string.format(T("Download \"%s\"?"), filename),
            ok_text = T("Download"),
            ok_callback = ok_callback,
            cancel_text = T("Cancel")
        }
        UIManager:show(dialog)
    end
end

function Ui.confirmOpenBook(filename, has_wifi_toggle, default_turn_off_wifi, ok_open_callback, cancel_callback)
    local turn_off_wifi = default_turn_off_wifi

    local function showDialog()
        local full_text = string.format(T("\"%s\" downloaded successfully. Open it now?"), filename)

        local dialog
        local other_buttons = nil

        if has_wifi_toggle then
            other_buttons = {{
                {
                    text = turn_off_wifi and ("☑ " .. T("Turn off Wi-Fi after closing this dialog")) or ("☐ " .. T("Turn off Wi-Fi after closing this dialog")),
                    callback = function()
                        turn_off_wifi = not turn_off_wifi
                        Config.setTurnOffWifiAfterDownload(turn_off_wifi)
                        UIManager:close(dialog)
                        showDialog()
                    end,
                },
            }}
        end

        dialog = ConfirmBox:new{
            text = full_text,
            ok_text = T("Open book"),
            ok_callback = function()
                ok_open_callback(turn_off_wifi)
            end,
            cancel_text = T("Close"),
            cancel_callback = function()
                cancel_callback(turn_off_wifi)
            end,
            other_buttons = other_buttons,
            other_buttons_first = true,
        }

        _showAndTrackDialog(dialog)
    end

    showDialog()
end

function Ui.showRetryErrorDialog(err_msg, operation_name, retry_callback, cancel_callback, loading_msg_to_close)
    local error_string = tostring(err_msg)
    

    local is_http_400 = string.match(error_string, "HTTP Error: 400")
    local is_timeout = string.find(error_string, T("Request timed out")) or 
                      string.find(error_string, "timeout") or 
                      string.find(error_string, "timed out") or
                      string.find(error_string, "sink timeout")
    local is_network_error = string.find(error_string, T("Network connection error")) or
                            string.find(error_string, T("Network request failed"))
    
    if is_http_400 or is_timeout or is_network_error then
        local retry_message
        if is_timeout then
            retry_message = string.format(T("%s failed due to a timeout. Would you like to retry?"), operation_name)
        elseif is_network_error then
            retry_message = string.format(T("%s failed due to a network error. Would you like to retry?"), operation_name)
        else
            retry_message = string.format(T("%s failed due to a temporary issue. Would you like to retry?"), operation_name)
        end
        
        if _plugin_instance and _plugin_instance.dialog_manager then
            _plugin_instance.dialog_manager:showConfirmDialog({
                text = retry_message,
                ok_text = T("Retry"),
                cancel_text = T("Cancel"),
                ok_callback = function()
                    if loading_msg_to_close then
                        Ui.closeMessage(loading_msg_to_close)
                    end
                    retry_callback()
                end,
                cancel_callback = function()
                    if loading_msg_to_close then
                        Ui.closeMessage(loading_msg_to_close)
                    end
                    cancel_callback(err_msg)
                end
            })
        else
            if loading_msg_to_close then
                Ui.closeMessage(loading_msg_to_close)
            end
            Ui.showErrorMessage(error_string)
            cancel_callback(err_msg)
        end
    else
        if loading_msg_to_close then
            Ui.closeMessage(loading_msg_to_close)
        end
        Ui.showErrorMessage(error_string)
        cancel_callback(err_msg)
    end
end

return Ui

--[[--
@module koplugin.Annas
--]]--

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local util = require("util")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("annas.gettext")
local Config = require("annas.config")
local Ui = require("annas.ui")
local ReaderUI = require("apps/reader/readerui")
local AsyncHelper = require("annas.async_helper")
local logger = require("logger")
local Ota = require("annas.ota")
local Device = require("device")
local DialogManager = require("annas.dialog_manager")

require('src.scraper')

local Annas = WidgetContainer:extend{
    name = T("Anna's Archive"),
    is_doc_only = false,
    plugin_path = nil,
    dialog_manager = nil,
}

-- Versions before the annas/ rename shipped a "zlibrary" subfolder and a
-- zlibrary_credentials.lua file under the same names as the (unrelated)
-- zlibrary.koplugin project, which caused module/setting collisions when
-- both plugins were installed. A manual copy-over update (rather than the
-- in-app updater, which replaces the whole plugin folder) can leave those
-- files behind, so sweep them up on startup.
local function cleanupLegacyZlibraryFiles(plugin_path)
    -- Sanity-check plugin_path before doing anything destructive with it: if
    -- path detection ever misbehaves, this must fail safe (do nothing) rather
    -- than rm -rf some unintended directory.
    if not (plugin_path and plugin_path:match("annas%.koplugin/?$")) then
        logger.warn("Annas: Skipping legacy file cleanup, unexpected plugin_path: " .. tostring(plugin_path))
        return
    end

    local legacy_dir = plugin_path .. "zlibrary"
    if lfs.attributes(legacy_dir, "mode") == "directory" then
        logger.info("Annas: Removing leftover 'zlibrary' directory from a pre-rename version: " .. legacy_dir)
        os.execute(string.format("rm -rf '%s'", legacy_dir))
    end

    local legacy_credentials = plugin_path .. "zlibrary_credentials.lua"
    if lfs.attributes(legacy_credentials, "mode") == "file" then
        logger.info("Annas: Removing leftover legacy file: " .. legacy_credentials)
        os.remove(legacy_credentials)
    end
end

function Annas:onDispatcherRegisterActions()
    Dispatcher:registerAction("annas_search", { category="none", event="AnnasSearch", title=T("Anna's Archive search"), general=true,})
end

function Annas:init()
    local full_source_path = debug.getinfo(1, "S").source
    if full_source_path:sub(1,1) == "@" then
        full_source_path = full_source_path:sub(2)
    end
    self.plugin_path, _ = util.splitFilePathName(full_source_path):gsub("/+", "/")

    cleanupLegacyZlibraryFiles(self.plugin_path)
    Config.migrateLegacySettings()

    local current_version = Ota.getCurrentPluginVersion(self.plugin_path)

    self.dialog_manager = DialogManager:new()
    Ui.setPluginInstance(self)

    self:onDispatcherRegisterActions()
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    else
        logger.warn("self.ui or self.ui.menu not initialized in Annas:init")
    end

    logger.info(string.format("Annas: Init successful, version is: %s", current_version))

end

function Annas:onAnnasSearch()
    local def_search_input
    if self.ui and self.ui.doc_settings and self.ui.doc_settings.data.doc_props then
      local doc_props = self.ui.doc_settings.data.doc_props
      def_search_input = doc_props.authors or doc_props.title
    end
    Ui.showSearchDialog(self, def_search_input)
    return true
end

function Annas:addToMainMenu(menu_items)

    if not self.ui.view then
        menu_items.annas_main = {
            sorting_hint = "search",
            text = T("Anna's Archive"),
            callback = function()
                Ui.showSearchDialog(self)
            end,
        }
    end
end

function Annas:performSearch(query)
    if not NetworkMgr:isOnline() then
        Ui.showErrorMessage(T("No internet connection detected."))
        return
    end

    local loading_msg = Ui.showLoadingMessage(T("Searching for \"") .. query .. "\"...")

    local function task_search()
        return scraper(query)
    end

    local function on_success_search(res)
        if type(res) ~= "table" then
            -- scraper() failed outright (e.g. every mirror unreachable/blocked)
            -- and returned a message describing why, instead of results.
            logger.warn("Annas:performSearch - Search failed: " .. tostring(res))
            Ui.showErrorMessage(tostring(res))
            return
        end

        if #res == 0 then
            Ui.showInfoMessage(T("No results found for \"") .. query .. "\".")
            return
        end

        logger.info(string.format("Annas:performSearch - Fetch successful. Results: %d", #res))
        self.current_search_query = query
        self.all_search_results_data = res
        self:displaySearchResults(self.all_search_results_data, self.current_search_query)
    end

    local function on_error_search(err_msg)
        Ui.showErrorMessage(tostring(err_msg))
    end

    AsyncHelper.run(task_search, on_success_search, on_error_search, loading_msg)
end

function Annas:displaySearchResults(initial_book_data_list, query_string)
    if not initial_book_data_list or #initial_book_data_list == 0 then
        logger.info("Annas:displaySearchResults - No initial results to display.")
        return
    end

    local menu_items = {}
    logger.info(string.format("Annas:displaySearchResults - Preparing menu items from %d initial results.", #initial_book_data_list))

    for i = 1, #initial_book_data_list do
        local book_menu_item_data = initial_book_data_list[i]
        menu_items[i] = Ui.createBookMenuItem(book_menu_item_data, self)
    end

    if self.active_results_menu then
        UIManager:close(self.active_results_menu)
        self.active_results_menu = nil
    end

    self.active_results_menu = Ui.createSearchResultsMenu(self.ui, query_string, menu_items)
end

function Annas:downloadBook(book)
    if not NetworkMgr:isOnline() then
        Ui.showErrorMessage(T("No internet connection detected."))
        return
    end

    if not book.download then
        Ui.showErrorMessage(T("No download link available for this book."))
        return
    end

    local target_dir = Config.getDownloadDir()

    if not target_dir then
        target_dir = Config.DEFAULT_DOWNLOAD_DIR_FALLBACK
        logger.warn(string.format("Annas:downloadBook - Download directory setting not found, using fallback: %s", target_dir))
    else
        logger.info(string.format("Annas:downloadBook - Using configured download directory: %s", target_dir))
    end

    if lfs.attributes(target_dir, "mode") ~= "directory" then
        local ok, err_mkdir = lfs.mkdir(target_dir)
        if not ok then
            Ui.showErrorMessage(string.format(T("Cannot create downloads directory: %s"), err_mkdir or "Unknown error"))
            return
        end
        logger.info(string.format("Annas:downloadBook - Created downloads directory: %s", target_dir))
    end

    local function attemptDownload()
        local loading_msg = Ui.showLoadingMessage(T("Downloading, please wait …"))

        local function task_download()
            return download_book(book, target_dir)
        end

        local function on_success_download(api_result)
            Ui.closeMessage(loading_msg)
            if not string.find(api_result, 'Failed,', 1, true) then
                local has_wifi_toggle = Device:hasWifiToggle()
                local default_turn_off_wifi = Config.getTurnOffWifiAfterDownload()

                Ui.confirmOpenBook(api_result, has_wifi_toggle, default_turn_off_wifi, function(should_turn_off_wifi)
                    if should_turn_off_wifi then
                        NetworkMgr:disableWifi(function()
                            logger.info("Annas:downloadBook - Wi-Fi disabled after download as requested by user")
                        end)
                    end

                    if ReaderUI then
                        logger.info("Annas:downloadBook - Cleaning up dialogs before opening reader")
                        self.dialog_manager:closeAllDialogs()
                        ReaderUI:showReader(api_result)
                    else
                        Ui.showErrorMessage(T("Could not open reader UI."))
                        logger.warn("Annas:downloadBook - ReaderUI not available.")
                    end
                end,
                function(should_turn_off_wifi)
                    if should_turn_off_wifi then
                        NetworkMgr:disableWifi(function()
                            logger.info("Annas:downloadBook - Wi-Fi disabled after download as requested by user")
                        end)
                        logger.info("Annas:downloadBook - Cleaning up dialogs cause wifi is turned off")
                        self.dialog_manager:closeAllDialogs()
                    end
                end
                )
            else
                Ui.showErrorMessage(api_result)
            end
        end

        local function on_error_download(err_msg)
            local error_string = tostring(err_msg)
            if string.find(error_string, "Download limit reached or file is an HTML page", 1, true) then
                Ui.closeMessage(loading_msg)
                Ui.showErrorMessage(T("Download limit reached. Please try again later or check your account."))
                return
            end

            Ui.showRetryErrorDialog(err_msg, T("Download"), function()
                local new_loading_msg = Ui.showLoadingMessage(T("Retrying download..."))
                loading_msg = new_loading_msg
                AsyncHelper.run(task_download, on_success_download, on_error_download, loading_msg)
            end, function(final_err_msg)
            end, loading_msg)
        end

        AsyncHelper.run(task_download, on_success_download, on_error_download, loading_msg)
    end

    Ui.confirmDownload(book.title, function()
        attemptDownload()
    end)
end

function Annas:onExit()
    if self.dialog_manager and self.dialog_manager:getDialogCount() > 0 then
        logger.info("Annas:onExit - Cleaning up " .. self.dialog_manager:getDialogCount() .. " remaining dialogs")
        self.dialog_manager:closeAllDialogs()
    end
end

function Annas:onCloseWidget()
    if self.dialog_manager and self.dialog_manager:getDialogCount() > 0 then
        logger.info("Annas:onCloseWidget - Cleaning up " .. self.dialog_manager:getDialogCount() .. " remaining dialogs")
        self.dialog_manager:closeAllDialogs()
    end
end

return Annas

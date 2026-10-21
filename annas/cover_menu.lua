local Menu = require("annas.menu")
local CoverCache = require("annas.cover_cache")
local CoverLoader = require("annas.cover_loader")
local CoverUtils = require("annas.cover_utils")
local ImageWidget = require("ui/widget/imagewidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local T = require("annas.gettext")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")

local M = Menu:extend{ items_per_page = 6 }

function M:init()
    self._cover_loader = CoverLoader:new()
    Menu.init(self)
end

function M:_coverLabel(book)
    local key = CoverUtils.key(book)
    local state = key and self._cover_loader.states[key]
    if not state then
        return CoverCache.should_fetch(book) and T("Queued") or T("No cover")
    end
    if state.stage == "download" then
        if state.total and state.total > 0 then

            return string.format("%d%%", math.min(99, math.floor((state.received or 0) * 100 / state.total)))
        end
        if state.received and state.received > 0 then
            return string.format("%s\n%d %s", T("Loading"), math.ceil(state.received / 1024), T("KB"))
        end
        return T("Loading")
    end
    local labels = {
        queued = T("Queued"), lookup = T("Finding cover"), connecting = T("Connecting"),
        ready = "100%", unavailable = T("No cover"), error = T("Error"),
        timeout = T("Timed out"), cancelled = T("Stopped"),
    }
    return labels[state.stage] or T("Queued")
end

function M:_recalculateDimen(...)
    Menu._recalculateDimen(self, ...)
    if not self.item_dimen then return end
    local gap = Screen:scaleBySize(8)
    local height = math.max(20, self.item_dimen.h - 2 * gap)
    local width = math.floor(height * 0.65)
    self.state_w = width + gap
    local first = (self.page - 1) * self.perpage + 1
    for index = first, math.min(first + self.perpage - 1, #self.item_table) do
        local item = self.item_table[index]
        local file = CoverCache.get(item.original_book_data_ref)
        if file then
            item.state = ImageWidget:new{
                file = file, width = width, height = height,
                scale_factor = 0, alpha = true,
            }
        else
            item.state = FrameContainer:new{
                bordersize = 1, padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{w = width - 2, h = height - 2},
                    TextBoxWidget:new{
                        text = self:_coverLabel(item.original_book_data_ref),
                        face = Font:getFace("smallinfofont", 16),
                        width = width - 6, alignment = "center",
                    },
                },
            }
        end
    end
end

function M:updateItems(...)
    if self._cover_loader then self._cover_loader:stop() end
    if self._cover_loader then self._cover_loader.states = {} end
    if self._cover_start then UIManager:unschedule(self._cover_start) end
    Menu.updateItems(self, ...)
    self._cover_start = function()
        self._cover_start = nil
        if self._cover_closed then return end
        local books, seen = {}, {}
        local first = (self.page - 1) * self.perpage + 1
        for index = first, math.min(first + self.perpage - 1, #self.item_table) do
            local book = self.item_table[index].original_book_data_ref
            local key = CoverUtils.key(book)
            if key and not seen[key] and CoverCache.should_fetch(book) then
                seen[key] = true
                books[#books + 1] = book
            end
        end
        self._cover_loader:start(books, function()
            if not self._cover_closed then

                Menu.updateItems(self, nil, true)
            end
        end)
    end
    UIManager:nextTick(self._cover_start)
end

function M:onCloseWidget()
    self._cover_closed = true
    if self._cover_start then UIManager:unschedule(self._cover_start) end
    self._cover_loader:stop()
    Menu.onCloseWidget(self)
end

return M

--[[--
D&D 5e character sheets for KOReader.

"D&D 5e character sheets" in the Tools menu opens the character list, then
the sheet. "Open the last character" can be bound to a gesture.
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")

local I18n = require("dnd5e_i18n")
local Data = require("dnd5e_data")
local Sheet = require("dnd5e_sheet")
local T, F = I18n.T, I18n.F

local DnD = WidgetContainer:extend{
    name = "dnd5e",
    is_doc_only = false,
}

function DnD:init()
    Dispatcher:registerAction("dnd5e_last", {
        category = "none", event = "DnD5eOpenLast", general = true,
        title = T("D&D 5e sheets: open the last character"),
    })
    Dispatcher:registerAction("dnd5e_list", {
        category = "none", event = "DnD5eOpenList", general = true,
        title = T("D&D 5e sheets: character list"),
    })
    self.ui.menu:registerToMainMenu(self)
end

function DnD:addToMainMenu(menu_items)
    menu_items.dnd5e = {
        text = T("D&D 5e character sheets"),
        sorting_hint = "tools",
        callback = function() self:showList() end,
    }
end

function DnD:onDnD5eOpenList()
    self:showList()
    return true
end

function DnD:onDnD5eOpenLast()
    local id = G_reader_settings:readSetting("dnd5e_last")
    local c = id and Data.load(id)
    if c then
        self:openSheet(c)
    else
        self:showList()
    end
    return true
end

function DnD:openSheet(c)
    G_reader_settings:saveSetting("dnd5e_last", c.id)
    UIManager:show(Sheet:new{
        character = c,
        on_close = function() self:refreshList() end,
    })
end

local function describe(c)
    local parts = {}
    local class = util.trim(c.class or "")
    table.insert(parts, class ~= "" and (class .. " " .. (c.level or 1)) or F("Level %d", c.level or 1))
    if util.trim(c.race or "") ~= "" then table.insert(parts, c.race) end
    table.insert(parts, c.edition)
    return table.concat(parts, " · ")
end

function DnD:listItems()
    local items = {
        {
            text = T("+ New character"),
            bold = true,
            callback = function() self:newCharacter() end,
        },
    }
    for _, c in ipairs(Data.list()) do
        table.insert(items, {
            text = c.name,
            mandatory = describe(c),
            character_id = c.id,
            callback = function()
                local fresh = Data.load(c.id)
                if fresh then self:openSheet(fresh) end
            end,
        })
    end
    return items
end

function DnD:showList()
    local plugin = self
    self.list = Menu:new{
        title = T("D&D 5e character sheets"),
        subtitle = T("Hold a character to duplicate or delete it"),
        item_table = self:listItems(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_left_icon = "appbar.settings",
        onLeftButtonTap = function() plugin:languageMenu() end,
        onMenuHold = function(_, item)
            if item.character_id then plugin:characterMenu(item) end
            return true
        end,
    }
    -- Menu also calls close_callback when an item is chosen: the real close
    -- goes through onCloseAllMenus
    local orig_close = self.list.onCloseAllMenus
    self.list.onCloseAllMenus = function(menu)
        plugin.list = nil
        return orig_close(menu)
    end
    UIManager:show(self.list)
end

function DnD:refreshList()
    if self.list then
        self.list:switchItemTable(nil, self:listItems())
    end
end

function DnD:languageMenu()
    local dialog
    local current = I18n.setting()
    local function item(code, label)
        return { {
            text = label .. (current == code and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                I18n.set(code)
                -- rebuild the list so its texts follow the new language
                if self.list then
                    UIManager:close(self.list)
                    self.list = nil
                    self:showList()
                end
            end,
        } }
    end
    local buttons = {
        item("auto", F("Automatic (%s)", I18n.name(I18n.uiLanguage()))),
    }
    for _, code in ipairs(I18n.available()) do
        table.insert(buttons, item(code, I18n.name(code)))
    end
    dialog = ButtonDialog:new{ title = T("Language"), buttons = buttons }
    UIManager:show(dialog)
end

function DnD:newCharacter()
    local dialog
    local function create(edition)
        local name = util.trim(dialog:getInputText())
        if name == "" then return end
        UIManager:close(dialog)
        local c = Data.newCharacter(name, edition)
        Data.save(c)
        self:refreshList()
        self:openSheet(c)
    end
    dialog = InputDialog:new{
        title = T("New character"),
        input = "",
        input_hint = T("Character name"),
        description = T("Choose the rules edition: you can change it later from the sheet menu."),
        buttons = { {
            { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = T("Create (2014)"), callback = function() create("2014") end },
            { text = T("Create (2024)"), is_enter_default = true, callback = function() create("2024") end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function DnD:characterMenu(item)
    local dialog
    dialog = ButtonDialog:new{
        title = item.text,
        buttons = {
            { { text = T("Duplicate"), callback = function()
                UIManager:close(dialog)
                local c = Data.load(item.character_id)
                if c then
                    local copy = Data.duplicate(c)
                    self:refreshList()
                    UIManager:show(InfoMessage:new{ text = F("Created «%s».", copy.name), timeout = 2 })
                end
            end } },
            { { text = T("Delete"), callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = F("Delete «%s»?", item.text) .. "\n" .. T("This cannot be undone."),
                    ok_text = T("Delete"),
                    cancel_text = T("Cancel"),
                    ok_callback = function()
                        Data.delete(item.character_id)
                        self:refreshList()
                    end,
                })
            end } },
        },
    }
    UIManager:show(dialog)
end

return DnD

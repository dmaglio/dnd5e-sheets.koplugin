--[[--
The character sheet screen: title bar, tabs, paged content and a footer with
the latest roll.

Each tab builds a list of rows; rows are split into pages by screen height
and turned with a swipe or the arrows at the bottom, as elsewhere in
KOReader. Every change is saved to disk immediately.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Utf8Proc = require("ffi/utf8proc")
local util = require("util")
local Screen = Device.screen

local Classes = require("dnd5e_classes")
local Species = require("dnd5e_species")
local Data = require("dnd5e_data")
local Dice = require("dnd5e_dice")
local I18n = require("dnd5e_i18n")
local Spells = require("dnd5e_spells")
local T, F = I18n.T, I18n.F

local signed = Dice.signed

--- A copy of a list of { name = English name } sorted by translated name.
local function sortedByName(list)
    local out = {}
    for _, v in ipairs(list) do table.insert(out, v) end
    table.sort(out, function(a, b) return T(a.name) < T(b.name) end)
    return out
end

--- First letter in upper case (for names shown alone on a button).
local function ucfirst(text)
    local ch = text:match("^[%z\1-\127\194-\244][\128-\191]*")
    return ch and (Utf8Proc.uppercase_dumb(ch) .. text:sub(#ch + 1)) or text
end
local PIP_ON, PIP_OFF = "●", "○"

local TABS = {
    { { id = "game", text = "Play" }, { id = "abilities", text = "Abilities" },
      { id = "skills", text = "Skills" }, { id = "attacks", text = "Attacks" } },
    { { id = "spells", text = "Spells" }, { id = "equipment", text = "Gear" },
      { id = "traits", text = "Traits" }, { id = "bio", text = "Story" }, { id = "dice", text = "Dice" } },
}

-- Tappable row: tap and hold anywhere on it ----------------------------------

local TapRow = InputContainer:extend{
    tap = nil,
    hold = nil,
}

function TapRow:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    if Device:isTouchDevice() then
        local range = function() return self.dimen end
        self.ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = range } },
            Hold = { GestureRange:new{ ges = "hold", range = range } },
        }
    end
end

function TapRow:onTap()
    if self.tap then
        self.tap()
        return true
    end
end

function TapRow:onHold()
    if self.hold then
        self.hold()
        return true
    end
end

-- Sheet ---------------------------------------------------------------------

local Sheet = InputContainer:extend{
    character = nil,
    on_close = nil,   -- called on close (to refresh the list)
    tab = "game",
    page = 1,
}

function Sheet:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    self.width = self.dimen.w
    self.margin = Size.padding.large
    self.inner_w = self.width - 2 * self.margin
    self.row_h = Screen:scaleBySize(38)

    self.f_label = Font:getFace("cfont", 19)
    self.f_value = Font:getFace("cfont", 20)
    self.f_small = Font:getFace("cfont", 15)
    self.f_text = Font:getFace("x_smallinfofont", 18)
    self.f_header = Font:getFace("tfont", 18)
    self.f_footer = Font:getFace("cfont", 18)

    if Device:isTouchDevice() then
        self.ges_events = {
            Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
    end
    self:build()
end

function Sheet:is2024()
    return self.character.edition == "2024"
end

function Sheet:save()
    Data.save(self.character)
end

--- Save and redraw, keeping the current page.
function Sheet:changed()
    self:save()
    self:refresh()
end

function Sheet:refresh()
    if self[1] then self[1]:free() end
    self:build()
    UIManager:setDirty(self, "ui")
end

function Sheet:subtitle()
    local c = self.character
    local parts = { Data.classLine(c) }
    -- the species without its lineage, to keep the line short
    local sp = Species.get(c.species.key, c.edition)
    local race = sp and T(sp.name) or util.trim(c.race or "")
    if race ~= "" then table.insert(parts, race) end
    table.insert(parts, F("HP %d/%d", c.hp.current, c.hp.max))
    table.insert(parts, F("AC %s", tostring(c.ac)))
    table.insert(parts, c.edition)
    return table.concat(parts, " · ")
end

-- Layout --------------------------------------------------------------------

function Sheet:build()
    local c = self.character
    local title_bar = TitleBar:new{
        width = self.width,
        fullscreen = true,
        align = "left",
        title = c.name,
        subtitle = self:subtitle(),
        with_bottom_line = false,
        left_icon = "appbar.menu",
        left_icon_tap_callback = function() self:showMenu() end,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local tabs = VerticalGroup:new{ align = "left" }
    for _, tab_row in ipairs(TABS) do
        local buttons = {}
        for _, tab in ipairs(tab_row) do
            local selected = tab.id == self.tab
            table.insert(buttons, {
                text = T(tab.text),
                font_bold = selected,
                font_size = 18,
                background = selected and Blitbuffer.COLOR_LIGHT_GRAY or nil,
                callback = function()
                    if self.tab ~= tab.id then
                        self.tab = tab.id
                        self.page = 1
                        self:refresh()
                    end
                end,
            })
        end
        table.insert(tabs, ButtonTable:new{
            width = self.width,
            buttons = { buttons },
            zero_sep = true,
            show_parent = self,
        })
    end
    table.insert(tabs, LineWidget:new{
        dimen = Geom:new{ w = self.width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })

    -- Pagination: rows of the current tab split by height
    local rows = self:rowsFor(self.tab)
    local footer_probe = self:buildFooter(1, 2)
    local avail_h = self.dimen.h - title_bar:getSize().h - tabs:getSize().h
        - footer_probe:getSize().h - Size.padding.default
    footer_probe:free()

    local pages, current, used = {}, {}, 0
    for _, row in ipairs(rows) do
        local h = row:getSize().h
        if used + h > avail_h and #current > 0 then
            -- don't leave a header alone at the bottom of a page
            local carry
            if current[#current].is_header then
                carry = table.remove(current)
            end
            table.insert(pages, current)
            current, used = {}, 0
            if carry then
                table.insert(current, carry)
                used = carry:getSize().h
            end
        end
        table.insert(current, row)
        used = used + h
    end
    if #current > 0 then table.insert(pages, current) end
    if #pages == 0 then pages = { {} } end
    self.page_count = #pages
    self.page = math.max(1, math.min(self.page, #pages))

    local content = VerticalGroup:new{ align = "left" }
    local content_h = 0
    for _, row in ipairs(pages[self.page]) do
        table.insert(content, row)
        content_h = content_h + row:getSize().h
    end
    -- rows on the other pages are not shown: free them
    for p, page_rows in ipairs(pages) do
        if p ~= self.page then
            for _, row in ipairs(page_rows) do row:free() end
        end
    end

    local footer = self:buildFooter(self.page, self.page_count)

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            title_bar,
            tabs,
            VerticalSpan:new{ width = Size.padding.default },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = self.margin },
                content,
            },
            VerticalSpan:new{ width = math.max(0, avail_h - content_h) },
            footer,
        },
    }
end

function Sheet:buildFooter(page, page_count)
    local c = self.character
    local group = VerticalGroup:new{ align = "left" }
    table.insert(group, LineWidget:new{
        dimen = Geom:new{ w = self.width, h = Size.line.thick },
        background = Blitbuffer.COLOR_BLACK,
    })
    local text
    if self.next_mode then
        text = self.next_mode == "adv" and T("Next d20: ADVANTAGE") or T("Next d20: DISADVANTAGE")
        if c.log[1] then text = text .. "\n" .. c.log[1] end
    else
        text = c.log[1] or T("Tap a roll (skill, attack, check…) to roll the dice.")
    end
    table.insert(group, FrameContainer:new{
        bordersize = 0,
        padding = Size.padding.default,
        padding_left = self.margin,
        padding_right = self.margin,
        TextBoxWidget:new{
            text = text,
            face = self.f_footer,
            bold = c.log[1] ~= nil,
            width = self.inner_w,
            height = 2 * self.f_footer.size + Screen:scaleBySize(16),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        },
    })
    if page_count > 1 then
        table.insert(group, ButtonTable:new{
            width = self.width,
            zero_sep = true,
            show_parent = self,
            buttons = { {
                { text = "◁", enabled = page > 1, callback = function() self:goPage(-1) end },
                { text = F("page %d of %d", page, page_count), enabled = false, callback = function() end },
                { text = "▷", enabled = page < page_count, callback = function() self:goPage(1) end },
            } },
        })
    end
    return group
end

function Sheet:goPage(delta)
    local new = self.page + delta
    if new >= 1 and new <= (self.page_count or 1) then
        self.page = new
        self:refresh()
    end
end

function Sheet:onSwipe(_, ges)
    local dir = ges.direction
    if dir == "west" then
        self:goPage(1)
        return true
    elseif dir == "east" then
        self:goPage(-1)
        return true
    end
end

function Sheet:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    if self.on_close then self.on_close() end
    return true
end

-- Row building blocks -------------------------------------------------------

function Sheet:separator()
    return LineWidget:new{
        dimen = Geom:new{ w = self.inner_w, h = Size.line.thin },
        background = Blitbuffer.COLOR_LIGHT_GRAY,
    }
end

--- Section header. text is already translated.
function Sheet:header(text)
    local w = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.large },
        TextWidget:new{ text = Utf8Proc.uppercase_dumb(text), face = self.f_header, bold = true, max_width = self.inner_w },
        VerticalSpan:new{ width = Size.padding.small },
        LineWidget:new{ dimen = Geom:new{ w = self.inner_w, h = Size.line.medium }, background = Blitbuffer.COLOR_BLACK },
    }
    w.is_header = true
    return w
end

--- "label ............ value" row. tap/hold are optional.
function Sheet:kv(label, value, tap, hold)
    local dimen = Geom:new{ w = self.inner_w, h = self.row_h }
    local value_w = TextWidget:new{
        text = tostring(value), face = self.f_value, bold = true,
        max_width = math.floor(self.inner_w * 0.5),
    }
    local label_w = TextWidget:new{
        text = label, face = self.f_label,
        max_width = self.inner_w - value_w:getSize().w - Size.padding.large,
    }
    return TapRow:new{
        tap = tap, hold = hold,
        VerticalGroup:new{
            align = "left",
            OverlapGroup:new{
                dimen = dimen,
                LeftContainer:new{ dimen = dimen:copy(), label_w },
                RightContainer:new{ dimen = dimen:copy(), value_w },
            },
            self:separator(),
        },
    }
end

--- Full-width row of framed buttons. Entries: { text, callback, [selected], [enabled] }
function Sheet:buttons(list)
    local row = {}
    for _, b in ipairs(list) do
        table.insert(row, {
            text = b.text,
            callback = b.callback,
            hold_callback = b.hold_callback,
            enabled = b.enabled,
            width = b.width,
            font_size = b.font_size or 18,
            font_bold = b.selected,
            background = b.selected and Blitbuffer.COLOR_LIGHT_GRAY or nil,
        })
    end
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.small },
        FrameContainer:new{
            bordersize = Size.border.thin,
            padding = 0,
            margin = 0,
            radius = Size.radius.button,
            ButtonTable:new{
                width = self.inner_w - 2 * Size.border.thin,
                buttons = { row },
                show_parent = self,
            },
        },
        VerticalSpan:new{ width = Size.padding.small },
    }
end

--- Flat buttons side by side, one row tall, separated by thin lines.
-- (ButtonTable adds its own margins and lines, too tall inside a row.)
function Sheet:inlineButtons(list, total_w)
    local group = HorizontalGroup:new{ align = "center" }
    local sep_w = Size.line.thin
    local each = math.floor((total_w - sep_w * #list) / #list)
    for _, b in ipairs(list) do
        table.insert(group, LineWidget:new{
            dimen = Geom:new{ w = sep_w, h = self.row_h - 2 * Size.padding.small },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        })
        table.insert(group, Button:new{
            text = b.text,
            callback = b.callback,
            hold_callback = b.hold_callback,
            enabled = b.enabled,
            width = each,
            height = self.row_h,
            bordersize = 0,
            margin = 0,
            padding = 0,
            text_font_size = b.font_size or 18,
            text_font_bold = b.bold ~= false,
            show_parent = self,
        })
    end
    return group
end

--- Label and value on the left, buttons on the right, on one row.
function Sheet:labelButtons(label, value, list, tap)
    local buttons_w = math.floor(self.inner_w * (#list >= 3 and 0.5 or 0.36))
    local label_area = self.inner_w - buttons_w
    local dimen = Geom:new{ w = label_area, h = self.row_h }
    local value_w = TextWidget:new{
        text = tostring(value or ""), face = self.f_value, bold = true,
        max_width = math.floor(label_area * 0.45),
    }
    local label_w = TextWidget:new{
        text = label, face = self.f_label,
        max_width = label_area - value_w:getSize().w - 2 * Size.padding.large,
    }
    local left = TapRow:new{
        tap = tap,
        OverlapGroup:new{
            dimen = dimen,
            LeftContainer:new{ dimen = dimen:copy(), label_w },
            RightContainer:new{ dimen = dimen:copy(), HorizontalGroup:new{
                value_w, HorizontalSpan:new{ width = Size.padding.large } } },
        },
    }
    local bt = self:inlineButtons(list, buttons_w)
    return VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{ align = "center", left, bt },
        self:separator(),
    }
end

--- Tappable pips: tapping the n-th sets the value to n
-- (or n-1 if it already was n, so they can be cleared).
function Sheet:pips(label, count, value, on_set, tap_label)
    local list = {}
    for i = 1, count do
        table.insert(list, {
            text = i <= value and PIP_ON or PIP_OFF,
            font_size = 22,
            callback = function()
                on_set(value == i and i - 1 or i)
            end,
        })
    end
    local pip_w = Screen:scaleBySize(44)
    local buttons_w = math.min(math.floor(self.inner_w * 0.62), pip_w * count)
    local label_area = self.inner_w - buttons_w
    local dimen = Geom:new{ w = label_area, h = self.row_h }
    local bt = self:inlineButtons(list, buttons_w)
    return VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "center",
            TapRow:new{
                tap = tap_label,
                LeftContainer:new{ dimen = dimen,
                    TextWidget:new{ text = label, face = self.f_label, max_width = label_area - Size.padding.large } },
            },
            bt,
        },
        self:separator(),
    }
end

--- Free text block with an optional title; tap to edit it.
function Sheet:textBlock(label, text, on_save, max_lines)
    max_lines = max_lines or 6
    local empty = util.trim(text or "") == ""
    local shown = empty and T("(tap to write)") or text
    local box = TextBoxWidget:new{
        text = shown,
        face = self.f_text,
        width = self.inner_w,
        fgcolor = empty and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
    }
    local max_h = box:getLineHeight() * max_lines
    if box:getSize().h > max_h then
        box:free()
        box = TextBoxWidget:new{
            text = shown,
            face = self.f_text,
            width = self.inner_w,
            height = max_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
    end
    local group = VerticalGroup:new{ align = "left" }
    if label then
        table.insert(group, VerticalSpan:new{ width = Size.padding.small })
        table.insert(group, TextWidget:new{ text = label, face = self.f_small, bold = true, max_width = self.inner_w })
    end
    table.insert(group, VerticalSpan:new{ width = Size.padding.small })
    table.insert(group, box)
    table.insert(group, VerticalSpan:new{ width = Size.padding.small })
    table.insert(group, self:separator())
    return TapRow:new{
        tap = function()
            self:editText(label or self.current_header or T("Text"), text, on_save, true)
        end,
        group,
    }
end

--- Small grey description row.
function Sheet:caption(text)
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.small },
        TextBoxWidget:new{
            text = text, face = self.f_small, width = self.inner_w,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        },
        VerticalSpan:new{ width = Size.padding.small },
    }
end

-- Dialogs -------------------------------------------------------------------

function Sheet:editText(title, value, on_save, multiline)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = value or "",
        allow_newline = multiline,
        fullscreen = multiline,
        condensed = multiline,
        buttons = { {
            {
                text = T("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = T("Save"),
                is_enter_default = not multiline,
                callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    on_save(multiline and text or util.trim(text))
                    self:changed()
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Number input; with relative = true, "+5" / "-3" change the current value.
local function parseNumber(text, current, relative)
    text = util.trim(text or ""):gsub(",", ".")
    if text == "" then return nil end
    local sign, digits = text:match("^([%+%-])%s*(%d+)$")
    if relative and sign then
        local n = tonumber(digits)
        return sign == "+" and current + n or current - n
    end
    return tonumber(text)
end

function Sheet:editNumber(title, current, on_save, opts)
    opts = opts or {}
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = tostring(current or ""),
        input_hint = opts.relative and T("e.g. 12, +5 or -3") or nil,
        description = opts.description,
        buttons = { {
            { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            {
                text = T("Save"),
                is_enter_default = true,
                callback = function()
                    local n = parseNumber(dialog:getInputText(), tonumber(current) or 0, opts.relative)
                    if not n then
                        UIManager:show(InfoMessage:new{ text = T("Not a number."), timeout = 2 })
                        return
                    end
                    if opts.min then n = math.max(opts.min, n) end
                    if opts.max then n = math.min(opts.max, n) end
                    if opts.integer ~= false then n = math.floor(n) end
                    UIManager:close(dialog)
                    on_save(n)
                    self:changed()
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Pick one option: list = { { text, value } }
function Sheet:choose(title, list, on_pick)
    local dialog
    local buttons = {}
    for _, item in ipairs(list) do
        table.insert(buttons, { {
            text = item.text,
            callback = function()
                UIManager:close(dialog)
                on_pick(item.value)
                self:changed()
            end,
        } })
    end
    dialog = ButtonDialog:new{ title = title, buttons = buttons }
    UIManager:show(dialog)
end

function Sheet:confirm(text, ok_text, on_ok)
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        cancel_text = T("Cancel"),
        ok_callback = on_ok,
    })
end

-- Rolls ---------------------------------------------------------------------

function Sheet:report(text)
    Data.addLog(self.character, text)
    self:changed()
end

function Sheet:rollD20(label, bonus)
    local mode = self.next_mode
    self.next_mode = nil
    local r = Dice.d20(bonus, mode)
    self:report(label .. ": " .. r.text)
    return r
end

function Sheet:rollExpr(label, expr)
    local r = Dice.roll(expr)
    if not r then
        UIManager:show(InfoMessage:new{ text = F("Invalid expression: %s", tostring(expr)), timeout = 3 })
        return
    end
    self:report(label .. ": " .. r.text)
    return r
end

-- Character menu (top left icon) ---------------------------------------------

function Sheet:showMenu()
    local c = self.character
    local dialog
    dialog = ButtonDialog:new{
        title = c.name,
        buttons = {
            { { text = T("Rename"), callback = function()
                UIManager:close(dialog)
                self:editText(T("Character name"), c.name, function(t)
                    if t ~= "" then c.name = t end
                end)
            end } },
            { { text = T("Duplicate"), callback = function()
                UIManager:close(dialog)
                local copy = Data.duplicate(c)
                UIManager:show(InfoMessage:new{ text = F("Created «%s».", copy.name), timeout = 2 })
            end } },
            { { text = F("Edition: %s (change)", c.edition), callback = function()
                UIManager:close(dialog)
                local other = c.edition == "2024" and "2014" or "2024"
                self:confirm(F("Switch this sheet to the %s edition?", other) .. "\n"
                    .. T("All data is kept; only the fields shown and the long rest rules change."),
                    F("Switch to %s", other), function()
                        c.edition = other
                        self.page = 1
                        self:changed()
                    end)
            end } },
            { { text = T("Clear roll history"), callback = function()
                UIManager:close(dialog)
                c.log = {}
                self:changed()
            end } },
            { { text = T("Delete character"), callback = function()
                UIManager:close(dialog)
                self:confirm(F("Delete «%s»?", c.name) .. "\n" .. T("This cannot be undone."), T("Delete"), function()
                    Data.delete(c.id)
                    self:onClose()
                end)
            end } },
        },
    }
    UIManager:show(dialog)
end

-- Tab contents --------------------------------------------------------------

function Sheet:rowsFor(tab)
    local fn = self["rows_" .. tab]
    return fn and fn(self) or {}
end

--- Header that also remembers its title for untitled text blocks below it.
function Sheet:section(text)
    self.current_header = text
    return self:header(text)
end

function Sheet:hpDialog()
    local c = self.character
    local dialog
    local function apply(kind)
        local n = tonumber(util.trim(dialog:getInputText() or ""))
        if not n or n < 0 then
            UIManager:show(InfoMessage:new{ text = T("Enter a number of points."), timeout = 2 })
            return
        end
        n = math.floor(n)
        UIManager:close(dialog)
        if kind == "damage" then
            Data.damage(c, n)
            Data.addLog(c, F("Damage %d → HP %d/%d", n, c.hp.current, c.hp.max))
        elseif kind == "heal" then
            Data.heal(c, n)
            Data.addLog(c, F("Healing %d → HP %d/%d", n, c.hp.current, c.hp.max))
        else
            c.hp.temp = n
        end
        self:changed()
    end
    local title = F("Hit points %d/%d", c.hp.current, c.hp.max)
    if c.hp.temp > 0 then title = title .. " " .. F("(+%d temp.)", c.hp.temp) end
    dialog = InputDialog:new{
        title = title,
        input = "",
        input_type = "number",
        input_hint = T("how many points?"),
        buttons = {
            {
                { text = T("Damage"), callback = function() apply("damage") end },
                { text = T("Heal"), callback = function() apply("heal") end },
                { text = T("Temp. HP"), callback = function() apply("temp") end },
            },
            {
                { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Sheet:yesNo(v)
    return v and T("Yes") or T("No")
end

function Sheet:rows_game()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end

    add(self:section(T("Hit points")))
    local hp = string.format("%d / %d", c.hp.current, c.hp.max)
    if c.hp.temp > 0 then hp = hp .. "  " .. F("(+%d temp.)", c.hp.temp) end
    add(self:kv(T("Current hit points"), hp, function() self:hpDialog() end))
    add(self:buttons{
        { text = "−5", callback = function() Data.damage(c, 5); self:changed() end },
        { text = "−1", callback = function() Data.damage(c, 1); self:changed() end },
        { text = T("Damage/heal"), callback = function() self:hpDialog() end },
        { text = "+1", callback = function() Data.heal(c, 1); self:changed() end },
        { text = "+5", callback = function() Data.heal(c, 5); self:changed() end },
    })
    add(self:kv(T("Hit point maximum"), c.hp.max, function()
        self:editNumber(T("Hit point maximum"), c.hp.max, function(n)
            c.hp.max = n
            c.hp.current = math.min(c.hp.current, n)
        end, { min = 1 })
    end))
    add(self:kv(T("Temporary hit points"), c.hp.temp, function()
        self:editNumber(T("Temporary hit points"), c.hp.temp, function(n) c.hp.temp = n end, { min = 0 })
    end))

    add(self:section(T("Combat")))
    add(self:kv(T("Armor class"), c.ac, function()
        self:editNumber(T("Armor class"), c.ac, function(n) c.ac = n end, { min = 0 })
    end))
    if self:is2024() then
        add(self:kv(T("Shield"), self:yesNo(c.shield), function()
            c.shield = not c.shield
            self:changed()
        end))
    end
    add(self:kv(T("Initiative  (tap to roll)"), signed(Data.initiative(c)),
        function() self:rollD20(T("Initiative"), Data.initiative(c)) end,
        function()
            self:editNumber(T("Extra initiative bonus (on top of Dexterity)"), c.init_bonus,
                function(n) c.init_bonus = n end)
        end))
    add(self:kv(T("Speed"), c.speed, function()
        self:editText(T("Speed"), c.speed, function(t) c.speed = t end)
    end))
    add(self:kv(T("Passive Wisdom (Perception)"), Data.passivePerception(c)))
    add(self:kv(self:is2024() and T("Heroic inspiration") or T("Inspiration"), self:yesNo(c.inspiration > 0), function()
        c.inspiration = c.inspiration > 0 and 0 or 1
        self:changed()
    end))

    add(self:section(T("Hit dice")))
    for _, pool in ipairs(Data.hitDice(c)) do
        local left = pool.total - pool.spent
        add(self:labelButtons(string.format("d%d", pool.die), string.format("%d / %d", left, pool.total), {
            { text = T("Spend & roll"), enabled = left > 0 and c.hp.current < c.hp.max, callback = function()
                local con = Data.abilityMod(c, "con")
                local roll = Dice.die(pool.die)
                local healed = math.max(0, roll + con)
                Data.setSpentHitDice(c, pool.die, pool.spent + 1)
                Data.heal(c, healed)
                self:report(F("Hit die: d%d [%d] %s %d = %d HP → %d/%d", pool.die, roll,
                    con >= 0 and "+" or "−", math.abs(con), healed, c.hp.current, c.hp.max))
            end },
            { text = "+1", enabled = pool.spent > 0, callback = function()
                Data.setSpentHitDice(c, pool.die, pool.spent - 1); self:changed() end },
        }, function() self:editHitDice() end))
    end

    add(self:section(T("Death saves")))
    add(self:pips(T("Successes"), 3, c.death.success, function(n) c.death.success = n; self:changed() end))
    add(self:pips(T("Failures"), 3, c.death.fail, function(n) c.death.fail = n; self:changed() end))
    add(self:buttons{
        { text = T("Roll death save"), callback = function() self:deathSave() end },
        { text = T("Reset"), callback = function()
            c.death.success, c.death.fail = 0, 0; self:changed() end },
    })

    local any_slots = false
    for lvl = 1, 9 do
        if c.spell.slots[lvl].total > 0 then any_slots = true break end
    end
    if any_slots then
        add(self:section(T("Available spell slots")))
        for lvl = 1, 9 do
            local s = c.spell.slots[lvl]
            if s.total > 0 then
                add(self:pips(F("Level %d", lvl), s.total, s.total - s.used, function(n)
                    s.used = s.total - n
                    self:changed()
                end))
            end
        end
    end

    add(self:section(T("Rest")))
    add(self:buttons{
        { text = T("Long rest"), callback = function()
            self:confirm(self:is2024()
                    and T("Long rest: HP to maximum, spell slots and all hit dice recovered, death saves reset.")
                    or T("Long rest: HP to maximum, spell slots and half your hit dice recovered, death saves reset."),
                T("Rest"), function()
                    Data.longRest(c)
                    self:report(T("Long rest"))
                end)
        end },
    })
    add(self:caption(T("Short rest: spend hit dice above.")))

    add(self:section(T("Session notes")))
    add(self:textBlock(nil, c.session_notes, function(t) c.session_notes = t end, 8))
    return rows
end

function Sheet:editHitDice()
    local c = self.character
    if #c.classes > 0 and not self:hasCustomClass() then
        self:editClasses()
        return
    end
    local list = {}
    for _, d in ipairs(Data.HIT_DICE) do
        table.insert(list, { text = "d" .. d .. (d == c.hd.die and "  ✓" or ""), value = d })
    end
    table.insert(list, { text = T("Total number of hit dice…"), value = "total" })
    self:choose(T("Hit dice"), list, function(v)
        if v == "total" then
            UIManager:nextTick(function()
                self:editNumber(T("Total number of hit dice"), c.hd.total, function(n)
                    c.hd.total = n
                end, { min = 1, max = 40 })
            end)
        else
            c.hd.die = v
        end
    end)
end

function Sheet:deathSave()
    local c = self.character
    local roll = Dice.die(20)
    local outcome
    if roll == 20 then
        c.death.success, c.death.fail = 0, 0
        c.hp.current = math.max(c.hp.current, 1)
        outcome = T("natural 20: back to 1 HP!")
    elseif roll == 1 then
        c.death.fail = math.min(3, c.death.fail + 2)
        outcome = T("natural 1: two failures")
    elseif roll >= 10 then
        c.death.success = math.min(3, c.death.success + 1)
        outcome = T("success")
    else
        c.death.fail = math.min(3, c.death.fail + 1)
        outcome = T("failure")
    end
    if c.death.success >= 3 then outcome = outcome .. " — " .. T("stable")
    elseif c.death.fail >= 3 then outcome = outcome .. " — " .. T("dead") end
    self:report(F("Death save: d20 [%d] %s", roll, outcome))
end

function Sheet:rows_abilities()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    add(self:section(T("General")))
    add(self:levelRow())
    add(self:kv(T("Proficiency bonus") .. (c.prof_override and " " .. T("(manual)") or ""),
        signed(Data.profBonus(c)), function()
            self:choose(T("Proficiency bonus"), {
                { text = T("Automatic from level"), value = "auto" },
                { text = T("Set by hand…"), value = "manual" },
            }, function(v)
                if v == "auto" then
                    c.prof_override = nil
                else
                    UIManager:nextTick(function()
                        self:editNumber(T("Proficiency bonus"), Data.profBonus(c),
                            function(n) c.prof_override = n end, { min = 0, max = 10 })
                    end)
                end
            end)
        end))

    add(self:section(T("Ability scores and saving throws")))
    add(self:caption(T("Tap the name to change the score. ● = proficient in the saving throw.")))
    for _, a in ipairs(Data.ABILITIES) do
        local name = T(a.name)
        local m = Data.abilityMod(c, a.key)
        local save = Data.saveBonus(c, a.key)
        add(self:labelButtons(name, string.format("%d (%s)", c.scores[a.key], signed(m)), {
            { text = F("Check %s", signed(m)), callback = function()
                self:rollD20(F("%s check", name), m) end },
            { text = F("Save %s", signed(save)), callback = function()
                self:rollD20(F("%s save", name), save) end },
            { text = c.saves[a.key] and PIP_ON or PIP_OFF, font_size = 22, callback = function()
                c.saves[a.key] = not c.saves[a.key] or nil
                self:changed()
            end },
        }, function()
            self:editNumber(name, c.scores[a.key], function(n) c.scores[a.key] = n end, { min = 1, max = 30 })
        end))
    end
    return rows
end

function Sheet:rows_skills()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    add(self:section(T("Skills")))
    add(self:caption(T("Tap the name to roll. First pip: proficiency; second: expertise (double bonus).")))
    for _, s in ipairs(Data.sortedSkills()) do
        local level = c.skills[s.key] or 0
        local bonus = Data.skillBonus(c, s)
        local ab = Data.ABILITY_BY_KEY[s.ab]
        add(self:labelButtons(string.format("%s (%s)", T(s.name), T(ab.short)), signed(bonus), {
            { text = level >= 1 and PIP_ON or PIP_OFF, font_size = 22, callback = function()
                c.skills[s.key] = level >= 1 and nil or 1
                self:changed()
            end },
            { text = level >= 2 and "◆" or "◇", font_size = 22, callback = function()
                c.skills[s.key] = level >= 2 and 1 or 2
                self:changed()
            end },
        }, function() self:rollD20(T(s.name), bonus) end))
    end
    add(self:kv(T("Passive Wisdom (Perception)"), Data.passivePerception(c)))
    if self:is2024() then
        add(self:section(T("Languages")))
        add(self:textBlock(nil, c.languages, function(t) c.languages = t end))
    else
        add(self:section(T("Other proficiencies and languages")))
        add(self:textBlock(nil, c.proficiencies, function(t) c.proficiencies = t end))
    end
    return rows
end

function Sheet:editAttack(attack, is_new)
    local c = self.character
    local dc_word = T("DC")
    local dialog
    dialog = MultiInputDialog:new{
        title = is_new and T("New attack") or T("Edit attack"),
        fields = {
            { description = T("Name"), text = attack.name or "", hint = T("Longsword") },
            { description = T("Attack bonus, or DC"), hint = T("5 or DC 13"),
              text = attack.dc and (dc_word .. " " .. attack.dc) or (attack.bonus and tostring(attack.bonus) or "") },
            { description = T("Damage and type"), text = attack.damage or "", hint = T("1d8+3 slashing") },
            { description = T("Notes"), text = attack.notes or "", hint = T("Range 150/600, mastery: Slow") },
        },
        buttons = { {
            { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = T("Save"), callback = function()
                local f = dialog:getFields()
                UIManager:close(dialog)
                attack.name = util.trim(f[1]) ~= "" and util.trim(f[1]) or T("Attack")
                -- "DC 13" (or the translated word) means a saving throw instead of an attack roll
                local raw = util.trim(f[2]):upper()
                local dc = raw:match("^DC%s*(%d+)$") or raw:match("^" .. dc_word:upper() .. "%s*(%d+)$")
                if dc then
                    attack.dc, attack.bonus = tonumber(dc), nil
                else
                    attack.dc = nil
                    attack.bonus = tonumber((util.trim(f[2]):gsub("^%+", ""))) or 0
                end
                attack.damage = util.trim(f[3])
                attack.notes = util.trim(f[4] or "")
                if is_new then table.insert(c.attacks, attack) end
                self:changed()
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Sheet:attackMenu(index)
    local c = self.character
    local attack = c.attacks[index]
    local dialog
    local function move(delta)
        local j = index + delta
        if j >= 1 and j <= #c.attacks then
            c.attacks[index], c.attacks[j] = c.attacks[j], c.attacks[index]
            self:changed()
        end
    end
    dialog = ButtonDialog:new{
        title = attack.name,
        buttons = {
            { { text = T("Edit"), callback = function()
                UIManager:close(dialog); self:editAttack(attack, false) end } },
            { { text = T("Attack roll only"), enabled = attack.dc == nil, callback = function()
                UIManager:close(dialog); self:rollD20(F("%s (to hit)", attack.name), attack.bonus or 0) end },
              { text = T("Damage only"), callback = function()
                UIManager:close(dialog); self:rollExpr(F("%s (damage)", attack.name), attack.damage) end } },
            { { text = T("Up"), enabled = index > 1, callback = function() UIManager:close(dialog); move(-1) end },
              { text = T("Down"), enabled = index < #c.attacks, callback = function() UIManager:close(dialog); move(1) end } },
            { { text = T("Delete"), callback = function()
                UIManager:close(dialog)
                self:confirm(F("Delete the attack «%s»?", attack.name), T("Delete"), function()
                    table.remove(c.attacks, index)
                    self:changed()
                end)
            end } },
        },
    }
    UIManager:show(dialog)
end

function Sheet:rollAttack(attack)
    if attack.dc then
        -- with a DC the target rolls: here we only roll damage
        local dmg = Dice.parse(attack.damage) and Dice.roll(attack.damage)
        self:report(attack.name .. ": " .. T("DC") .. " " .. attack.dc
            .. (dmg and (" · " .. T("damage") .. " " .. dmg.text) or ""))
        return
    end
    local mode = self.next_mode
    self.next_mode = nil
    local hit = Dice.d20(attack.bonus or 0, mode)
    local text = attack.name .. ": " .. T("to hit") .. " " .. hit.text
    local dmg = Dice.parse(attack.damage) and Dice.roll(attack.damage)
    if dmg then
        if hit.nat == 20 then
            -- critical hit: roll the damage dice again (not the modifiers)
            local extra = 0
            for _, t in ipairs(Dice.parse(attack.damage)) do
                if t.sides then
                    for _ = 1, t.count do extra = extra + Dice.die(t.sides) end
                end
            end
            text = text .. " · " .. T("damage") .. " " .. dmg.text .. " + " .. T("critical") .. " "
                .. extra .. " = " .. (dmg.total + extra)
        else
            text = text .. " · " .. T("damage") .. " " .. dmg.text
        end
    end
    self:report(text)
end

function Sheet:rows_attacks()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    add(self:section(self:is2024() and T("Weapons and damage cantrips") or T("Attacks")))
    if #c.attacks == 0 then
        add(self:caption(T("No attacks yet. Add one: name, attack bonus and damage (e.g. 1d8+3 slashing).")))
    else
        add(self:caption(T("Tap to roll to hit and damage together; hold to edit.")))
    end
    for i, attack in ipairs(c.attacks) do
        local value = attack.dc and (T("DC") .. " " .. attack.dc) or signed(attack.bonus or 0)
        if attack.damage and attack.damage ~= "" then value = value .. "  " .. attack.damage end
        add(self:kv(attack.name, value,
            function() self:rollAttack(attack) end,
            function() self:attackMenu(i) end))
    end
    add(self:buttons{
        { text = T("+ Add attack"), callback = function() self:editAttack({}, true) end },
    })
    local with_notes = {}
    for _, attack in ipairs(c.attacks) do
        if attack.notes and attack.notes ~= "" then
            table.insert(with_notes, attack.name .. ": " .. attack.notes)
        end
    end
    if #with_notes > 0 then
        add(self:caption(table.concat(with_notes, "\n")))
    end
    if not self:is2024() then
        add(self:section(T("Attacks and spellcasting (notes)")))
        add(self:textBlock(nil, c.attacks_notes, function(t) c.attacks_notes = t end))
    end
    return rows
end

function Sheet:editSpell(spell, is_new)
    local c = self.character
    local dialog
    dialog = MultiInputDialog:new{
        title = is_new and T("New spell") or T("Edit spell"),
        fields = {
            { description = T("Name"), text = spell.name or "", hint = T("Magic Missile") },
            { description = T("Level (0 = cantrip)"), text = tostring(spell.level or 0), input_type = "number" },
            { description = T("Casting time"), text = spell.time or "", hint = T("Action") },
            { description = T("Range"), text = spell.range or "", hint = T("120 feet") },
            { description = T("Notes"), text = spell.notes or "", hint = "" },
        },
        buttons = { {
            { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = T("Save"), callback = function()
                local f = dialog:getFields()
                local name = util.trim(f[1])
                if name == "" then return end
                UIManager:close(dialog)
                spell.name = name
                spell.level = math.max(0, math.min(9, math.floor(tonumber(f[2]) or 0)))
                spell.time = util.trim(f[3] or "")
                spell.range = util.trim(f[4] or "")
                spell.notes = util.trim(f[5] or "")
                if is_new then table.insert(c.spell.list, spell) end
                self:changed()
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Sheet:spellMenu(spell)
    local c = self.character
    local dialog
    local function flag(key, label)
        return { text = label .. (spell[key] and "  ✓" or ""), callback = function()
            UIManager:close(dialog)
            spell[key] = not spell[key] or nil
            self:changed()
        end }
    end
    local details = {}
    if spell.time and spell.time ~= "" then table.insert(details, F("Casting time: %s", spell.time)) end
    if spell.range and spell.range ~= "" then table.insert(details, F("Range: %s", spell.range)) end
    if spell.notes and spell.notes ~= "" then table.insert(details, spell.notes) end
    local srd = Spells.get(c.edition, spell.srd)
    local buttons = {
        { flag("conc", T("Concentration")), flag("ritual", T("Ritual")), flag("material", T("Material")) },
    }
    if srd then
        table.insert(buttons, { { text = T("Description"), callback = function()
            UIManager:close(dialog); self:showSpellText(srd) end } })
    end
    table.insert(buttons, { { text = T("Edit"), callback = function()
        UIManager:close(dialog); self:editSpell(spell, false) end } })
    table.insert(buttons, { { text = T("Delete"), callback = function()
        UIManager:close(dialog)
        for i, s in ipairs(c.spell.list) do
            if s == spell then table.remove(c.spell.list, i) break end
        end
        self:changed()
    end } })
    dialog = ButtonDialog:new{
        title = spell.name .. (#details > 0 and ("\n" .. table.concat(details, "\n")) or ""),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- Classes and levels ----------------------------------------------------------

function Sheet:classNames()
    local names = {}
    for _, e in ipairs(self.character.classes) do table.insert(names, Classes.entryName(e)) end
    return table.concat(names, " / ")
end

function Sheet:hasCustomClass()
    for _, e in ipairs(self.character.classes) do
        if not e.key then return true end
    end
    return false
end

--- Level row: the total of the classes, or a number typed by hand.
function Sheet:levelRow()
    local c = self.character
    if #c.classes > 0 then
        return self:kv(T("Level"), c.level, function() self:editClasses() end)
    end
    return self:kv(T("Level"), c.level, function()
        self:editNumber(T("Level"), c.level, function(n) c.level = n end, { min = 1, max = 20 })
    end)
end

--- Apply a change to the class list, then show the list again.
function Sheet:changeClasses(fn)
    local c = self.character
    local first_before = c.classes[1] and c.classes[1].key
    fn(c.classes)
    Data.classesChanged(c, first_before)
    self:changed()
    UIManager:nextTick(function() self:editClasses() end)
end

function Sheet:editClasses()
    local c = self.character
    local dialog
    local buttons = {}
    for i, e in ipairs(c.classes) do
        local sub = Classes.entrySubclass(e, c.edition)
        table.insert(buttons, { {
            text = Classes.entryName(e) .. " " .. (e.level or 1) .. (sub and ("  ·  " .. sub) or ""),
            callback = function()
                UIManager:close(dialog)
                self:classMenu(i)
            end,
        } })
    end
    table.insert(buttons, { {
        text = #c.classes == 0 and T("+ Choose the class") or T("+ Add a class (multiclass)"),
        callback = function()
            UIManager:close(dialog)
            self:chooseClass(nil)
        end,
    } })
    local title = T("Classes and levels")
    if #c.classes > 0 then
        title = title .. "\n" .. F("Total level: %d", c.level)
    else
        title = title .. "\n" .. T("Choosing a class fills in hit dice, saving throws and spellcasting.")
    end
    if #c.classes > 1 then
        title = title .. "\n" .. T("Saving throw proficiencies come from the first class.")
    end
    dialog = ButtonDialog:new{ title = title, buttons = buttons }
    UIManager:show(dialog)
end

function Sheet:classMenu(i)
    local c = self.character
    local e = c.classes[i]
    local dialog
    local sub = Classes.entrySubclass(e, c.edition)
    local buttons = {
        { { text = F("Class: %s", Classes.entryName(e)), callback = function()
            UIManager:close(dialog); self:chooseClass(i) end } },
        { { text = F("Subclass: %s", sub or "—"), callback = function()
            UIManager:close(dialog); self:chooseSubclass(i) end } },
        { { text = F("Level: %d", e.level or 1), callback = function()
            UIManager:close(dialog)
            self:editNumber(F("%s: level", Classes.entryName(e)), e.level or 1, function(n)
                self:changeClasses(function() e.level = n end)
            end, { min = 1, max = 20 })
        end } },
        { { text = T("Remove this class"), callback = function()
            UIManager:close(dialog)
            self:confirm(F("Remove «%s» from the classes?", Classes.entryName(e)), T("Remove"), function()
                self:changeClasses(function(list) table.remove(list, i) end)
            end)
        end } },
        { { text = T("Back"), callback = function()
            UIManager:close(dialog); self:editClasses() end } },
    }
    dialog = ButtonDialog:new{ title = Classes.entryName(e) .. " " .. (e.level or 1), buttons = buttons }
    UIManager:show(dialog)
end

--- Pick a class for entry i, or for a new entry if i is nil.
function Sheet:chooseClass(i)
    local c = self.character
    local current = i and c.classes[i]
    local dialog
    local function set(key, name)
        self:changeClasses(function(list)
            if current then
                if current.key ~= key or key == nil then current.sub, current.sub_name = nil, nil end
                current.key, current.name = key, name
            else
                -- the first class takes the level already on the sheet
                table.insert(list, { key = key, name = name, level = #list == 0 and (c.level or 1) or 1 })
            end
        end)
    end
    local buttons, row = {}, {}
    for _, cl in ipairs(sortedByName(Classes.LIST)) do
        table.insert(row, {
            text = T(cl.name) .. (current and current.key == cl.key and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                set(cl.key, nil)
            end,
        })
        if #row == 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    table.insert(buttons, { {
        text = T("Other…"),
        callback = function()
            UIManager:close(dialog)
            self:editText(T("Class"), current and current.name or "", function(t)
                if t == "" then return end
                local key = Classes.fromText(t)
                set(key, not key and t or nil)
            end)
        end,
    } })
    dialog = ButtonDialog:new{ title = T("Class"), buttons = buttons }
    UIManager:show(dialog)
end

function Sheet:chooseSubclass(i)
    local c = self.character
    local e = c.classes[i]
    local function typed()
        self:editText(T("Subclass"), e.sub_name or "", function(t)
            self:changeClasses(function()
                local key = e.key and Classes.subclassFromText(e.key, t, c.edition)
                e.sub, e.sub_name = key, (not key and t ~= "") and t or nil
            end)
        end)
    end
    local list = Classes.subclasses(e.key, c.edition)
    if #list == 0 then
        typed()
        return
    end
    local dialog
    local buttons = {}
    for _, s in ipairs(list) do
        table.insert(buttons, { {
            text = T(s.name) .. (e.sub == s.key and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                self:changeClasses(function() e.sub, e.sub_name = s.key, nil end)
            end,
        } })
    end
    table.insert(buttons, { {
        text = T("Other…"),
        callback = function() UIManager:close(dialog); typed() end,
    }, {
        text = T("None"),
        callback = function()
            UIManager:close(dialog)
            self:changeClasses(function() e.sub, e.sub_name = nil, nil end)
        end,
    } })
    dialog = ButtonDialog:new{
        title = F("%s: subclass", Classes.entryName(e)),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- Alignment -------------------------------------------------------------------

function Sheet:chooseAlignment()
    local c = self.character
    local dialog
    local function set(key, text)
        c.alignment_key = key
        c.alignment = key and T(key) or text
        self:changed()
    end
    local buttons = {}
    for first = 1, 9, 3 do
        local row = {}
        for i = first, first + 2 do
            local name = Data.ALIGNMENTS[i]
            table.insert(row, {
                text = T(name) .. (c.alignment_key == name and "  ✓" or ""),
                callback = function() UIManager:close(dialog); set(name) end,
            })
        end
        table.insert(buttons, row)
    end
    table.insert(buttons, { {
        text = T("Other…"),
        callback = function()
            UIManager:close(dialog)
            self:editText(T("Alignment"), c.alignment, function(t)
                set(Data.alignmentFromText(t), t)
            end)
        end,
    }, {
        text = T("None"),
        callback = function() UIManager:close(dialog); set(nil, "") end,
    } })
    dialog = ButtonDialog:new{ title = T("Alignment"), buttons = buttons }
    UIManager:show(dialog)
end

-- Species ---------------------------------------------------------------------

function Sheet:chooseSpecies()
    local c = self.character
    local label = self:is2024() and T("Species") or T("Race")
    local dialog
    local function set(key, sub, text)
        c.species = { key = key, sub = sub }
        if not key then c.race = text end
        Data.speciesChanged(c)
        self:changed()
    end
    local buttons, row = {}, {}
    for _, sp in ipairs(sortedByName(Species.list(c.edition))) do
        table.insert(row, {
            text = T(sp.name) .. (c.species.key == sp.key and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                if sp.subs then
                    self:chooseSpeciesSub(sp, set)
                else
                    set(sp.key, nil)
                end
            end,
        })
        if #row == 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, { {
        text = T("Other…"),
        callback = function()
            UIManager:close(dialog)
            self:editText(label, Species.line(c), function(t)
                local key, sub = Species.fromText(t, c.edition)
                set(key, sub, t)
            end)
        end,
    } })
    dialog = ButtonDialog:new{
        title = label .. "\n" .. T("Speed and size are filled in; you can change them."),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function Sheet:chooseSpeciesSub(sp, set)
    local c = self.character
    local dialog
    local buttons = {}
    for _, sub in ipairs(sp.subs) do
        table.insert(buttons, { {
            text = ucfirst(T(sub.name)) .. (c.species.key == sp.key and c.species.sub == sub.key and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                set(sp.key, sub.key)
            end,
        } })
    end
    table.insert(buttons, { {
        text = T("Choose later"),
        callback = function()
            UIManager:close(dialog)
            set(sp.key, nil)
        end,
    } })
    dialog = ButtonDialog:new{ title = T(sp.name), buttons = buttons }
    UIManager:show(dialog)
end

-- Spells from the SRD lists ---------------------------------------------------

--- Class used to filter the spell lists: the one chosen in the Spells tab,
-- else a class recognized in its free text or in the character's class.
function Sheet:spellClassKey()
    local c = self.character
    if c.spell.class_key then return c.spell.class_key end
    for _, e in ipairs(c.classes) do
        local list = Classes.entrySpellcasting(e, c.edition)
        if list then return list end
    end
    return Spells.classFromText(c.spell.class) or Spells.classFromText(c.class)
end

function Sheet:chooseSpellClass()
    local sp = self.character.spell
    local dialog
    local buttons, row = {}, {}
    for _, cl in ipairs(sortedByName(Spells.CLASSES)) do
        table.insert(row, {
            text = T(cl.name) .. (sp.class_key == cl.key and "  ✓" or ""),
            callback = function()
                UIManager:close(dialog)
                sp.class_key = cl.key
                sp.class = T(cl.name)
                sp.ability = cl.ability
                self:changed()
            end,
        })
        if #row == 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    table.insert(buttons, { {
        text = T("Other…"),
        callback = function()
            UIManager:close(dialog)
            self:editText(T("Spellcasting class"), sp.class, function(t)
                sp.class = t
                sp.class_key = Spells.classFromText(t)
            end)
        end,
    } })
    dialog = ButtonDialog:new{
        title = T("Spellcasting class") .. "\n" .. T("The spellcasting ability is set too; you can change it."),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function Sheet:hasSpell(s)
    for _, spell in ipairs(self.character.spell.list) do
        if spell.srd == s.id or spell.name:lower() == s.name:lower() then return true end
    end
    return false
end

function Sheet:addSrdSpell(s)
    table.insert(self.character.spell.list, {
        name = s.name,
        level = s.level,
        time = s.time,
        range = s.range,
        notes = "",
        conc = s.conc or nil,
        ritual = s.ritual or nil,
        material = (s.comp or ""):find("M") and true or nil,
        srd = s.id,
    })
    self:changed()
end

--- Description of a spell; with on_add, a button adds it to the sheet.
function Sheet:showSpellText(s, on_add)
    local viewer
    local buttons = { {
        { text = T("Close"), callback = function() UIManager:close(viewer) end },
    } }
    if on_add then
        local known = self:hasSpell(s)
        table.insert(buttons[1], {
            text = known and T("On the sheet ✓") or T("Add to the sheet"),
            enabled = not known,
            callback = function()
                UIManager:close(viewer)
                on_add()
            end,
        })
    end
    viewer = TextViewer:new{
        title = s.name,
        text = Spells.html(s),
        text_format = "html",
        buttons_table = buttons,
    }
    UIManager:show(viewer)
end

--- Choose a level, then a spell from the list of the character's class.
function Sheet:pickSpellLevel(all_classes)
    local c = self.character
    local class = self:spellClassKey()
    local filter = (not all_classes) and class or nil
    if not Spells.load(c.edition) then
        UIManager:show(InfoMessage:new{ text = T("The spell list could not be read."), timeout = 3 })
        return
    end
    local counts = Spells.counts(c.edition, filter)
    local dialog
    local function level_button(lvl)
        local label = lvl == 0 and T("Cantrips") or F("Level %d", lvl)
        return {
            text = label .. "  (" .. counts[lvl] .. ")",
            enabled = counts[lvl] > 0,
            callback = function()
                UIManager:close(dialog)
                self:showSpellList(lvl, filter)
            end,
        }
    end
    local buttons = { { level_button(0) } }
    for first = 1, 9, 3 do
        table.insert(buttons, { level_button(first), level_button(first + 1), level_button(first + 2) })
    end
    local title
    if filter then
        title = F("Spells: %s", Spells.className(filter))
        table.insert(buttons, { { text = T("Show all classes"), callback = function()
            UIManager:close(dialog); self:pickSpellLevel(true) end } })
    else
        title = T("Spells: all classes")
        if class then
            table.insert(buttons, { { text = F("Only %s", Spells.className(class)), callback = function()
                UIManager:close(dialog); self:pickSpellLevel(false) end } })
        end
    end
    if not class then
        title = title .. "\n" .. T("Choose the spellcasting class to see only its spells.")
    end
    title = title .. "\n\n" .. Spells.source(c.edition)
    dialog = ButtonDialog:new{ title = title, buttons = buttons }
    UIManager:show(dialog)
end

function Sheet:showSpellList(level, class)
    local c = self.character
    local menu
    local function items()
        local list = {}
        for _, s in ipairs(Spells.list(c.edition, level, class)) do
            local tags = {}
            if s.conc then table.insert(tags, T("C")) end
            if s.ritual then table.insert(tags, T("R")) end
            if self:hasSpell(s) then table.insert(tags, "✓") end
            table.insert(list, {
                text = s.name,
                mandatory = table.concat(tags, " "),
                callback = function()
                    self:showSpellText(s, function()
                        self:addSrdSpell(s)
                        menu:switchItemTable(nil, items(), -1)
                        UIManager:show(InfoMessage:new{ text = F("Added «%s».", s.name), timeout = 1 })
                    end)
                end,
            })
        end
        return list
    end
    menu = Menu:new{
        title = level == 0 and T("Cantrips") or F("Level %d spells", level),
        subtitle = (class and Spells.className(class) or T("All classes")) .. " · " .. T("✓ = on the sheet"),
        item_table = items(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        single_line = true,
    }
    UIManager:show(menu)
end

function Sheet:rows_spells()
    local c = self.character
    local sp = c.spell
    local rows = {}
    local function add(w) table.insert(rows, w) end
    local ab = Data.ABILITY_BY_KEY[sp.ability] or Data.ABILITY_BY_KEY.int

    add(self:section(T("Spellcasting")))
    local class_label = sp.class_key and Spells.className(sp.class_key) or (sp.class ~= "" and sp.class) or "—"
    add(self:kv(T("Spellcasting class"), class_label, function() self:chooseSpellClass() end))
    add(self:kv(T("Spellcasting ability"), T(ab.name), function()
        local list = {}
        for _, a in ipairs(Data.ABILITIES) do
            table.insert(list, { text = T(a.name) .. (a.key == sp.ability and "  ✓" or ""), value = a.key })
        end
        self:choose(T("Spellcasting ability"), list, function(v) sp.ability = v end)
    end))
    add(self:kv(T("Spell save DC"), Data.spellDC(c)))
    add(self:kv(T("Spell attack bonus  (tap to roll)"), signed(Data.spellAttack(c)),
        function() self:rollD20(T("Spell attack"), Data.spellAttack(c)) end))

    add(self:section(T("Total slots")))
    add(self:caption(T("Tap a level to set its number of slots. Spend them from the Play tab.")))
    local top = 0
    for lvl = 1, 9 do
        if sp.slots[lvl].total > 0 then top = lvl end
    end
    for lvl = 1, math.min(9, top + 1) do
        local s = sp.slots[lvl]
        local value = s.total == 0 and "—" or F("%d of %d available", s.total - s.used, s.total)
        add(self:kv(F("Level %d", lvl), value, function()
            self:editNumber(F("Level %d slots", lvl), s.total, function(n)
                s.total = n
                s.used = math.min(s.used, n)
            end, { min = 0, max = 9 })
        end))
    end

    local by_level = {}
    for _, spell in ipairs(sp.list) do
        by_level[spell.level] = by_level[spell.level] or {}
        table.insert(by_level[spell.level], spell)
    end
    for lvl = 0, 9 do
        local list = by_level[lvl]
        if list then
            table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
            add(self:section(lvl == 0 and T("Cantrips") or F("Level %d spells", lvl)))
            for _, spell in ipairs(list) do
                local tags = {}
                if spell.conc then table.insert(tags, T("C")) end
                if spell.ritual then table.insert(tags, T("R")) end
                if spell.material then table.insert(tags, T("M")) end
                local tag = table.concat(tags, " ")
                if lvl == 0 then
                    add(self:kv(spell.name, tag, function() self:spellMenu(spell) end,
                        function() self:spellMenu(spell) end))
                else
                    add(self:labelButtons(spell.name, tag, {
                        { text = spell.prepared and PIP_ON or PIP_OFF, font_size = 22, callback = function()
                            spell.prepared = not spell.prepared or nil
                            self:changed()
                        end },
                    }, function() self:spellMenu(spell) end))
                end
            end
        end
    end
    if #sp.list == 0 then
        add(self:section(T("Spells")))
        add(self:caption(T("No spells yet. ● next to the name = prepared.")))
    else
        add(self:caption(T("Tap a spell for its details and to mark C (concentration), R (ritual), M (material). ● = prepared.")))
    end
    add(self:buttons{
        { text = T("+ From the list"), callback = function() self:pickSpellLevel(false) end },
        { text = T("+ Write one"), callback = function() self:editSpell({ level = 0 }, true) end },
    })
    return rows
end

function Sheet:rows_equipment()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    add(self:section(T("Coins")))
    add(self:caption(T("Tap a coin to type a value, also as +10 or -5.")))
    for _, coin in ipairs(Data.COINS) do
        local key = coin.key
        add(self:labelButtons(T(coin.short) .. "  " .. T(coin.name), c.coins[key], {
            { text = "−1", enabled = c.coins[key] > 0, callback = function()
                c.coins[key] = c.coins[key] - 1; self:changed() end },
            { text = "+1", callback = function()
                c.coins[key] = c.coins[key] + 1; self:changed() end },
        }, function()
            self:editNumber(F("Coins: %s", T(coin.name)), c.coins[key], function(n) c.coins[key] = n end,
                { relative = true, min = 0 })
        end))
    end
    add(self:section(T("Equipment")))
    add(self:textBlock(nil, c.equipment, function(t) c.equipment = t end, 12))
    if self:is2024() then
        add(self:section(T("Magic item attunement")))
        add(self:textBlock(nil, c.attunement, function(t) c.attunement = t end, 3))
        add(self:section(T("Equipment training and proficiencies")))
        local list = {}
        for _, a in ipairs(Data.ARMOR_TRAINING) do
            local on = c.armor_training[a.key]
            table.insert(list, { text = (on and PIP_ON or PIP_OFF) .. " " .. I18n.C("armor", a.name), bold = false,
                font_size = 17, callback = function()
                    c.armor_training[a.key] = not on or nil
                    self:changed()
                end })
        end
        add(self:caption(T("Armor")))
        add(VerticalGroup:new{ align = "left", self:inlineButtons(list, self.inner_w), self:separator() })
        add(self:textBlock(T("Weapons"), c.weapons_training, function(t) c.weapons_training = t end, 3))
        add(self:textBlock(T("Tools"), c.tools_training, function(t) c.tools_training = t end, 3))
    else
        add(self:section(T("Treasure")))
        add(self:textBlock(nil, c.treasure, function(t) c.treasure = t end))
    end
    return rows
end

function Sheet:rows_traits()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    if self:is2024() then
        add(self:section(T("Class features")))
        add(self:textBlock(nil, c.features, function(t) c.features = t end, 12))
        add(self:section(T("Species traits")))
        add(self:textBlock(nil, c.species_traits, function(t) c.species_traits = t end, 8))
        add(self:section(T("Feats")))
        add(self:textBlock(nil, c.feats, function(t) c.feats = t end, 8))
        return rows
    end
    add(self:section(T("Personality")))
    add(self:textBlock(T("Personality traits"), c.traits, function(t) c.traits = t end, 4))
    add(self:textBlock(T("Ideals"), c.ideals, function(t) c.ideals = t end, 4))
    add(self:textBlock(T("Bonds"), c.bonds, function(t) c.bonds = t end, 4))
    add(self:textBlock(T("Flaws"), c.flaws, function(t) c.flaws = t end, 4))
    add(self:section(T("Features and traits")))
    add(self:textBlock(nil, c.features, function(t) c.features = t end, 12))
    add(self:section(T("Additional features and traits")))
    add(self:textBlock(nil, c.extra_features, function(t) c.extra_features = t end, 8))
    return rows
end

function Sheet:rows_bio()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    local function textField(label, key)
        add(self:kv(label, c[key] ~= "" and c[key] or "—", function()
            self:editText(label, c[key], function(t) c[key] = t end)
        end))
    end
    local function level()
        add(self:levelRow())
    end
    local function speciesField(label)
        local value = Species.line(c)
        add(self:kv(label, value ~= "" and value or "—", function() self:chooseSpecies() end))
    end
    local function alignmentField()
        local a = c.alignment_key and T(c.alignment_key) or c.alignment
        add(self:kv(T("Alignment"), a ~= "" and a or "—", function() self:chooseAlignment() end))
    end
    local function classField(label, value)
        add(self:kv(label, value ~= "" and value or "—", function() self:editClasses() end))
    end
    local function xp()
        add(self:kv(T("Experience points"), c.xp, function()
            self:editNumber(T("Experience points"), c.xp, function(n) c.xp = n end, { relative = true, min = 0 })
        end))
    end
    if self:is2024() then
        add(self:section(T("Character")))
        textField(T("Character name"), "name")
        classField(T("Class"), #c.classes > 0 and self:classNames() or c.class)
        classField(T("Subclass"), #c.classes > 0 and Data.subclassLine(c) or c.subclass)
        level()
        speciesField(T("Species"))
        textField(T("Background"), "background")
        textField(T("Size"), "size")
        alignmentField()
        xp()
        add(self:section(T("Appearance")))
        add(self:textBlock(nil, c.appearance, function(t) c.appearance = t end, 5))
        add(self:section(T("Backstory and personality")))
        add(self:textBlock(nil, c.backstory, function(t) c.backstory = t end, 14))
        return rows
    end
    add(self:section(T("Character")))
    textField(T("Character name"), "name")
    textField(T("Player name"), "player")
    classField(T("Class"), #c.classes > 0 and Data.classLine(c) or c.class)
    level()
    speciesField(T("Race"))
    textField(T("Background"), "background")
    alignmentField()
    xp()
    add(self:section(T("Appearance")))
    textField(T("Age"), "age")
    textField(T("Height"), "height")
    textField(T("Weight"), "weight")
    textField(T("Eyes"), "eyes")
    textField(T("Skin"), "skin")
    textField(T("Hair"), "hair")
    add(self:textBlock(T("Character appearance"), c.appearance, function(t) c.appearance = t end, 5))
    add(self:section(T("Character backstory")))
    add(self:textBlock(nil, c.backstory, function(t) c.backstory = t end, 14))
    add(self:section(T("Allies and organizations")))
    textField(T("Organization name"), "faction")
    add(self:textBlock(nil, c.allies, function(t) c.allies = t end, 8))
    return rows
end

function Sheet:rows_dice()
    local c = self.character
    local rows = {}
    local function add(w) table.insert(rows, w) end
    add(self:section(T("Next d20 roll")))
    add(self:buttons{
        { text = T("Normal"), selected = self.next_mode == nil, callback = function()
            self.next_mode = nil; self:refresh() end },
        { text = T("Advantage"), selected = self.next_mode == "adv", callback = function()
            self.next_mode = "adv"; self:refresh() end },
        { text = T("Disadvantage"), selected = self.next_mode == "dis", callback = function()
            self.next_mode = "dis"; self:refresh() end },
    })
    add(self:caption(T("Applies to the next d20 roll from any tab, then goes back to normal.")))
    add(self:section(T("Roll")))
    local function die(n)
        return { text = "d" .. n, callback = function()
            if n == 20 then
                self:rollD20("d20", 0)
            else
                self:rollExpr("d" .. n, "1d" .. n)
            end
        end }
    end
    add(self:buttons{ die(4), die(6), die(8), die(10) })
    add(self:buttons{ die(12), die(20), die(100), { text = T("Other…"), callback = function()
        local dialog
        dialog = InputDialog:new{
            title = T("Roll dice"),
            input = self.last_expr or "",
            input_hint = T("e.g. 2d6+3, 4d6, 1d8+1d6"),
            buttons = { {
                { text = T("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = T("Roll"), is_enter_default = true, callback = function()
                    local expr = util.trim(dialog:getInputText())
                    if not Dice.parse(expr) then
                        UIManager:show(InfoMessage:new{ text = T("Invalid expression."), timeout = 2 })
                        return
                    end
                    UIManager:close(dialog)
                    self.last_expr = expr
                    self:rollExpr(expr, expr)
                end },
            } },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end } })
    add(self:section(T("Latest rolls")))
    if #c.log == 0 then
        add(self:caption(T("No rolls yet.")))
    end
    for _, entry in ipairs(c.log) do
        add(VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Size.padding.small },
            TextBoxWidget:new{ text = entry, face = self.f_text, width = self.inner_w },
            VerticalSpan:new{ width = Size.padding.small },
            self:separator(),
        })
    end
    return rows
end

return Sheet

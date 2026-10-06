--[[--
Translations for the plugin.

Source strings are English. Each other language lives in l10n/<code>.lua and
returns a table { ["English text"] = "translation" }; missing entries fall
back to English. The language follows KOReader's UI language unless the user
picks one from the character list (setting "dnd5e_language").

To add a language: copy l10n/it.lua to l10n/<code>.lua (two-letter code,
e.g. "fr"), translate the values and add its name to NAMES below.
--]]

local lfs = require("libs/libkoreader-lfs")

local I18n = {}

-- Display names of the languages, in their own language
I18n.NAMES = {
    en = "English",
    it = "Italiano",
}

local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./")
local l10n_dir = plugin_dir .. "l10n/"

local current_code, current_table

local function loadTable(code)
    if code == "en" then return {} end
    local ok, t = pcall(dofile, l10n_dir .. code .. ".lua")
    if ok and type(t) == "table" then return t end
    return nil
end

--- Codes of the available languages ("en" plus every l10n/*.lua file).
function I18n.available()
    local codes = { "en" }
    if lfs.attributes(l10n_dir, "mode") == "directory" then
        for file in lfs.dir(l10n_dir) do
            local code = file:match("^(%a%a)%.lua$")
            if code then table.insert(codes, code) end
        end
    end
    table.sort(codes)
    return codes
end

function I18n.name(code)
    return I18n.NAMES[code] or code
end

--- Language chosen in the plugin: "auto" or a code.
function I18n.setting()
    return G_reader_settings:readSetting("dnd5e_language") or "auto"
end

--- The language KOReader itself is using, reduced to two letters.
function I18n.uiLanguage()
    local lang = G_reader_settings:readSetting("language") or os.getenv("LANGUAGE") or os.getenv("LANG") or "en"
    return (lang:match("^(%a%a)") or "en"):lower()
end

function I18n.code()
    if not current_code then
        local wanted = I18n.setting()
        if wanted == "auto" then wanted = I18n.uiLanguage() end
        current_table = loadTable(wanted)
        if current_table then
            current_code = wanted
        else
            current_code, current_table = "en", {}
        end
    end
    return current_code
end

function I18n.set(code)
    if code == "auto" then
        G_reader_settings:delSetting("dnd5e_language")
    else
        G_reader_settings:saveSetting("dnd5e_language", code)
    end
    current_code, current_table = nil, nil
end

--- Translate a source string.
function I18n.T(text)
    I18n.code()
    return current_table[text] or text
end

--- Translate a string that needs a context to be told apart, e.g.
-- C("size", "Medium") vs C("armor", "Medium"). The key in the language
-- table is "context|text"; without it, the plain translation of text is
-- used, and English shows the bare text.
function I18n.C(context, text)
    I18n.code()
    return current_table[context .. "|" .. text] or current_table[text] or text
end

--- Translate a format string and fill it in.
function I18n.F(text, ...)
    return string.format(I18n.T(text), ...)
end

return I18n

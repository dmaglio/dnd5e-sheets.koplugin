-- Lists the strings missing from (or unused in) a translation.
-- Usage, from the plugin folder: luajit tools/check_l10n.lua it
local code = arg[1] or error("usage: luajit tools/check_l10n.lua <language code>")

-- Strings that are never translated (symbols, numbers, dice)
local IGNORE = { ["◁"] = true, ["▷"] = true, ["−5"] = true, ["−1"] = true,
                 ["+1"] = true, ["+5"] = true, ["d"] = true }

local wanted, order = {}, {}
local function want(s)
    if not wanted[s] and not IGNORE[s] then
        wanted[s] = true
        table.insert(order, s)
    end
end

local files = { "main.lua", "dnd5e_data.lua", "dnd5e_dice.lua", "dnd5e_sheet.lua", "dnd5e_spells.lua", "dnd5e_classes.lua", "dnd5e_species.lua" }
for _, name in ipairs(files) do
    local src = assert(io.open(name)):read("*a")
    for s in src:gmatch('[^%w_][TF]%(%s*"(.-[^\\])"') do want(s) end
    for ctx, s in src:gmatch('C%(%s*"([%w_]+)",%s*"(.-[^\\])"') do want(ctx .. "|" .. s) end
    -- names in the data tables and tab labels
    if name == "dnd5e_data.lua" or name == "dnd5e_sheet.lua" or name == "dnd5e_spells.lua" or name == "dnd5e_classes.lua" or name == "dnd5e_species.lua" then
        for s in src:gmatch('%f[%w]name = "(.-)"') do want(s) end
        for s in src:gmatch('%f[%w]short = "(.-)"') do want(s) end
        for s in src:gmatch('id = "[%w_]+", text = "(.-)"') do want(s) end
    end
end
-- the alignments are a plain list of names
do
    local src = assert(io.open("dnd5e_data.lua")):read("*a")
    local block = src:match("Data%.ALIGNMENTS = (%b{})")
    for s in block:gmatch('"(.-)"') do want(s) end
end
-- armor names are only used with the "armor" context
for _, s in ipairs({ "Light", "Medium", "Heavy", "Shields" }) do
    want("armor|" .. s)
    wanted[s] = nil
end

local t = dofile("l10n/" .. code .. ".lua")
local missing = 0
for _, s in ipairs(order) do
    if wanted[s] and t[s] == nil and not (s:match("^armor|") and t[s:gsub("^armor|", "")]) then
        print("missing: " .. s)
        missing = missing + 1
    end
end
local unused = 0
for k in pairs(t) do
    if not wanted[k] and not (k:match("^%a+|") == nil and wanted["armor|" .. k]) then
        print("unused:  " .. k)
        unused = unused + 1
    end
end
print(string.format("%s: %d strings, %d missing, %d unused", code, #order, missing, unused))
os.exit(missing == 0 and 0 or 1)

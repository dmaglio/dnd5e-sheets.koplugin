--[[--
Species (2024) and races (2014) of the Player's Handbook, with their
subraces, lineages, legacies or ancestries, and what the sheet can fill in
by itself: speed (in feet) and size. Only names are listed here.

A sub entry with full = true already names the species ("High Elf"); the
others are shown after it ("Goliath (Frost Giant)").
--]]

local I18n = require("dnd5e_i18n")
local util = require("util")
local T, C = I18n.T, I18n.C

local Species = {}

local DRAGONS = {
    { key = "black", name = "Black (acid)" }, { key = "blue", name = "Blue (lightning)" },
    { key = "brass", name = "Brass (fire)" }, { key = "bronze", name = "Bronze (lightning)" },
    { key = "copper", name = "Copper (acid)" }, { key = "gold", name = "Gold (fire)" },
    { key = "green", name = "Green (poison)" }, { key = "red", name = "Red (fire)" },
    { key = "silver", name = "Silver (cold)" }, { key = "white", name = "White (cold)" },
}

-- size: "medium", "small" or "choice" (Medium or Small, chosen by the player)
Species.LIST2014 = {
    { key = "dragonborn", name = "Dragonborn", speed = 30, size = "medium", subs = DRAGONS },
    { key = "dwarf", name = "Dwarf", speed = 25, size = "medium", subs = {
        { key = "hill", name = "Hill Dwarf", full = true },
        { key = "mountain", name = "Mountain Dwarf", full = true } } },
    { key = "elf", name = "Elf", speed = 30, size = "medium", subs = {
        { key = "high", name = "High Elf", full = true },
        { key = "wood", name = "Wood Elf", full = true, speed = 35 },
        { key = "drow", name = "Dark Elf (Drow)", full = true } } },
    { key = "gnome", name = "Gnome", speed = 25, size = "small", subs = {
        { key = "forest", name = "Forest Gnome", full = true },
        { key = "rock", name = "Rock Gnome", full = true } } },
    { key = "half-elf", name = "Half-Elf", speed = 30, size = "medium" },
    { key = "half-orc", name = "Half-Orc", speed = 30, size = "medium" },
    { key = "halfling", name = "Halfling", speed = 25, size = "small", subs = {
        { key = "lightfoot", name = "Lightfoot Halfling", full = true },
        { key = "stout", name = "Stout Halfling", full = true } } },
    { key = "human", name = "Human", speed = 30, size = "medium" },
    { key = "tiefling", name = "Tiefling", speed = 30, size = "medium" },
}

Species.LIST2024 = {
    { key = "aasimar", name = "Aasimar", speed = 30, size = "choice" },
    { key = "dragonborn", name = "Dragonborn", speed = 30, size = "medium", subs = DRAGONS },
    { key = "dwarf", name = "Dwarf", speed = 30, size = "medium" },
    { key = "elf", name = "Elf", speed = 30, size = "medium", subs = {
        { key = "drow", name = "Drow" },
        { key = "high", name = "High Elf", full = true },
        { key = "wood", name = "Wood Elf", full = true, speed = 35 } } },
    { key = "gnome", name = "Gnome", speed = 30, size = "small", subs = {
        { key = "forest", name = "Forest Gnome", full = true },
        { key = "rock", name = "Rock Gnome", full = true } } },
    { key = "goliath", name = "Goliath", speed = 35, size = "medium", subs = {
        { key = "cloud", name = "Cloud Giant" }, { key = "fire", name = "Fire Giant" },
        { key = "frost", name = "Frost Giant" }, { key = "hill", name = "Hill Giant" },
        { key = "stone", name = "Stone Giant" }, { key = "storm", name = "Storm Giant" } } },
    { key = "halfling", name = "Halfling", speed = 30, size = "small" },
    { key = "human", name = "Human", speed = 30, size = "choice" },
    { key = "orc", name = "Orc", speed = 30, size = "medium" },
    { key = "tiefling", name = "Tiefling", speed = 30, size = "choice", subs = {
        { key = "abyssal", name = "Abyssal" }, { key = "chthonic", name = "Chthonic" },
        { key = "infernal", name = "Infernal" } } },
}

function Species.list(edition)
    return edition == "2024" and Species.LIST2024 or Species.LIST2014
end

--- A species by key, in the given edition first, then in the other one.
function Species.get(key, edition)
    if not key then return nil end
    for _, ed in ipairs({ edition, edition == "2024" and "2014" or "2024" }) do
        for _, sp in ipairs(Species.list(ed)) do
            if sp.key == key then return sp end
        end
    end
end

function Species.sub(sp, sub_key)
    if not (sp and sub_key and sp.subs) then return nil end
    for _, s in ipairs(sp.subs) do
        if s.key == sub_key then return s end
    end
end

--- The character's species as text: "Wood Elf", "Goliath (Frost Giant)",
-- the free text typed by hand, or "".
function Species.line(c)
    local e = c.species or {}
    local sp = Species.get(e.key, c.edition)
    if not sp then return util.trim(c.race or "") end
    local sub = Species.sub(sp, e.sub)
    if not sub then return T(sp.name) end
    if sub.full then return T(sub.name) end
    return T(sp.name) .. " (" .. T(sub.name) .. ")"
end

--- Speed as text in the units of the current language: "30 ft" or "9 m".
function Species.speedText(feet)
    if C("unit", "ft") == "m" then
        local m = feet * 0.3
        local text = (m == math.floor(m)) and tostring(math.floor(m)) or string.format("%.1f", m):gsub("%.", ",")
        return text .. " m"
    end
    return feet .. " ft"
end

--- Species and sub key for a free text ("Elfo dei boschi", "Goliath", ...).
function Species.fromText(text, edition)
    text = util.trim(text or ""):lower()
    if text == "" then return nil end
    for _, ed in ipairs({ edition, edition == "2024" and "2014" or "2024" }) do
        for _, sp in ipairs(Species.list(ed)) do
            for _, s in ipairs(sp.subs or {}) do
                if s.full and (text == s.name:lower() or text == T(s.name):lower()) then
                    return sp.key, s.key
                end
            end
        end
        for _, sp in ipairs(Species.list(ed)) do
            if text == sp.name:lower() or text == T(sp.name):lower() then return sp.key end
        end
    end
end

return Species

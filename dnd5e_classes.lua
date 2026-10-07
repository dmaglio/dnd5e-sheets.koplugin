--[[--
Classes and subclasses of the Player's Handbook (2014 and 2024), with what
the sheet can fill in by itself: hit die, saving throw proficiencies and
spellcasting. Only names are listed here, no rules text.
--]]

local I18n = require("dnd5e_i18n")
local util = require("util")
local T = I18n.T

local Classes = {}

-- spell = spell list used by the class (see dnd5e_spells.lua) and its ability
Classes.LIST = {
    { key = "barbarian", name = "Barbarian", hd = 12, saves = { "str", "con" },
      sub2014 = { { key = "berserker", name = "Path of the Berserker" },
                  { key = "totem-warrior", name = "Path of the Totem Warrior" } },
      sub2024 = { { key = "berserker", name = "Path of the Berserker" },
                  { key = "wild-heart", name = "Path of the Wild Heart" },
                  { key = "world-tree", name = "Path of the World Tree" },
                  { key = "zealot", name = "Path of the Zealot" } } },
    { key = "bard", name = "Bard", hd = 8, saves = { "dex", "cha" }, spell = "bard", ability = "cha",
      sub2014 = { { key = "lore", name = "College of Lore" },
                  { key = "valor", name = "College of Valor" } },
      sub2024 = { { key = "dance", name = "College of Dance" },
                  { key = "glamour", name = "College of Glamour" },
                  { key = "lore", name = "College of Lore" },
                  { key = "valor", name = "College of Valor" } } },
    { key = "cleric", name = "Cleric", hd = 8, saves = { "wis", "cha" }, spell = "cleric", ability = "wis",
      sub2014 = { { key = "knowledge", name = "Knowledge Domain" },
                  { key = "life", name = "Life Domain" },
                  { key = "light", name = "Light Domain" },
                  { key = "nature", name = "Nature Domain" },
                  { key = "tempest", name = "Tempest Domain" },
                  { key = "trickery", name = "Trickery Domain" },
                  { key = "war", name = "War Domain" } },
      sub2024 = { { key = "life", name = "Life Domain" },
                  { key = "light", name = "Light Domain" },
                  { key = "trickery", name = "Trickery Domain" },
                  { key = "war", name = "War Domain" } } },
    { key = "druid", name = "Druid", hd = 8, saves = { "int", "wis" }, spell = "druid", ability = "wis",
      sub2014 = { { key = "land", name = "Circle of the Land" },
                  { key = "moon", name = "Circle of the Moon" } },
      sub2024 = { { key = "land", name = "Circle of the Land" },
                  { key = "moon", name = "Circle of the Moon" },
                  { key = "sea", name = "Circle of the Sea" },
                  { key = "stars", name = "Circle of the Stars" } } },
    { key = "fighter", name = "Fighter", hd = 10, saves = { "str", "con" },
      sub2014 = { { key = "battle-master", name = "Battle Master" },
                  { key = "champion", name = "Champion" },
                  { key = "eldritch-knight", name = "Eldritch Knight", spell = "wizard", ability = "int" } },
      sub2024 = { { key = "battle-master", name = "Battle Master" },
                  { key = "champion", name = "Champion" },
                  { key = "eldritch-knight", name = "Eldritch Knight", spell = "wizard", ability = "int" },
                  { key = "psi-warrior", name = "Psi Warrior" } } },
    { key = "monk", name = "Monk", hd = 8, saves = { "str", "dex" },
      sub2014 = { { key = "open-hand", name = "Way of the Open Hand" },
                  { key = "shadow", name = "Way of Shadow" },
                  { key = "four-elements", name = "Way of the Four Elements" } },
      sub2024 = { { key = "mercy", name = "Warrior of Mercy" },
                  { key = "shadow", name = "Warrior of Shadow" },
                  { key = "elements", name = "Warrior of the Elements" },
                  { key = "open-hand", name = "Warrior of the Open Hand" } } },
    { key = "paladin", name = "Paladin", hd = 10, saves = { "wis", "cha" }, spell = "paladin", ability = "cha",
      sub2014 = { { key = "devotion", name = "Oath of Devotion" },
                  { key = "ancients", name = "Oath of the Ancients" },
                  { key = "vengeance", name = "Oath of Vengeance" } },
      sub2024 = { { key = "devotion", name = "Oath of Devotion" },
                  { key = "glory", name = "Oath of Glory" },
                  { key = "ancients", name = "Oath of the Ancients" },
                  { key = "vengeance", name = "Oath of Vengeance" } } },
    { key = "ranger", name = "Ranger", hd = 10, saves = { "str", "dex" }, spell = "ranger", ability = "wis",
      sub2014 = { { key = "beast-master", name = "Beast Master" },
                  { key = "hunter", name = "Hunter" } },
      sub2024 = { { key = "beast-master", name = "Beast Master" },
                  { key = "fey-wanderer", name = "Fey Wanderer" },
                  { key = "gloom-stalker", name = "Gloom Stalker" },
                  { key = "hunter", name = "Hunter" } } },
    { key = "rogue", name = "Rogue", hd = 8, saves = { "dex", "int" },
      sub2014 = { { key = "arcane-trickster", name = "Arcane Trickster", spell = "wizard", ability = "int" },
                  { key = "assassin", name = "Assassin" },
                  { key = "thief", name = "Thief" } },
      sub2024 = { { key = "arcane-trickster", name = "Arcane Trickster", spell = "wizard", ability = "int" },
                  { key = "assassin", name = "Assassin" },
                  { key = "soulknife", name = "Soulknife" },
                  { key = "thief", name = "Thief" } } },
    { key = "sorcerer", name = "Sorcerer", hd = 6, saves = { "con", "cha" }, spell = "sorcerer", ability = "cha",
      sub2014 = { { key = "draconic", name = "Draconic Bloodline" },
                  { key = "wild-magic", name = "Wild Magic" } },
      sub2024 = { { key = "aberrant", name = "Aberrant Sorcery" },
                  { key = "clockwork", name = "Clockwork Sorcery" },
                  { key = "draconic", name = "Draconic Sorcery" },
                  { key = "wild-magic", name = "Wild Magic Sorcery" } } },
    { key = "warlock", name = "Warlock", hd = 8, saves = { "wis", "cha" }, spell = "warlock", ability = "cha",
      sub2014 = { { key = "archfey", name = "The Archfey" },
                  { key = "fiend", name = "The Fiend" },
                  { key = "great-old-one", name = "The Great Old One" } },
      sub2024 = { { key = "archfey", name = "Archfey Patron" },
                  { key = "celestial", name = "Celestial Patron" },
                  { key = "fiend", name = "Fiend Patron" },
                  { key = "great-old-one", name = "Great Old One Patron" } } },
    { key = "wizard", name = "Wizard", hd = 6, saves = { "int", "wis" }, spell = "wizard", ability = "int",
      sub2014 = { { key = "abjuration", name = "School of Abjuration" },
                  { key = "conjuration", name = "School of Conjuration" },
                  { key = "divination", name = "School of Divination" },
                  { key = "enchantment", name = "School of Enchantment" },
                  { key = "evocation", name = "School of Evocation" },
                  { key = "illusion", name = "School of Illusion" },
                  { key = "necromancy", name = "School of Necromancy" },
                  { key = "transmutation", name = "School of Transmutation" } },
      sub2024 = { { key = "abjuration", name = "Abjurer" },
                  { key = "divination", name = "Diviner" },
                  { key = "evocation", name = "Evoker" },
                  { key = "illusion", name = "Illusionist" } } },
}

Classes.BY_KEY = {}
for _, cl in ipairs(Classes.LIST) do Classes.BY_KEY[cl.key] = cl end

function Classes.get(key)
    return key and Classes.BY_KEY[key]
end

--- Subclasses of a class for an edition.
function Classes.subclasses(key, edition)
    local cl = Classes.get(key)
    if not cl then return {} end
    return edition == "2024" and cl.sub2024 or cl.sub2014
end

--- A subclass by key, looked up in the given edition first, then in the other
-- one (a character can switch edition).
function Classes.subclass(key, sub_key, edition)
    if not sub_key then return nil end
    local other = edition == "2024" and "2014" or "2024"
    for _, ed in ipairs({ edition, other }) do
        for _, s in ipairs(Classes.subclasses(key, ed)) do
            if s.key == sub_key then return s end
        end
    end
end

--- Class key for a free text such as "Wizard", "mago" or "Chierico 5".
function Classes.fromText(text)
    text = util.trim(text or ""):lower()
    if text == "" then return nil end
    for _, cl in ipairs(Classes.LIST) do
        for _, name in ipairs({ cl.name:lower(), T(cl.name):lower() }) do
            if text == name or text:find("^" .. name .. "%f[^%w]") then
                return cl.key
            end
        end
    end
end

--- Subclass key for a free text, among the subclasses of a class.
function Classes.subclassFromText(key, text, edition)
    text = util.trim(text or ""):lower()
    if text == "" then return nil end
    for _, ed in ipairs({ edition, edition == "2024" and "2014" or "2024" }) do
        for _, s in ipairs(Classes.subclasses(key, ed)) do
            if text == s.name:lower() or text == T(s.name):lower() then return s.key end
        end
    end
end

-- One entry of a character's class list:
-- { key = class key or nil, name = free text when key is nil,
--   sub = subclass key or nil, sub_name = free text when sub is nil, level = n }

function Classes.entryName(e)
    local cl = Classes.get(e.key)
    return cl and T(cl.name) or (e.name or "?")
end

function Classes.entrySubclass(e, edition)
    local s = Classes.subclass(e.key, e.sub, edition)
    if s then return T(s.name) end
    if e.sub_name and e.sub_name ~= "" then return e.sub_name end
end

--- Hit die of an entry; nil for a class that isn't in the list.
function Classes.entryHitDie(e)
    local cl = Classes.get(e.key)
    return cl and cl.hd
end

--- Spell list and ability of an entry, from its class or its subclass.
function Classes.entrySpellcasting(e, edition)
    local cl = Classes.get(e.key)
    if cl and cl.spell then return cl.spell, cl.ability end
    local s = Classes.subclass(e.key, e.sub, edition)
    if s and s.spell then return s.spell, s.ability end
end

return Classes

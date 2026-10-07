--[[--
Rules and storage.

Fields follow the official character sheets of both editions (2014 and 2024).
The edition is chosen per character (field "edition"); the file always holds
the fields of both, and the sheet only shows those of the chosen edition.
Each character is a LuaSettings file in <settings>/dnd5e/<id>.lua.

Names here are English source strings: translate them with I18n.T when
displaying them.
--]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local Classes = require("dnd5e_classes")
local Species = require("dnd5e_species")
local I18n = require("dnd5e_i18n")
local T, C = I18n.T, I18n.C

local Data = {}

Data.ABILITIES = {
    { key = "str", name = "Strength",     short = "Str" },
    { key = "dex", name = "Dexterity",    short = "Dex" },
    { key = "con", name = "Constitution", short = "Con" },
    { key = "int", name = "Intelligence", short = "Int" },
    { key = "wis", name = "Wisdom",       short = "Wis" },
    { key = "cha", name = "Charisma",     short = "Cha" },
}
Data.ABILITY_BY_KEY = {}
for _, a in ipairs(Data.ABILITIES) do Data.ABILITY_BY_KEY[a.key] = a end

Data.SKILLS = {
    { key = "acrobatics",    name = "Acrobatics",      ab = "dex" },
    { key = "animal",        name = "Animal Handling", ab = "wis" },
    { key = "arcana",        name = "Arcana",          ab = "int" },
    { key = "athletics",     name = "Athletics",       ab = "str" },
    { key = "deception",     name = "Deception",       ab = "cha" },
    { key = "history",       name = "History",         ab = "int" },
    { key = "insight",       name = "Insight",         ab = "wis" },
    { key = "intimidation",  name = "Intimidation",    ab = "cha" },
    { key = "investigation", name = "Investigation",   ab = "int" },
    { key = "medicine",      name = "Medicine",        ab = "wis" },
    { key = "nature",        name = "Nature",          ab = "int" },
    { key = "perception",    name = "Perception",      ab = "wis" },
    { key = "performance",   name = "Performance",     ab = "cha" },
    { key = "persuasion",    name = "Persuasion",      ab = "cha" },
    { key = "religion",      name = "Religion",        ab = "int" },
    { key = "sleight",       name = "Sleight of Hand", ab = "dex" },
    { key = "stealth",       name = "Stealth",         ab = "dex" },
    { key = "survival",      name = "Survival",        ab = "wis" },
}

--- Skills sorted alphabetically in the current language, as on the sheets.
function Data.sortedSkills()
    local list = {}
    for _, s in ipairs(Data.SKILLS) do table.insert(list, s) end
    table.sort(list, function(a, b) return T(a.name) < T(b.name) end)
    return list
end

-- Coins in sheet order: copper, silver, electrum, gold, platinum
Data.COINS = {
    { key = "cp", short = "CP", name = "Copper" },
    { key = "sp", short = "SP", name = "Silver" },
    { key = "ep", short = "EP", name = "Electrum" },
    { key = "gp", short = "GP", name = "Gold" },
    { key = "pp", short = "PP", name = "Platinum" },
}

Data.HIT_DICE = { 6, 8, 10, 12 }

-- Alignments in grid order: lawful, neutral, chaotic by good, neutral, evil
Data.ALIGNMENTS = {
    "Lawful Good", "Lawful Neutral", "Lawful Evil",
    "Neutral Good", "Neutral", "Neutral Evil",
    "Chaotic Good", "Chaotic Neutral", "Chaotic Evil",
}

--- The alignment (English name) a free text stands for, in any language.
function Data.alignmentFromText(text)
    text = util.trim(text or ""):lower()
    if text == "" then return nil end
    for _, name in ipairs(Data.ALIGNMENTS) do
        if text == name:lower() or text == T(name):lower() then return name end
    end
    if text == "true neutral" or text == "neutrale puro" then return "Neutral" end
end

-- Armor training (2024 sheet)
Data.ARMOR_TRAINING = {
    { key = "light", name = "Light" },
    { key = "medium", name = "Medium" },
    { key = "heavy", name = "Heavy" },
    { key = "shields", name = "Shields" },
}

function Data.newCharacter(name, edition)
    local c = {
        schema = 1,
        edition = edition or "2024",
        name = name or T("New character"),
        player = "", class = "", level = 1, background = "", race = "",
        classes = {},        -- { key | name, sub | sub_name, level }, see dnd5e_classes.lua
        species = {},        -- { key, sub } from dnd5e_species.lua; "race" holds its text
        alignment = "", xp = 0,   -- alignment: text; alignment_key: one of Data.ALIGNMENTS
        scores = { str = 10, dex = 10, con = 10, int = 10, wis = 10, cha = 10 },
        saves = {},          -- [ability] = true when proficient
        skills = {},         -- [skill] = 1 proficiency, 2 expertise
        prof_override = nil, -- proficiency bonus set by hand
        inspiration = 0,
        ac = 10, init_bonus = 0, speed = T("30 ft"),
        hp = { max = 10, current = 10, temp = 0 },
        hd = { die = 8, total = 1, spent = {} }, -- die and total only without classes; spent["d8"] = n
        death = { success = 0, fail = 0 },
        attacks = {},        -- { name, bonus | dc, damage, notes }
        attacks_notes = "",
        coins = { cp = 0, sp = 0, ep = 0, gp = 0, pp = 0 },
        equipment = "", proficiencies = "", features = "",
        traits = "", ideals = "", bonds = "", flaws = "",
        age = "", height = "", weight = "", eyes = "", skin = "", hair = "",
        appearance = "", backstory = "", allies = "", faction = "",
        extra_features = "", treasure = "",
        spell = {
            class = "", ability = "int",
            slots = {},      -- [level] = { total, used }
            list = {},       -- { name, level, prepared, time, range, notes, conc, ritual, material }
        },
        -- 2024 sheet only
        subclass = "", size = C("size", "Medium"), shield = false,
        species_traits = "", feats = "", languages = "",
        armor_training = {}, weapons_training = "", tools_training = "",
        attunement = "",
        session_notes = "",
        log = {},            -- latest rolls, newest first
    }
    for lvl = 1, 9 do c.spell.slots[lvl] = { total = 0, used = 0 } end
    return c
end

--- Fill a character read from disk with fields added in later versions.
local function fill(c, defaults)
    for k, v in pairs(defaults) do
        if c[k] == nil then
            c[k] = util.tableDeepCopy(v)
        elseif type(v) == "table" and type(c[k]) == "table" and k ~= "attacks"
                and k ~= "list" and k ~= "log" and k ~= "saves" and k ~= "skills"
                and k ~= "armor_training" then
            fill(c[k], v)
        end
    end
end

-- Calculations --------------------------------------------------------------

function Data.mod(score)
    return math.floor(((tonumber(score) or 10) - 10) / 2)
end

function Data.abilityMod(c, ab)
    return Data.mod(c.scores[ab])
end

function Data.profBonus(c)
    if c.prof_override then return c.prof_override end
    local lvl = math.max(1, math.min(20, tonumber(c.level) or 1))
    return 2 + math.floor((lvl - 1) / 4)
end

function Data.saveBonus(c, ab)
    return Data.abilityMod(c, ab) + (c.saves[ab] and Data.profBonus(c) or 0)
end

function Data.skillBonus(c, skill)
    local level = c.skills[skill.key] or 0
    return Data.abilityMod(c, skill.ab) + level * Data.profBonus(c)
end

function Data.skillByKey(key)
    for _, s in ipairs(Data.SKILLS) do
        if s.key == key then return s end
    end
end

function Data.passivePerception(c)
    return 10 + Data.skillBonus(c, Data.skillByKey("perception"))
end

function Data.initiative(c)
    return Data.abilityMod(c, "dex") + (tonumber(c.init_bonus) or 0)
end

function Data.spellDC(c)
    return 8 + Data.profBonus(c) + Data.abilityMod(c, c.spell.ability)
end

function Data.spellAttack(c)
    return Data.profBonus(c) + Data.abilityMod(c, c.spell.ability)
end

-- Damage goes to temporary hit points first
function Data.damage(c, n)
    local temp = c.hp.temp or 0
    local absorbed = math.min(temp, n)
    c.hp.temp = temp - absorbed
    c.hp.current = math.max(0, c.hp.current - (n - absorbed))
end

function Data.heal(c, n)
    if c.hp.current == 0 and n > 0 then
        c.death.success, c.death.fail = 0, 0
    end
    c.hp.current = math.min(c.hp.max, c.hp.current + n)
end

-- Classes and hit dice --------------------------------------------------------

--- Hit dice as pools, largest die first: { { die, total, spent } }.
-- With classes, each class adds its level in dice of its own size; a class
-- that isn't in the list uses the die chosen by hand.
function Data.hitDice(c)
    local totals = {}
    if #c.classes > 0 then
        for _, e in ipairs(c.classes) do
            local die = Classes.entryHitDie(e) or c.hd.die
            totals[die] = (totals[die] or 0) + (tonumber(e.level) or 1)
        end
    else
        totals[c.hd.die] = c.hd.total
    end
    local pools = {}
    for die, total in pairs(totals) do
        table.insert(pools, { die = die, total = total,
            spent = math.min(total, c.hd.spent["d" .. die] or 0) })
    end
    table.sort(pools, function(a, b) return a.die > b.die end)
    return pools
end

function Data.setSpentHitDice(c, die, n)
    c.hd.spent["d" .. die] = math.max(0, n)
end

--- "Wizard 5", "Fighter 3 / Wizard 2", or the free text of older sheets.
function Data.classLine(c)
    if #c.classes > 0 then
        local parts = {}
        for _, e in ipairs(c.classes) do
            table.insert(parts, Classes.entryName(e) .. " " .. (e.level or 1))
        end
        return table.concat(parts, " / ")
    end
    local class = util.trim(c.class or "")
    if class ~= "" then return class .. " " .. (c.level or 1) end
    return I18n.F("Level %d", c.level or 1)
end

--- Subclasses of all classes, "" if none.
function Data.subclassLine(c)
    local parts = {}
    for _, e in ipairs(c.classes) do
        local sub = Classes.entrySubclass(e, c.edition)
        if sub then table.insert(parts, sub) end
    end
    return table.concat(parts, " / ")
end

--- After the class list changes: total level, text fields, and what follows
-- from the classes. first_before is the key of the first class before the
-- change: saving throw proficiencies come from the first class only.
function Data.classesChanged(c, first_before)
    if #c.classes > 0 then
        local total = 0
        for _, e in ipairs(c.classes) do total = total + (tonumber(e.level) or 1) end
        c.level = total
    end
    local names = {}
    for _, e in ipairs(c.classes) do table.insert(names, Classes.entryName(e)) end
    c.class = table.concat(names, " / ")
    c.subclass = Data.subclassLine(c)

    local first = c.classes[1] and c.classes[1].key
    if first ~= first_before then
        local old = Classes.get(first_before)
        if old then
            for _, ab in ipairs(old.saves) do c.saves[ab] = nil end
        end
        local new = Classes.get(first)
        if new then
            for _, ab in ipairs(new.saves) do c.saves[ab] = true end
        end
    end

    -- spellcasting: keep the spell list chosen by hand if one of the classes
    -- uses it, otherwise take the first class that casts spells
    local lists, first_list, first_ability = {}, nil, nil
    for _, e in ipairs(c.classes) do
        local list, ability = Classes.entrySpellcasting(e, c.edition)
        if list then
            lists[list] = true
            if not first_list then first_list, first_ability = list, ability end
        end
    end
    if first_list and not lists[c.spell.class_key or ""] then
        c.spell.class_key = first_list
        c.spell.class = T(Classes.get(first_list).name)
        c.spell.ability = first_ability
    end
end

--- After choosing the species: its text, speed and (if fixed) size.
function Data.speciesChanged(c)
    local e = c.species
    local sp = Species.get(e.key, c.edition)
    c.race = Species.line(c)
    if not sp then return end
    local sub = Species.sub(sp, e.sub)
    c.speed = Species.speedText(sub and sub.speed or sp.speed)
    if sp.size == "small" then
        c.size = C("size", "Small")
    elseif sp.size == "medium" then
        c.size = C("size", "Medium")
    end
end

function Data.longRest(c)
    c.hp.current = c.hp.max
    c.hp.temp = 0
    c.death.success, c.death.fail = 0, 0
    for lvl = 1, 9 do c.spell.slots[lvl].used = 0 end
    if c.edition == "2024" then
        -- 2024: all spent hit dice come back
        c.hd.spent = {}
    else
        -- 2014: half of the total hit dice come back (at least one),
        -- the largest first
        local pools = Data.hitDice(c)
        local total = 0
        for _, p in ipairs(pools) do total = total + p.total end
        local regain = math.max(1, math.floor(total / 2))
        for _, p in ipairs(pools) do
            local back = math.min(regain, p.spent)
            Data.setSpentHitDice(c, p.die, p.spent - back)
            regain = regain - back
        end
    end
end

function Data.addLog(c, text)
    table.insert(c.log, 1, os.date("%H:%M") .. "  " .. text)
    while #c.log > 30 do table.remove(c.log) end
end

-- Storage -------------------------------------------------------------------

function Data.dir()
    local dir = DataStorage:getSettingsDir() .. "/dnd5e"
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
    return dir
end

local function pathFor(id)
    return Data.dir() .. "/" .. id .. ".lua"
end

function Data.newId()
    return os.date("%Y%m%d%H%M%S") .. string.format("%04d", math.random(0, 9999))
end

function Data.load(id)
    local settings = LuaSettings:open(pathFor(id))
    local c = settings:readSetting("character")
    if not c then return nil end
    -- characters saved before editions existed were all 2014
    c.edition = c.edition or "2014"
    local had_classes = c.classes ~= nil
    local had_species = c.species ~= nil
    local had_alignment = c.alignment_key ~= nil
    fill(c, Data.newCharacter())
    if type(c.hd.used) == "number" then
        -- before 1.1 there was a single pool of hit dice
        c.hd.spent["d" .. c.hd.die] = c.hd.used
        c.hd.used = nil
    end
    if not had_alignment then
        -- before 1.1 the alignment was free text: recognize it if it's one of the nine
        c.alignment_key = Data.alignmentFromText(c.alignment)
    end
    if not had_species and util.trim(c.race or "") ~= "" then
        -- before 1.1 the species was free text: recognize it if it's in the list
        local key, sub = Species.fromText(c.race, c.edition)
        if key then c.species = { key = key, sub = sub } end
    end
    if not had_classes and util.trim(c.class or "") ~= "" then
        -- before 1.1 the class was free text: "Wizard", "Mago 5" or
        -- "Fighter 3 / Wizard 2" become a class list when every part is a known
        -- class, otherwise the text is kept as one class with the sheet's level
        local parts, entries = util.splitToArray(c.class, "/"), {}
        for _, part in ipairs(parts) do
            local key = Classes.fromText(part)
            if not key then entries = nil break end
            table.insert(entries, { key = key, level = tonumber(part:match("(%d+)%s*$")) })
        end
        if entries and #entries == 1 then
            entries[1].level = c.level or 1
        elseif entries then
            for _, e in ipairs(entries) do
                if not e.level then entries = nil break end
            end
        end
        if not entries then
            entries = { { name = util.trim(c.class), level = c.level or 1 } }
        end
        local sub = util.trim(c.subclass or "")
        if sub ~= "" then
            local first = entries[1]
            first.sub = first.key and Classes.subclassFromText(first.key, sub, c.edition)
            if not first.sub then first.sub_name = sub end
        end
        c.classes = entries
        -- spent hit dice of the single old pool go to the first class's die
        local old_spent = c.hd.spent["d" .. c.hd.die]
        local first_die = Classes.entryHitDie(entries[1])
        if old_spent and first_die and first_die ~= c.hd.die then
            c.hd.spent = { ["d" .. first_die] = old_spent }
        end
        if #entries > 1 then
            local total = 0
            for _, e in ipairs(entries) do total = total + e.level end
            c.level = total
        end
    end
    c.id = id
    return c
end

function Data.save(c)
    if not c.id then c.id = Data.newId() end
    local settings = LuaSettings:open(pathFor(c.id))
    settings:saveSetting("character", c)
    settings:flush()
end

function Data.delete(id)
    os.remove(pathFor(id))
    os.remove(pathFor(id) .. ".old")
end

function Data.duplicate(c)
    local copy = util.tableDeepCopy(c)
    copy.id = Data.newId()
    copy.name = I18n.F("%s (copy)", c.name)
    Data.save(copy)
    return copy
end

--- Saved characters, sorted by name.
function Data.list()
    local out = {}
    local dir = Data.dir()
    for file in lfs.dir(dir) do
        local id = file:match("^(.+)%.lua$")
        if id then
            local c = Data.load(id)
            if c then table.insert(out, c) end
        end
    end
    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

return Data

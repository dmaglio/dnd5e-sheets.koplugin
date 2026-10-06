--[[--
Dice roller: expressions like "2d6+3", "1d8+1d6-1", "d20".

Every roll returns { total, text, nat }: text is ready to display, nat is the
natural die of a d20 (for criticals).
--]]

local I18n = require("dnd5e_i18n")
local T = I18n.T

local Dice = {}

local seeded = false
local function seed()
    if not seeded then
        math.randomseed(os.time())
        -- the first values after seeding are not very random on some libcs
        for _ = 1, 5 do math.random() end
        seeded = true
    end
end

function Dice.die(sides)
    seed()
    return math.random(1, sides)
end

local function signed(n)
    return n >= 0 and ("+" .. n) or tostring(n)
end
Dice.signed = signed

--- Parse an expression into a list of terms, or nil.
-- Text after the expression (e.g. "1d8+3 slashing") is ignored.
function Dice.parse(expr)
    if type(expr) ~= "string" then return nil end
    local s = expr:lower():gsub("%s+", "")
    -- keep only the leading part made of dice, numbers and signs
    s = s:match("^[%+%-]?[%dd%+%-]+") or ""
    if s == "" then return nil end
    local terms = {}
    for sign, body in s:gmatch("([%+%-]?)([^%+%-]+)") do
        local neg = sign == "-"
        local n, sides = body:match("^(%d*)d(%d+)$")
        if sides then
            n = tonumber(n) or 1
            sides = tonumber(sides)
            if n < 1 or n > 100 or sides < 2 or sides > 1000 then return nil end
            table.insert(terms, { count = n, sides = sides, neg = neg })
        elseif body:match("^%d+$") then
            table.insert(terms, { const = tonumber(body), neg = neg })
        else
            return nil
        end
    end
    if #terms == 0 then return nil end
    return terms
end

--- Roll an expression. Returns nil if it is not valid.
function Dice.roll(expr)
    local terms = Dice.parse(expr)
    if not terms then return nil end
    local total, parts = 0, {}
    for i, t in ipairs(terms) do
        local value, shown
        if t.const then
            value = t.const
            shown = tostring(t.const)
        else
            local rolls = {}
            value = 0
            for _ = 1, t.count do
                local r = Dice.die(t.sides)
                value = value + r
                table.insert(rolls, r)
            end
            shown = t.count .. "d" .. t.sides .. " [" .. table.concat(rolls, ",") .. "]"
        end
        if t.neg then value = -value end
        total = total + value
        if i == 1 then
            table.insert(parts, (t.neg and "−" or "") .. shown)
        else
            table.insert(parts, (t.neg and " − " or " + ") .. shown)
        end
    end
    return { total = total, text = table.concat(parts) .. " = " .. total }
end

--- d20 roll with a bonus. mode: nil, "adv" (advantage) or "dis" (disadvantage).
function Dice.d20(bonus, mode)
    bonus = bonus or 0
    local a, b = Dice.die(20), nil
    local nat = a
    local shown
    if mode == "adv" or mode == "dis" then
        b = Dice.die(20)
        nat = (mode == "adv") and math.max(a, b) or math.min(a, b)
        shown = string.format("d20 [%d,%d] %s", a, b, mode == "adv" and T("adv.") or T("dis."))
    else
        shown = string.format("d20 [%d]", a)
    end
    local total = nat + bonus
    local text = shown
    if bonus ~= 0 then
        text = text .. " " .. (bonus > 0 and "+ " or "− ") .. math.abs(bonus)
    end
    text = text .. " = " .. total
    if nat == 20 then
        text = text .. "  " .. T("CRITICAL!")
    elseif nat == 1 then
        text = text .. "  " .. T("critical miss")
    end
    return { total = total, text = text, nat = nat }
end

return Dice

-- HealPop core: saved variables, tooltip scanning, candidate resolution,
-- and the secure macro the button actually fires.

local ADDON, ns = ...

-- ── Compat shims ─────────────────────────────────────────────────────
--
-- These functions have been shuffled between the global table, C_Item and
-- C_Container across Classic patches, and which ones survive differs per
-- flavour -- GetItemCooldown is gone entirely on Anniversary 2.5.6. Probe
-- every home we know of and take the first that's actually callable.

local function Pick(...)
    for i = 1, select("#", ...) do
        local fn = (select(i, ...))
        if type(fn) == "function" then return fn end
    end
    return nil
end

local GetContainerNumSlots = Pick(C_Container and C_Container.GetContainerNumSlots,
                                  _G.GetContainerNumSlots)
local GetContainerItemID   = Pick(C_Container and C_Container.GetContainerItemID,
                                  _G.GetContainerItemID)
local GetContainerItemCooldown = Pick(C_Container and C_Container.GetContainerItemCooldown,
                                  _G.GetContainerItemCooldown)
local GetItemCooldown      = Pick(C_Item and C_Item.GetItemCooldown,
                                  C_Container and C_Container.GetItemCooldown,
                                  _G.GetItemCooldown)
local GetItemCount         = Pick(C_Item and C_Item.GetItemCount, _G.GetItemCount)
local GetItemSpell         = Pick(C_Item and C_Item.GetItemSpell, _G.GetItemSpell)
local IsUsableItem         = Pick(C_Item and C_Item.IsUsableItem, _G.IsUsableItem)
local GetInventoryItemCooldown = Pick(C_Item and C_Item.GetInventoryItemCooldown,
                                  _G.GetInventoryItemCooldown)

local MACRO_BUDGET = 250    -- macrotext is capped near 255; leave headroom
local GCD          = 1.5    -- cooldown reads below this are just the GCD

HealPopDB = HealPopDB or {}

local defaults = {
    point = "CENTER", relPoint = "CENTER", x = 0, y = -140,
    scale        = 1.0,
    bgAlpha      = 0.85,
    fontSize     = 20,
    fontFace     = 1,
    spellGuard   = 90,        -- gate spells above this health %; 100 disables
    chainAcross  = false,     -- true: one click may spend more than one thing
    buttonSize   = 48,
    panelSide    = "RIGHT",   -- TOP | BOTTOM | LEFT | RIGHT
    panelRows    = 4,
    panelAlways  = false,     -- show the panel without mousing over
    chainDepth   = 3,         -- how many fallbacks go into the macro
    autoDiscover = true,      -- pick up healing items not in the shipped tables
    hideEmpty    = false,     -- hide the button entirely when nothing is usable
    seeded       = nil,
}

function ns.DB()
    local db = HealPopDB
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
    db.categoryOrder    = db.categoryOrder    or nil
    db.categoryEnabled  = db.categoryEnabled  or nil
    db.disabled         = db.disabled         or {}

    if not db.categoryOrder then
        db.categoryOrder = {}
        for i, key in ipairs(ns.DEFAULT_CATEGORY_ORDER) do db.categoryOrder[i] = key end
    end
    if not db.categoryEnabled then
        db.categoryEnabled = {}
        for _, cat in ipairs(ns.CATEGORIES) do db.categoryEnabled[cat.key] = cat.default end
    end

    -- Seed the shipped-off spells exactly once, so a later re-enable sticks.
    if db.seeded ~= 1 then
        for _, s in ipairs(ns.SPELLS) do
            if s.off then db.disabled["spell:" .. s.id] = true end
        end
        db.seeded = 1
    end
    return db
end

-- ── Tooltip scanning ─────────────────────────────────────────────────

local scanner = CreateFrame("GameTooltip", "HealPopScanTooltip", nil, "GameTooltipTemplate")
scanner:SetOwner(UIParent, "ANCHOR_NONE")

-- Ordered most-specific-first. Each returns the healing implied by the line.
-- Classic tooltips are inconsistent about "health" vs "damage" and about where
-- the number sits, so this needs more variants than you'd hope: potions say
-- "Restores 1500 to 2500 health", bandages say "Heals 3400 damage over 8 sec",
-- Renew says "Heals the target for 1010 over 15 sec", Desperate Prayer says
-- "Instantly heals you for 1128 to 1332".
local HEAL_PATTERNS = {
    { "(%d+) health per second for (%d+)", function(a, b) return a * b end },
    { "(%d+) to (%d+) health",             function(a, b) return (a + b) / 2 end },
    { "heals? you for (%d+) to (%d+)",     function(a, b) return (a + b) / 2 end },
    { "restores? (%d+) to (%d+)",          function(a, b) return (a + b) / 2 end },
    { "for (%d+) to (%d+)",                function(a, b) return (a + b) / 2 end },
    { "restores? (%d+) health",            function(a)    return a end },
    { "heals? you for (%d+)",              function(a)    return a end },
    { "heals? the target for (%d+)",       function(a)    return a end },
    { "heals? (%d+) damage",               function(a)    return a end },
    { "for (%d+) over %d+ sec",            function(a)    return a end },
    { "(%d+) health over",                 function(a)    return a end },
    { "absorbing (%d+)",                   function(a)    return a end },
    { "(%d+) health",                      function(a)    return a end },
}

-- Anything that only works parked on the floor is not a panic button. This is
-- what separates a tuber from Golden Fish Sticks.
-- "resurrect" catches soulstones, whose TBC tooltip reads "...allowing them to
-- resurrect upon death with 400 health and 700 mana" -- a health number that
-- has nothing to do with healing you now.
local REJECT_PATTERNS = { "remain seated", "must remain", "while sitting",
                          "resurrect", "upon death" }

-- A line is worth running patterns against only if it's talking about healing
-- at all, and isn't a mana line -- otherwise "Restores 900 to 1500 mana" reads
-- as a 1200-point heal, and Dark Rune's "but causes 600 damage" isn't a rescue.
local function IsHealLine(line)
    if not (line:find("heal") or line:find("restor") or line:find("absorb")
            or line:find("health")) then
        return false
    end
    if line:find("mana") and not (line:find("health") or line:find("heal")) then
        return false
    end
    return true
end

local function ParseHealFromScanner()
    local found
    for i = 1, scanner:NumLines() do
        local fs = _G["HealPopScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            local line = text:lower()

            for _, reject in ipairs(REJECT_PATTERNS) do
                if line:find(reject, 1, true) then return nil end
            end

            -- Keep scanning even once we have a number: a reject line may
            -- still be waiting further down the tooltip.
            if not found and IsHealLine(line) then
                for _, entry in ipairs(HEAL_PATTERNS) do
                    local a, b = line:match(entry[1])
                    if a then
                        local value = entry[2](tonumber(a), tonumber(b) or 0)
                        if value and value > 0 then
                            found = math.floor(value + 0.5)
                        end
                        break
                    end
                end
            end
        end
    end
    return found
end

-- Successful scans are cached for the session. Misses go in a separate table
-- because most of them are just "the client hasn't cached that item's tooltip
-- yet" -- caching those as permanent failures makes items vanish for the rest
-- of the session. GET_ITEM_INFO_RECEIVED clears the misses, not the hits.
local healCache = {}
local healMiss  = {}

function ns.ClearHealCache()
    wipe(healCache)
    wipe(healMiss)
end

function ns.ClearHealMisses()
    if next(healMiss) == nil then return false end
    wipe(healMiss)
    return true
end

local function CacheGet(key)
    if healCache[key] then return healCache[key], true end
    if healMiss[key] then return nil, true end
    return nil, false
end

local function CacheSet(key, heal)
    if heal then healCache[key] = heal else healMiss[key] = true end
    return heal
end

local function ScanItemHeal(itemID)
    local key = "item:" .. itemID
    local cached, hit = CacheGet(key)
    if hit then return cached end

    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = pcall(scanner.SetHyperlink, scanner, "item:" .. itemID)
    return CacheSet(key, ok and ParseHealFromScanner() or nil)
end

local function ScanSpellHeal(bookIndex, spellID)
    local key = "spell:" .. spellID
    local cached, hit = CacheGet(key)
    if hit then return cached end

    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = false
    if bookIndex then
        ok = pcall(scanner.SetSpellBookItem, scanner, bookIndex, "spell")
    end
    if not ok then
        local link = GetSpellLink and GetSpellLink(spellID)
        if link then ok = pcall(scanner.SetHyperlink, scanner, link) end
    end
    return CacheSet(key, ok and ParseHealFromScanner() or nil)
end

local function ScanInventoryHeal(slot)
    scanner:ClearLines()
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = pcall(scanner.SetInventoryItem, scanner, "player", slot)
    return ok and ParseHealFromScanner() or nil
end

-- Spells whose real value can't be read off a tooltip.
local SPECIAL_HEAL = {
    maxhealth = function() return UnitHealthMax("player") end,
    pct30     = function() return UnitHealthMax("player") * 0.30 end,
    pct35     = function() return UnitHealthMax("player") * 0.35 end,
}

-- ── Spellbook ────────────────────────────────────────────────────────
-- Walk the book once per SPELLS_CHANGED and keep the *highest* rank of each
-- name we care about. Later book entries are higher ranks, so last write wins.

local knownSpells = {}   -- [refSpellID] = { id, name, icon, bookIndex }

function ns.RefreshSpells()
    wipe(knownSpells)

    local wanted = {}    -- [localizedName] = refSpellID
    for _, s in ipairs(ns.SPELLS) do
        local name = GetSpellInfo(s.id)
        if name then wanted[name] = s.id end
    end

    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tab = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for i = offset + 1, offset + numSpells do
                local bookName = GetSpellBookItemName(i, "spell")
                local ref = bookName and wanted[bookName]
                if ref then
                    local _, id = GetSpellBookItemInfo(i, "spell")
                    local _, _, icon = GetSpellInfo(id or ref)
                    knownSpells[ref] = {
                        id        = id or ref,
                        name      = bookName,
                        icon      = icon,
                        bookIndex = i,
                    }
                end
            end
        end
    end
    ns.ClearHealCache()
end

-- ── Inventory ────────────────────────────────────────────────────────

local curated = {}       -- [itemID] = { category, heal }
do
    local function add(list, category)
        for _, e in ipairs(list) do
            curated[e.id] = { category = category, heal = e.heal }
        end
    end
    add(ns.HEALTHSTONES, "stones")
    add(ns.POTIONS,      "potions")
    add(ns.FOOD,         "food")
    add(ns.BANDAGES,     "bandages")
end
local healthstoneIDs = {}
for _, e in ipairs(ns.HEALTHSTONES) do healthstoneIDs[e.id] = true end

local function ClassifyDiscovered(itemID)
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if healthstoneIDs[itemID] then return "stones" end
    if itemType ~= "Consumable" then return nil end
    if itemSubType == "Bandage" then return "bandages" end
    if itemSubType == "Potion"  then return "potions"  end
    return "food"
end

local bagItems = {}      -- [itemID] = { bag, slot } of the first stack found

function ns.RefreshBags()
    wipe(bagItems)
    if not (GetContainerNumSlots and GetContainerItemID) then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local id = GetContainerItemID(bag, slot)
            if id and not bagItems[id] then
                bagItems[id] = { bag = bag, slot = slot }
            end
        end
    end
end

function ns.BagLocation(itemID)
    return bagItems[itemID]
end

-- ── Candidate list ───────────────────────────────────────────────────
--
-- An entry:
--   key       unique, stable, used for the per-entry enable state
--   kind      "spell" | "item" | "inventory"
--   category  one of ns.CATEGORIES
--   heal      estimated HP restored (0 if unknown)
--   macro     the line that goes into the button's macrotext

local function SpellCooldown(spellID)
    local start, duration, enabled = GetSpellCooldown(spellID)
    if enabled == 0 then return 0, 0, false end
    if start and duration and duration > GCD and start > 0 then
        return start, duration, false
    end
    return 0, 0, true
end

-- Falls back to the item's bag slot when the by-ID call is missing, and to
-- "ready" when neither exists -- a wrong-looking swipe beats erroring 10x a
-- second inside OnUpdate.
local function ItemCooldown(itemID)
    local start, duration, enabled
    if GetItemCooldown then
        start, duration, enabled = GetItemCooldown(itemID)
    elseif GetContainerItemCooldown then
        local loc = ns.BagLocation(itemID)
        if loc then
            start, duration, enabled = GetContainerItemCooldown(loc.bag, loc.slot)
        end
    end
    if not start then return 0, 0, true end
    if enabled == 0 then return 0, 0, false end
    if duration and duration > GCD and start > 0 then
        return start, duration, false
    end
    return 0, 0, true
end

local function InventoryCooldown(slot)
    if not GetInventoryItemCooldown then return 0, 0, true end
    local start, duration, enabled = GetInventoryItemCooldown("player", slot)
    if not start then return 0, 0, true end
    if enabled == 0 then return 0, 0, false end
    if start and duration and duration > GCD and start > 0 then
        return start, duration, false
    end
    return 0, 0, true
end

local function CollectSpells(out)
    for _, s in ipairs(ns.SPELLS) do
        local known = knownSpells[s.id]
        if known then
            local heal
            local fn = SPECIAL_HEAL[s.special]
            if fn then
                heal = fn()
            else
                heal = ScanSpellHeal(known.bookIndex, known.id)
            end
            out[#out + 1] = {
                key      = "spell:" .. s.id,
                kind     = "spell",
                category = "spells",
                id       = known.id,
                name     = known.name,
                icon     = known.icon,
                heal     = math.floor((heal or 0) + 0.5),
                count    = nil,
                macro    = "/cast " .. known.name,
            }
        end
    end
end

local function CollectItems(out)
    local db = ns.DB()
    local seen = {}

    local function consider(itemID, category, fallbackHeal)
        if seen[itemID] or ns.ITEM_BLACKLIST[itemID] then return end
        local count = (GetItemCount and GetItemCount(itemID)) or 0
        if count <= 0 then return end
        -- nil means not cached yet; only an explicit false is a real no. Done
        -- here rather than at annotate time so a level-gated item can't win
        -- its cooldown group and hide the lesser one you can actually drink.
        if IsUsableItem and IsUsableItem(itemID) == false then return end
        local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
        if not name then return end          -- not cached yet; next refresh picks it up
        local heal = ScanItemHeal(itemID) or fallbackHeal
        if not heal or heal <= 0 then return end
        seen[itemID] = true

        local prefix = (category == "bandages") and "/use [@player] " or "/use "
        out[#out + 1] = {
            key      = "item:" .. itemID,
            kind     = "item",
            category = category,
            id       = itemID,
            name     = name,
            icon     = icon,
            heal     = math.floor(heal + 0.5),
            count    = count,
            macro    = prefix .. name,
        }
    end

    for itemID, info in pairs(curated) do
        consider(itemID, info.category, info.heal)
    end

    if db.autoDiscover then
        for itemID in pairs(bagItems) do
            if not seen[itemID] and not curated[itemID] then
                local category = ClassifyDiscovered(itemID)
                if category then consider(itemID, category, nil) end
            end
        end
    end
end

local function CollectTrinkets(out)
    for _, slot in ipairs({ 13, 14 }) do
        local itemID = GetInventoryItemID and GetInventoryItemID("player", slot)
        if itemID and GetItemSpell and GetItemSpell(itemID) then
            local heal = ScanInventoryHeal(slot)
            if heal and heal > 0 then
                local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
                out[#out + 1] = {
                    key      = "inv:" .. slot,
                    kind     = "inventory",
                    category = "trinkets",
                    id       = slot,
                    itemID   = itemID,
                    name     = name or ("Trinket " .. slot),
                    icon     = icon,
                    heal     = heal,
                    macro    = "/use " .. slot,
                }
            end
        end
    end
end

-- Everything the character *could* use, ignoring enable state and cooldowns.
-- Config lists this; the button filters it down.
function ns.AllEntries()
    local out = {}
    CollectSpells(out)
    CollectItems(out)
    CollectTrinkets(out)
    return out
end

function ns.Cooldown(entry)
    if entry.kind == "spell" then
        return SpellCooldown(entry.id)
    elseif entry.kind == "inventory" then
        return InventoryCooldown(entry.id)
    end
    return ItemCooldown(entry.id)
end

-- Items in these categories share one cooldown with each other, so only the
-- best one is ever reachable -- using any healthstone puts every healthstone
-- down, and likewise for potions. Listing the rest implies a fallback that
-- doesn't exist, and worse, lets them eat slots in the macro chain that a
-- different category should have had.
--
-- Food is deliberately absent: tubers share with each other but Crystal
-- Restore and Fel Blossom don't obviously share with anything, and collapsing
-- them would hide a genuinely usable item. Spells and trinkets each carry
-- their own cooldown, so they never group.
local SHARED_COOLDOWN = { stones = true, potions = true, bandages = true }

local function GroupKey(e)
    if SHARED_COOLDOWN[e.category] then return "cd:" .. e.category end
    return e.key
end

-- The ordered, enabled list. Category order comes from config; within a
-- category we always sort by healing, strongest first.
function ns.BuildPriority()
    local db = ns.DB()
    local all = ns.AllEntries()

    local rank = {}
    for i, key in ipairs(db.categoryOrder) do rank[key] = i end

    local kept = {}
    for _, e in ipairs(all) do
        if db.categoryEnabled[e.category] and not db.disabled[e.key] and rank[e.category] then
            kept[#kept + 1] = e
        end
    end

    table.sort(kept, function(a, b)
        local ra, rb = rank[a.category], rank[b.category]
        if ra ~= rb then return ra < rb end
        if a.heal ~= b.heal then return a.heal > b.heal end
        return a.name < b.name
    end)

    -- Already sorted, so the first member of each cooldown group is its best.
    local best, out = {}, {}
    for _, e in ipairs(kept) do
        local g = GroupKey(e)
        local head = best[g]
        if head then
            head.alternatives = head.alternatives + 1
            head.groupMembers[#head.groupMembers + 1] = e
        else
            best[g] = e
            e.alternatives = 0
            e.groupMembers = {}
            e.groupKey = g
            out[#out + 1] = e
        end
    end
    return out
end

-- Annotate an existing priority list with live cooldown state and bag counts.
-- Kept separate from BuildPriority so the hot loop doesn't rebuild the whole
-- structure 10x a second -- that only happens when bags/spells/config change.
function ns.Annotate(list)
    local now = GetTime()
    for _, e in ipairs(list) do
        local start, duration, ready = ns.Cooldown(e)
        e.cdStart, e.cdDuration, e.ready = start, duration, ready
        e.remaining = ready and 0 or math.max(0, (start + duration) - now)
        if e.kind == "item" then
            e.count = (GetItemCount and GetItemCount(e.id)) or 0
            if e.count <= 0 then e.ready = false end
            -- nil means "item info not cached yet"; only false is a real no.
            if IsUsableItem and IsUsableItem(e.id) == false then e.ready = false end
        end
    end
    return list
end

-- Available first, then everything on cooldown, each group keeping priority
-- order. Both the flyout and the macro build from this, so what the button
-- shows and what it fires can't disagree.
function ns.SortForDisplay(list)
    local rank, out = {}, {}
    for i, e in ipairs(list) do
        rank[e] = i
        out[i] = e
    end
    table.sort(out, function(a, b)
        local ra, rb = a.ready and true or false, b.ready and true or false
        if ra ~= rb then return ra end
        return rank[a] < rank[b]
    end)

    -- Left-click fires items, so an item has to lead: the button's icon, the
    -- flyout header and the macro all read position 1, and they'd otherwise
    -- advertise a spell the left button won't cast. Spells stay in the list
    -- below, where right-click reaches them.
    if not ns.DB().chainAcross then
        for i, e in ipairs(out) do
            if e.kind ~= "spell" then
                if i > 1 then table.insert(out, 1, table.remove(out, i)) end
                break
            end
        end
    end
    return out
end

-- ── Secure macro ─────────────────────────────────────────────────────
--
-- The button is a SecureActionButton with type="macro". Its attributes are
-- locked while you're in combat, so we can't re-point it mid-fight -- instead
-- the macrotext holds a fallback chain. A `/cast` or `/use` whose subject is
-- on cooldown or missing fails silently and the next line runs, and because
-- consumables share the GCD in Classic only one line can actually fire.
-- Set chainDepth to 1 if you'd rather have strictly one action per click.

-- Above the guard threshold, spell lines get a [combat] conditional rather
-- than being dropped. Dropping them would be worse than useless: you're
-- almost always at full health when you pull, so the chain the fight starts
-- with would be the one *without* your cooldowns in it. [combat] keeps them
-- out of reach of an idle click while leaving them armed for the fight.
--
-- There is no health conditional in the macro language, so this is as close
-- as a secure button can get to reading your health.
local function SpellGuardActive()
    local pct = ns.DB().spellGuard or 100
    if pct >= 100 then return false end
    local max = UnitHealthMax("player") or 0
    if max <= 0 then return false end
    return (UnitHealth("player") / max) * 100 > pct
end

-- Split by kind, not by cooldown group. Each binding only has to be safe
-- *internally*, and both kinds already are: a spell's GCD blocks another
-- spell, and an item's cooldown blocks another item. It's only spell -> item
-- that crosses tracks and fires both. So left-click chains every item in
-- priority order -- stone, potion, tuber -- and right-click chains the spells.
-- One press each, no waste, and the item side is a genuine one-click button.
--
-- `filter` is "items", "spells", or nil for everything (panic mode).
local function MatchesFilter(e, filter)
    if filter == "spells" then return e.kind == "spell" end
    if filter == "items"  then return e.kind ~= "spell" end
    return true
end

function ns.BuildMacro(list, filter)
    local db = ns.DB()
    local depth = math.max(1, math.min(db.chainDepth or 3, 6))
    local guard = SpellGuardActive()

    local lines, budget = {}, MACRO_BUDGET
    for _, e in ipairs(list) do
        if #lines >= depth then break end
        if MatchesFilter(e, filter) then
            local line = e.macro
            if guard and e.kind == "spell" then
                line = (line:gsub("^/cast ", "/cast [combat] ", 1))
            end
            if #line + 1 <= budget then
                lines[#lines + 1] = line
                budget = budget - (#line + 1)
            end
        end
    end

    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

local lastMacro, lastAltMacro = nil, nil

-- Push the macro onto the secure button. No-ops during combat lockdown --
-- the chain built before the pull carries you through the fight.
function ns.ApplyMacro(button, list)
    if not button then return false end
    if InCombatLockdown() then return false end

    list = list or ns.SortForDisplay(ns.Annotate(ns.BuildPriority()))
    -- Panic mode ignores the split entirely and chains everything.
    local macro
    if ns.DB().chainAcross then
        macro = ns.BuildMacro(list)
    else
        macro = ns.BuildMacro(list, "items") or ns.BuildMacro(list, "spells")
    end
    local alt = ns.BuildMacro(list, "spells")
    if macro == lastMacro and alt == lastAltMacro then return true end
    lastMacro, lastAltMacro = macro, alt

    if macro then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", macro)
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
    end

    -- Right-click. Suffixed attributes take precedence over the bare ones for
    -- that button, so type/macrotext keep serving left-click untouched.
    if alt then
        button:SetAttribute("type2", "macro")
        button:SetAttribute("macrotext2", alt)
    else
        button:SetAttribute("type2", nil)
        button:SetAttribute("macrotext2", nil)
    end
    return true
end

function ns.CurrentMacro()
    return lastMacro, lastAltMacro
end

function ns.InvalidateMacro()
    lastMacro, lastAltMacro = nil, nil
end

-- ── Formatting helpers ───────────────────────────────────────────────

function ns.FormatHeal(n)
    if not n or n <= 0 then return "?" end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n + 0.5))
end

function ns.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
    end
    if seconds >= 10 then return string.format("%ds", math.floor(seconds)) end
    return string.format("%.1fs", seconds)
end

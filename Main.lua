-- HealPop entry point: event wiring, the throttled refresh loop, slash command.

local ADDON, ns = ...

BINDING_HEADER_HEALPOP = "HealPop"
_G["BINDING_NAME_CLICK HealPopButton:LeftButton"] = "Pop best heal"

local UPDATE_INTERVAL = 0.1

local priority = {}      -- structural list; rebuilt only when something changes
local dirty    = true
local ready    = false

function ns.RequestUpdate()
    dirty = true
end

local function Rebuild()
    ns.RefreshBags()
    priority = ns.BuildPriority()
    dirty = false
end

local driver = CreateFrame("Frame")
local acc = 0

driver:SetScript("OnUpdate", function(_, elapsed)
    if not ready then return end
    acc = acc + elapsed
    if acc < UPDATE_INTERVAL then return end
    acc = 0

    if dirty then Rebuild() end
    ns.Annotate(priority)
    local display = ns.SortForDisplay(priority)

    -- Write the macros first: the button face is drawn from the chains they
    -- record, so the other order paints last tick's bindings.
    ns.ApplyMacro(ns.ui.button, display)    -- no-ops while in combat lockdown
    ns.ui.Refresh(display)
end)

-- ── Events ───────────────────────────────────────────────────────────

local ev = CreateFrame("Frame")

-- Which of these exist varies by flavour (LEARNED_SPELL_IN_TAB and the talent
-- events aren't on every Classic client), so registration is best-effort.
local STRUCTURAL = {
    BAG_UPDATE_DELAYED          = true,
    SPELLS_CHANGED              = true,
    LEARNED_SPELL_IN_TAB        = true,
    PLAYER_EQUIPMENT_CHANGED    = true,
    PLAYER_LEVEL_UP             = true,
    ACTIVE_TALENT_GROUP_CHANGED = true,
    CHARACTER_POINTS_CHANGED    = true,
    UNIT_INVENTORY_CHANGED      = true,
}

local function TryRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ns.DB()
        ns.ui.Create()
        ns.CreateConfig()
        ns.RefreshSpells()
        Rebuild()
        ns.ApplyMacro(ns.ui.button, ns.SortForDisplay(priority))
        ready = true

        for name in pairs(STRUCTURAL) do TryRegister(self, name) end
        TryRegister(self, "PLAYER_REGEN_ENABLED")
        TryRegister(self, "GET_ITEM_INFO_RECEIVED")

        print("|cffFFD100HealPop|r loaded. |cffFFD100/healpop|r for options. "
            .. "Bind a key under Key Bindings \226\134\146 HealPop.")

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat lockdown just lifted; push the fresh chain, and re-apply any
        -- frame geometry that was skipped because the anchor is protected.
        ns.ui.ApplySize()
        ns.ui.ApplyPosition()
        ns.RequestUpdate()

    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- An item we skipped because the client hadn't cached it is now known,
        -- so retry the tooltip scans that came back empty.
        if ns.ClearHealMisses() then
            ns.RequestUpdate()
            ns.RefreshConfigEntries()
        end

    elseif STRUCTURAL[event] then
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "UNIT_INVENTORY_CHANGED" then
            ns.ClearHealCache()
        elseif event ~= "BAG_UPDATE_DELAYED" then
            ns.RefreshSpells()
        end
        ns.RequestUpdate()
        ns.RefreshConfigEntries()
    end
end)

-- ── Slash command ────────────────────────────────────────────────────

SLASH_HEALPOP1 = "/healpop"
SLASH_HEALPOP2 = "/hp"
SlashCmdList["HEALPOP"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "macro" then
        local macro, alt = ns.CurrentMacro()
        print("|cffFFD100HealPop|r macro (depth " .. (ns.DB().chainDepth or 3)
            .. ", " .. (ns.DB().chainAcross and "one-click, may spend extra"
            or "one action per click") .. "):")
        print("  left-click:\n" .. (macro or "  <empty>"))
        print("  right-click:\n" .. (alt or "  <empty>"))
    elseif msg == "debug" then
        -- Reads attributes back off the button rather than trusting our own
        -- cache, and toggles click tracing so a dead click can be located.
        local b = ns.ui.button
        local macro = tostring(b and b:GetAttribute("macrotext") or "<nil>")
        ns.debugClicks = not ns.debugClicks
        print("|cffFFD100HealPop|r debug:")
        print(string.format("  type=%s  type2=%s  clicksRegistered=%s",
            tostring(b and b:GetAttribute("type")),
            tostring(b and b:GetAttribute("type2")),
            tostring(b and b:IsMouseEnabled())))
        print(string.format("  editMode=%s  combat=%s",
            tostring(ns.editMode and true or false),
            tostring(InCombatLockdown())))
        print("  macrotext: |cff88ff88" .. (macro:gsub("\n", " | ")) .. "|r")
        print(string.format("  useKeyDown=%s",
            tostring(GetCVarBool and GetCVarBool("ActionButtonUseKeyDown"))))
        print("  click tracing " .. (ns.debugClicks and "|cff66cc66ON|r -- click the button now"
            or "|cffcc4444OFF|r"))
    elseif msg == "list" then
        -- The macro only shows the top few lines; this is the whole ranking.
        local list = ns.SortForDisplay(ns.Annotate(ns.BuildPriority()))
        local depth = math.max(1, math.min(ns.DB().chainDepth or 3, 6))
        print("|cffFFD100HealPop|r priority (" .. #list
            .. " usable; the macro fires #1 plus up to " .. (depth - 1)
            .. " sharing its cooldown):")
        for i, e in ipairs(list) do
            -- A not-ready entry with no time left is out of stock or blocked,
            -- not cooling down -- don't print a blank and call it a timer.
            local state
            if e.ready then
                state = "|cff66cc66ready|r"
            elseif e.remaining and e.remaining > 0 then
                state = "|cffcc8844" .. ns.FormatTime(e.remaining) .. "|r"
            else
                state = "|cffcc4444unavailable|r"
            end
            local alt = (e.alternatives or 0) > 0
                and string.format(" |cff777777(+%d sharing its cooldown)|r", e.alternatives) or ""
            print(string.format("  %s%d.|r %s%s  |cff888888[%s]|r  %s hp  %s",
                i == 1 and "|cffFFD100" or "|cff888888", i,
                e.name or "?", alt, e.category, ns.FormatHeal(e.heal), state))
        end
        local skipped = {}
        for _, cat in ipairs(ns.CATEGORIES) do
            if not ns.DB().categoryEnabled[cat.key] then
                skipped[#skipped + 1] = cat.label
            end
        end
        if #skipped > 0 then
            print("  |cff888888disabled categories: " .. table.concat(skipped, ", ") .. "|r")
        end
    else
        ns.ToggleConfig()
    end
end

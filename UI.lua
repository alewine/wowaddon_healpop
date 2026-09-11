-- HealPop UI: the secure one-click button plus the mouseover priority panel.
--
-- Layout note: the secure button can't be moved by us during combat, and a
-- click-to-use button that also drags eats clicks. So the movable thing is a
-- plain `anchor` frame; the secure button just fills it, and an insecure drag
-- overlay sits on top only while the frame is unlocked.

local ADDON, ns = ...

local GOLD   = { 1, 0.82, 0 }
local DIM    = { 0.72, 0.68, 0.60 }
local BG     = { 0.06, 0.05, 0.08 }

local CATEGORY_COLOR = {
    spells   = { 0.62, 0.51, 0.95 },
    stones   = { 0.88, 0.38, 0.36 },
    potions  = { 0.35, 0.75, 0.95 },
    trinkets = { 0.95, 0.76, 0.29 },
    food     = { 0.55, 0.80, 0.45 },
    bandages = { 0.85, 0.80, 0.70 },
}

local PANEL_WIDTH = 264
local ROW_HEIGHT  = 24

local ui = {}
ns.ui = ui

local function Backdrop(frame, r, g, b, a)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(r, g, b, a)
    frame:SetBackdropBorderColor(0, 0, 0, 0.9)
end

-- ── Panel ────────────────────────────────────────────────────────────
--
-- Display only. Rows were briefly SecureActionButtons so they could be
-- clicked, but protected frames can't be reassigned, shown, hidden or moved
-- during combat -- which would have frozen the ordering exactly when it
-- matters most. Live availability sorting is worth more than click-to-pick,
-- so rows are plain frames and re-sort freely mid-fight.
--
-- The top entry sits in the header as a readout of what the main button will
-- fire, with the rest of the list below it.

local MAX_ROWS  = 10
local LIST_TOP  = 56     -- first row's offset from the panel's top edge
local ROW_GAP   = 2
local HEADER_HEIGHT = 15
local HIDE_GRACE = 0.35  -- seconds of no-hover before the flyout closes

local function BuildRowWidgets(row, iconSize, fontSize)
    row.tag = row:CreateTexture(nil, "ARTWORK")
    row.tag:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.tag:SetSize(2, iconSize - 2)
    row.tag:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(iconSize, iconSize)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetPoint("LEFT", row.tag, "RIGHT", 5, 0)

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -76, 0)

    row.heal = row:CreateFontString(nil, "OVERLAY")
    row.heal:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "")
    row.heal:SetJustifyH("RIGHT")
    row.heal:SetPoint("RIGHT", row, "RIGHT", -38, 0)

    row.timer = row:CreateFontString(nil, "OVERLAY")
    row.timer:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "")
    row.timer:SetJustifyH("RIGHT")
    row.timer:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    -- A row can also render as a group heading. Reusing the row pool keeps
    -- the layout loop to one list rather than two interleaved ones.
    row.header = row:CreateFontString(nil, "OVERLAY")
    row.header:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    row.header:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    row.header:SetJustifyH("LEFT")
    row.header:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.header:Hide()
end

local function PaintHeader(row, text)
    row.tag:Hide()
    row.icon:SetTexture(nil)
    row.name:SetText("")
    row.heal:SetText("")
    row.timer:SetText("")
    row.header:SetText(text)
    row.header:Show()
end

local function PaintRow(row, e)
    if row.header then row.header:Hide() end
    if not e then
        row.tag:Hide()
        row.icon:SetTexture(nil)
        row.name:SetText("")
        row.heal:SetText("")
        row.timer:SetText("")
        return
    end
    row.tag:Show()
    local c = CATEGORY_COLOR[e.category] or DIM
    row.tag:SetVertexColor(c[1], c[2], c[3], 1)
    row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local label = e.name or "?"
    if e.count and e.count > 1 then label = label .. " x" .. e.count end
    if e.alternatives and e.alternatives > 0 then
        label = label .. " |cff777777+" .. e.alternatives .. "|r"
    end
    row.name:SetText(label)

    row.heal:SetText(ns.FormatHeal(e.heal))
    row.heal:SetTextColor(0.55, 0.85, 0.55, 1)

    if e.ready then
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1)
        row.name:SetTextColor(1, 1, 1, 1)
        row.timer:SetText("")
    else
        row.icon:SetDesaturated(true)
        row.icon:SetAlpha(0.5)
        row.name:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
        if e.remaining and e.remaining > 0 then
            row.timer:SetText(ns.FormatTime(e.remaining))
        else
            row.timer:SetText("")
        end
        row.timer:SetTextColor(0.95, 0.55, 0.35, 1)
    end
end

local function CreatePanel()
    local panel = CreateFrame("Frame", "HealPopPanel", ui.anchor, "BackdropTemplate")
    panel:SetWidth(PANEL_WIDTH)
    panel:SetHeight(80)
    panel:EnableMouse(false)
    panel:SetFrameStrata("HIGH")
    Backdrop(panel, BG[1], BG[2], BG[3], ns.DB().bgAlpha or 0.85)
    panel:Hide()
    ui.panel = panel

    panel.caption = panel:CreateFontString(nil, "OVERLAY")
    panel.caption:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    panel.caption:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    panel.caption:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -7)
    panel.caption:SetText("UP NEXT")

    panel.hint = panel:CreateFontString(nil, "OVERLAY")
    panel.hint:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    panel.hint:SetTextColor(DIM[1], DIM[2], DIM[3], 0.7)
    panel.hint:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -8)
    panel.hint:SetText("left-click")


    -- Primary readout: what the main button fires. Plain frame, no click.
    local primary = CreateFrame("Frame", nil, panel)
    primary:SetHeight(24)
    primary:SetPoint("TOPLEFT",  panel, "TOPLEFT",  8, -19)
    primary:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -19)
    primary.bg = primary:CreateTexture(nil, "BACKGROUND")
    primary.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    primary.bg:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.10)
    primary.bg:SetAllPoints(primary)
    BuildRowWidgets(primary, 20, 12)
    panel.primary = primary

    panel.rule = panel:CreateTexture(nil, "OVERLAY")
    panel.rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    panel.rule:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.30)
    panel.rule:SetHeight(1)
    panel.rule:SetPoint("TOPLEFT",  panel, "TOPLEFT",  10, -47)
    panel.rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -47)

    panel.rows = {}
    for i = 1, MAX_ROWS do
        local y = LIST_TOP + (i - 1) * (ROW_HEIGHT + ROW_GAP)
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT",  panel, "TOPLEFT",  8, -y)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -y)
        BuildRowWidgets(row, 18, 11)
        row:Hide()
        panel.rows[i] = row
    end

    panel.empty = panel:CreateFontString(nil, "OVERLAY")
    panel.empty:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    panel.empty:SetTextColor(0.85, 0.45, 0.35, 1)
    panel.empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -24)
    panel.empty:SetText("Nothing available.")
    panel.empty:Hide()

    -- Hover tracking has to span the button, the flyout, and the gap between
    -- them, so it polls rather than relying on OnLeave.
    panel:SetScript("OnUpdate", function(self, elapsed)
        if ns.DB().panelAlways then return end
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.1 then return end
        self.acc = 0
        local over = MouseIsOver(self)
            or (ui.button and MouseIsOver(ui.button))
            or (ui.drag and ui.drag:IsShown() and MouseIsOver(ui.drag))

        if over then
            self.lastOver = GetTime()
        elseif GetTime() - (self.lastOver or 0) > HIDE_GRACE then
            self:Hide()
        end
    end)

    return panel
end

function ui.ShowPanel()
    local panel = ui.panel
    if not panel then return end
    panel.lastOver = GetTime()
    panel:Show()
    ns.RequestUpdate()
end

function ui.AnchorPanel()
    local db = ns.DB()
    local panel, anchor = ui.panel, ui.anchor
    if not panel then return end
    panel:ClearAllPoints()
    local side, gap = db.panelSide or "RIGHT", 6
    if side == "LEFT" then
        panel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, 0)
    elseif side == "TOP" then
        panel:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
    elseif side == "BOTTOM" then
        panel:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    else
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", gap, 0)
    end
end

-- Left-click chains items, right-click chains spells (see Core.BuildMacro).
-- So the headline entry -- the icon, the big number, the gold row -- has to
-- be the best *item*, not the best thing overall: showing a spell there
-- would promise something a plain press cannot fire. In one-click mode the
-- two chains merge, so the global best is correct again.
function ns.PrimaryEntry(display)
    if not display or not display[1] then return nil end
    if ns.DB().chainAcross then return display[1] end
    for _, e in ipairs(display) do
        if e.kind ~= "spell" then return e end
    end
    return display[1]   -- spells only: nothing on the item side to prefer
end

function ui.UpdatePanel(display)
    local panel = ui.panel
    if not panel then return end
    local db = ns.DB()
    local maxRows = math.max(1, math.min(db.panelRows or 4, MAX_ROWS))

    local primary = ns.PrimaryEntry(display)
    PaintRow(panel.primary, primary)
    panel.primary:SetShown(primary ~= nil)
    panel.empty:SetShown(primary == nil)
    panel.hint:SetText(db.chainAcross and "one click: everything" or "left-click")

    -- Build a slot list first: entries, plus a heading where the chain the
    -- rows belong to changes. Without it the panel reads as one sequence
    -- when there are two, and you get rows the click above cannot reach.
    local slots = {}
    local budget = maxRows

    if db.chainAcross then
        for _, e in ipairs(display) do
            if budget <= 0 then break end
            if e ~= primary then
                slots[#slots + 1] = { entry = e }
                budget = budget - 1
            end
        end
    else
        for _, e in ipairs(display) do          -- rest of the left-click chain
            if budget <= 0 then break end
            if e ~= primary and e.kind ~= "spell" then
                slots[#slots + 1] = { entry = e }
                budget = budget - 1
            end
        end

        local spells = {}
        for _, e in ipairs(display) do
            if e ~= primary and e.kind == "spell" then spells[#spells + 1] = e end
        end
        if #spells > 0 and budget > 0 then
            slots[#slots + 1] = { header = "RIGHT-CLICK" }
            for _, e in ipairs(spells) do
                if budget <= 0 then break end
                slots[#slots + 1] = { entry = e }
                budget = budget - 1
            end
        end
    end

    -- Lay out sequentially: headings are shorter than entries, so fixed row
    -- positions would leave gaps.
    local y = LIST_TOP
    for i = 1, MAX_ROWS do
        local row, slot = panel.rows[i], slots[i]
        if not slot then
            row:Hide()
        else
            local height = slot.header and HEADER_HEIGHT or ROW_HEIGHT
            row:SetHeight(height)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  panel, "TOPLEFT",   8, -y)
            row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -y)
            if slot.header then PaintHeader(row, slot.header) else PaintRow(row, slot.entry) end
            row:Show()
            y = y + height + ROW_GAP
        end
    end

    if primary == nil then
        panel:SetHeight(46)
    else
        panel:SetHeight(y + 6)
    end
end

-- ── Button ───────────────────────────────────────────────────────────

-- The anchor parents a secure button, which makes the anchor protected too:
-- Show, Hide, SetPoint, SetSize and SetScale on it are all blocked during
-- combat. Everything here is cosmetic, so skipping it in combat costs nothing
-- and the next out-of-combat pass applies it.
local function AnchorShown(shown)
    if not ui.anchor or ui.anchor:IsShown() == shown then return end
    if InCombatLockdown() then return end
    if shown then ui.anchor:Show() else ui.anchor:Hide() end
end

local function ApplyButtonSize()
    if InCombatLockdown() then return end
    local db = ns.DB()
    local size = math.max(24, math.min(db.buttonSize or 48, 96))
    ui.anchor:SetSize(size, size)
    ui.button:SetSize(size, size)
    if ui.drag then ui.drag:SetSize(size, size) end
end

-- Edit mode is the options window being open -- there is no separate lock.
-- While it is open the drag overlay covers the secure button, which both
-- makes the button movable and stops it firing; the gold border says so.
function ui.UpdateLockVisuals()
    if ns.editMode then
        if ui.drag then ui.drag:Show() end
        ui.anchor:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    else
        if ui.drag then ui.drag:Hide() end
        ui.anchor:SetBackdropBorderColor(0.38, 0.38, 0.42, 0.6)
    end
end

function ui.ApplyPosition()
    if InCombatLockdown() then return end
    local db = ns.DB()
    ui.anchor:ClearAllPoints()
    ui.anchor:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    ui.anchor:SetScale(db.scale or 1.0)
end

function ui.ApplyScale()
    if InCombatLockdown() or not ui.anchor then return end
    ui.anchor:SetScale(ns.DB().scale or 1.0)
end

function ui.ApplyFont()
    local db = ns.DB()
    local face = ns.FONTS[db.fontFace or 1] or ns.FONTS[1]
    local text = ui.button and ui.button.healTag and ui.button.healTag.text
    if not text then return end
    if not text:SetFont(face.path, db.fontSize or 20, "OUTLINE") then
        text:SetFont(ns.FONTS[1].path, db.fontSize or 20, "OUTLINE")
    end
end

function ui.ApplyBgAlpha()
    local a = ns.DB().bgAlpha or 0.85
    -- The button's own backdrop is almost entirely hidden behind the icon, so
    -- the flyout is where this setting actually reads.
    ui.anchor:SetBackdropColor(BG[1], BG[2], BG[3], a)
    if ui.panel then ui.panel:SetBackdropColor(BG[1], BG[2], BG[3], a) end
end

function ui.Create()
    local db = ns.DB()

    local anchor = CreateFrame("Frame", "HealPopAnchor", UIParent, "BackdropTemplate")
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    Backdrop(anchor, BG[1], BG[2], BG[3], db.bgAlpha or 0.85)
    ui.anchor = anchor

    local button = CreateFrame("Button", "HealPopButton", anchor,
        "SecureActionButtonTemplate,BackdropTemplate")
    button:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    -- Both edges, matching Blizzard's own action buttons. Modern clients gate
    -- the secure action on the ActionButtonUseKeyDown cvar and silently drop
    -- the click that doesn't match -- which is why "AnyUp" alone fired
    -- PreClick and then did nothing. The gate is what makes registering both
    -- safe: only one edge ever reaches the action.
    button:RegisterForClicks("AnyUp", "AnyDown")
    ui.button = button

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexture("Interface\\Icons\\INV_Potion_54")

    button.cooldown = CreateFrame("Cooldown", "HealPopButtonCooldown", button,
        "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetDrawEdge(false)
    if button.cooldown.SetHideCountdownNumbers then
        button.cooldown:SetHideCountdownNumbers(false)
    end

    -- Count badge, on a child frame so the cooldown swipe can't cover it.
    local badge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    badge:SetSize(22, 16)
    badge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
    badge:SetFrameLevel(button:GetFrameLevel() + 8)
    badge:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    badge:SetBackdropColor(0, 0, 0, 0.88)
    badge:SetBackdropBorderColor(0, 0, 0, 0.95)
    badge:Hide()
    button.badge = badge

    badge.text = badge:CreateFontString(nil, "OVERLAY")
    badge.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    badge.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    badge.text:SetPoint("CENTER", badge, "CENTER", 0, 0)

    -- Healing estimate, centred over the icon and above the cooldown swipe
    -- for the same z-order reason as the count badge.
    local healTag = CreateFrame("Frame", nil, button)
    healTag:SetAllPoints(button)
    healTag:SetFrameLevel(button:GetFrameLevel() + 8)
    healTag.text = healTag:CreateFontString(nil, "OVERLAY")
    healTag.text:SetTextColor(0.62, 1.0, 0.62, 1)
    healTag.text:SetShadowColor(0, 0, 0, 1)
    healTag.text:SetShadowOffset(1, -1)
    healTag.text:SetJustifyH("CENTER")
    healTag.text:SetPoint("CENTER", healTag, "CENTER", 0, 0)
    button.healTag = healTag

    local function SaveAnchorPos()
        anchor:StopMovingOrSizing()
        local p, _, rp, x, y = anchor:GetPoint()
        local d = ns.DB()
        d.point, d.relPoint, d.x, d.y = p, rp, x, y
    end

    CreatePanel()
    ui.AnchorPanel()

    -- Move handle: the whole button, while the options window is open. A
    -- plain frame laid over the secure button, so it swallows the clicks that
    -- would otherwise fire a heal -- which is exactly what we want in edit
    -- mode, and why it only exists then.
    local drag = CreateFrame("Frame", nil, anchor)
    drag:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    drag:SetFrameLevel(button:GetFrameLevel() + 10)
    drag:EnableMouse(true)
    drag:Hide()
    ui.drag = drag

    drag.wash = drag:CreateTexture(nil, "OVERLAY")
    drag.wash:SetTexture("Interface\\Buttons\\WHITE8X8")
    drag.wash:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.18)
    drag.wash:SetAllPoints(drag)

    drag:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and not InCombatLockdown() then anchor:StartMoving() end
    end)
    drag:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then SaveAnchorPos() end
    end)

    -- Closing is handled by the panel's own hover poll rather than OnLeave,
    -- so crossing the gap between button and flyout doesn't dismiss it.
    -- Both surfaces need it: in edit mode the overlay is what's under the
    -- cursor, not the button.
    button:SetScript("OnEnter", ui.ShowPanel)
    drag:SetScript("OnEnter", ui.ShowPanel)

    -- Click tracing, off unless /hp debug turns it on. These two handlers
    -- split the failure: OnMouseDown proves the cursor is reaching the frame,
    -- PreClick proves the secure template dispatched. Neither replaces the
    -- secure OnClick -- overwriting that would break the action outright.
    button:SetScript("OnMouseDown", function(self, btn)
        if ns.debugClicks then
            print("|cffFFD100HealPop|r trace: OnMouseDown btn=" .. tostring(btn))
        end
    end)
    button:SetScript("PreClick", function(self, btn, down)
        if ns.debugClicks then
            print(string.format("|cffFFD100HealPop|r trace: PreClick btn=%s down=%s type=%s",
                tostring(btn), tostring(down), tostring(self:GetAttribute("type"))))
        end
    end)

    ApplyButtonSize()
    ui.ApplyFont()
    ui.ApplyBgAlpha()
    ui.ApplyPosition()
    ui.UpdateLockVisuals()
    if db.panelAlways and ui.panel then ui.panel:Show() end
end

function ui.ApplySize()
    ApplyButtonSize()
    ui.AnchorPanel()
end

-- Called from the throttled update loop with the ready-first sorted list.
function ui.Refresh(display)
    local button = ui.button
    if not button then return end
    local db = ns.DB()

    -- Sorted upstream in Core so the macro builds from the same order, and
    -- narrowed to the left-click chain here: the button can't show one thing
    -- and fire another.
    local show = ns.PrimaryEntry(display)

    if not show then
        if db.hideEmpty then
            AnchorShown(false)
            if ui.panel then ui.panel:Hide() end
            return
        end
        AnchorShown(true)
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        button.icon:SetDesaturated(true)
        button.icon:SetAlpha(0.5)
        button.badge:Hide()
        button.healTag.text:SetText("")
        button.cooldown:Clear()
    else
        AnchorShown(true)
        button.icon:SetTexture(show.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.icon:SetDesaturated(not show.ready)
        button.icon:SetAlpha(show.ready and 1 or 0.6)
        -- Blank rather than "?" when the value is unknown, and hidden while a
        -- cooldown runs: the cooldown frame -- or ElvUI/OmniCC text layered on
        -- it -- draws its countdown dead centre, exactly where this sits.
        local cooling = not show.ready and show.cdStart and show.cdStart > 0
        local known = show.heal and show.heal > 0
        button.healTag.text:SetText((known and not cooling) and ns.FormatHeal(show.heal) or "")

        if show.count and show.count > 1 then
            button.badge.text:SetText(show.count)
            button.badge:Show()
        else
            button.badge:Hide()
        end

        if show.ready then
            button.cooldown:Clear()
        else
            if show.cdStart and show.cdStart > 0 then
                button.cooldown:SetCooldown(show.cdStart, show.cdDuration)
            else
                button.cooldown:Clear()
            end
        end
    end

    ui.UpdatePanel(display)
end

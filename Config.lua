-- HealPop config window: category priority on the left, every entry this
-- character can actually use on the right, display settings underneath.

local ADDON, ns = ...

local GOLD = { 1, 0.82, 0 }
local DIM  = { 0.72, 0.68, 0.60 }

local CATEGORY_COLOR = {
    spells   = { 0.62, 0.51, 0.95 },
    stones   = { 0.88, 0.38, 0.36 },
    potions  = { 0.35, 0.75, 0.95 },
    trinkets = { 0.95, 0.76, 0.29 },
    food     = { 0.55, 0.80, 0.45 },
    bandages = { 0.85, 0.80, 0.70 },
}

local PANEL_SIDES = { "TOP", "RIGHT", "BOTTOM", "LEFT" }

-- Three columns: priority + toggles | sliders | the entry list.
local COL1_X, COL2_X, COL3_X = 14, 222, 418
local COL_TOP = -46

local config
local categoryRows = {}
local entryRows = {}
local RefreshCategories, RefreshEntries

local function CategoryLabel(key)
    for _, c in ipairs(ns.CATEGORIES) do
        if c.key == key then return c.label end
    end
    return key
end

local function Changed()
    ns.InvalidateMacro()
    ns.RequestUpdate()
end

local function MoveCategory(index, delta)
    local order = ns.DB().categoryOrder
    local target = index + delta
    if target < 1 or target > #order then return end
    order[index], order[target] = order[target], order[index]
    RefreshCategories()
    RefreshEntries()
    Changed()
end

-- ── Category priority rows ───────────────────────────────────────────

local function CreateCategoryRow(parent, i, anchorTo)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(186, 22)
    if i == 1 then
        row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
    else
        row:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -2)
    end

    row.tag = row:CreateTexture(nil, "ARTWORK")
    row.tag:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.tag:SetSize(3, 16)
    row.tag:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.check = CreateFrame("CheckButton", "HealPopCatCheck" .. i, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", row.tag, "RIGHT", 3, 0)
    row.check:SetScript("OnClick", function(self)
        local key = ns.DB().categoryOrder[i]
        ns.DB().categoryEnabled[key] = self:GetChecked() and true or false
        RefreshCategories()
        RefreshEntries()
        Changed()
    end)

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.label:SetJustifyH("LEFT")

    row.down = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.down:SetSize(20, 18)
    row.down:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.down:SetText("v")
    row.down:SetScript("OnClick", function() MoveCategory(i, 1) end)

    row.up = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.up:SetSize(20, 18)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.up:SetText("^")
    row.up:SetScript("OnClick", function() MoveCategory(i, -1) end)

    row.rank = row:CreateFontString(nil, "OVERLAY")
    row.rank:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    row.rank:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    row.rank:SetPoint("RIGHT", row.up, "LEFT", -6, 0)

    return row
end

function RefreshCategories()
    local db = ns.DB()
    for i, row in ipairs(categoryRows) do
        local key = db.categoryOrder[i]
        local enabled = db.categoryEnabled[key] and true or false
        local c = CATEGORY_COLOR[key] or DIM
        row.tag:SetVertexColor(c[1], c[2], c[3], enabled and 1 or 0.3)
        row.check:SetChecked(enabled)
        row.label:SetText(CategoryLabel(key))
        row.label:SetTextColor(enabled and 1 or 0.5, enabled and 1 or 0.5, enabled and 1 or 0.5, 1)
        row.rank:SetText(i)
        if i > 1 then row.up:Enable() else row.up:Disable() end
        if i < #db.categoryOrder then row.down:Enable() else row.down:Disable() end
    end
end

-- ── Entry list ───────────────────────────────────────────────────────

local function CreateEntryRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -(i - 1) * 20)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * 20)

    row.check = CreateFrame("CheckButton", "HealPopEntryCheck" .. i, row, "UICheckButtonTemplate")
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        if not row.entryKey then return end
        ns.DB().disabled[row.entryKey] = (not self:GetChecked()) or nil
        Changed()
    end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -46, 0)

    row.heal = row:CreateFontString(nil, "OVERLAY")
    row.heal:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    row.heal:SetJustifyH("RIGHT")
    row.heal:SetTextColor(0.55, 0.85, 0.55, 1)
    row.heal:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    -- Header variant: reuses the same row, hiding the widgets.
    row.header = row:CreateFontString(nil, "OVERLAY")
    row.header:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    row.header:SetJustifyH("LEFT")
    row.header:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.header:Hide()

    return row
end

function RefreshEntries()
    if not config or not config.entryContent then return end
    local db = ns.DB()

    -- Group by the current category order so the list mirrors real priority.
    local byCategory = {}
    for _, e in ipairs(ns.AllEntries()) do
        byCategory[e.category] = byCategory[e.category] or {}
        table.insert(byCategory[e.category], e)
    end
    for _, list in pairs(byCategory) do
        table.sort(list, function(a, b)
            if a.heal ~= b.heal then return a.heal > b.heal end
            return a.name < b.name
        end)
    end

    local flat = {}
    for _, key in ipairs(db.categoryOrder) do
        local list = byCategory[key]
        if list and #list > 0 then
            flat[#flat + 1] = { header = true, category = key }
            for _, e in ipairs(list) do flat[#flat + 1] = e end
        end
    end

    for i = #entryRows + 1, #flat do
        entryRows[i] = CreateEntryRow(config.entryContent, i)
    end

    for i, row in ipairs(entryRows) do
        local item = flat[i]
        if not item then
            row:Hide()
        else
            row:Show()
            if item.header then
                local c = CATEGORY_COLOR[item.category] or DIM
                row.header:SetText(CategoryLabel(item.category):upper())
                row.header:SetTextColor(c[1], c[2], c[3], 1)
                row.header:Show()
                row.check:Hide(); row.icon:Hide(); row.name:Hide(); row.heal:Hide()
                row.entryKey = nil
            else
                row.header:Hide()
                row.check:Show(); row.icon:Show(); row.name:Show(); row.heal:Show()
                row.entryKey = item.key
                row.check:SetChecked(not db.disabled[item.key])
                row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                local label = item.name or "?"
                if item.count and item.count > 1 then label = label .. " x" .. item.count end
                row.name:SetText(label)
                local catOn = db.categoryEnabled[item.category]
                row.name:SetTextColor(catOn and 1 or 0.5, catOn and 1 or 0.5, catOn and 1 or 0.5, 1)
                row.heal:SetText(ns.FormatHeal(item.heal))
            end
        end
    end

    config.entryContent:SetHeight(math.max(1, #flat * 20))
    config.entryEmpty:SetShown(#flat == 0)
end

-- ── Window ───────────────────────────────────────────────────────────

local function AddSlider(parent, name, anchor, gapX, gapY, label, minV, maxV, step, lowText, highText, onChange)
    local s = CreateFrame("Slider", "HealPopCfg" .. name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", gapX, gapY)
    s:SetSize(178, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    _G[s:GetName() .. "Low"]:SetText(lowText)
    _G[s:GetName() .. "High"]:SetText(highText)
    _G[s:GetName() .. "Text"]:SetText(label)
    s.labelText = label
    s:SetScript("OnValueChanged", function(self, value) onChange(self, value) end)
    return s
end

local function AddCheck(parent, name, anchor, gapY, label, get, set)
    local cb = CreateFrame("CheckButton", "HealPopCfg" .. name, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -2, gapY)
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb.get = get
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    return cb
end

function ns.CreateConfig()
    config = CreateFrame("Frame", "HealPopConfig", UIParent, "BackdropTemplate")
    config:SetSize(704, 480)
    config:SetPoint("CENTER")
    config:SetFrameStrata("DIALOG")
    config:SetMovable(true)
    config:EnableMouse(true)
    config:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    config:SetBackdropColor(0.09, 0.09, 0.10, 0.92)
    config:SetBackdropBorderColor(0.02, 0.02, 0.02, 0.95)
    config:Hide()
    config:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    config:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local d = ns.DB()
        local point, _, relPoint, x, y = self:GetPoint(1)
        d.cfgPoint, d.cfgRelPoint, d.cfgX, d.cfgY = point, relPoint, x, y
    end)
    ns.config = config
    -- Lets Escape close it, the same as any Blizzard dialog.
    tinsert(UISpecialFrames, "HealPopConfig")

    local title = config:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    title:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    title:SetShadowColor(0, 0, 0, 1)
    title:SetShadowOffset(1, -1)
    title:SetPoint("TOPLEFT", config, "TOPLEFT", 14, -14)
    title:SetText("HealPop")

    local subtitle = config:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    subtitle:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2)
    subtitle:SetText("ONE-CLICK PANIC BUTTON")

    local rule = config:CreateTexture(nil, "OVERLAY")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.35)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    rule:SetPoint("TOPRIGHT", config, "TOPRIGHT", -14, 0)

    local close = CreateFrame("Button", nil, config, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", config, "TOPRIGHT", -3, -3)

    -- Hairline gutters so the three columns read as columns.
    for _, x in ipairs({ COL2_X - 12, COL3_X - 12 }) do
        local gutter = config:CreateTexture(nil, "ARTWORK")
        gutter:SetTexture("Interface\\Buttons\\WHITE8X8")
        gutter:SetVertexColor(1, 1, 1, 0.08)
        gutter:SetWidth(1)
        gutter:SetPoint("TOPLEFT", config, "TOPLEFT", x, COL_TOP - 2)
        gutter:SetPoint("BOTTOMLEFT", config, "BOTTOMLEFT", x, 14)
    end

    -- Left column: priority ------------------------------------------
    local priHeader = config:CreateFontString(nil, "OVERLAY")
    priHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    priHeader:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    priHeader:SetPoint("TOPLEFT", config, "TOPLEFT", COL1_X, COL_TOP)
    priHeader:SetText("PRIORITY  (^ / v to reorder)")

    local prev = priHeader
    for i = 1, #ns.DEFAULT_CATEGORY_ORDER do
        categoryRows[i] = CreateCategoryRow(config, i, prev)
        prev = categoryRows[i]
    end

    -- Column 1 continued: toggles, kept with the priority list ---------
    local col1Rule = config:CreateTexture(nil, "OVERLAY")
    col1Rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    col1Rule:SetVertexColor(1, 1, 1, 0.10)
    col1Rule:SetHeight(1)
    col1Rule:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
    col1Rule:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -10)

    -- No lock checkbox: the button is unlocked exactly while this window is
    -- open (see the OnShow/OnHide pair below).
    config.always = AddCheck(config, "Always", col1Rule, -6, "Always show panel",
        function() return ns.DB().panelAlways end,
        function(v)
            ns.DB().panelAlways = v
            if ns.ui.panel then
                if v then ns.ui.panel:Show() else ns.ui.panel:Hide() end
            end
            ns.RequestUpdate()
        end)

    config.discover = AddCheck(config, "Discover", config.always, -4, "Auto-detect bag items",
        function() return ns.DB().autoDiscover end,
        function(v) ns.DB().autoDiscover = v; ns.ClearHealCache(); Changed(); RefreshEntries() end)

    config.hideEmpty = AddCheck(config, "HideEmpty", config.discover, -4, "Hide when nothing usable",
        function() return ns.DB().hideEmpty end,
        function(v) ns.DB().hideEmpty = v; ns.RequestUpdate() end)

    config.chainAcross = AddCheck(config, "ChainAcross", config.hideEmpty, -4,
        "One click, may spend extra",
        function() return ns.DB().chainAcross end,
        function(v) ns.DB().chainAcross = v; Changed() end)

    local reset = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    reset:SetSize(130, 20)
    reset:SetPoint("TOPLEFT", config.chainAcross, "BOTTOMLEFT", 4, -6)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function()
        local d = ns.DB()
        d.point, d.relPoint, d.x, d.y = "CENTER", "CENTER", 0, -140
        ns.ui.ApplyPosition()
    end)

    -- Column 2: display sliders ----------------------------------------
    local dispHeader = config:CreateFontString(nil, "OVERLAY")
    dispHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    dispHeader:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    dispHeader:SetPoint("TOPLEFT", config, "TOPLEFT", COL2_X, COL_TOP)
    dispHeader:SetText("DISPLAY")

    config.panelSide = CreateFrame("Frame", "HealPopCfgSide", config, "UIDropDownMenuTemplate")
    config.panelSide:SetPoint("TOPLEFT", dispHeader, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(config.panelSide, 130)
    UIDropDownMenu_Initialize(config.panelSide, function()
        for _, side in ipairs(PANEL_SIDES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = "Panel: " .. side:lower()
            info.checked = (ns.DB().panelSide == side)
            info.func    = function()
                ns.DB().panelSide = side
                UIDropDownMenu_SetText(config.panelSide, "Panel: " .. side:lower())
                ns.ui.AnchorPanel()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- UIDropDownMenuTemplate carries ~16px of invisible padding on its left.
    config.scale = AddSlider(config, "Scale", config.panelSide, 16, -22, "Scale",
        0.5, 2.0, 0.05, "0.5", "2.0", function(self, v)
            ns.DB().scale = v
            _G[self:GetName() .. "Text"]:SetText(string.format("Scale  %.2f", v))
            ns.ui.ApplyScale()
        end)

    config.size = AddSlider(config, "Size", config.scale, 0, -28, "Button size",
        24, 96, 2, "24", "96", function(self, v)
            ns.DB().buttonSize = v
            _G[self:GetName() .. "Text"]:SetText(string.format("Button size  %d", v))
            ns.ui.ApplySize()
        end)

    config.alpha = AddSlider(config, "Alpha", config.size, 0, -28, "Background opacity",
        0, 1, 0.05, "0%", "100%", function(self, v)
            ns.DB().bgAlpha = v
            _G[self:GetName() .. "Text"]:SetText(string.format("Background opacity  %d%%", v * 100))
            ns.ui.ApplyBgAlpha()
        end)

    config.rows = AddSlider(config, "Rows", config.alpha, 0, -28, "Panel rows",
        1, 10, 1, "1", "10", function(self, v)
            ns.DB().panelRows = math.floor(v)
            _G[self:GetName() .. "Text"]:SetText(string.format("Panel rows  %d", v))
            ns.RequestUpdate()
        end)

    config.chain = AddSlider(config, "Chain", config.rows, 0, -28, "Fallback depth",
        1, 6, 1, "1", "6", function(self, v)
            ns.DB().chainDepth = math.floor(v)
            _G[self:GetName() .. "Text"]:SetText(string.format("Fallback depth  %d", v))
            Changed()
        end)

    config.guard = AddSlider(config, "Guard", config.chain, 0, -28, "Spell guard",
        50, 100, 5, "50%", "off", function(self, v)
            ns.DB().spellGuard = math.floor(v)
            _G[self:GetName() .. "Text"]:SetText(v >= 100 and "Spell guard  off"
                or string.format("Spell guard  above %d%%", v))
            Changed()
        end)

    config.fontSize = AddSlider(config, "FontSize", config.guard, 0, -28, "Heal text size",
        8, 36, 1, "8", "36", function(self, v)
            ns.DB().fontSize = math.floor(v)
            _G[self:GetName() .. "Text"]:SetText(string.format("Heal text size  %d", v))
            ns.ui.ApplyFont()
        end)

    -- A dropdown rather than the slider that was asked for: a slider reading
    -- "3" tells you nothing about which face you're on, and the names are the
    -- whole point. Still updates the button the moment you pick one.
    config.fontFace = CreateFrame("Frame", "HealPopCfgFontFace", config, "UIDropDownMenuTemplate")
    config.fontFace:SetPoint("TOPLEFT", config.fontSize, "BOTTOMLEFT", -16, -24)
    UIDropDownMenu_SetWidth(config.fontFace, 130)
    UIDropDownMenu_Initialize(config.fontFace, function()
        for i, face in ipairs(ns.FONTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = face.name
            info.checked = (ns.DB().fontFace == i)
            info.func    = function()
                ns.DB().fontFace = i
                UIDropDownMenu_SetText(config.fontFace, face.name)
                ns.ui.ApplyFont()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    -- Column 3: everything this character can use ----------------------
    local entHeader = config:CreateFontString(nil, "OVERLAY")
    entHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    entHeader:SetTextColor(DIM[1], DIM[2], DIM[3], 1)
    entHeader:SetPoint("TOPLEFT", config, "TOPLEFT", COL3_X, COL_TOP)
    entHeader:SetText("AVAILABLE TO THIS CHARACTER")

    local box = CreateFrame("Frame", nil, config, "BackdropTemplate")
    box:SetPoint("TOPLEFT", entHeader, "BOTTOMLEFT", 0, -6)
    box:SetPoint("BOTTOMRIGHT", config, "BOTTOMRIGHT", -14, 14)
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0, 0, 0, 0.35)
    box:SetBackdropBorderColor(0, 0, 0, 0.9)

    local scroll = CreateFrame("ScrollFrame", "HealPopCfgScroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(math.max(1, scroll:GetWidth()), 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then content:SetWidth(w) end
    end)
    config.entryContent = content

    config.entryEmpty = box:CreateFontString(nil, "OVERLAY")
    config.entryEmpty:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    config.entryEmpty:SetTextColor(0.85, 0.45, 0.35, 1)
    config.entryEmpty:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -10)
    config.entryEmpty:SetText("No usable heals found.")
    config.entryEmpty:Hide()

    config:SetScript("OnShow", function()
        local d = ns.DB()

        config:ClearAllPoints()
        config:SetPoint(d.cfgPoint or "CENTER", UIParent,
            d.cfgRelPoint or "CENTER", d.cfgX or 0, d.cfgY or 0)

        UIDropDownMenu_SetText(config.panelSide, "Panel: " .. (d.panelSide or "RIGHT"):lower())
        config.scale:SetValue(d.scale or 1.0)
        config.size:SetValue(d.buttonSize or 48)
        config.alpha:SetValue(d.bgAlpha or 0.85)
        config.rows:SetValue(d.panelRows or 4)
        config.chain:SetValue(d.chainDepth or 3)
        config.guard:SetValue(d.spellGuard or 90)
        config.fontSize:SetValue(d.fontSize or 20)
        local face = ns.FONTS[d.fontFace or 1] or ns.FONTS[1]
        UIDropDownMenu_SetText(config.fontFace, face.name)
        for _, cb in ipairs({ config.always, config.discover,
                              config.hideEmpty, config.chainAcross }) do
            cb:SetChecked(cb.get() and true or false)
        end
        RefreshCategories()
        RefreshEntries()

        ns.editMode = true
        ns.ui.UpdateLockVisuals()
    end)

    config:SetScript("OnHide", function()
        ns.editMode = false
        ns.ui.UpdateLockVisuals()
    end)
end

function ns.ToggleConfig()
    if not config then return end
    if config:IsShown() then config:Hide() else config:Show() end
end

-- Keeps the checkboxes honest when something outside the window changes the
-- state they mirror.
function ns.RefreshConfigToggles()
    if not (config and config:IsShown()) then return end
    for _, cb in ipairs({ config.always, config.discover,
                          config.hideEmpty, config.chainAcross }) do
        cb:SetChecked(cb.get() and true or false)
    end
end

function ns.RefreshConfigEntries()
    if config and config:IsShown() then RefreshEntries() end
end

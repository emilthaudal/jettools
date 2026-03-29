-- JetTools Options Panel
-- Pure WoW API: left sidebar (module nav) + right scroll pane + Profiles tab
-- No external library dependencies.

local addonName, JT = ...

local optionsFrame = nil

-- Sentinel values for synthetic (multi-module) tabs
local PROFILES_TAB    = "Profiles"
local COMBAT_TAB      = "__Combat__"
local REMINDERS_TAB   = "__Reminders__"
local CHARACTER_TAB   = "__Character__"

-- Which real modules each synthetic tab aggregates (in display order)
local TAB_MODULES = {
    [COMBAT_TAB]    = { "CombatStatus", "CombatTimer", "CombatRes" },
    [REMINDERS_TAB] = { "PetReminders", "StealthReminder" },
    [CHARACTER_TAB] = { "CharacterSheet", "GearUpgradeRanks", "CharacterStatFormatting" },
}

-- Defined display order for modules in the sidebar (Profiles is last)
local MODULE_ORDER = {
    "RangeIndicator",
    "CurrentExpansionFilter",
    "AutoRoleQueue",
    CHARACTER_TAB,
    "CDMAuraRemover",
    "SlashCommands",
    COMBAT_TAB,
    REMINDERS_TAB,
    "BuffBarStyling",
    PROFILES_TAB,
}

-- Human-friendly display names for sidebar buttons
local MODULE_LABELS = {
    RangeIndicator          = "Range Indicator",
    CurrentExpansionFilter  = "Expansion Filter",
    AutoRoleQueue           = "Auto Role Queue",
    CDMAuraRemover          = "Aura Remover",
    SlashCommands           = "Slash Commands",
    BuffBarStyling          = "Buff Bar Styling",
    [CHARACTER_TAB]         = "Character",
    [COMBAT_TAB]            = "Combat",
    [REMINDERS_TAB]         = "Reminders",
    [PROFILES_TAB]          = "Profiles",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- StaticPopup dialogs
-- ─────────────────────────────────────────────────────────────────────────────

StaticPopupDialogs["JETTOOLS_COPY_PROFILE"] = {
    text = "Copy settings from '%s' into the current profile?\nThis will overwrite all current settings.",
    button1 = "Copy",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.sourceName then
            JT:CopyProfile(data.sourceName)
            if JT.RefreshProfilePane then
                JT.RefreshProfilePane()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["JETTOOLS_RESET_PROFILE"] = {
    text = "Reset the current profile to defaults?\nAll settings will be lost.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function(self, data)
        JT:ResetProfile()
        if JT.RefreshProfilePane then
            JT.RefreshProfilePane()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Pure WoW API widget helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Helper: fully override all Blizzard UIPanelButtonTemplate textures on a button
-- so none of the default red/orange artwork bleeds through in any state.
local function JT_StripButtonTextures(btn, normalColor, pushedColor, highlightColor)
    -- Override all four texture slots; leaving any nil lets Blizzard artwork show.
    btn:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    btn:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    btn:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")

    normalColor    = normalColor    or { 0.22, 0.22, 0.28 }
    pushedColor    = pushedColor    or { normalColor[1] * 0.7, normalColor[2] * 0.7, normalColor[3] * 0.7 }
    highlightColor = highlightColor or { normalColor[1] * 1.4, normalColor[2] * 1.4, normalColor[3] * 1.4 }

    btn:GetNormalTexture():SetVertexColor(normalColor[1], normalColor[2], normalColor[3])
    btn:GetPushedTexture():SetVertexColor(pushedColor[1], pushedColor[2], pushedColor[3])
    -- Highlight texture is additive-blend; keep it subtle
    local hl = btn:GetHighlightTexture()
    hl:SetVertexColor(highlightColor[1], highlightColor[2], highlightColor[3], 0.25)
    hl:SetBlendMode("ADD")
    btn:GetDisabledTexture():SetVertexColor(normalColor[1] * 0.5, normalColor[2] * 0.5, normalColor[3] * 0.5)
end

-- Styled button using WoW templates
local function JT_CreateButton(parent, text, width, height, style)
    width  = width  or 120
    height = height or 24
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, height)
    btn:SetText(text or "")

    -- Always strip all Blizzard artwork — pick colours based on style.
    if style == "red" then
        JT_StripButtonTextures(btn, { 0.55, 0.18, 0.18 }, { 0.4, 0.12, 0.12 }, { 0.9, 0.3, 0.3 })
    elseif style == "accent" then
        JT_StripButtonTextures(btn, { 0.20, 0.36, 0.65 }, { 0.14, 0.26, 0.48 }, { 0.35, 0.55, 1.0 })
    else
        -- Default neutral style — darker than sidebar so it's still distinguishable
        JT_StripButtonTextures(btn, { 0.22, 0.22, 0.28 }, { 0.14, 0.14, 0.18 }, { 0.35, 0.45, 0.65 })
    end

    -- Convenience: SetOnClick
    btn.SetOnClick = function(self, fn) self:SetScript("OnClick", fn) end
    return btn
end

-- Section header: colored label + horizontal line
local function JT_CreateHeader(parent, text, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 340, 20)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    label:SetText(text or "")
    label:SetTextColor(0.6, 0.8, 1)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    line:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    line:SetColorTexture(0.3, 0.5, 0.8, 0.6)

    return f
end

-- FontString label (style: "normal", "gray", "disabled")
local function JT_CreateFontString(parent, text, style)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text or "")
    if style == "gray" then
        fs:SetTextColor(0.7, 0.7, 0.7)
    elseif style == "disabled" then
        fs:SetTextColor(0.5, 0.5, 0.5)
        fs:SetFontObject("GameFontDisableSmall")
    end
    return fs
end

-- Checkbox with label to the right
local function JT_CreateCheckButton(parent, text, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    label:SetText(text or "")
    cb._label = label
    cb:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked()) end
    end)
    -- NOTE: CheckButton frames already have SetChecked built-in; no shim needed.
    return cb
end

-- Slider with title label and value display
local function JT_CreateSlider(parent, text, width, minVal, maxVal, step)
    width = width or 300
    -- Container: label (14px) + track (16px) + gap (4px) + value row (14px) = 48px
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 48)

    -- Label above
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(text or "")
    label:SetTextColor(0.9, 0.9, 0.9)

    -- Plain slider (no template) — avoids OptionsSliderTemplate's Low/High/Text
    -- children which fight with our own layout.
    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -16)
    slider:SetSize(width, 16)
    slider:SetMinMaxValues(minVal or 0, maxVal or 100)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)

    -- Track background
    local trackBg = slider:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Thumb texture (small bright nub)
    slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(8, 20)
    thumb:SetVertexColor(0.4, 0.6, 1, 1)

    -- Min/Max labels flanking the track
    local loLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loLabel:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    loLabel:SetText(tostring(minVal or 0))
    loLabel:SetTextColor(0.55, 0.55, 0.55)

    local hiLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hiLabel:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    hiLabel:SetText(tostring(maxVal or 100))
    hiLabel:SetTextColor(0.55, 0.55, 0.55)

    -- Current value centred below the track
    local valLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valLabel:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    valLabel:SetTextColor(0.9, 0.9, 0.9)

    local function UpdateVal(v)
        v = math.floor(v / (step or 1) + 0.5) * (step or 1)
        valLabel:SetText(tostring(v))
    end

    slider:SetScript("OnValueChanged", function(self, val)
        UpdateVal(val)
        if container._afterValueChanged then
            container._afterValueChanged(val)
        end
    end)

    container.slider = slider

    function container:SetValue(v)
        slider:SetValue(v)
        UpdateVal(v)
    end

    function container:SetAfterValueChanged(fn)
        self._afterValueChanged = fn
    end

    return container
end

-- EditBox with a label above
local function JT_CreateEditBox(parent, labelText, width, height)
    width  = width  or 200
    height = height or 28

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 4, height + 20)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(labelText or "")
    label:SetTextColor(0.9, 0.9, 0.9)

    local eb = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -18)
    eb:SetSize(width, height)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(64)

    container.editBox = eb

    function container:SetText(t)  eb:SetText(t or "") end
    function container:GetText()   return eb:GetText() end
    function container:SetOnTextChanged(fn)
        eb:SetScript("OnTextChanged", function(self, userInput)
            if userInput and fn then fn(self:GetText()) end
        end)
        eb:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
            if fn then fn(self:GetText()) end
        end)
    end

    return container
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Lightweight dropdown implementation
-- A button that shows a popup list. Stores selected value.
-- ─────────────────────────────────────────────────────────────────────────────

-- Shared popup frame (singleton, reused by all dropdowns)
local DropdownPopup = nil

local function GetDropdownPopup()
    if DropdownPopup then return DropdownPopup end

    local popup = CreateFrame("Frame", "JetToolsDropdownPopup", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(200)
    popup:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    popup:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    popup:SetBackdropBorderColor(0.3, 0.5, 0.8, 0.8)
    popup:Hide()

    popup._owner = nil

    -- Inner scroll frame that holds item rows
    local sf = CreateFrame("ScrollFrame", nil, popup)
    popup.scrollFrame = sf

    local sc = CreateFrame("Frame", nil, sf)
    sf:SetScrollChild(sc)
    popup.scrollContent = sc

    -- Scrollbar for the popup's item list — plain Slider, no template.
    -- UIPanelScrollBarTemplate fires OnValueChanged during SetValue(0) before
    -- our scroll frame is linked, causing a SecureScrollTemplates crash.
    local bar = CreateFrame("Slider", nil, popup)
    popup.scrollBar = bar
    bar:SetOrientation("VERTICAL")
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetValueStep(20)
    bar:SetObeyStepOnDrag(true)

    -- Track background
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.08, 0.08, 0.08, 1)

    -- Thumb
    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(6, 30)
    thumb:SetVertexColor(0.35, 0.55, 0.9, 0.9)

    bar:SetScript("OnValueChanged", function(self, val)
        sf:SetVerticalScroll(val)
    end)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local cur = bar:GetValue()
        local mn, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(mn, math.min(mx, cur - delta * 20)))
    end)

    popup:SetScript("OnHide", function(self)
        self._owner = nil
        -- Clear item rows so they don't leak between dropdowns
        local children = { self.scrollContent:GetChildren() }
        for _, c in ipairs(children) do c:Hide() end
    end)

    -- Close when clicking outside
    popup:SetScript("OnUpdate", function(self)
        if not self:IsShown() then return end
        if IsMouseButtonDown("LeftButton") then
            local x, y = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local l, b, w, h = self:GetRect()
            if l and not (x/scale >= l and x/scale <= l+w and y/scale >= b and y/scale <= b+h) then
                self:Hide()
            end
        end
    end)

    DropdownPopup = popup
    return popup
end

local function JT_CreateDropdown(parent, width, maxVisible)
    width      = width      or 200
    maxVisible = maxVisible or 8

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 28)

    -- Label above the button
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 14)
    label:SetTextColor(0.9, 0.9, 0.9)
    container._label = label

    -- Main dropdown button — strip ALL Blizzard artwork to prevent red/orange bleed
    local btn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    btn:SetSize(width, 22)
    btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    btn:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
    btn:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
    btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    btn:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")
    btn:GetNormalTexture():SetVertexColor(0.25, 0.25, 0.35)
    btn:GetPushedTexture():SetVertexColor(0.17, 0.17, 0.24)
    local ddHl = btn:GetHighlightTexture()
    ddHl:SetVertexColor(0.40, 0.55, 0.90, 0.20)
    ddHl:SetBlendMode("ADD")
    btn:GetDisabledTexture():SetVertexColor(0.15, 0.15, 0.20)

    -- Selected value text inside the button (left-aligned)
    local selText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selText:SetPoint("LEFT", btn, "LEFT", 6, 0)
    selText:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    selText:SetJustifyH("LEFT")
    selText:SetText("--")
    btn._selText = selText

    -- Arrow indicator — use a WoW texture atlas arrow to avoid font glyph gaps
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 8)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetTexCoord(0, 1, 0, 0.5)
    arrow:SetVertexColor(0.7, 0.7, 0.7)

    container._items    = {}
    container._selected = nil
    container._onSelect = nil

    function container:SetLabel(text)
        label:SetText(text or "")
    end

    function container:SetItems(items)
        self._items = items or {}
    end

    function container:SetSelectedValue(value)
        self._selected = value
        for _, item in ipairs(self._items) do
            if item.value == value then
                selText:SetText(item.text or tostring(value))
                return
            end
        end
        selText:SetText(value ~= nil and tostring(value) or "--")
    end

    function container:GetSelectedValue()
        return self._selected
    end

    function container:SetOnSelect(fn)
        self._onSelect = fn
    end

    btn:SetScript("OnClick", function()
        local popup = GetDropdownPopup()

        -- Toggle: close if already open for this dropdown
        if popup:IsShown() and popup._owner == container then
            popup:Hide()
            return
        end

        popup._owner = container

        local items      = container._items
        local itemH      = 20
        local visCount   = math.min(#items, maxVisible)
        local needsBar   = #items > maxVisible
        local barW       = needsBar and 16 or 0
        local popW       = width
        local popH       = visCount * itemH + 4

        -- Layout scroll frame and bar inside popup
        local sf  = popup.scrollFrame
        local sc  = popup.scrollContent
        local bar = popup.scrollBar

        popup:SetSize(popW, popH)

        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     1, -1)
        sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -(1 + barW), 1)

        sc:SetWidth(popW - 2 - barW)
        sc:SetHeight(#items * itemH)

        local scrollRange = math.max(0, #items * itemH - (popH - 2))
        bar:SetMinMaxValues(0, scrollRange)
        bar:SetValue(0)
        sf:SetVerticalScroll(0)

        if needsBar then
            bar:ClearAllPoints()
            bar:SetPoint("TOPRIGHT",    popup, "TOPRIGHT",    -1, -1)
            bar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -1,  1)
            bar:Show()
        else
            bar:Hide()
        end

        -- Hide all existing item rows (they may belong to a prior dropdown)
        local existing = { sc:GetChildren() }
        for _, c in ipairs(existing) do c:Hide() end

        -- Create or reuse item row buttons (keyed in popup._rows)
        popup._rows = popup._rows or {}
        for i = #popup._rows + 1, #items do
            local b = CreateFrame("Button", nil, sc)
            b:SetHeight(itemH)
            local bText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            bText:SetPoint("LEFT", b, "LEFT", 8, 0)
            bText:SetJustifyH("LEFT")
            b._text = bText

            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.3, 0.5, 0.8, 0.25)

            popup._rows[i] = b
        end

        -- Populate rows for the current container's items
        for idx, item in ipairs(items) do
            local b = popup._rows[idx]
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -((idx-1) * itemH))
            b:SetWidth(sc:GetWidth())
            b._text:SetText(item.text or tostring(item.value))
            b._text:SetTextColor(
                item.value == container._selected and 0.4 or 0.9,
                item.value == container._selected and 0.8 or 0.9,
                item.value == container._selected and 1.0 or 0.9
            )
            b:Show()

            -- Always assign a fresh OnClick — this is critical so rows point to
            -- the currently-open container's selText, not a stale closure.
            local capturedItem      = item
            local capturedContainer = container
            local capturedSelText   = selText
            b:SetScript("OnClick", function()
                capturedContainer._selected = capturedItem.value
                capturedSelText:SetText(capturedItem.text or tostring(capturedItem.value))
                popup:Hide()
                if capturedContainer._onSelect then
                    capturedContainer._onSelect(capturedItem.value)
                end
            end)
        end

        -- Position popup below button
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        popup:Show()
    end)

    return container
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Scroll frame helper
-- Returns a frame with a .scrollContent child that grows vertically.
-- Exposes :SetContentHeight(h) and :ResetScroll()
-- ─────────────────────────────────────────────────────────────────────────────

local function JT_CreateScrollFrame(parent, width, height)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetSize(width, height)
    scrollFrame:EnableMouse(true)
    scrollFrame:EnableMouseWheel(true)

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(width, height)
    scrollFrame:SetScrollChild(content)
    scrollFrame.scrollContent = content

    -- Scrollbar — plain Slider (no template) to avoid SecureScrollTemplates
    -- firing SetVerticalScroll during construction before the link is set up.
    local bar = CreateFrame("Slider", nil, scrollFrame)
    bar:SetOrientation("VERTICAL")
    bar:SetPoint("TOPRIGHT",    scrollFrame, "TOPRIGHT",    0, 0)
    bar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)
    bar:SetWidth(8)

    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.08, 0.08, 0.15, 0.8)

    bar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(6, 40)
    thumb:SetVertexColor(0.35, 0.55, 0.9, 0.85)

    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetValueStep(20)
    bar:SetObeyStepOnDrag(true)
    bar:Hide()

    bar:SetScript("OnValueChanged", function(self, val)
        scrollFrame:SetVerticalScroll(val)
    end)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = bar:GetValue()
        local min, max = bar:GetMinMaxValues()
        local new = math.max(min, math.min(max, current - delta * 40))
        bar:SetValue(new)
    end)

    function scrollFrame:SetContentHeight(h)
        content:SetHeight(math.max(h, height))
        local scrollRange = math.max(0, h - height)
        bar:SetMinMaxValues(0, scrollRange)
        if bar:GetValue() > scrollRange then
            bar:SetValue(scrollRange)
        end
        -- Hide the scrollbar entirely when there is nothing to scroll
        if scrollRange == 0 then
            bar:Hide()
        else
            bar:Show()
        end
    end

    function scrollFrame:ResetScroll()
        bar:SetValue(0)
        self:SetVerticalScroll(0)
    end

    return scrollFrame
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function ClearFrame(parent)
    local children = { parent:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        -- Do NOT SetParent(nil) — in modern WoW that reparents to WorldFrame
        -- instead of destroying the frame. Hiding is sufficient; frames are
        -- recreated fresh on the next PopulateModulePane call.
    end
    local regions = { parent:GetRegions() }
    for _, region in ipairs(regions) do
        region:Hide()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Option control builder
-- ─────────────────────────────────────────────────────────────────────────────

local CONTENT_WIDTH = 340
local LEFT_PAD      = 12
local INDENT        = 16

local groupState = {}

local function BuildOptionControl(parent, moduleName, schema, yOffset)
    local schemaType = schema.type
    local key        = schema.key

    local currentValue = schema.default
    if key then
        local settings = JT:GetModuleSettings(moduleName)
        if settings and settings[key] ~= nil then
            currentValue = settings[key]
        end
    end

    if schemaType == "header" then
        local pane = JT_CreateHeader(parent, schema.label, CONTENT_WIDTH)
        pane:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD, yOffset)
        return yOffset - 30

    elseif schemaType == "subheader" then
        local fs = JT_CreateFontString(parent, schema.label, "gray")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
        return yOffset - 22

    elseif schemaType == "description" then
        local fs = JT_CreateFontString(parent, schema.text, "disabled")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
        fs:SetWidth(CONTENT_WIDTH - INDENT)
        fs:SetJustifyH("LEFT")
        local h = math.max(fs:GetStringHeight(), 18)
        return yOffset - h - 8

    elseif schemaType == "checkbox" then
        local onChange
        if key == "enabled" then
            onChange = function(checked)
                JT:SetModuleEnabled(moduleName, checked)
            end
        else
            onChange = function(checked)
                JT:SetModuleSetting(moduleName, key, checked)
            end
        end

        local indent = (key == "enabled") and 0 or INDENT
        local cb = JT_CreateCheckButton(parent, schema.label, function(checked)
            onChange(checked)
        end)
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + indent, yOffset)
        cb:SetChecked(currentValue)
        return yOffset - 28

    elseif schemaType == "slider" then
        local slider = JT_CreateSlider(parent, schema.label, CONTENT_WIDTH - INDENT,
            schema.min, schema.max, schema.step)
        slider:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
        slider:SetValue(currentValue)
        slider:SetAfterValueChanged(function(val)
            JT:SetModuleSetting(moduleName, key, val)
        end)
        return yOffset - 62   -- 48px container + 14px bottom gap

    elseif schemaType == "input" then
        local editBox = JT_CreateEditBox(parent, schema.label,
            schema.width or (CONTENT_WIDTH - INDENT), 24)
        editBox:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
        editBox:SetText(currentValue or "")
        editBox:SetOnTextChanged(function(text)
            JT:SetModuleSetting(moduleName, key, text)
        end)
        return yOffset - 58   -- ~48px container + 10px bottom gap

    elseif schemaType == "dropdown" then
        local items = {}
        if type(schema.options) == "table" then
            local first = schema.options[1]
            if type(first) == "table" and first.text ~= nil then
                -- Already {text, value} pairs — use directly
                items = schema.options
            elseif first ~= nil then
                -- Plain string/value array — wrap each entry
                for _, v in ipairs(schema.options) do
                    table.insert(items, { text = tostring(v), value = v })
                end
            else
                -- Key→label map (no numeric index)
                for v, label in pairs(schema.options) do
                    table.insert(items, { text = label, value = v })
                end
            end
        end

        -- The dropdown label FontString is anchored 14px ABOVE the container top.
        -- Shift the container down by 14px so the label sits inside the allotted space.
        local dd = JT_CreateDropdown(parent, schema.width or (CONTENT_WIDTH - INDENT), 8)
        dd:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset - 14)
        dd:SetLabel(schema.label)
        dd:SetItems(items)
        dd:SetOnSelect(function(value)
            JT:SetModuleSetting(moduleName, key, value)
        end)
        dd:SetSelectedValue(currentValue)
        return yOffset - 14 - 28 - 12   -- label(14) + button(28) + gap(12)

    elseif schemaType == "button" then
        local btn = JT_CreateButton(parent, schema.label, schema.width or 120, 24, "accent")
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
        btn:SetOnClick(schema.func)
        return yOffset - 36

    elseif schemaType == "color" then
        -- Color swatch button that opens the WoW color picker
        local swatch = CreateFrame("Button", nil, parent)
        swatch:SetSize(24, 24)
        swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)

        local swatchTex = swatch:CreateTexture(nil, "BACKGROUND")
        swatchTex:SetAllPoints()
        if currentValue then
            swatchTex:SetColorTexture(currentValue.r or 1, currentValue.g or 1,
                currentValue.b or 1, 1)
        else
            swatchTex:SetColorTexture(1, 1, 1, 1)
        end

        local colorLabel = JT_CreateFontString(parent, schema.label, "normal")
        colorLabel:SetPoint("LEFT", swatch, "RIGHT", 6, 0)

        swatch:SetScript("OnClick", function()
            local r = currentValue and currentValue.r or 1
            local g = currentValue and currentValue.g or 1
            local b = currentValue and currentValue.b or 1
            local a = currentValue and (currentValue.a or 1) or 1

            local function onChange()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = 1 - OpacitySliderFrame:GetValue()
                currentValue = { r = nr, g = ng, b = nb, a = na }
                swatchTex:SetColorTexture(nr, ng, nb, 1)
                JT:SetModuleSetting(moduleName, key, currentValue)
            end

            local info = {
                r = r, g = g, b = b,
                opacity = 1 - a,
                hasOpacity = true,
                swatchFunc = onChange,
                opacityFunc = onChange,
                cancelFunc = function()
                    swatchTex:SetColorTexture(r, g, b, 1)
                    JT:SetModuleSetting(moduleName, key, { r = r, g = g, b = b, a = a })
                end,
            }
            ColorPickerFrame:SetupColorPickerAndShow(info)
        end)

        return yOffset - 36

    elseif schemaType == "group" then
        local groupKey = moduleName .. ":" .. (schema.label or "")
        if groupState[groupKey] == nil then
            groupState[groupKey] = schema.expanded ~= false
        end

        local isExpanded = groupState[groupKey]
        local toggleLabel = (isExpanded and "- " or "+ ") .. (schema.label or "Group")

        local groupBtn = JT_CreateButton(parent, toggleLabel, CONTENT_WIDTH - INDENT, 24, nil)
        groupBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_PAD, yOffset)
        yOffset = yOffset - 30

        if isExpanded and schema.children then
            for _, child in ipairs(schema.children) do
                yOffset = BuildOptionControl(parent, moduleName, child, yOffset)
            end
        end

        groupBtn:SetOnClick(function()
            groupState[groupKey] = not groupState[groupKey]
            if JT._requestOptionsRepopulate then
                JT._requestOptionsRepopulate()
            end
        end)

        return yOffset
    end

    return yOffset
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Profile pane
-- ─────────────────────────────────────────────────────────────────────────────

JT.RefreshProfilePane = nil

local function PopulateProfilePane(scrollParent)
    local scrollContent = scrollParent.scrollContent
    ClearFrame(scrollContent)

    local yOffset = -8

    -- Active Profile
    local profileHeader = JT_CreateHeader(scrollContent, "Profile", CONTENT_WIDTH)
    profileHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD, yOffset)
    yOffset = yOffset - 36

    local profileItems = {}
    for _, name in ipairs(JT:GetProfileNames()) do
        table.insert(profileItems, { text = name, value = name })
    end

    local profileDD = JT_CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT, 10)
    profileDD:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    profileDD:SetLabel("Active Profile")
    profileDD:SetItems(profileItems)
    profileDD:SetSelectedValue(JT:GetActiveProfileName())
    profileDD:SetOnSelect(function(value)
        JT:SetActiveProfile(value)
        PopulateProfilePane(scrollParent)
    end)
    yOffset = yOffset - 52

    -- Spec Overrides
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    if numSpecs > 0 then
        yOffset = yOffset - 4
        local specHeader = JT_CreateHeader(scrollContent, "Spec-Specific Profiles", CONTENT_WIDTH)
        specHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD, yOffset)
        yOffset = yOffset - 36

        local specProfileItems = { { text = "None (use character profile)", value = "" } }
        for _, name in ipairs(JT:GetProfileNames()) do
            table.insert(specProfileItems, { text = name, value = name })
        end

        for i = 1, numSpecs do
            local specId, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(i)
            if specId then
                local iconStr = specIcon and ("|T" .. specIcon .. ":16:16:0:0|t ") or ""
                local specLabel = iconStr .. (specName or ("Spec " .. i))

                local specDD = JT_CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT, 10)
                specDD:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
                specDD:SetLabel(specLabel)
                specDD:SetItems(specProfileItems)

                local currentOverride = JT:GetSpecProfileName(i) or ""
                specDD:SetSelectedValue(currentOverride)

                local specIndex = i
                specDD:SetOnSelect(function(value)
                    if value == "" then
                        JT:ClearSpecProfile(specIndex)
                    else
                        JT:SetSpecProfile(specIndex, value)
                    end
                end)
                yOffset = yOffset - 52
            end
        end
    end

    -- New Profile
    yOffset = yOffset - 4
    local newHeader = JT_CreateHeader(scrollContent, "New Profile", CONTENT_WIDTH)
    newHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD, yOffset)
    yOffset = yOffset - 36

    local newDesc = JT_CreateFontString(scrollContent,
        "Creates a new profile starting from default settings.", "disabled")
    newDesc:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    newDesc:SetWidth(CONTENT_WIDTH - INDENT)
    newDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 26

    local newEditBox = JT_CreateEditBox(scrollContent, "Profile Name",
        CONTENT_WIDTH - INDENT - 80 - 8, 24)
    newEditBox:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)

    local createBtn = JT_CreateButton(scrollContent, "Create", 80, 24, "accent")
    createBtn:SetPoint("LEFT", newEditBox, "RIGHT", 8, -18)
    createBtn:SetOnClick(function()
        local name = newEditBox:GetText()
        if not name or name == "" then return end
        if JT:CreateProfile(name) then
            JT:SetActiveProfile(name)
            PopulateProfilePane(scrollParent)
        else
            print("|cff00aaffJetTools|r: Profile '" .. name .. "' already exists.")
        end
    end)
    yOffset = yOffset - 50

    -- Copy From
    yOffset = yOffset - 4
    local copyHeader = JT_CreateHeader(scrollContent, "Copy From", CONTENT_WIDTH)
    copyHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD, yOffset)
    yOffset = yOffset - 36

    local copyDesc = JT_CreateFontString(scrollContent,
        "Overwrites the current profile settings with those from another profile.", "disabled")
    copyDesc:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    copyDesc:SetWidth(CONTENT_WIDTH - INDENT)
    copyDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 26

    local activeName = JT:GetActiveProfileName()
    local copyItems = {}
    for _, name in ipairs(JT:GetProfileNames()) do
        if name ~= activeName then
            table.insert(copyItems, { text = name, value = name })
        end
    end

    local copyDD = JT_CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT - 80 - 8, 10)
    copyDD:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    copyDD:SetItems(copyItems)
    if copyItems[1] then copyDD:SetSelectedValue(copyItems[1].value) end

    local copyBtn = JT_CreateButton(scrollContent, "Copy", 80, 24, "accent")
    copyBtn:SetPoint("LEFT", copyDD, "RIGHT", 8, 0)
    copyBtn:SetOnClick(function()
        local selectedValue = copyDD:GetSelectedValue()
        if not selectedValue or selectedValue == "" then
            if copyItems[1] then selectedValue = copyItems[1].value else return end
        end
        local dialog = StaticPopup_Show("JETTOOLS_COPY_PROFILE", selectedValue)
        if dialog then
            dialog.data = { sourceName = selectedValue }
        end
    end)
    yOffset = yOffset - 36

    -- Reset Profile
    yOffset = yOffset - 4
    local resetHeader = JT_CreateHeader(scrollContent, "Reset Profile", CONTENT_WIDTH)
    resetHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD, yOffset)
    yOffset = yOffset - 36

    local resetDesc = JT_CreateFontString(scrollContent,
        "Resets the current profile (\"" .. activeName .. "\") back to default settings.", "disabled")
    resetDesc:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    resetDesc:SetWidth(CONTENT_WIDTH - INDENT)
    resetDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 26

    local resetBtn = JT_CreateButton(scrollContent, "Reset to Defaults", 160, 24, "red")
    resetBtn:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    resetBtn:SetOnClick(function()
        StaticPopup_Show("JETTOOLS_RESET_PROFILE")
    end)
    yOffset = yOffset - 36

    -- Delete Profile
    yOffset = yOffset - 4
    local deleteHeader = JT_CreateHeader(scrollContent, "Delete Profile", CONTENT_WIDTH)
    deleteHeader:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD, yOffset)
    yOffset = yOffset - 36

    local deleteDesc = JT_CreateFontString(scrollContent,
        "Permanently delete a profile. Cannot delete 'Default' or the active profile.", "disabled")
    deleteDesc:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    deleteDesc:SetWidth(CONTENT_WIDTH - INDENT)
    deleteDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 36

    local deleteItems = {}
    for _, name in ipairs(JT:GetProfileNames()) do
        if name ~= "Default" and name ~= activeName then
            table.insert(deleteItems, { text = name, value = name })
        end
    end

    local deleteDD = JT_CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT - 80 - 8, 10)
    deleteDD:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", LEFT_PAD + INDENT, yOffset)
    deleteDD:SetItems(deleteItems)
    if deleteItems[1] then deleteDD:SetSelectedValue(deleteItems[1].value) end

    local deleteBtn = JT_CreateButton(scrollContent, "Delete", 80, 24, "red")
    deleteBtn:SetPoint("LEFT", deleteDD, "RIGHT", 8, 0)
    deleteBtn:SetOnClick(function()
        local selectedValue = deleteDD:GetSelectedValue()
        if not selectedValue or selectedValue == "" then
            if deleteItems[1] then selectedValue = deleteItems[1].value else return end
        end
        if JT:DeleteProfile(selectedValue) then
            PopulateProfilePane(scrollParent)
        else
            print("|cff00aaffJetTools|r: Cannot delete profile '" .. selectedValue .. "'.")
        end
    end)
    yOffset = yOffset - 36

    local totalHeight = math.abs(yOffset) + 16
    scrollParent:SetContentHeight(math.max(totalHeight, 1))
    scrollParent:ResetScroll()

    JT.RefreshProfilePane = function()
        PopulateProfilePane(scrollParent)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module pane population
-- ─────────────────────────────────────────────────────────────────────────────

local currentModuleName = nil

local function PopulateModulePane(scrollParent, moduleName)
    JT.RefreshProfilePane = nil

    if moduleName == PROFILES_TAB then
        currentModuleName = PROFILES_TAB
        PopulateProfilePane(scrollParent)
        return
    end

    local scrollContent = scrollParent.scrollContent
    ClearFrame(scrollContent)
    currentModuleName = moduleName

    -- Check if this is a synthetic multi-module tab
    local moduleList = TAB_MODULES[moduleName]
    if moduleList then
        -- Render options from each constituent module in sequence
        local yOffset = -8
        for _, subName in ipairs(moduleList) do
            local subModule = JT.modules[subName]
            if subModule and subModule.GetOptions then
                local schema = subModule:GetOptions()
                for _, item in ipairs(schema) do
                    yOffset = BuildOptionControl(scrollContent, subName, item, yOffset)
                end
                yOffset = yOffset - 8  -- small gap between sub-modules
            end
        end
        local totalHeight = math.abs(yOffset) + 16
        scrollParent:SetContentHeight(math.max(totalHeight, 1))
        scrollParent:ResetScroll()

        JT._requestOptionsRepopulate = function()
            PopulateModulePane(scrollParent, moduleName)
        end
        return
    end

    -- Normal single-module tab
    local module = JT.modules[moduleName]
    if not module or not module.GetOptions then return end

    local schema = module:GetOptions()
    local yOffset = -8

    for _, item in ipairs(schema) do
        yOffset = BuildOptionControl(scrollContent, moduleName, item, yOffset)
    end

    local totalHeight = math.abs(yOffset) + 16
    scrollParent:SetContentHeight(math.max(totalHeight, 1))
    scrollParent:ResetScroll()

    JT._requestOptionsRepopulate = function()
        PopulateModulePane(scrollParent, moduleName)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main options frame construction
-- ─────────────────────────────────────────────────────────────────────────────

local FRAME_W     = 820
local FRAME_H     = 600
local SIDEBAR_W   = 160
local SIDEBAR_PAD = 8
local BTN_H       = 26
local RIGHT_PAD   = 12
local DIVIDER_W   = 1

local function CreateOptionsFrame()
    -- Main window
    local frame = CreateFrame("Frame", "JetToolsOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
    frame:SetBackdropBorderColor(0.3, 0.4, 0.6, 0.8)
    frame:Hide()

    -- Auto-preview: show CombatTimer and CombatRes overlays while options are open,
    -- but only if the module's 'enabled' setting is true.
    local PREVIEW_MODULES = { "CombatTimer", "CombatRes" }
    frame:SetScript("OnShow", function()
        -- Refresh the global font dropdown to reflect the current DB value
        if frame._refreshGlobalFontDD then frame._refreshGlobalFontDD() end
        -- Show previews only for modules that are actually enabled by the user.
        -- If a module is disabled (settings.enabled == false), do not show its preview.
        for _, name in ipairs(PREVIEW_MODULES) do
            local m = JT.modules[name]
            if m and m.ShowPreview then
                local settings = JT:GetModuleSettings(name)
                if settings and settings.enabled then
                    m:ShowPreview()
                end
            end
        end
    end)
    frame:SetScript("OnHide", function()
        for _, name in ipairs(PREVIEW_MODULES) do
            local m = JT.modules[name]
            if m and m.HidePreview then m:HidePreview() end
        end
    end)

    table.insert(UISpecialFrames, "JetToolsOptionsFrame")

    -- Title bar background
    local titleBg = frame:CreateTexture(nil, "BACKGROUND")
    titleBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    titleBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    titleBg:SetHeight(34)
    titleBg:SetColorTexture(0.12, 0.15, 0.25, 1)

    -- Title text
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    title:SetText("|cff00aaffJet|r|cffaa66ffTools|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Global font dropdown — lives in the title bar to the right of the title text.
    -- Operates on JetToolsDB.globalFont and broadcasts to all font-aware modules.
    local globalFontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    globalFontLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 120, -10)
    globalFontLabel:SetText("Global Font:")
    globalFontLabel:SetTextColor(0.7, 0.7, 0.7)

    local globalFontDD = JT_CreateDropdown(frame, 180, 10)
    -- Align dropdown vertically centered with the label; dropdown container is 28px tall
    globalFontDD:SetPoint("TOPLEFT", globalFontLabel, "TOPRIGHT", 6, 7)
    -- No label on the dropdown widget itself (the FontString above acts as label)
    globalFontDD._label:SetText("")

    -- Populate items and set initial selection once options frame exists
    local function RefreshGlobalFontDD()
        local fontItems = JT:GetAvailableFonts()
        globalFontDD:SetItems(fontItems)
        local cur = JetToolsDB and JetToolsDB.globalFont
        if cur and cur ~= "" then
            globalFontDD:SetSelectedValue(cur)
        else
            globalFontDD:SetSelectedValue(fontItems[1] and fontItems[1].value or nil)
        end
    end

    globalFontDD:SetOnSelect(function(value)
        JT:ApplyGlobalFont(value)
    end)

    -- Store refresh fn on the frame so OnShow can call it
    frame._refreshGlobalFontDD = RefreshGlobalFontDD

    -- ── Left sidebar ─────────────────────────────────────────────────────────

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetSize(SIDEBAR_W, FRAME_H - 40)
    sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_PAD, -36)
    sidebar:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    sidebar:SetBackdropColor(0.06, 0.06, 0.10, 1)
    sidebar:SetBackdropBorderColor(0.2, 0.3, 0.5, 0.5)

    -- ── Vertical divider ─────────────────────────────────────────────────────

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetSize(DIVIDER_W, FRAME_H - 40)
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", SIDEBAR_PAD, 0)
    divider:SetColorTexture(0.3, 0.4, 0.6, 0.5)

    -- ── Right scroll pane ─────────────────────────────────────────────────────

    local rightX = SIDEBAR_W + SIDEBAR_PAD * 2 + DIVIDER_W + RIGHT_PAD
    local rightW = FRAME_W - rightX - RIGHT_PAD - 20 -- leave room for scrollbar
    local rightH = FRAME_H - 40 - 8

    local scrollParent = JT_CreateScrollFrame(frame, rightW, rightH)
    scrollParent:SetPoint("TOPLEFT", frame, "TOPLEFT", rightX, -36)

    -- ── Sidebar module buttons ────────────────────────────────────────────────

    local sidebarButtons = {}
    local selectedIndex  = nil

    local function DeselectAll()
        for _, b in ipairs(sidebarButtons) do
            if b._bg then b._bg:SetVertexColor(0.18, 0.18, 0.28) end
            b:SetNormalFontObject("GameFontNormalSmall")
        end
    end

    local function SelectButton(idx)
        DeselectAll()
        selectedIndex = idx
        local b = sidebarButtons[idx]
        if b then
            if b._bg then b._bg:SetVertexColor(0.3, 0.5, 0.9) end
        end
        PopulateModulePane(scrollParent, sidebarButtons[idx]._moduleName)
    end

    for i, moduleName in ipairs(MODULE_ORDER) do
        local label = MODULE_LABELS[moduleName] or moduleName
        local btn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
        btn:SetSize(SIDEBAR_W - SIDEBAR_PAD * 2, BTN_H)
        btn:SetText(label)
        btn:SetNormalFontObject("GameFontNormalSmall")

        -- Strip all Blizzard artwork so the custom bg tinting shows cleanly.
        -- We use the normal/pushed/highlight slots as the selection background.
        btn:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
        btn:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
        btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        btn:SetDisabledTexture("Interface\\Buttons\\WHITE8X8")
        btn:GetNormalTexture():SetVertexColor(0.18, 0.18, 0.28)
        btn:GetPushedTexture():SetVertexColor(0.12, 0.12, 0.20)
        local sidebarHl = btn:GetHighlightTexture()
        sidebarHl:SetVertexColor(0.35, 0.50, 0.85, 0.20)
        sidebarHl:SetBlendMode("ADD")
        btn:GetDisabledTexture():SetVertexColor(0.10, 0.10, 0.15)

        -- Keep _bg pointing to the NormalTexture so DeselectAll/SelectButton
        -- can tint it for the active-tab highlight.
        btn._bg = btn:GetNormalTexture()

        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT",
            SIDEBAR_PAD, -(SIDEBAR_PAD + (i - 1) * (BTN_H + 4)))
        btn.id          = i
        btn._moduleName = moduleName

        sidebarButtons[i] = btn

        local capturedI = i
        btn:SetScript("OnClick", function()
            SelectButton(capturedI)
        end)
    end

    -- Select first module by default
    if #sidebarButtons > 0 then
        SelectButton(1)
    end

    return frame
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

function JT:ToggleOptions()
    if not optionsFrame then
        optionsFrame = CreateOptionsFrame()
    end

    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

function JT:ShowOptions()
    if not optionsFrame then
        optionsFrame = CreateOptionsFrame()
    end
    optionsFrame:Show()
end

function JT:HideOptions()
    if optionsFrame then
        optionsFrame:Hide()
    end
end

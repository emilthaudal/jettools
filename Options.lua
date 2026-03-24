-- JetTools Options Panel
-- AF-based: left sidebar (module nav) + right scroll pane + Profiles tab

local addonName, JT = ...

---@type AbstractFramework
local AF = _G.AbstractFramework

local optionsFrame = nil

-- Sentinel value for the Profiles tab
local PROFILES_TAB = "Profiles"

-- Defined display order for modules in the sidebar (Profiles is last)
local MODULE_ORDER = {
    "RangeIndicator",
    "CurrentExpansionFilter",
    "AutoRoleQueue",
    "CharacterSheet",
    "GearUpgradeRanks",
    "CDMAuraRemover",
    "CharacterStatFormatting",
    "SlashCommands",
    "CombatStatus",
    "PetReminders",
    "StealthReminder",
    PROFILES_TAB,
}

-- Human-friendly display names for sidebar buttons
local MODULE_LABELS = {
    RangeIndicator          = "Range Indicator",
    CurrentExpansionFilter  = "Expansion Filter",
    AutoRoleQueue           = "Auto Role Queue",
    CharacterSheet          = "Character Sheet",
    GearUpgradeRanks        = "Gear Ranks",
    CDMAuraRemover          = "Aura Remover",
    CharacterStatFormatting = "Stat Formatting",
    SlashCommands           = "Slash Commands",
    CombatStatus            = "Combat Status",
    PetReminders            = "Pet Reminders",
    StealthReminder         = "Stealth Reminder",
    [PROFILES_TAB]          = "Profiles",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- StaticPopup dialogs (defined at file level, before any function uses them)
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
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Destroy all children/regions of a frame (clear the right pane before re-populating)
local function ClearFrame(parent)
    local children = { parent:GetChildren() }
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    local regions = { parent:GetRegions() }
    for _, region in ipairs(regions) do
        region:Hide()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Option control builder (AF widgets)
-- ─────────────────────────────────────────────────────────────────────────────

local CONTENT_WIDTH = 340
local INDENT        = 16

-- Returns the new yOffset after placing the control
local function BuildOptionControl(parent, moduleName, schema, yOffset)
    local schemaType = schema.type
    local key        = schema.key

    -- Resolve current value
    local currentValue = schema.default
    if key then
        local settings = JT:GetModuleSettings(moduleName)
        if settings and settings[key] ~= nil then
            currentValue = settings[key]
        end
    end

    if schemaType == "header" then
        local pane = AF.CreateTitledPane(parent, schema.label, CONTENT_WIDTH, 20)
        AF.SetPoint(pane, "TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        return yOffset - 30

    elseif schemaType == "subheader" then
        local fs = AF.CreateFontString(parent, schema.label, "gray")
        AF.SetPoint(fs, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        return yOffset - 22

    elseif schemaType == "description" then
        local fs = AF.CreateFontString(parent, schema.text, "disabled")
        AF.SetPoint(fs, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
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
        local cb = AF.CreateCheckButton(parent, schema.label, function(checked)
            onChange(checked)
        end)
        AF.SetPoint(cb, "TOPLEFT", parent, "TOPLEFT", indent, yOffset)
        cb:SetChecked(currentValue)
        return yOffset - 28

    elseif schemaType == "slider" then
        local slider = AF.CreateSlider(parent, schema.label, CONTENT_WIDTH - INDENT,
            schema.min, schema.max, schema.step)
        AF.SetPoint(slider, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        slider:SetValue(currentValue)
        slider:SetAfterValueChanged(function(val)
            JT:SetModuleSetting(moduleName, key, val)
        end)
        return yOffset - 52

    elseif schemaType == "input" then
        local editBox = AF.CreateEditBox(parent, schema.label,
            schema.width or (CONTENT_WIDTH - INDENT), 32, "normal")
        AF.SetPoint(editBox, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        editBox:SetText(currentValue or "")
        editBox:SetOnTextChanged(function(text)
            JT:SetModuleSetting(moduleName, key, text)
        end)
        return yOffset - 50

    elseif schemaType == "dropdown" then
        local items = {}
        if type(schema.options) == "table" then
            if schema.options[1] then
                for _, v in ipairs(schema.options) do
                    table.insert(items, { text = v, value = v })
                end
            else
                for v, label in pairs(schema.options) do
                    table.insert(items, { text = label, value = v })
                end
            end
        end

        local dd = AF.CreateDropdown(parent, schema.width or (CONTENT_WIDTH - INDENT), 8)
        AF.SetPoint(dd, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        dd:SetLabel(schema.label)
        dd:SetItems(items)
        dd:SetOnSelect(function(value)
            JT:SetModuleSetting(moduleName, key, value)
        end)
        dd:SetSelectedValue(currentValue)
        return yOffset - 55

    elseif schemaType == "button" then
        local btn = AF.CreateButton(parent, schema.label, "accent",
            schema.width or 120, 24)
        AF.SetPoint(btn, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        btn:SetOnClick(schema.func)
        return yOffset - 36

    elseif schemaType == "color" then
        local cp = AF.CreateColorPicker(parent, schema.label, true,
            function(r, g, b, a)
                JT:SetModuleSetting(moduleName, key, { r = r, g = g, b = b, a = a })
            end,
            function(r, g, b, a)
                JT:SetModuleSetting(moduleName, key, { r = r, g = g, b = b, a = a })
            end
        )
        AF.SetPoint(cp, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        if currentValue then
            cp:SetColor(currentValue.r, currentValue.g, currentValue.b, currentValue.a or 1)
        end
        return yOffset - 36
    end

    return yOffset
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Profile pane
-- ─────────────────────────────────────────────────────────────────────────────

-- Stored so StaticPopup callbacks can trigger a refresh
JT.RefreshProfilePane = nil  -- set when profile pane is active

local function PopulateProfilePane(scrollParent)
    local scrollContent = scrollParent.scrollContent
    ClearFrame(scrollContent)

    local yOffset = -8

    -- ── Section: Active Profile ───────────────────────────────────────────────

    local profileHeader = AF.CreateTitledPane(scrollContent, "Profile", CONTENT_WIDTH, 20)
    AF.SetPoint(profileHeader, "TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    yOffset = yOffset - 30

    -- Profile selector dropdown
    local profileItems = {}
    for _, name in ipairs(JT:GetProfileNames()) do
        table.insert(profileItems, { text = name, value = name })
    end

    local profileDD = AF.CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT, 10)
    AF.SetPoint(profileDD, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    profileDD:SetLabel("Active Profile")
    profileDD:SetItems(profileItems)
    profileDD:SetSelectedValue(JT:GetActiveProfileName())
    profileDD:SetOnSelect(function(value)
        JT:SetActiveProfile(value)
        -- Rebuild pane to reflect new profile state
        PopulateProfilePane(scrollParent)
    end)
    yOffset = yOffset - 55

    -- ── Section: Spec Overrides ───────────────────────────────────────────────

    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    if numSpecs > 0 then
        yOffset = yOffset - 8
        local specHeader = AF.CreateTitledPane(scrollContent, "Spec-Specific Profiles", CONTENT_WIDTH, 20)
        AF.SetPoint(specHeader, "TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
        yOffset = yOffset - 30

        -- Build items including "None" as the first entry
        local specProfileItems = { { text = "None (use character profile)", value = "" } }
        for _, name in ipairs(JT:GetProfileNames()) do
            table.insert(specProfileItems, { text = name, value = name })
        end

        for i = 1, numSpecs do
            local specId, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(i)
            if specId then
                -- Icon + name label
                local iconStr = specIcon and ("|T" .. specIcon .. ":16:16:0:0|t ") or ""
                local specLabel = iconStr .. (specName or ("Spec " .. i))

                local specDD = AF.CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT, 10)
                AF.SetPoint(specDD, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
                specDD:SetLabel(specLabel)
                specDD:SetItems(specProfileItems)

                local currentOverride = JT:GetSpecProfileName(i) or ""
                specDD:SetSelectedValue(currentOverride)

                -- Capture i in a local for the closure
                local specIndex = i
                specDD:SetOnSelect(function(value)
                    if value == "" then
                        JT:ClearSpecProfile(specIndex)
                    else
                        JT:SetSpecProfile(specIndex, value)
                    end
                end)
                yOffset = yOffset - 55
            end
        end
    end

    -- ── Section: New Profile ──────────────────────────────────────────────────

    yOffset = yOffset - 8
    local newHeader = AF.CreateTitledPane(scrollContent, "New Profile", CONTENT_WIDTH, 20)
    AF.SetPoint(newHeader, "TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    yOffset = yOffset - 30

    local newDesc = AF.CreateFontString(scrollContent,
        "Creates a new profile starting from default settings.", "disabled")
    AF.SetPoint(newDesc, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    newDesc:SetWidth(CONTENT_WIDTH - INDENT)
    newDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 22

    local newEditBox = AF.CreateEditBox(scrollContent, "Profile Name",
        CONTENT_WIDTH - INDENT - 80 - 8, 28, "normal")
    AF.SetPoint(newEditBox, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)

    local createBtn = AF.CreateButton(scrollContent, "Create", "accent", 80, 28)
    AF.SetPoint(createBtn, "LEFT", newEditBox, "RIGHT", 8, 0)
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
    yOffset = yOffset - 40

    -- ── Section: Copy From ────────────────────────────────────────────────────

    yOffset = yOffset - 8
    local copyHeader = AF.CreateTitledPane(scrollContent, "Copy From", CONTENT_WIDTH, 20)
    AF.SetPoint(copyHeader, "TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    yOffset = yOffset - 30

    local copyDesc = AF.CreateFontString(scrollContent,
        "Overwrites the current profile settings with those from another profile.", "disabled")
    AF.SetPoint(copyDesc, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    copyDesc:SetWidth(CONTENT_WIDTH - INDENT)
    copyDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 22

    -- Populate only with profiles other than the active one
    local activeName = JT:GetActiveProfileName()
    local copyItems = {}
    for _, name in ipairs(JT:GetProfileNames()) do
        if name ~= activeName then
            table.insert(copyItems, { text = name, value = name })
        end
    end

    local copyDD = AF.CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT - 80 - 8, 10)
    AF.SetPoint(copyDD, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    copyDD:SetLabel("Copy from")
    copyDD:SetItems(copyItems)
    if copyItems[1] then
        copyDD:SetSelectedValue(copyItems[1].value)
    end

    local copyBtn = AF.CreateButton(scrollContent, "Copy", "accent", 80, 28)
    AF.SetPoint(copyBtn, "TOPLEFT", scrollContent, "TOPLEFT",
        INDENT + (CONTENT_WIDTH - INDENT - 80 - 8) + 8, yOffset - 14)
    copyBtn:SetOnClick(function()
        local getVal = copyDD.GetSelectedValue
        local selectedValue = getVal and copyDD:GetSelectedValue()
        if not selectedValue or selectedValue == "" then
            if copyItems[1] then selectedValue = copyItems[1].value else return end
        end
        local dialog = StaticPopup_Show("JETTOOLS_COPY_PROFILE", selectedValue)
        if dialog then
            dialog.data = { sourceName = selectedValue }
        end
    end)
    yOffset = yOffset - 55

    -- ── Section: Reset Profile ────────────────────────────────────────────────

    yOffset = yOffset - 8
    local resetHeader = AF.CreateTitledPane(scrollContent, "Reset Profile", CONTENT_WIDTH, 20)
    AF.SetPoint(resetHeader, "TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    yOffset = yOffset - 30

    local resetDesc = AF.CreateFontString(scrollContent,
        "Resets the current profile (\"" .. activeName .. "\") back to default settings.", "disabled")
    AF.SetPoint(resetDesc, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    resetDesc:SetWidth(CONTENT_WIDTH - INDENT)
    resetDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 22

    local resetBtn = AF.CreateButton(scrollContent, "Reset to Defaults", "red", 160, 28)
    AF.SetPoint(resetBtn, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    resetBtn:SetOnClick(function()
        StaticPopup_Show("JETTOOLS_RESET_PROFILE")
    end)
    yOffset = yOffset - 40

    -- ── Section: Delete Profile ───────────────────────────────────────────────

    yOffset = yOffset - 8
    local deleteHeader = AF.CreateTitledPane(scrollContent, "Delete Profile", CONTENT_WIDTH, 20)
    AF.SetPoint(deleteHeader, "TOPLEFT", scrollContent, "TOPLEFT", 0, yOffset)
    yOffset = yOffset - 30

    local deleteDesc = AF.CreateFontString(scrollContent,
        "Permanently delete a profile. Cannot delete 'Default' or the active profile.",
        "disabled")
    AF.SetPoint(deleteDesc, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    deleteDesc:SetWidth(CONTENT_WIDTH - INDENT)
    deleteDesc:SetJustifyH("LEFT")
    yOffset = yOffset - 32

    -- Profiles eligible for deletion: not Default, not active
    local deleteItems = {}
    for _, name in ipairs(JT:GetProfileNames()) do
        if name ~= "Default" and name ~= activeName then
            table.insert(deleteItems, { text = name, value = name })
        end
    end

    local deleteDD = AF.CreateDropdown(scrollContent, CONTENT_WIDTH - INDENT - 80 - 8, 10)
    AF.SetPoint(deleteDD, "TOPLEFT", scrollContent, "TOPLEFT", INDENT, yOffset)
    deleteDD:SetLabel("Delete profile")
    deleteDD:SetItems(deleteItems)
    if deleteItems[1] then
        deleteDD:SetSelectedValue(deleteItems[1].value)
    end

    local deleteBtn = AF.CreateButton(scrollContent, "Delete", "red", 80, 28)
    AF.SetPoint(deleteBtn, "TOPLEFT", scrollContent, "TOPLEFT",
        INDENT + (CONTENT_WIDTH - INDENT - 80 - 8) + 8, yOffset - 14)
    deleteBtn:SetOnClick(function()
        local getVal = deleteDD.GetSelectedValue
        local selectedValue = getVal and deleteDD:GetSelectedValue()
        if not selectedValue or selectedValue == "" then
            if deleteItems[1] then selectedValue = deleteItems[1].value else return end
        end
        if JT:DeleteProfile(selectedValue) then
            PopulateProfilePane(scrollParent)
        else
            print("|cff00aaffJetTools|r: Cannot delete profile '" .. selectedValue .. "'.")
        end
    end)
    yOffset = yOffset - 55

    -- Update scroll frame content height
    local totalHeight = math.abs(yOffset) + 16
    scrollParent:SetContentHeight(math.max(totalHeight, 1))
    scrollParent:ResetScroll()

    -- Expose refresh so StaticPopup callbacks can trigger it
    JT.RefreshProfilePane = function()
        PopulateProfilePane(scrollParent)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module pane population
-- ─────────────────────────────────────────────────────────────────────────────

local currentModuleName = nil

local function PopulateModulePane(scrollParent, moduleName)
    -- Clear any stale profile pane refresh hook
    JT.RefreshProfilePane = nil

    if moduleName == PROFILES_TAB then
        currentModuleName = PROFILES_TAB
        PopulateProfilePane(scrollParent)
        return
    end

    local scrollContent = scrollParent.scrollContent
    ClearFrame(scrollContent)
    currentModuleName = moduleName

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
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main options frame construction
-- ─────────────────────────────────────────────────────────────────────────────

local FRAME_W     = 820
local FRAME_H     = 600
local SIDEBAR_W   = 160
local SIDEBAR_PAD = 8
local BTN_H       = 28
local RIGHT_PAD   = 12
local DIVIDER_W   = 1

local function CreateOptionsFrame()
    -- Main panel
    local frame = AF.CreateHeaderedFrame(UIParent, "JetToolsOptionsFrame",
        "|cff00aaffJet|r|cffaa66ffTools|r", FRAME_W, FRAME_H, "DIALOG", 100)
    frame:SetPoint("CENTER")
    frame:Hide()

    table.insert(UISpecialFrames, "JetToolsOptionsFrame")

    -- ── Left sidebar ─────────────────────────────────────────────────────────

    local sidebar = AF.CreateBorderedFrame(frame, nil, SIDEBAR_W, FRAME_H - 40)
    AF.SetPoint(sidebar, "TOPLEFT", frame, "TOPLEFT", SIDEBAR_PAD, -36)

    -- ── Vertical divider ─────────────────────────────────────────────────────

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetSize(DIVIDER_W, FRAME_H - 40)
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", SIDEBAR_PAD, 0)
    divider:SetColorTexture(0.3, 0.4, 0.6, 0.5)

    -- ── Right pane ───────────────────────────────────────────────────────────

    local rightX = SIDEBAR_W + SIDEBAR_PAD * 2 + DIVIDER_W + RIGHT_PAD
    local rightW = FRAME_W - rightX - RIGHT_PAD
    local rightH = FRAME_H - 40 - 8

    local scrollParent = AF.CreateScrollFrame(frame, nil, rightW, rightH)
    AF.SetPoint(scrollParent, "TOPLEFT", frame, "TOPLEFT", rightX, -36)

    -- ── Sidebar module buttons ────────────────────────────────────────────────

    local sidebarButtons = {}

    for i, moduleName in ipairs(MODULE_ORDER) do
        local label = MODULE_LABELS[moduleName] or moduleName
        local btn = AF.CreateButton(sidebar, label, "widget",
            SIDEBAR_W - SIDEBAR_PAD * 2, BTN_H)
        btn.id = i
        btn._moduleName = moduleName
        AF.SetPoint(btn, "TOPLEFT", sidebar, "TOPLEFT",
            SIDEBAR_PAD, -(SIDEBAR_PAD + (i - 1) * (BTN_H + 4)))

        sidebarButtons[i] = btn
    end

    -- ButtonGroup: onClick is the 4th arg, fires AFTER selection visual
    local Highlight = AF.CreateButtonGroup(
        sidebarButtons,
        function(btn) btn:SetColor("accent") end,   -- onSelect
        function(btn) btn:SetColor("widget") end,   -- onDeselect
        function(btn)                               -- onClick
            PopulateModulePane(scrollParent, btn._moduleName)
        end
    )

    -- Select first module by default
    if #sidebarButtons > 0 then
        Highlight(1)
        PopulateModulePane(scrollParent, MODULE_ORDER[1])
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

-- JetTools Options Panel
-- AF-based: left sidebar (module nav) + right scroll pane + profile management

local addonName, JT = ...

---@type AbstractFramework
local AF = _G.AbstractFramework

local optionsFrame = nil

-- Defined display order for modules in the sidebar
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
}

-- Human-friendly display names for sidebar buttons
local MODULE_LABELS = {
    RangeIndicator        = "Range Indicator",
    CurrentExpansionFilter = "Expansion Filter",
    AutoRoleQueue         = "Auto Role Queue",
    CharacterSheet        = "Character Sheet",
    GearUpgradeRanks      = "Gear Ranks",
    CDMAuraRemover        = "Aura Remover",
    CharacterStatFormatting = "Stat Formatting",
    SlashCommands         = "Slash Commands",
    CombatStatus          = "Combat Status",
    PetReminders          = "Pet Reminders",
    StealthReminder       = "Stealth Reminder",
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

-- Destroy all children of a frame (clear the right pane before re-populating)
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

-- Returns the new yOffset after placing the control
local function BuildOptionControl(parent, moduleName, schema, yOffset)
    local CONTENT_WIDTH = 340
    local INDENT        = 16

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
        -- AF titled pane (underline title) used as a section header
        local pane = AF.CreateTitledPane(parent, schema.label, CONTENT_WIDTH, 20)
        AF.SetPoint(pane, "TOPLEFT", parent, "TOPLEFT", 0, yOffset)
        return yOffset - 30

    elseif schemaType == "subheader" then
        local fs = AF.CreateFontString(parent, schema.label, "silver", "accent")
        AF.SetPoint(fs, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        return yOffset - 22

    elseif schemaType == "description" then
        local fs = AF.CreateFontString(parent, schema.text, "disabled", "normal")
        AF.SetPoint(fs, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        fs:SetWidth(CONTENT_WIDTH - INDENT)
        fs:SetJustifyH("LEFT")
        -- GetStringHeight is only valid after layout; use a minimum of 18px
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
        local slider = AF.CreateSlider(parent, schema.label, CONTENT_WIDTH - INDENT, schema.min, schema.max, schema.step)
        AF.SetPoint(slider, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        slider:SetValue(currentValue)
        slider:SetOnValueChanged(function(val)
            JT:SetModuleSetting(moduleName, key, val)
        end)
        return yOffset - 52

    elseif schemaType == "input" then
        local editBox = AF.CreateEditBox(parent, schema.label, schema.width or CONTENT_WIDTH - INDENT, 32, "normal")
        AF.SetPoint(editBox, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        editBox:SetText(currentValue or "")
        editBox:SetOnTextChanged(function(text)
            JT:SetModuleSetting(moduleName, key, text)
        end)
        return yOffset - 50

    elseif schemaType == "dropdown" then
        -- Build items list: schema.options is either array or {value=label} table
        local items = {}
        if type(schema.options) == "table" then
            if schema.options[1] then
                -- indexed array of strings
                for _, v in ipairs(schema.options) do
                    table.insert(items, { text = v, value = v })
                end
            else
                -- key=value pairs
                for v, label in pairs(schema.options) do
                    table.insert(items, { text = label, value = v })
                end
            end
        end

        local dd = AF.CreateDropdown(parent, schema.width or CONTENT_WIDTH - INDENT, 8, "DOWN")
        AF.SetPoint(dd, "TOPLEFT", parent, "TOPLEFT", INDENT, yOffset)
        dd:SetLabel(schema.label)
        dd:SetItems(items)
        dd:SetOnSelect(function(item)
            JT:SetModuleSetting(moduleName, key, item.value)
        end)
        -- Set current selection
        for _, item in ipairs(items) do
            if item.value == currentValue then
                dd:SetSelectedItem(item)
                break
            end
        end
        return yOffset - 55

    elseif schemaType == "button" then
        local btn = AF.CreateButton(parent, schema.label, "accent", schema.width or 120, 24)
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
-- Module pane population
-- ─────────────────────────────────────────────────────────────────────────────

local currentModuleName = nil

local function PopulateModulePane(scrollContent, moduleName)
    ClearFrame(scrollContent)
    currentModuleName = moduleName

    local module = JT.modules[moduleName]
    if not module or not module.GetOptions then return end

    local schema = module:GetOptions()
    local yOffset = -8

    for _, item in ipairs(schema) do
        yOffset = BuildOptionControl(scrollContent, moduleName, item, yOffset)
    end

    -- Ensure scroll content is tall enough
    local totalHeight = math.abs(yOffset) + 16
    scrollContent:SetHeight(math.max(totalHeight, 1))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Profile management UI (top strip of the right pane)
-- ─────────────────────────────────────────────────────────────────────────────

local profileDropdown = nil

local function RefreshProfileDropdown()
    if not profileDropdown then return end

    local names = JT:GetProfileNames()
    local items = {}
    for _, name in ipairs(names) do
        table.insert(items, { text = name, value = name })
    end
    profileDropdown:SetItems(items)

    -- Highlight the active profile
    local activeName = JT:GetActiveProfileName()
    for _, item in ipairs(items) do
        if item.value == activeName then
            profileDropdown:SetSelectedItem(item)
            break
        end
    end
end

local function BuildProfileStrip(parent, scrollContent)
    -- Label
    local label = AF.CreateFontString(parent, "Profile:", "white", "accent")
    AF.SetPoint(label, "TOPLEFT", parent, "TOPLEFT", 0, -8)

    -- Dropdown (200px wide, max 8 items)
    local dd = AF.CreateDropdown(parent, 200, 8, "DOWN")
    AF.SetPoint(dd, "TOPLEFT", label, "TOPRIGHT", 8, 0)
    dd:SetOnSelect(function(item)
        JT:SetActiveProfile(item.value)
        -- Re-populate current module pane to reflect new profile values
        if currentModuleName then
            PopulateModulePane(scrollContent, currentModuleName)
        end
    end)
    profileDropdown = dd

    -- New Profile button
    local newBtn = AF.CreateButton(parent, "New", "accent", 60, 22)
    AF.SetPoint(newBtn, "TOPLEFT", dd, "TOPRIGHT", 6, 0)
    newBtn:SetOnClick(function()
        AF.ShowGlobalDialog("New Profile", "Enter profile name:", function(name)
            if name and name ~= "" then
                if JT:CreateProfile(name) then
                    JT:SetActiveProfile(name)
                    RefreshProfileDropdown()
                    if currentModuleName then
                        PopulateModulePane(scrollContent, currentModuleName)
                    end
                else
                    print("|cff00aaffJetTools|r: Profile '" .. name .. "' already exists.")
                end
            end
        end)
    end)

    -- Delete Profile button
    local delBtn = AF.CreateButton(parent, "Delete", "red", 60, 22)
    AF.SetPoint(delBtn, "TOPLEFT", newBtn, "TOPRIGHT", 4, 0)
    delBtn:SetOnClick(function()
        local activeName = JT:GetActiveProfileName()
        if activeName == "Default" then
            print("|cff00aaffJetTools|r: Cannot delete the Default profile.")
            return
        end
        if JT:DeleteProfile(activeName) then
            JT:SetActiveProfile("Default")
            RefreshProfileDropdown()
            if currentModuleName then
                PopulateModulePane(scrollContent, currentModuleName)
            end
        end
    end)

    RefreshProfileDropdown()
    return 40 -- height consumed by the profile strip
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main options frame construction
-- ─────────────────────────────────────────────────────────────────────────────

-- Dimensions
local FRAME_W       = 820
local FRAME_H       = 600
local SIDEBAR_W     = 160
local SIDEBAR_PAD   = 8
local BTN_H         = 28
local RIGHT_PAD     = 12
local PROFILE_H     = 44  -- height of the profile strip area
local DIVIDER_W     = 1

local function CreateOptionsFrame()
    -- Main panel (AF headered frame: draggable, close button, title)
    local frame = AF.CreateHeaderedFrame(UIParent, "JetToolsOptionsFrame", "|cff00aaffJet|r|cffaa66ffTools|r", FRAME_W, FRAME_H, "DIALOG", 100)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:Hide()

    -- Make Escape close it
    table.insert(UISpecialFrames, "JetToolsOptionsFrame")

    -- ── Left sidebar ─────────────────────────────────────────────────────────

    local sidebar = AF.CreateBorderedFrame(frame, nil, SIDEBAR_W, FRAME_H - 40, nil, "accent")
    AF.SetPoint(sidebar, "TOPLEFT", frame, "TOPLEFT", SIDEBAR_PAD, -36)

    -- ── Vertical divider ─────────────────────────────────────────────────────

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetSize(DIVIDER_W, FRAME_H - 40)
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", SIDEBAR_PAD, 0)
    divider:SetColorTexture(0.3, 0.4, 0.6, 0.5)

    -- ── Right pane ───────────────────────────────────────────────────────────

    local rightX     = SIDEBAR_W + SIDEBAR_PAD * 2 + DIVIDER_W + RIGHT_PAD
    local rightW     = FRAME_W - rightX - RIGHT_PAD
    local rightH     = FRAME_H - 40 - PROFILE_H - 8

    -- Profile strip container (above the scroll frame)
    local profileStrip = CreateFrame("Frame", nil, frame)
    profileStrip:SetSize(rightW, PROFILE_H)
    profileStrip:SetPoint("TOPLEFT", frame, "TOPLEFT", rightX, -36)

    -- Scroll frame for module settings
    local scrollFrame = AF.CreateScrollFrame(frame, nil, rightW, rightH, nil, nil)
    AF.SetPoint(scrollFrame, "TOPLEFT", profileStrip, "BOTTOMLEFT", 0, -4)

    -- The scrollable content frame (where widgets are placed)
    local scrollContent = scrollFrame.scrollContent
    scrollContent:SetWidth(rightW - 20) -- leave room for scrollbar

    -- Build profile strip (needs scrollContent ref for live refresh)
    BuildProfileStrip(profileStrip, scrollContent)

    -- ── Sidebar module buttons ────────────────────────────────────────────────

    local sidebarButtons = {}
    local buttonGroupHighlight

    for i, moduleName in ipairs(MODULE_ORDER) do
        local label = MODULE_LABELS[moduleName] or moduleName
        local btn = AF.CreateButton(sidebar, label, "normal", SIDEBAR_W - SIDEBAR_PAD * 2, BTN_H)
        AF.SetPoint(btn, "TOPLEFT", sidebar, "TOPLEFT", SIDEBAR_PAD, -(SIDEBAR_PAD + (i - 1) * (BTN_H + 4)))

        -- Capture moduleName in a closure
        local capturedName = moduleName
        btn:SetOnClick(function()
            if buttonGroupHighlight then
                buttonGroupHighlight(i)
            end
            PopulateModulePane(scrollContent, capturedName)
        end)

        sidebarButtons[i] = btn
    end

    -- Wire up ButtonGroup for radio-style highlight
    buttonGroupHighlight = AF.CreateButtonGroup(sidebarButtons,
        function(btn) btn:SetColor("accent") end,   -- onSelect
        function(btn) btn:SetColor("normal") end,   -- onDeselect
        nil                                          -- onClick handled above
    )

    -- Select first module by default
    if #sidebarButtons > 0 then
        buttonGroupHighlight(1)
        PopulateModulePane(scrollContent, MODULE_ORDER[1])
    end

    frame.RefreshProfileDropdown = RefreshProfileDropdown

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
        RefreshProfileDropdown()
        optionsFrame:Show()
    end
end

function JT:ShowOptions()
    if not optionsFrame then
        optionsFrame = CreateOptionsFrame()
    end
    RefreshProfileDropdown()
    optionsFrame:Show()
end

function JT:HideOptions()
    if optionsFrame then
        optionsFrame:Hide()
    end
end

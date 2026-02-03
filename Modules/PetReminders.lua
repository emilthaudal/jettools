-- JetTools Pet Reminders Module
-- Alerts when pet is missing or in passive mode
-- Only loads for pet classes: Hunter (BM/SV), Warlock (all), Death Knight (Unholy), Mage (Frost)

local addonName, JT = ...

local PetReminders = {}
JT:RegisterModule("PetReminders", PetReminders)

-- Upvalues for performance
local UnitExists = UnitExists
local UnitClass = UnitClass
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local IsPlayerSpell = C_SpellBook.IsSpellKnown
local PetHasActionBar = PetHasActionBar
local GetPetActionInfo = GetPetActionInfo
local IsMounted = IsMounted
local UnitOnTaxi = UnitOnTaxi
local UnitHasVehicleUI = UnitHasVehicleUI
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitAffectingCombat = UnitAffectingCombat
local GetTime = GetTime
local C_Timer = C_Timer
local C_ClassColor = C_ClassColor

-- Constants
local STATUS_OK = 1
local STATUS_MISSING = 2
local STATUS_PASSIVE = 3
local STATUS_EXCLUDED = 4

local UPDATE_THROTTLE = 0.1 -- Minimum time between updates (seconds)
local DISMOUNT_DELAY = 5    -- Seconds to wait after dismount before checking

-- Pet data by class
local PET_DATA = {
    HUNTER = {
        specs = { 253, 255 }, -- BM, SV (exclude MM)
        iconID = 132161,
        text = "PET MISSING!",
        passiveText = "PET PASSIVE!",
        passiveIconID = 132311,
        exclusionSpells = { 466846, 1232995, 1223323 }, -- Lone Wolf variants
        checkPassive = true,
    },
    WARLOCK = {
        specs = { 265, 266, 267 }, -- All specs
        iconID = 236292,
        text = "PET MISSING!",
        passiveText = "PET PASSIVE!",
        passiveIconID = 132311,
        exclusionSpells = { 108503 }, -- Grimoire of Sacrifice
        checkPassive = true,
    },
    DEATHKNIGHT = {
        specs = { 252 }, -- Unholy only
        iconID = 1100170,
        text = "PET MISSING!",
        passiveText = "PET PASSIVE!",
        passiveIconID = 132311,
        exclusionSpells = {},
        checkPassive = true,
    },
    MAGE = {
        specs = { 64 }, -- Frost only
        iconID = 135862,
        text = "PET MISSING!",
        passiveText = "PET PASSIVE!",
        passiveIconID = 132311,
        exclusionSpells = { 205024 }, -- Lonely Winter
        requiredSpell = 31687,      -- Water Elemental
        checkPassive = true,
    },
}

-- Module state
local isEnabled = false
local warningFrame = nil
local eventFrame = nil
local lastUpdateTime = 0
local dismountTimer = nil

-- Cached state (rebuilt on spec/class changes)
local cachedPlayerClass = nil
local cachedPlayerSpec = nil
local cachedClassColor = nil
local cachedPetData = nil

-- Current warning data
local currentWarningText = nil
local currentWarningIcon = nil

-- Helper: Check if pet exists
local function HasPet()
    return UnitExists("pet")
end

-- Helper: Check if pet is in passive mode
local function IsPetPassive()
    if not HasPet() or not PetHasActionBar() then
        return false
    end

    -- Check pet action bar for passive mode
    for slot = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(slot)
        if isToken and name == "PET_MODE_PASSIVE" and isActive then
            return true
        end
    end

    return false
end

-- Helper: Check if warning should be hidden (mount, vehicle, dead, combat)
local function ShouldHideWarning()
    local settings = JT:GetModuleSettings("PetReminders")
    local hideInCombat = settings and settings.hideInCombat

    return IsMounted()
        or UnitOnTaxi("player")
        or UnitHasVehicleUI("player")
        or UnitIsDeadOrGhost("player")
        or (hideInCombat and UnitAffectingCombat("player"))
end

-- Helper: Check if current spec/talents should track pets
local function ShouldTrackPet()
    if not cachedPetData then
        return false
    end

    -- Check if current spec is supported
    local specSupported = false
    for _, specID in ipairs(cachedPetData.specs) do
        if specID == cachedPlayerSpec then
            specSupported = true
            break
        end
    end

    if not specSupported then
        return false
    end

    -- Check exclusion spells (e.g., Lone Wolf, Grimoire of Sacrifice)
    for _, spellID in ipairs(cachedPetData.exclusionSpells) do
        if IsPlayerSpell(spellID) then
            return false
        end
    end

    -- Mage-specific: Must have Water Elemental spell
    if cachedPlayerClass == "MAGE" and cachedPetData.requiredSpell then
        if not IsPlayerSpell(cachedPetData.requiredSpell) then
            return false
        end
    end

    return true
end

-- Rebuild the cached state (class, spec, pet data)
local function RebuildCache()
    local _, classFilename = UnitClass("player")
    cachedPlayerClass = classFilename

    local specIndex = GetSpecialization()
    if specIndex then
        cachedPlayerSpec = select(1, GetSpecializationInfo(specIndex))
    else
        cachedPlayerSpec = nil
    end

    cachedClassColor = C_ClassColor.GetClassColor(classFilename)
    cachedPetData = PET_DATA[classFilename]
end

-- Get the current pet status
local function GetPetStatus()
    if not ShouldTrackPet() then
        return STATUS_EXCLUDED
    end

    if not cachedPetData then
        return STATUS_EXCLUDED
    end

    -- Check missing pet
    if not HasPet() then
        currentWarningText = cachedPetData.text
        currentWarningIcon = cachedPetData.iconID
        return STATUS_MISSING
    end

    -- Check passive mode
    if cachedPetData.checkPassive and IsPetPassive() then
        currentWarningText = cachedPetData.passiveText
        currentWarningIcon = cachedPetData.passiveIconID
        return STATUS_PASSIVE
    end

    return STATUS_OK
end

-- Create the warning frame UI
local function CreateWarningFrame()
    if warningFrame then return end

    local frame = CreateFrame("Frame", "JetToolsPetReminder", UIParent)
    frame:SetSize(250, 50)
    frame:SetFrameStrata("MEDIUM")

    -- Get saved position or use default
    local settings = JT:GetModuleSettings("PetReminders")
    local pos = settings and settings.framePosition
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 280)
    end

    frame:Hide()

    -- Make movable with SHIFT+drag
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        local point, _, relativePoint, x, y = self:GetPoint()
        JT:SetModuleSetting("PetReminders", "framePosition", {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        })
    end)

    -- Icon texture
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetSize(50, 50)
    icon:SetPoint("LEFT", frame, "CENTER", -150, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.icon = icon

    -- Icon border
    local iconBorder = frame:CreateTexture(nil, "BORDER")
    iconBorder:SetColorTexture(0, 0, 0, 1)
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)

    -- Warning text
    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    text:SetShadowOffset(1, -1)
    text:SetShadowColor(0, 0, 0, 1)
    frame.text = text

    warningFrame = frame

    -- Apply initial font settings
    PetReminders:ApplySettings()
end

-- Show the warning with current data
local function ShowWarning()
    if not warningFrame then
        CreateWarningFrame()
    end

    if not warningFrame then return end

    warningFrame.icon:SetTexture(currentWarningIcon)
    warningFrame.text:SetText(currentWarningText)

    -- Set text color to class color
    if cachedClassColor then
        warningFrame.text:SetTextColor(cachedClassColor.r, cachedClassColor.g, cachedClassColor.b)
    else
        warningFrame.text:SetTextColor(1, 0, 0) -- Fallback to red
    end

    warningFrame:Show()
end

-- Hide the warning
local function HideWarning()
    if warningFrame and warningFrame:IsShown() then
        warningFrame:Hide()
    end
end

-- Update the display based on current state (throttled)
local function UpdateDisplay()
    -- Throttle updates
    local now = GetTime()
    if (now - lastUpdateTime) < UPDATE_THROTTLE then
        return
    end
    lastUpdateTime = now

    -- Check if warning should be hidden due to game state
    if ShouldHideWarning() then
        HideWarning()
        return
    end

    -- Check pet status and show/hide accordingly
    local status = GetPetStatus()
    if status == STATUS_OK or status == STATUS_EXCLUDED then
        HideWarning()
    else
        ShowWarning()
    end
end

-- Event handler
local function OnEvent(self, event, ...)
    if not isEnabled then return end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        RebuildCache()
        -- Delay initial check to let game state settle
        C_Timer.After(1, function()
            if isEnabled then
                UpdateDisplay()
            end
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED" then
        RebuildCache()
        UpdateDisplay()
    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            UpdateDisplay()
        end
    elseif event == "PET_BAR_UPDATE" or event == "UNIT_PET_EXPERIENCE" then
        UpdateDisplay()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        if IsMounted() then
            HideWarning()
        else
            -- Cancel existing timer
            if dismountTimer then
                dismountTimer:Cancel()
            end
            -- Wait before checking after dismount (pet needs time to respawn)
            dismountTimer = C_Timer.NewTimer(DISMOUNT_DELAY, function()
                dismountTimer = nil
                if not IsMounted() and isEnabled then
                    UpdateDisplay()
                end
            end)
        end
    elseif event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE" then
        local unit = ...
        if unit == "player" then
            UpdateDisplay()
        end
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat - hide if setting enabled
        local settings = JT:GetModuleSettings("PetReminders")
        if settings and settings.hideInCombat then
            HideWarning()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat - recheck status
        UpdateDisplay()
    end
end

-- Module interface: Get options for UI
function PetReminders:GetOptions()
    return {
        { type = "header",      label = "Pet Reminders" },
        { type = "description", text = "Alerts when pet is missing or in passive mode" },
        { type = "checkbox",    label = "Enabled",                                     key = "enabled",      default = true },
        { type = "checkbox",    label = "Hide warnings during combat",                 key = "hideInCombat", default = true },
        { type = "slider",      label = "Font Size",                                   key = "fontSize",     min = 24,      max = 60, step = 2, default = 36 },
    }
end

-- Module interface: Apply settings to UI
function PetReminders:ApplySettings()
    if not warningFrame or not warningFrame.text then return end

    local settings = JT:GetModuleSettings("PetReminders")
    if not settings then return end

    local fontSize = settings.fontSize or 36
    warningFrame.text:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
end

-- Module interface: Initialize
function PetReminders:Init()
    RebuildCache()
    CreateWarningFrame()
end

-- Module interface: Enable
function PetReminders:Enable()
    if isEnabled then return end

    -- Validate class before enabling
    local canEnable, reason = self:CanEnable()
    if not canEnable then
        print("|cff00aaffJetTools|r Pet Reminders: " .. reason)
        return
    end

    isEnabled = true

    RebuildCache()
    CreateWarningFrame()

    -- Create event handler frame if needed
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end

    -- Register all events
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("PET_BAR_UPDATE")
    eventFrame:RegisterEvent("UNIT_PET_EXPERIENCE")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    eventFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Delayed initial update
    C_Timer.After(1, function()
        if isEnabled then
            UpdateDisplay()
        end
    end)
end

-- Module interface: Disable
function PetReminders:Disable()
    if not isEnabled then return end

    isEnabled = false

    -- Cancel any pending timers
    if dismountTimer then
        dismountTimer:Cancel()
        dismountTimer = nil
    end

    -- Unregister all events
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    HideWarning()
end

-- Module interface: Setting changed callback
function PetReminders:OnSettingChanged(key, value)
    if key == "fontSize" then
        self:ApplySettings()
    elseif key == "hideInCombat" then
        -- Immediately update display based on new combat hiding setting
        UpdateDisplay()
    end
end

-- Module interface: Validate if module can be enabled
function PetReminders:CanEnable()
    local _, class = UnitClass("player")
    if not PET_DATA[class] then
        return false, "Not a pet class (Hunter/Warlock/DK/Mage)"
    end
    return true, ""
end

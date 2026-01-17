-- JetTools Range Indicator Module
-- Displays a "+" indicator above the Personal Resource Display
-- Shows green when in range, red when out of range
-- Only visible during combat

local addonName, JT = ...

local RangeIndicator = {}
JT:RegisterModule("RangeIndicator", RangeIndicator)

-- LibSharedMedia support (optional)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Fallback fonts if LSM is not available
local FALLBACK_FONTS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
}

-- Get list of available fonts (for Options UI)
function RangeIndicator:GetAvailableFonts()
    if LSM then
        local fonts = {}
        for _, name in ipairs(LSM:List("font")) do
            fonts[name] = name
        end
        return fonts
    else
        local fonts = {}
        for name, _ in pairs(FALLBACK_FONTS) do
            fonts[name] = name
        end
        return fonts
    end
end

-- Get font path by name
local function GetFontPath(fontName)
    if LSM then
        return LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    else
        return FALLBACK_FONTS[fontName] or "Fonts\\FRIZQT__.TTF"
    end
end

-- Class-specific range check abilities (melee abilities for accurate range)
local CLASS_RANGE_ABILITIES = {
    WARRIOR = "Slam",
    PALADIN = "Crusader Strike",
    DEATHKNIGHT = "Death Strike",
    MONK = "Tiger Palm",
    DEMONHUNTER = "Demon's Bite",
    ROGUE = "Sinister Strike",
    DRUID = "Shred",
    SHAMAN = "Stormstrike",
    EVOKER = "Quell",  -- Mid-range class, 25yd ability
}

-- Module state
local indicatorFrame = nil
local indicatorText = nil
local isEnabled = false
local isInCombat = false
local rangeAbility = nil
local updateElapsed = 0
local UPDATE_INTERVAL = 0.1 -- Check range every 0.1 seconds

-- Colors
local COLOR_IN_RANGE = { r = 0, g = 1, b = 0 }     -- Green
local COLOR_OUT_OF_RANGE = { r = 1, g = 0, b = 0 } -- Red
local COLOR_NO_TARGET = { r = 0, g = 1, b = 0 }    -- Green (default when no target)

-- Get the player's range check ability
local function GetRangeAbility()
    local _, playerClass = UnitClass("player")
    return CLASS_RANGE_ABILITIES[playerClass]
end

-- Check if target is in range
local function IsTargetInRange()
    if not UnitExists("target") or UnitIsDead("target") then
        return nil -- No valid target
    end
    
    if not rangeAbility then
        return nil
    end
    
    local inRange = C_Spell.IsSpellInRange(rangeAbility, "target")
    return inRange
end

-- Update the indicator color based on range
local function UpdateIndicator()
    if not indicatorText or not indicatorFrame:IsShown() then return end
    
    local inRange = IsTargetInRange()
    
    if inRange == nil then
        -- No target or can't check range - show green
        indicatorText:SetTextColor(COLOR_NO_TARGET.r, COLOR_NO_TARGET.g, COLOR_NO_TARGET.b)
    elseif inRange then
        indicatorText:SetTextColor(COLOR_IN_RANGE.r, COLOR_IN_RANGE.g, COLOR_IN_RANGE.b)
    else
        indicatorText:SetTextColor(COLOR_OUT_OF_RANGE.r, COLOR_OUT_OF_RANGE.g, COLOR_OUT_OF_RANGE.b)
    end
end

-- Find and anchor to the Personal Resource Display
local function AnchorToPersonalResourceDisplay()
    if not indicatorFrame then return end
    
    indicatorFrame:ClearAllPoints()
    
    -- The Personal Resource Display is attached to the player's nameplate
    -- We need to find the player nameplate and anchor to it
    local playerPlate = C_NamePlate.GetNamePlateForUnit("player")
    
    if playerPlate then
        -- Anchor to the player nameplate (PRD is part of this)
        indicatorFrame:SetPoint("BOTTOM", playerPlate, "TOP", 1, 40)
    else
        -- Fallback: anchor to UIParent at a reasonable position
        -- This handles cases where PRD might not be visible yet
        indicatorFrame:SetPoint("CENTER", UIParent, "CENTER", 1, -100)
    end
end

-- Create the indicator frame
local function CreateIndicator()
    if indicatorFrame then return end
    
    indicatorFrame = CreateFrame("Frame", "JetToolsRangeIndicator", UIParent)
    indicatorFrame:SetSize(50, 50)
    indicatorFrame:SetFrameStrata("HIGH")
    indicatorFrame:Hide()
    
    indicatorText = indicatorFrame:CreateFontString(nil, "OVERLAY")
    indicatorText:SetPoint("CENTER")
    
    -- Set font before SetText to avoid "Font not set" error
    local settings = JT:GetModuleSettings("RangeIndicator")
    local fontSize = settings and settings.fontSize or 24
    local fontPath = GetFontPath(settings and settings.fontFace or "Friz Quadrata TT")
    indicatorText:SetFont(fontPath, fontSize, "OUTLINE")
    
    indicatorText:SetText("+")
    
    -- OnUpdate for range checking
    indicatorFrame:SetScript("OnUpdate", function(self, elapsed)
        updateElapsed = updateElapsed + elapsed
        if updateElapsed >= UPDATE_INTERVAL then
            updateElapsed = 0
            UpdateIndicator()
            -- Also re-anchor in case nameplate changed
            AnchorToPersonalResourceDisplay()
        end
    end)
    
    RangeIndicator:ApplySettings()
end

-- Apply current settings to the indicator
function RangeIndicator:ApplySettings()
    if not indicatorText then return end
    
    local settings = JT:GetModuleSettings("RangeIndicator")
    if not settings then return end
    
    local fontPath = GetFontPath(settings.fontFace or "Friz Quadrata TT")
    indicatorText:SetFont(fontPath, settings.fontSize, "OUTLINE")
end

-- Show the indicator
local function ShowIndicator()
    if not indicatorFrame then
        CreateIndicator()
    end
    
    AnchorToPersonalResourceDisplay()
    indicatorFrame:Show()
    UpdateIndicator()
end

-- Hide the indicator
local function HideIndicator()
    if indicatorFrame then
        indicatorFrame:Hide()
    end
end

-- Event handler
local function OnEvent(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entered combat
        isInCombat = true
        if isEnabled then
            ShowIndicator()
        end
        
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Left combat
        isInCombat = false
        HideIndicator()
        
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if unit == "player" and isInCombat and isEnabled then
            AnchorToPersonalResourceDisplay()
        end
        
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        if unit == "player" and indicatorFrame then
            -- Re-anchor to fallback position
            AnchorToPersonalResourceDisplay()
        end
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

-- Initialize the module
function RangeIndicator:Init()
    rangeAbility = GetRangeAbility()
    
    if not rangeAbility then
        print("|cff00aaffJetTools|r: RangeIndicator - No range ability found for your class.")
    end
end

-- Enable the module
function RangeIndicator:Enable()
    isEnabled = true
    
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    
    -- If already in combat, show immediately
    if InCombatLockdown() then
        isInCombat = true
        ShowIndicator()
    end
end

-- Disable the module
function RangeIndicator:Disable()
    isEnabled = false
    
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
    
    HideIndicator()
end

-- Handle setting changes
function RangeIndicator:OnSettingChanged(key, value)
    if key == "fontSize" or key == "fontFace" then
        self:ApplySettings()
    end
end

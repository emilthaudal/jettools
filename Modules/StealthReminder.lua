-- JetTools Stealth Reminder Module
-- Displays an on-screen text warning when a Rogue or Druid is not in stealth
-- Only active for: Rogue (all specs), Druid (Feral spec 2, Guardian spec 3)

local addonName, JT = ...

local StealthReminder = {}
JT:RegisterModule("StealthReminder", StealthReminder)

-- Upvalues for performance
local UnitClass             = UnitClass
local UnitAffectingCombat   = UnitAffectingCombat
local IsMounted             = IsMounted
local IsStealthed           = IsStealthed
local IsResting             = IsResting
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo

-- Spec IDs for stealth-capable Druid specs
local DRUID_FERAL_SPEC_ID    = 103
local DRUID_GUARDIAN_SPEC_ID = 104

-- Module state
local isEnabled      = false
local inCombat       = false
local stealthed      = false
local isResting      = false
local playerClass    = nil  -- "ROGUE" or "DRUID" or other
local playerSpecID   = nil  -- numeric spec ID

-- Frame references (created once in Init)
local warningFrame = nil
local warningText  = nil

-- ──────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────

local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return (GetSpecializationInfo(specIndex))
end

-- Returns true if this player/spec should ever see the reminder
local function IsApplicableSpec()
    if playerClass == "ROGUE" then
        return true
    end
    if playerClass == "DRUID" then
        return playerSpecID == DRUID_FERAL_SPEC_ID
            or playerSpecID == DRUID_GUARDIAN_SPEC_ID
    end
    return false
end

-- ──────────────────────────────────────────────────────────────
-- Display logic
-- ──────────────────────────────────────────────────────────────

local function UpdateDisplay()
    if not warningFrame then
        print("|cffff8800JetTools SR|r UpdateDisplay: no warningFrame")
        return
    end

    local settings = JT:GetModuleSettings("StealthReminder")
    if not settings then
        print("|cffff8800JetTools SR|r UpdateDisplay: no settings")
        return
    end

    -- Normal mode: mouse interaction disabled
    warningFrame:EnableMouse(false)

    -- Must be enabled
    if not isEnabled then
        print("|cffff8800JetTools SR|r UpdateDisplay: not enabled")
        warningFrame:Hide()
        return
    end

    -- Only relevant for stealth classes/specs
    if not IsApplicableSpec() then
        print("|cffff8800JetTools SR|r UpdateDisplay: not applicable spec (class=" .. tostring(playerClass) .. " specID=" .. tostring(playerSpecID) .. ")")
        warningFrame:Hide()
        return
    end

    -- Hide during combat
    if inCombat then
        print("|cffff8800JetTools SR|r UpdateDisplay: in combat")
        warningFrame:Hide()
        return
    end

    -- Hide while mounted
    if IsMounted() then
        print("|cffff8800JetTools SR|r UpdateDisplay: mounted")
        warningFrame:Hide()
        return
    end

    -- Optionally hide while resting
    if isResting and settings.hideWhenResting then
        print("|cffff8800JetTools SR|r UpdateDisplay: resting")
        warningFrame:Hide()
        return
    end

    -- Decide what to show based on stealth state
    if stealthed then
        if not settings.showWhenStealthed then
            print("|cffff8800JetTools SR|r UpdateDisplay: stealthed but showWhenStealthed=false")
            warningFrame:Hide()
            return
        end
        print("|cffff8800JetTools SR|r UpdateDisplay: showing (stealthed=true)")
        warningText:SetText("Stealthed")
        warningText:SetTextColor(0.2, 1, 0.2)  -- green
    else
        print("|cffff8800JetTools SR|r UpdateDisplay: showing (not stealthed)")
        warningText:SetText("ENTER STEALTH!")
        warningText:SetTextColor(1, 0.15, 0.15)  -- red
    end

    warningFrame:Show()
end

-- ──────────────────────────────────────────────────────────────
-- Frame creation
-- ──────────────────────────────────────────────────────────────

local function CreateWarningFrame()
    if warningFrame then return end

    warningFrame = CreateFrame("Frame", "JetToolsStealthReminder", UIParent)
    warningFrame:SetFrameStrata("MEDIUM")
    warningFrame:SetClampedToScreen(true)

    -- Load saved position or use a sensible default
    local settings = JT:GetModuleSettings("StealthReminder")
    local x = (settings and settings.posX) or 0
    local y = (settings and settings.posY) or 150
    warningFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)

    -- Size will be driven by font size; start with a reasonable default
    warningFrame:SetSize(220, 40)

    warningText = warningFrame:CreateFontString(nil, "OVERLAY")
    warningText:SetPoint("CENTER")

    warningFrame:Hide()

    StealthReminder:ApplySettings()
end

-- ──────────────────────────────────────────────────────────────
-- Settings application
-- ──────────────────────────────────────────────────────────────

function StealthReminder:ApplySettings()
    if not warningText then return end

    local settings = JT:GetModuleSettings("StealthReminder")
    if not settings then return end

    local fontSize = settings.fontSize or 24
    warningText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

    -- Resize frame height to match font size
    if warningFrame then
        warningFrame:SetHeight(math.max(30, fontSize + 12))
    end
end

function StealthReminder:ApplyPosition()
    if not warningFrame then return end
    local settings = JT:GetModuleSettings("StealthReminder")
    if not settings then return end
    local x = settings.posX or 0
    local y = settings.posY or 150
    warningFrame:ClearAllPoints()
    warningFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

-- ──────────────────────────────────────────────────────────────
-- Options
-- ──────────────────────────────────────────────────────────────

function StealthReminder:GetOptions()
    return {
        { type = "header",   label = "Stealth Reminder" },
        { type = "checkbox", label = "Enabled",             key = "enabled",           default = false },
        { type = "checkbox", label = "Show when stealthed", key = "showWhenStealthed", default = true  },
        { type = "checkbox", label = "Hide when resting",   key = "hideWhenResting",   default = true  },
        { type = "slider",   label = "Font Size",           key = "fontSize",          min = 12, max = 48, step = 2,    default = 24  },
        { type = "slider",   label = "Position X",          key = "posX",              min = -900, max = 900, step = 1, default = 0   },
        { type = "slider",   label = "Position Y",          key = "posY",              min = -500, max = 500, step = 1, default = 150 },
    }
end

-- ──────────────────────────────────────────────────────────────
-- Event handler
-- ──────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Snapshot initial game state
        local _, cls = UnitClass("player")
        playerClass  = cls
        playerSpecID = GetCurrentSpecID()
        stealthed    = IsStealthed()
        inCombat     = UnitAffectingCombat("player") and true or false
        isResting    = IsResting() and true or false

        print("|cffff8800JetTools SR|r PLAYER_LOGIN: class=" .. tostring(playerClass) .. " specID=" .. tostring(playerSpecID) .. " stealthed=" .. tostring(stealthed) .. " isEnabled=" .. tostring(isEnabled))

        UpdateDisplay()
        return
    end

    -- Guard: ignore all other events when disabled (except spec changes, which
    -- affect applicability even when the module is toggled off)
    if not isEnabled then
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            playerSpecID = GetCurrentSpecID()
        end
        return
    end

    if event == "UPDATE_STEALTH" then
        stealthed = IsStealthed()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_UPDATE_RESTING" then
        isResting = IsResting() and true or false
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        -- no extra state to capture; IsMounted() is called live in UpdateDisplay
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        playerSpecID = GetCurrentSpecID()
    end

    UpdateDisplay()
end)

-- ──────────────────────────────────────────────────────────────
-- Module interface
-- ──────────────────────────────────────────────────────────────

function StealthReminder:Init()
    print("|cffff8800JetTools SR|r Init() called")
    CreateWarningFrame()
    -- PLAYER_LOGIN fires before Enable is called by Core; register it always
    -- so we can snapshot initial state and restore saved position.
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    -- Spec changes affect applicability even when disabled
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

function StealthReminder:Enable()
    print("|cffff8800JetTools SR|r Enable() called")
    isEnabled = true
    eventFrame:RegisterEvent("UPDATE_STEALTH")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    UpdateDisplay()
end

function StealthReminder:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("UPDATE_STEALTH")
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:UnregisterEvent("PLAYER_UPDATE_RESTING")
    eventFrame:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    if warningFrame then
        warningFrame:Hide()
    end
end

function StealthReminder:OnSettingChanged(key, value)
    if key == "fontSize" then
        self:ApplySettings()
    elseif key == "posX" or key == "posY" then
        self:ApplyPosition()
    end
    -- All other keys (enabled toggle, checkboxes) go through Core which
    -- calls Enable/Disable for "enabled"; for the rest, UpdateDisplay handles
    -- reading the live settings table.
    UpdateDisplay()
end

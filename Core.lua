-- JetTools Core
-- Handles initialization, saved variables, module registration, and profiles

local addonName, JT = ...

---@type AbstractFramework
local AF = _G.AbstractFramework

-- Expose addon table globally for debugging
JetTools = JT

-- Module registry
JT.modules = {}

-- Default settings per module (used when creating a new profile)
local MODULE_DEFAULTS = {
    RangeIndicator = {
        enabled = true,
        fontSize = 32,
        fontFace = "Friz Quadrata TT",
    },
    CurrentExpansionFilter = {
        enabled = true,
        craftingOrdersEnabled = true,
        craftingOrdersFocusSearch = false,
        auctionHouseEnabled = true,
        auctionHouseFocusSearch = false,
    },
    AutoRoleQueue = {
        enabled = false,
    },
    CharacterSheet = {
        enabled = false,
    },
    GearUpgradeRanks = {
        enabled = true,
    },
    CDMAuraRemover = {
        enabled = false,
        enableAuraOverride = false,
    },
    CharacterStatFormatting = {
        enabled = true,
    },
    SlashCommands = {
        enabled = true,
    },
    CombatStatus = {
        enabled = false,
        fontSize = 24,
        fontFace = "Friz Quadrata TT",
    },
    PetReminders = {
        enabled = true,
        hideInCombat = true,
        fontSize = 36,
        posX = 0,
        posY = 280,
    },
    StealthReminder = {
        enabled = false,
        showWhenStealthed = true,
        hideWhenResting = true,
        fontSize = 24,
        posX = 0,
        posY = 150,
    },
}

-- Deep copy helper
local function DeepCopy(src, dest)
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = dest[k] or {}
            DeepCopy(v, dest[k])
        elseif dest[k] == nil then
            dest[k] = v
        end
    end
end

-- Full deep clone (for creating new profiles)
local function DeepClone(src)
    local clone = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            clone[k] = DeepClone(v)
        else
            clone[k] = v
        end
    end
    return clone
end

-- Build a fresh modules settings table from defaults
local function BuildDefaultModules()
    return DeepClone(MODULE_DEFAULTS)
end

-- Register a module
function JT:RegisterModule(name, module)
    self.modules[name] = module
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Profile API
-- ─────────────────────────────────────────────────────────────────────────────

-- Get the character key used for profile assignment (Realm-CharName)
local function GetCharKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    return realm .. "-" .. name
end

-- Get the active profile name for this character
function JT:GetActiveProfileName()
    local charKey = GetCharKey()
    return JetToolsDB.profileAssignments[charKey] or "Default"
end

-- Get the active profile settings table
function JT:GetActiveProfile()
    local profileName = self:GetActiveProfileName()
    return JetToolsDB.profiles[profileName]
end

-- Get sorted list of all profile names
function JT:GetProfileNames()
    local names = {}
    for name, _ in pairs(JetToolsDB.profiles) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Create a new profile (cloned from Default or current active profile)
function JT:CreateProfile(name)
    if not name or name == "" then return false end
    if JetToolsDB.profiles[name] then return false end -- already exists

    -- Clone from the active profile so the new one inherits current settings
    local activeProfile = self:GetActiveProfile()
    JetToolsDB.profiles[name] = { modules = DeepClone(activeProfile.modules) }
    return true
end

-- Delete a profile (cannot delete "Default" or the last remaining profile)
function JT:DeleteProfile(name)
    if name == "Default" then return false end
    if not JetToolsDB.profiles[name] then return false end

    -- If any character is on this profile, move them to Default
    for charKey, profileName in pairs(JetToolsDB.profileAssignments) do
        if profileName == name then
            JetToolsDB.profileAssignments[charKey] = "Default"
        end
    end

    JetToolsDB.profiles[name] = nil
    return true
end

-- Switch the active profile for this character, live-reloading all modules
function JT:SetActiveProfile(name)
    if not JetToolsDB.profiles[name] then return false end

    local currentName = self:GetActiveProfileName()
    if currentName == name then return true end

    -- Disable all currently-enabled modules
    for moduleName, module in pairs(self.modules) do
        if self:IsModuleEnabled(moduleName) and module.Disable then
            module:Disable()
        end
    end

    -- Swap the profile assignment
    local charKey = GetCharKey()
    JetToolsDB.profileAssignments[charKey] = name

    -- Fill in any missing keys from defaults for the new profile
    local profile = JetToolsDB.profiles[name]
    DeepCopy({ modules = MODULE_DEFAULTS }, profile)

    -- Re-enable modules that are enabled in the new profile
    for moduleName, module in pairs(self.modules) do
        if self:IsModuleEnabled(moduleName) and module.Enable then
            module:Enable()
        end
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Settings API (all routed through active profile)
-- ─────────────────────────────────────────────────────────────────────────────

-- Get module settings from the active profile
function JT:GetModuleSettings(name)
    local profile = self:GetActiveProfile()
    return profile and profile.modules and profile.modules[name]
end

-- Check if a module is enabled in the active profile
function JT:IsModuleEnabled(name)
    local settings = self:GetModuleSettings(name)
    return settings and settings.enabled
end

-- Enable/disable a module and persist to active profile
function JT:SetModuleEnabled(name, enabled)
    local settings = self:GetModuleSettings(name)
    if not settings then return end

    settings.enabled = enabled

    local module = self.modules[name]
    if module then
        if enabled and module.Enable then
            module:Enable()
        elseif not enabled and module.Disable then
            module:Disable()
        end
    end
end

-- Update a module setting and notify the module
function JT:SetModuleSetting(name, key, value)
    local settings = self:GetModuleSettings(name)
    if not settings then return end

    settings[key] = value

    local module = self.modules[name]
    if module and module.OnSettingChanged then
        module:OnSettingChanged(key, value)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Initialization
-- ─────────────────────────────────────────────────────────────────────────────

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize the top-level DB structure
        JetToolsDB = JetToolsDB or {}

        -- Profiles table: each profile holds { modules = { ... } }
        JetToolsDB.profiles = JetToolsDB.profiles or {}
        if not JetToolsDB.profiles["Default"] then
            JetToolsDB.profiles["Default"] = { modules = BuildDefaultModules() }
        end

        -- Per-character profile assignments
        JetToolsDB.profileAssignments = JetToolsDB.profileAssignments or {}

        -- Fill in any missing default keys for every existing profile
        for _, profile in pairs(JetToolsDB.profiles) do
            profile.modules = profile.modules or {}
            DeepCopy({ modules = MODULE_DEFAULTS }, profile)
        end

        -- Register with AbstractFramework if available
        if AF then
            AF.RegisterAddon("JetTools", "JT")
        end

        print("|cff00aaffJetTools|r loaded. Type |cffaa66ff/jt|r for options.")

    elseif event == "PLAYER_LOGIN" then
        -- Initialize all registered modules
        for name, module in pairs(JT.modules) do
            if module.Init then
                module:Init()
            end

            if JT:IsModuleEnabled(name) and module.Enable then
                module:Enable()
            end
        end
    end
end)

-- Slash command
SLASH_JETTOOLS1 = "/jt"
SLASH_JETTOOLS2 = "/jettools"

SlashCmdList["JETTOOLS"] = function(msg)
    if JT.ToggleOptions then
        JT:ToggleOptions()
    else
        print("|cff00aaffJetTools|r: Options panel not loaded.")
    end
end

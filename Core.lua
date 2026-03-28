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
    BuffBarStyling = {
        enabled = false,
        texture = "Solid",
        barHeight = 26,
        barWidth = 200,
        showIcon = true,
        fontFace = "Friz Quadrata TT",
        fontSize = 13,
        anchorFrame = "",
        anchorPoint = "TOPLEFT",
        relativePoint = "BOTTOMLEFT",
        matchAnchorWidth = false,
        offsetX = 0,
        offsetY = 0,
    },
}

-- Deep copy helper (fills in missing keys from src into dest)
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

-- Full deep clone (returns a fresh independent copy)
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

-- Get the active profile name for this character.
-- Checks spec override first, then character assignment, then "Default".
function JT:GetActiveProfileName()
    local charKey = GetCharKey()

    -- Check spec override
    local specAssignments = JetToolsDB.specAssignments
    if specAssignments and specAssignments[charKey] then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex then
            local specOverride = specAssignments[charKey][specIndex]
            if specOverride and JetToolsDB.profiles[specOverride] then
                return specOverride
            end
        end
    end

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

-- Create a new profile from defaults (not cloned from active)
function JT:CreateProfile(name)
    if not name or name == "" then return false end
    if JetToolsDB.profiles[name] then return false end -- already exists

    JetToolsDB.profiles[name] = { modules = BuildDefaultModules() }
    return true
end

-- Delete a profile (cannot delete "Default")
function JT:DeleteProfile(name)
    if name == "Default" then return false end
    if not JetToolsDB.profiles[name] then return false end

    -- If any character is on this profile, move them to Default
    for charKey, profileName in pairs(JetToolsDB.profileAssignments) do
        if profileName == name then
            JetToolsDB.profileAssignments[charKey] = "Default"
        end
    end

    -- Clear any spec overrides pointing to this profile
    if JetToolsDB.specAssignments then
        for charKey, specMap in pairs(JetToolsDB.specAssignments) do
            for specIndex, profileName in pairs(specMap) do
                if profileName == name then
                    specMap[specIndex] = nil
                end
            end
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

-- Copy settings from sourceName into the current active profile, then live-reload
function JT:CopyProfile(sourceName)
    if not sourceName or not JetToolsDB.profiles[sourceName] then return false end
    local activeProfile = self:GetActiveProfile()
    if not activeProfile then return false end

    local source = JetToolsDB.profiles[sourceName]

    -- Disable all currently-enabled modules before swapping data
    for moduleName, module in pairs(self.modules) do
        if self:IsModuleEnabled(moduleName) and module.Disable then
            module:Disable()
        end
    end

    -- Overwrite active profile modules with a clone of source
    activeProfile.modules = DeepClone(source.modules or {})
    -- Fill in any keys missing from defaults
    DeepCopy({ modules = MODULE_DEFAULTS }, activeProfile)

    -- Re-enable modules enabled in the new settings
    for moduleName, module in pairs(self.modules) do
        if self:IsModuleEnabled(moduleName) and module.Enable then
            module:Enable()
        end
    end

    return true
end

-- Reset the current active profile to defaults, then live-reload
function JT:ResetProfile()
    local activeProfile = self:GetActiveProfile()
    if not activeProfile then return false end

    -- Disable all currently-enabled modules
    for moduleName, module in pairs(self.modules) do
        if self:IsModuleEnabled(moduleName) and module.Disable then
            module:Disable()
        end
    end

    -- Wipe and replace with fresh defaults
    activeProfile.modules = BuildDefaultModules()

    -- Re-enable modules enabled in the reset profile
    for moduleName, module in pairs(self.modules) do
        if self:IsModuleEnabled(moduleName) and module.Enable then
            module:Enable()
        end
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Spec override API
-- ─────────────────────────────────────────────────────────────────────────────

-- Get the profile name assigned to a specific spec slot for this character (or nil)
function JT:GetSpecProfileName(specIndex)
    local charKey = GetCharKey()
    local specAssignments = JetToolsDB.specAssignments
    if not specAssignments or not specAssignments[charKey] then return nil end
    return specAssignments[charKey][specIndex]
end

-- Assign a profile to a spec slot for this character
function JT:SetSpecProfile(specIndex, profileName)
    if not specIndex then return end
    local charKey = GetCharKey()
    JetToolsDB.specAssignments = JetToolsDB.specAssignments or {}
    JetToolsDB.specAssignments[charKey] = JetToolsDB.specAssignments[charKey] or {}
    JetToolsDB.specAssignments[charKey][specIndex] = profileName
end

-- Clear the spec override for a spec slot
function JT:ClearSpecProfile(specIndex)
    if not specIndex then return end
    local charKey = GetCharKey()
    if not JetToolsDB.specAssignments then return end
    if not JetToolsDB.specAssignments[charKey] then return end
    JetToolsDB.specAssignments[charKey][specIndex] = nil
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
frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")

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

        -- Per-character per-spec profile overrides
        JetToolsDB.specAssignments = JetToolsDB.specAssignments or {}

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

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Auto-switch profile if the new spec has an override assigned
        local charKey = GetCharKey()
        local specAssignments = JetToolsDB.specAssignments
        if not specAssignments or not specAssignments[charKey] then return end

        local specIndex = C_SpecializationInfo.GetSpecialization()
        if not specIndex then return end

        local overrideProfile = specAssignments[charKey][specIndex]
        if not overrideProfile or not JetToolsDB.profiles[overrideProfile] then return end

        -- Only switch if it differs from current assignment
        local currentAssigned = JetToolsDB.profileAssignments[charKey] or "Default"
        if currentAssigned ~= overrideProfile then
            JT:SetActiveProfile(overrideProfile)
            print("|cff00aaffJetTools|r: Switched to profile '" .. overrideProfile .. "' for this spec.")
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

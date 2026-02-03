-- JetTools Core
-- Handles initialization, saved variables, and module registration

local addonName, JT = ...

-- Expose addon table globally for debugging
JetTools = JT

-- Module registry
JT.modules = {}

-- Default settings per character
local defaults = {
    modules = {
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
            enabled = true,
            enableAuraOverride = true,
        },
        CharacterStatFormatting = {
            enabled = true,
        },
        SlashCommands = {
            enabled = true,
        },
        CombatStatus = {
            enabled = true,
            fontSize = 24,
            fontFace = "Friz Quadrata TT",
        },
        PetReminders = {
            enabled = true,
            hideInCombat = true,
            fontSize = 36,
            framePosition = {
                point = "CENTER",
                relativePoint = "CENTER",
                x = 0,
                y = 280,
            },
        },
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

-- Register a module
function JT:RegisterModule(name, module)
    self.modules[name] = module
end

-- Get module settings
function JT:GetModuleSettings(name)
    return JetToolsDB and JetToolsDB.modules and JetToolsDB.modules[name]
end

-- Check if a module is enabled
function JT:IsModuleEnabled(name)
    local settings = self:GetModuleSettings(name)
    return settings and settings.enabled
end

-- Enable/disable a module
function JT:SetModuleEnabled(name, enabled)
    if JetToolsDB and JetToolsDB.modules and JetToolsDB.modules[name] then
        JetToolsDB.modules[name].enabled = enabled
        
        local module = self.modules[name]
        if module then
            if enabled and module.Enable then
                module:Enable()
            elseif not enabled and module.Disable then
                module:Disable()
            end
        end
    end
end

-- Update a module setting
function JT:SetModuleSetting(name, key, value)
    if JetToolsDB and JetToolsDB.modules and JetToolsDB.modules[name] then
        JetToolsDB.modules[name][key] = value
        
        local module = self.modules[name]
        if module and module.OnSettingChanged then
            module:OnSettingChanged(key, value)
        end
    end
end

-- Initialize addon
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- Initialize saved variables with defaults
        JetToolsDB = JetToolsDB or {}
        DeepCopy(defaults, JetToolsDB)
        
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

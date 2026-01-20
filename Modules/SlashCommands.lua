-- JetTools Slash Command Helpers Module
-- Adds common slash commands /rl and /wa

local addonName, JT = ...

local SlashCommands = {}
JT:RegisterModule("SlashCommands", SlashCommands)

-- Get options configuration
function SlashCommands:GetOptions()
    return {
        { type = "header", label = "Slash Commands" },
        { type = "description", text = "Adds /rl (reload) and /wa (cooldowns)" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = true }
    }
end

-- Module state
local isEnabled = false

-- Track which commands we successfully registered so we can potentially deregister them
local registeredCommands = {
    RL = false,
    WA = false
}

local function ReloadUIHandler()
    if not isEnabled then return end
    ReloadUI()
end

local function WeakAurasHandler()
    if not isEnabled then return end
    
    if CooldownViewerSettings and CooldownViewerSettings.ShowUIPanel then
        CooldownViewerSettings:ShowUIPanel(false)
    else
        print("|cff00aaffJetTools|r: Cooldown Manager (CooldownViewerSettings) not found.")
    end
end

-- Safely register a slash command
local function RegisterCommand(command, func, id)
    local slashKey = string.upper(command)
    
    -- Check if it already exists in the global SlashCmdList
    if SlashCmdList[slashKey] == nil then
        -- Find a free SLASH_ variable name (e.g., SLASH_RL1)
        -- We don't really need to search for a free one if we just use a unique prefix or assume standard
        -- But for safety, we just set the global directly and the SlashCmdList
        
        _G["SLASH_" .. slashKey .. "1"] = "/" .. string.lower(command)
        SlashCmdList[slashKey] = func
        
        registeredCommands[slashKey] = true
        return true
    end
    
    return false
end

function SlashCommands:Init()
    -- We don't do anything in Init because we want to respect the 'enabled' state
    -- checking happens in Enable
end

function SlashCommands:Enable()
    isEnabled = true
    
    -- Register /rl if not taken
    if not SlashCmdList["RL"] then
        RegisterCommand("rl", ReloadUIHandler)
    end
    
    -- Register /wa if not taken
    if not SlashCmdList["WA"] then
        RegisterCommand("wa", WeakAurasHandler)
    end
end

function SlashCommands:Disable()
    isEnabled = false
    
    -- We generally don't unregister slash commands in WoW because it can cause taint issues 
    -- or leave gaps if other addons expected them. 
    -- Instead, our handlers check the 'isEnabled' flag at the very start.
    -- If disabled, the command technically exists but does nothing (or we could print "Disabled").
    -- For now, silent failure is safer than unregistering globals at runtime.
end

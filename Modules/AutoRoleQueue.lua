-- JetTools Auto Role Queue Module
-- Automatically accepts LFG role checks when enabled

local addonName, JT = ...

local AutoRoleQueue = {}
JT:RegisterModule("AutoRoleQueue", AutoRoleQueue)

-- Get options configuration
function AutoRoleQueue:GetOptions()
    return {
        { type = "header", label = "Auto Role Queue" },
        { type = "description", text = "Automatically accepts role checks when queuing" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = false }
    }
end

-- Module state
local isEnabled = false

-- Event handler
local function OnEvent(self, event, ...)
    if not isEnabled then return end
    
    if event == "LFG_ROLE_CHECK_SHOW" then
        CompleteLFGRoleCheck(true)
        print("|cff00aaffJetTools|r Role check accepted.")
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

-- Initialize the module
function AutoRoleQueue:Init()
    -- Nothing special needed for init
end

-- Enable the module
function AutoRoleQueue:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("LFG_ROLE_CHECK_SHOW")
end

-- Disable the module
function AutoRoleQueue:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("LFG_ROLE_CHECK_SHOW")
end

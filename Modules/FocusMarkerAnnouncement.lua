-- JetTools Focus Marker Announcement Module
-- Announces focus marker to party chat on ready check

local addonName, JT = ...

local FocusMarkerAnnouncement = {}
JT:RegisterModule("FocusMarkerAnnouncement", FocusMarkerAnnouncement)

-- Get options configuration
function FocusMarkerAnnouncement:GetOptions()
    return {
        { type = "header", label = "Focus Marker Announcement" },
        { type = "description", text = "Announces your focus marker to party on ready check" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = false },
        { type = "input", label = "Macro Name", key = "macroName", width = 150, default = "focus" }
    }
end

local isEnabled = false

-- Extract marker number from configured macro
local function ExtractMarkerFromMacro()
    local settings = JT:GetModuleSettings("FocusMarkerAnnouncement")
    local macroName = settings and settings.macroName or "focus"
    
    for i = 1, GetNumMacros() do
        local name, icon, body = GetMacroInfo(i)
        if name == macroName and body then
            for line in body:gmatch("[^\n]+") do
                if string.find(line, "/tm") then
                    local marker = tonumber(line:match("/tm%s*(%d+)"))
                    if marker then
                        return marker
                    end
                end
            end
        end
    end
    return nil
end

-- Event handler
local function OnEvent(self, event, ...)
    if not isEnabled then return end
    
    if event == "READY_CHECK" then
        local marker = ExtractMarkerFromMacro()
        if marker then
            C_ChatInfo.SendChatMessage(
                string.format("My Focus Marker is {rt%d}", marker),
                "PARTY"
            )
        end
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

function FocusMarkerAnnouncement:Init()
    -- No initialization needed
end

function FocusMarkerAnnouncement:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("READY_CHECK")
end

function FocusMarkerAnnouncement:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("READY_CHECK")
end

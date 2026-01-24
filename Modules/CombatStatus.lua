-- JetTools Combat Status Module
-- Displays "Entering Combat" and "Leaving Combat" text notifications
-- Mimics common WeakAuras behavior with native frames

local addonName, JT = ...

local CombatStatus = {}
JT:RegisterModule("CombatStatus", CombatStatus)

-- LibSharedMedia support
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Fallback fonts
local FALLBACK_FONTS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Skurri"] = "Fonts\\SKURRI.TTF",
    ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
}

-- Get list of available fonts
function CombatStatus:GetAvailableFonts()
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

-- Options configuration
function CombatStatus:GetOptions()
    return {
        { type = "header", label = "Combat Status Text" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = true },
        { type = "slider", label = "Font Size", key = "fontSize", min = 12, max = 48, step = 2, default = 24 },
        { type = "dropdown", label = "Font", key = "fontFace", options = self:GetAvailableFonts(), default = "Friz Quadrata TT" }
    }
end

-- Module state
local messageFrame = nil
local messageText = nil
local animationGroup = nil
local isEnabled = false

-- Create the display frame and animations
local function CreateMessageFrame()
    if messageFrame then return end

    -- Frame
    messageFrame = CreateFrame("Frame", "JetToolsCombatStatus", UIParent)
    messageFrame:SetSize(300, 50)
    messageFrame:SetPoint("CENTER", 0, 150) -- Positioned slightly above center
    messageFrame:SetFrameStrata("HIGH")
    messageFrame:SetAlpha(0) -- Start hidden
    
    -- Text
    messageText = messageFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("CENTER")
    messageText:SetTextColor(1, 1, 1) -- White text as requested
    
    -- Animation Group
    animationGroup = messageFrame:CreateAnimationGroup()
    
    -- Fade In
    local fadeIn = animationGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    
    -- Slide Up (small movement)
    local slide = animationGroup:CreateAnimation("Translation")
    slide:SetOffset(0, 20)
    slide:SetDuration(0.2)
    slide:SetOrder(1)
    
    -- Hold (Wait)
    local hold = animationGroup:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(2.0)
    hold:SetOrder(2)
    
    -- Fade Out
    local fadeOut = animationGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1.0)
    fadeOut:SetOrder(3)
    
    animationGroup:SetScript("OnFinished", function()
        messageFrame:SetAlpha(0)
    end)
    
    CombatStatus:ApplySettings()
end

-- Show message with animation
local function ShowMessage(text)
    if not messageFrame then CreateMessageFrame() end
    
    -- Stop existing animation to reset
    if animationGroup:IsPlaying() then
        animationGroup:Stop()
    end
    
    messageText:SetText(text)
    messageFrame:SetAlpha(0) -- Ensure invisible before start
    animationGroup:Play()
end

-- Apply settings
function CombatStatus:ApplySettings()
    if not messageText then return end
    
    local settings = JT:GetModuleSettings("CombatStatus")
    if not settings then return end
    
    local fontPath = GetFontPath(settings.fontFace or "Friz Quadrata TT")
    local fontSize = settings.fontSize or 24
    
    messageText:SetFont(fontPath, fontSize, "OUTLINE")
end

-- Event handler
local function OnEvent(self, event)
    if not isEnabled then return end
    
    if event == "PLAYER_REGEN_DISABLED" then
        ShowMessage("* Entering Combat *")
    elseif event == "PLAYER_REGEN_ENABLED" then
        ShowMessage("* Leaving Combat *")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

-- Init
function CombatStatus:Init()
    CreateMessageFrame()
end

-- Enable
function CombatStatus:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

-- Disable
function CombatStatus:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    
    if animationGroup and animationGroup:IsPlaying() then
        animationGroup:Stop()
    end
    if messageFrame then
        messageFrame:SetAlpha(0)
    end
end

-- Setting changed
function CombatStatus:OnSettingChanged(key, value)
    if key == "fontSize" or key == "fontFace" then
        self:ApplySettings()
    end
end

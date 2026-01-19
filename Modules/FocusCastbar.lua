-- JetTools Focus Castbar Module
-- Enhanced focus target castbar with interrupt tracking and color-coded states

local addonName, JT = ...

local FocusCastbar = {}
JT:RegisterModule("FocusCastbar", FocusCastbar)

-- Class interrupt spell mapping
-- spellId: the interrupt spell ID
-- cooldown: base cooldown in seconds
local CLASS_INTERRUPTS = {
    WARRIOR = { spellId = 6552, cooldown = 15 },       -- Pummel
    PALADIN = { spellId = 96231, cooldown = 15 },      -- Rebuke
    DEATHKNIGHT = { spellId = 47528, cooldown = 15 },  -- Mind Freeze
    MONK = { spellId = 116705, cooldown = 15 },        -- Spear Hand Strike
    DEMONHUNTER = { spellId = 183752, cooldown = 15 }, -- Disrupt
    ROGUE = { spellId = 1766, cooldown = 15 },         -- Kick
    DRUID = { spellId = 106839, cooldown = 15 },       -- Skull Bash
    SHAMAN = { spellId = 57994, cooldown = 12 },       -- Wind Shear
    EVOKER = { spellId = 351338, cooldown = 20 },      -- Quell
    MAGE = { spellId = 2139, cooldown = 24 },          -- Counterspell
    HUNTER = { spellId = 147362, cooldown = 24 },      -- Counter Shot
    -- WARLOCK and PRIEST have no baseline interrupt
}

-- Module state
local isEnabled = false
local castbarFrame = nil
local interruptInfo = nil  -- { spellId, cooldown } for current class
local interruptOnCooldown = false
local interruptUsedTime = 0
local isInterruptable = false
local castStartTime = 0
local castEndTime = 0
local hooksInitialized = false

-- Colors
local COLOR_INTERRUPTABLE = { 0, 1, 0, 1 }      -- Green - can interrupt now
local COLOR_ON_COOLDOWN = { 1, 1, 0, 1 }        -- Yellow - interruptable but on CD
local COLOR_NOT_INTERRUPTABLE = { 1, 0, 0, 1 }  -- Red - cannot interrupt

-- Bar dimensions
local BAR_WIDTH = 250
local BAR_HEIGHT = 16
local ICON_SIZE = 16

-- Create the castbar frame and all components
local function CreateCastbarFrame()
    if castbarFrame then return end
    
    local settings = JT:GetModuleSettings("FocusCastbar")
    local posX = settings and settings.positionX or 0
    local posY = settings and settings.positionY or -50
    
    -- Main container frame
    castbarFrame = CreateFrame("Frame", "JetToolsFocusCastbar", UIParent)
    castbarFrame:SetSize(BAR_WIDTH, BAR_HEIGHT)
    castbarFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    castbarFrame:SetFrameStrata("HIGH")
    castbarFrame:Hide()
    
    -- Background
    castbarFrame.Background = castbarFrame:CreateTexture(nil, "BACKGROUND")
    castbarFrame.Background:SetColorTexture(0.1, 0.1, 0.1, 1)
    
    -- Cast bar (StatusBar)
    castbarFrame.CastBar = CreateFrame("StatusBar", nil, castbarFrame)
    castbarFrame.CastBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    castbarFrame.CastBar:SetSize(BAR_WIDTH - ICON_SIZE, BAR_HEIGHT)
    
    do
        local texture = castbarFrame.CastBar:GetStatusBarTexture()
        if texture then
            texture:SetDrawLayer("BACKGROUND")
        end
    end
    
    -- Spell icon (left side)
    castbarFrame.Icon = castbarFrame:CreateTexture(nil, "ARTWORK")
    castbarFrame.Icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    castbarFrame.Icon:SetPoint("TOPLEFT", castbarFrame, "TOPLEFT", 0, 0)
    castbarFrame.Icon:SetPoint("BOTTOMLEFT", castbarFrame, "BOTTOMLEFT", 0, 0)
    castbarFrame.Icon:SetWidth(ICON_SIZE)
    
    -- Position cast bar to the right of icon
    castbarFrame.CastBar:SetPoint("TOPLEFT", castbarFrame.Icon, "TOPRIGHT", 0, 0)
    castbarFrame.CastBar:SetPoint("BOTTOMRIGHT", castbarFrame, "BOTTOMRIGHT", 0, 0)
    
    -- Position background behind cast bar
    castbarFrame.Background:SetAllPoints(castbarFrame.CastBar)
    
    -- Border around main frame
    castbarFrame.Border = CreateFrame("Frame", nil, castbarFrame, "BackdropTemplate")
    castbarFrame.Border:SetPoint("TOPLEFT", castbarFrame, -1, 1)
    castbarFrame.Border:SetPoint("BOTTOMRIGHT", castbarFrame, 1, -1)
    castbarFrame.Border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    castbarFrame.Border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Spell name text (left side of bar)
    castbarFrame.SpellNameText = castbarFrame.CastBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castbarFrame.SpellNameText:SetJustifyH("LEFT")
    castbarFrame.SpellNameText:SetFont(select(1, castbarFrame.SpellNameText:GetFont()), 12, "OUTLINE")
    castbarFrame.SpellNameText:SetShadowOffset(0, 0)
    castbarFrame.SpellNameText:SetPoint("LEFT", castbarFrame.CastBar, "LEFT", 4, 0)
    
    -- Time text (right side of bar)
    castbarFrame.TimeText = castbarFrame.CastBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    castbarFrame.TimeText:SetJustifyH("RIGHT")
    castbarFrame.TimeText:SetFont(select(1, castbarFrame.TimeText:GetFont()), 12, "OUTLINE")
    castbarFrame.TimeText:SetShadowOffset(0, 0)
    castbarFrame.TimeText:SetPoint("RIGHT", castbarFrame.CastBar, "RIGHT", -4, 0)
    
    -- Spark texture (shows when interrupt will be ready)
    castbarFrame.Spark = castbarFrame.CastBar:CreateTexture(nil, "OVERLAY")
    castbarFrame.Spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castbarFrame.Spark:SetSize(16, BAR_HEIGHT + 8)
    castbarFrame.Spark:SetBlendMode("ADD")
    castbarFrame.Spark:Hide()
    
    -- Interrupt cooldown frame (right side)
    castbarFrame.InterruptFrame = CreateFrame("Frame", nil, castbarFrame)
    castbarFrame.InterruptFrame:SetPoint("TOPLEFT", castbarFrame, "TOPRIGHT", 2, 0)
    castbarFrame.InterruptFrame:SetPoint("BOTTOMLEFT", castbarFrame, "BOTTOMRIGHT", 2, 0)
    castbarFrame.InterruptFrame:SetWidth(ICON_SIZE)
    
    -- Interrupt icon
    castbarFrame.InterruptFrame.Icon = castbarFrame.InterruptFrame:CreateTexture(nil, "ARTWORK")
    castbarFrame.InterruptFrame.Icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    castbarFrame.InterruptFrame.Icon:SetAllPoints()
    
    -- Interrupt cooldown swipe
    castbarFrame.InterruptFrame.Cooldown = CreateFrame("Cooldown", nil, castbarFrame.InterruptFrame, "CooldownFrameTemplate")
    castbarFrame.InterruptFrame.Cooldown:SetAllPoints()
    castbarFrame.InterruptFrame.Cooldown:SetDrawEdge(false)
    
    -- Interrupt border
    castbarFrame.InterruptFrame.Border = CreateFrame("Frame", nil, castbarFrame.InterruptFrame, "BackdropTemplate")
    castbarFrame.InterruptFrame.Border:SetPoint("TOPLEFT", castbarFrame.InterruptFrame, -1, 1)
    castbarFrame.InterruptFrame.Border:SetPoint("BOTTOMRIGHT", castbarFrame.InterruptFrame, 1, -1)
    castbarFrame.InterruptFrame.Border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    castbarFrame.InterruptFrame.Border:SetBackdropBorderColor(0, 0, 0, 1)
    
    -- Set interrupt icon if we have one
    if interruptInfo then
        local iconTexture = C_Spell.GetSpellTexture(interruptInfo.spellId)
        if iconTexture then
            castbarFrame.InterruptFrame.Icon:SetTexture(iconTexture)
        end
        castbarFrame.InterruptFrame:Show()
    else
        castbarFrame.InterruptFrame:Hide()
    end
    
    -- Store state
    castbarFrame.isInterruptable = false
    castbarFrame.interruptOnCooldown = false
end

-- Update the castbar color based on state
local function UpdateCastBarColor()
    if not castbarFrame then return end
    
    if isInterruptable then
        if interruptOnCooldown then
            castbarFrame.CastBar:SetStatusBarColor(unpack(COLOR_ON_COOLDOWN))
        else
            castbarFrame.CastBar:SetStatusBarColor(unpack(COLOR_INTERRUPTABLE))
        end
    else
        castbarFrame.CastBar:SetStatusBarColor(unpack(COLOR_NOT_INTERRUPTABLE))
    end
end

-- Update spark position (shows when interrupt will be ready during the cast)
local function UpdateSpark()
    if not castbarFrame or not castbarFrame.Spark then return end
    
    -- Only show spark when interrupt is on cooldown and cast is interruptable
    if not interruptOnCooldown or not isInterruptable or not interruptInfo then
        castbarFrame.Spark:Hide()
        return
    end
    
    local interruptReadyTime = interruptUsedTime + interruptInfo.cooldown
    
    -- If interrupt will be ready after cast ends, hide spark
    if interruptReadyTime >= castEndTime then
        castbarFrame.Spark:Hide()
        return
    end
    
    -- Calculate position on the bar
    local castDuration = castEndTime - castStartTime
    if castDuration <= 0 then
        castbarFrame.Spark:Hide()
        return
    end
    
    local readyPoint = (interruptReadyTime - castStartTime) / castDuration
    if readyPoint < 0 or readyPoint > 1 then
        castbarFrame.Spark:Hide()
        return
    end
    
    local barWidth = castbarFrame.CastBar:GetWidth()
    castbarFrame.Spark:ClearAllPoints()
    castbarFrame.Spark:SetPoint("CENTER", castbarFrame.CastBar, "LEFT", readyPoint * barWidth, 0)
    castbarFrame.Spark:Show()
end

-- Update castbar position from settings
local function UpdatePosition()
    if not castbarFrame then return end
    
    local settings = JT:GetModuleSettings("FocusCastbar")
    local posX = settings and settings.positionX or 0
    local posY = settings and settings.positionY or -50
    
    castbarFrame:ClearAllPoints()
    castbarFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
end

-- Event handler
local function OnEvent(self, event, ...)
    if not isEnabled then return end
    
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID, spellId = ...
        
        -- Check if player used their interrupt
        if interruptInfo and spellId == interruptInfo.spellId then
            interruptOnCooldown = true
            interruptUsedTime = GetTime()
            UpdateCastBarColor()
            UpdateSpark()
            
            -- Show cooldown on interrupt frame
            if castbarFrame and castbarFrame.InterruptFrame then
                castbarFrame.InterruptFrame.Cooldown:SetCooldown(GetTime(), interruptInfo.cooldown)
            end
            
            -- Timer to reset interrupt state
            C_Timer.After(interruptInfo.cooldown, function()
                interruptOnCooldown = false
                
                if castbarFrame and castbarFrame:IsShown() then
                    UpdateCastBarColor()
                    UpdateSpark()
                end
            end)
        end
        
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        local unit = ...
        if unit == "focus" then
            isInterruptable = true
            UpdateCastBarColor()
            UpdateSpark()
        end
        
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        local unit = ...
        if unit == "focus" then
            isInterruptable = false
            UpdateCastBarColor()
            UpdateSpark()
        end
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

-- Initialize hooks on FocusFrame.spellbar
local function InitializeHooks()
    if hooksInitialized then return end
    
    -- Check if FocusFrame exists (it should in retail WoW)
    if not FocusFrame or not FocusFrame.spellbar then
        return
    end
    
    -- Hook OnShow - cast started
    FocusFrame.spellbar:HookScript("OnShow", function(self)
        if not isEnabled then return end
        if not castbarFrame then CreateCastbarFrame() end
        
        -- Get spell info
        castbarFrame.Icon:SetTexture(C_Spell.GetSpellTexture(self.spellID))
        castbarFrame.SpellNameText:SetText(self.Text:GetText())
        
        -- Get cast timing
        local min, max = self:GetMinMaxValues()
        castbarFrame.CastBar:SetMinMaxValues(min, max)
        
        -- Store cast timing for spark calculation
        local name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo("focus")
        if not startTimeMS then
            name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("focus")
        end
        
        if startTimeMS and endTimeMS then
            castStartTime = startTimeMS / 1000
            castEndTime = endTimeMS / 1000
        else
            castStartTime = GetTime()
            castEndTime = GetTime() + max
        end
        
        -- Check interruptable state
        isInterruptable = self:IsInterruptable()
        
        UpdateCastBarColor()
        UpdateSpark()
        castbarFrame:Show()
    end)
    
    -- Hook OnHide - cast ended
    FocusFrame.spellbar:HookScript("OnHide", function()
        if castbarFrame then
            castbarFrame:Hide()
        end
    end)
    
    -- Hook OnUpdate - update progress
    local timePattern = "%.1f/%.1f"
    FocusFrame.spellbar:HookScript("OnUpdate", function(self, elapsed)
        if not isEnabled or not castbarFrame or not castbarFrame:IsShown() then return end
        
        local progress = self:GetValue()
        local min, max = self:GetMinMaxValues()
        
        castbarFrame.CastBar:SetValue(progress)
        castbarFrame.TimeText:SetFormattedText(timePattern, progress, max)
        
        -- Update spark position in case interrupt came off cooldown
        UpdateSpark()
    end)
    
    -- Override fade animations for instant hide on interrupt/finish
    FocusFrame.spellbar.PlayInterruptAnims = function(self)
        self:Hide()
    end
    
    FocusFrame.spellbar.PlayFadeAnim = function(self)
        self:Hide()
    end
    
    hooksInitialized = true
end

-- Initialize the module
function FocusCastbar:Init()
    -- Get player's interrupt spell
    local _, playerClass = UnitClass("player")
    interruptInfo = CLASS_INTERRUPTS[playerClass]
    
    -- Initialize hooks (they check isEnabled before doing work)
    InitializeHooks()
end

-- Enable the module
function FocusCastbar:Enable()
    isEnabled = true
    
    -- Register events
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "focus")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "focus")
    
    -- Create frame if needed
    if not castbarFrame then
        CreateCastbarFrame()
    end
    
    -- Update position from settings
    UpdatePosition()
    
    -- Check current interrupt cooldown state
    if interruptInfo then
        local start, duration = C_Spell.GetSpellCooldown(interruptInfo.spellId)
        if start and duration and start > 0 and duration > 0 then
            interruptOnCooldown = true
            interruptUsedTime = start
            
            -- Set up timer for when it comes off cooldown
            local remaining = (start + duration) - GetTime()
            if remaining > 0 then
                C_Timer.After(remaining, function()
                    interruptOnCooldown = false
                    if castbarFrame and castbarFrame:IsShown() then
                        UpdateCastBarColor()
                        UpdateSpark()
                    end
                end)
            else
                interruptOnCooldown = false
            end
        else
            interruptOnCooldown = false
        end
    end
end

-- Disable the module
function FocusCastbar:Disable()
    isEnabled = false
    
    eventFrame:UnregisterAllEvents()
    
    if castbarFrame then
        castbarFrame:Hide()
    end
end

-- Handle setting changes
function FocusCastbar:OnSettingChanged(key, value)
    if key == "positionX" or key == "positionY" then
        UpdatePosition()
    end
end

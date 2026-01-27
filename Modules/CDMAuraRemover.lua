-- JetTools CDMAuraRemover Module
-- Replaces Aura Duration (yellow) with Spell Cooldown (black) on action bars when a buff is active
-- Originally "CooldownSwipeControl"

local addonName, JT = ...

local CDMAuraRemover = {}
JT:RegisterModule("CDMAuraRemover", CDMAuraRemover)

-- Helper Functions
local function HasActiveAura(icon)
    if not icon then return false end
    local auraID = icon.auraInstanceID
    return auraID and type(auraID) == "number" and auraID > 0
end

local function GetSpellID(icon)
    if not icon then return nil end
    if icon.cooldownInfo then
        return icon.cooldownInfo.overrideSpellID or icon.cooldownInfo.spellID
    end
    return nil
end

-- Apply desaturation when aura is active but we're showing spell cooldown
local function ApplyDesaturationForAuraActive(icon, desaturate)
    if not icon then return end
    
    local iconTexture = icon.icon or icon.Icon
    if not iconTexture then return end
    
    -- Set the force value flag - hooks will enforce this
    if desaturate then
        icon._CSC_ForceDesatValue = 1
    else
        icon._CSC_ForceDesatValue = nil
    end
    
    -- Apply immediately
    if desaturate then
        if iconTexture.SetDesaturation then
            iconTexture:SetDesaturation(1)
        elseif iconTexture.SetDesaturated then
            iconTexture:SetDesaturated(true)
        end
    else
        if iconTexture.SetDesaturation then
            iconTexture:SetDesaturation(0)
        elseif iconTexture.SetDesaturated then
            iconTexture:SetDesaturated(false)
        end
    end
end

-- Hook Desaturation on Icon Texture
local function HookDesaturation(icon)
    local iconTexture = icon.icon or icon.Icon
    if not iconTexture or iconTexture._CSC_DesatHooked then return end
    
    iconTexture._CSC_DesatHooked = true
    iconTexture._CSC_ParentIcon = icon
    
    -- Hook SetDesaturated (boolean version)
    if iconTexture.SetDesaturated then
        hooksecurefunc(iconTexture, "SetDesaturated", function(self, desaturated)
            local pf = self._CSC_ParentIcon
            if not pf or pf._CSC_BypassDesatHook then return end
            
            -- If we have a forced desaturation value, enforce it
            local forceValue = pf._CSC_ForceDesatValue
            if forceValue ~= nil and self.SetDesaturation then
                pf._CSC_BypassDesatHook = true
                self:SetDesaturation(forceValue)
                pf._CSC_BypassDesatHook = false
            end
        end)
    end
    
    -- Hook SetDesaturation (numeric version)
    if iconTexture.SetDesaturation then
        hooksecurefunc(iconTexture, "SetDesaturation", function(self, value)
            local pf = self._CSC_ParentIcon
            if not pf or pf._CSC_BypassDesatHook then return end
            
            -- If we have a forced desaturation value, enforce it
            local forceValue = pf._CSC_ForceDesatValue
            if forceValue ~= nil then
                pf._CSC_BypassDesatHook = true
                self:SetDesaturation(forceValue)
                pf._CSC_BypassDesatHook = false
            end
        end)
    end
end

-- Unified hook for SetCooldown that handles Aura Override
local function HookSetCooldown(icon)
    if not icon or not icon.Cooldown then return end
    
    -- Ensure desaturation hooks are in place
    HookDesaturation(icon)
    
    if icon._CSC_SetCooldownHooked then return end
    icon._CSC_SetCooldownHooked = true

    icon.Cooldown._CSCParentIcon = icon

    local function OnSetCooldown(self)
        -- Only run logic if module is enabled
        if not JT:IsModuleEnabled("CDMAuraRemover") then return end

        local parentIcon = self._CSCParentIcon
        if not parentIcon then return end

        if parentIcon._CSC_BypassCDHook then return end

        local settings = JT:GetModuleSettings("CDMAuraRemover")
        local overrideActive = false

        -- Aura Override Logic
        if settings and settings.enableAuraOverride and HasActiveAura(parentIcon) then
            local spellID = GetSpellID(parentIcon)
            if spellID then
                -- Check if this is a charge spell
                local isChargeSpell = false
                pcall(function()
                    local chargeInfo = C_Spell.GetSpellCharges(spellID)
                    isChargeSpell = chargeInfo ~= nil
                end)

                if isChargeSpell and C_Spell.GetSpellChargeDuration then
                    -- CHARGE SPELL
                    local ok, chargeDurObj = pcall(C_Spell.GetSpellChargeDuration, spellID)
                    if ok and chargeDurObj then
                        parentIcon._CSC_BypassCDHook = true
                        pcall(function()
                            if self.SetCooldownFromDurationObject then
                                self:SetCooldownFromDurationObject(chargeDurObj)
                            end
                        end)
                        parentIcon._CSC_BypassCDHook = false
                        
                        -- Set swipe color to black (like regular cooldown)
                        if self.SetSwipeColor then
                            self:SetSwipeColor(0, 0, 0, 0.8)
                        end
                        overrideActive = true
                    end
                else
                    -- NORMAL SPELL
                    local ok, cooldownInfo = pcall(C_Spell.GetSpellCooldown, spellID)
                    if ok and cooldownInfo and cooldownInfo.duration and cooldownInfo.startTime then
                        parentIcon._CSC_BypassCDHook = true
                        self:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
                        parentIcon._CSC_BypassCDHook = false
                        
                        -- Set swipe color to black
                        if self.SetSwipeColor then
                            self:SetSwipeColor(0, 0, 0, 0.8)
                        end
                        
                        -- Enforce desaturation
                        ApplyDesaturationForAuraActive(parentIcon, true)
                        overrideActive = true
                    end
                end
            end
        end
        
        if not overrideActive and settings and settings.enableAuraOverride then
             -- Reset desaturation if we are not overriding
             ApplyDesaturationForAuraActive(parentIcon, false)
        end
    end

    hooksecurefunc(icon.Cooldown, "SetCooldown", OnSetCooldown)
    
    -- Also hook SetCooldownFromDurationObject if available, redirecting to the same logic
    if icon.Cooldown.SetCooldownFromDurationObject then
        hooksecurefunc(icon.Cooldown, "SetCooldownFromDurationObject", function(self)
             OnSetCooldown(self)
        end)
    end
end

-- Process all icons in a viewer
local function ProcessViewer(viewer)
    if not viewer then return end
    local children = {viewer:GetChildren()}
    for _, icon in ipairs(children) do
        if icon.Cooldown then
            HookSetCooldown(icon)
        end
    end
end

-- Apply settings to all CDM viewers and refresh them if needed
function CDMAuraRemover:ApplyAllSettings()
    local settings = JT:GetModuleSettings("CDMAuraRemover")
    if not settings then return end

    local viewers = {
        _G.EssentialCooldownViewer,
        _G.UtilityCooldownViewer,
    }
    for _, viewer in ipairs(viewers) do
        ProcessViewer(viewer)
        if viewer and viewer.Layout and not viewer._CSC_LayoutHooked then
            viewer._CSC_LayoutHooked = true
            hooksecurefunc(viewer, "Layout", function()
                C_Timer.After(0.1, function()
                    ProcessViewer(viewer)
                end)
            end)
        end
        
        -- Force refresh of cooldowns to apply overrides immediately
        if viewer and viewer:IsShown() and settings.enableAuraOverride then
             local children = {viewer:GetChildren()}
             for _, icon in ipairs(children) do
                 if icon.Cooldown and HasActiveAura(icon) then
                      -- Trigger the hook by re-setting the current cooldown
                      local start = icon.Cooldown:GetCooldownTimes()
                      local duration = icon.Cooldown:GetCooldownDuration()
                      if start and duration then
                          icon.Cooldown:SetCooldown(start, duration)
                      end
                 end
             end
        end
    end
end

-- Event Handling
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, arg)
    if event == "UNIT_AURA" and arg == "player" then
        if JT:IsModuleEnabled("CDMAuraRemover") then
             C_Timer.After(0.1, function() CDMAuraRemover:ApplyAllSettings() end)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if JT:IsModuleEnabled("CDMAuraRemover") then
             C_Timer.After(0.1, function() CDMAuraRemover:ApplyAllSettings() end)
        end
    end
end)

-- Module Methods

function CDMAuraRemover:Init()
    -- Initial hook setup waiting for Blizzard_CooldownManager
    if C_AddOns.IsAddOnLoaded("Blizzard_CooldownManager") then
        self:ApplyAllSettings()
    else
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(self, event, arg)
            if arg == "Blizzard_CooldownManager" then
                C_Timer.After(0.5, function() CDMAuraRemover:ApplyAllSettings() end)
                self:UnregisterAllEvents()
            end
        end)
    end
end

function CDMAuraRemover:Enable()
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:ApplyAllSettings()
end

function CDMAuraRemover:Disable()
    eventFrame:UnregisterEvent("UNIT_AURA")
    eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    -- We can't unhook secure hooks, but the hook logic checks IsModuleEnabled
end

function CDMAuraRemover:OnSettingChanged(key, value)
    self:ApplyAllSettings()
end

function CDMAuraRemover:GetOptions()
    return {
        { type = "header", label = "Cooldown Swipe Control" },
        { type = "description", text = "Replaces the yellow Aura Duration swipe with the black Spell Cooldown swipe when a buff is active on the action bar." },
        { type = "checkbox", label = "Enabled", key = "enabled", default = true },
        { type = "checkbox", label = "Enable Aura Override", key = "enableAuraOverride", default = true },
    }
end

-- JetTools Character Stat Formatting Module
-- Formats character stats with raw numbers and percentages

local addonName, JT = ...

local CharacterStatFormatting = {}
JT:RegisterModule("CharacterStatFormatting", CharacterStatFormatting)

-- Module state
local isEnabled = false

-- Hooks
local hooksInitialized = false

local function HookItemLevel()
    hooksecurefunc("PaperDollFrame_SetItemLevel", function()
        if not isEnabled then return end
        if CharacterStatsPane and CharacterStatsPane.ItemLevelFrame and CharacterStatsPane.ItemLevelFrame.Value then
            CharacterStatsPane.ItemLevelFrame.Value:SetText(select(2, GetAverageItemLevel()))
        end
    end)
end

local function HookStatLabels()
    hooksecurefunc("PaperDollFrame_SetLabelAndText", function(statFrame, label, text, isPercentage, numericValue)
        if not isEnabled then return end
        
        if label == STAT_CRITICAL_STRIKE
        or label == STAT_HASTE
        or label == STAT_MASTERY
        or label == STAT_SPEED
        or label == STAT_LIFESTEAL
        or label == STAT_AVOIDANCE
        or label == STAT_VERSATILITY
        then
            local rawStatAmount = 0

            if label == STAT_HASTE then
                numericValue = GetHaste()
                rawStatAmount = GetCombatRating(CR_HASTE_RANGED)
            elseif label == STAT_CRITICAL_STRIKE then
                rawStatAmount = GetCombatRating(CR_CRIT_RANGED)
            elseif label == STAT_MASTERY then
                rawStatAmount = GetCombatRating(CR_MASTERY)
            elseif label == STAT_SPEED then
                rawStatAmount = GetCombatRating(CR_SPEED)
            elseif label == STAT_LIFESTEAL then
                rawStatAmount = GetCombatRating(CR_LIFESTEAL)
            elseif label == STAT_AVOIDANCE then
                rawStatAmount = GetCombatRating(CR_AVOIDANCE)
            elseif label == STAT_VERSATILITY then
                rawStatAmount = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)
            end

            if statFrame and statFrame.Value then
                statFrame.Value:SetText(string.format("%s | %.2f %%", BreakUpLargeNumbers(rawStatAmount), numericValue))
            end
        end
    end)
end

function CharacterStatFormatting:Init()
    if not hooksInitialized then
        HookItemLevel()
        HookStatLabels()
        hooksInitialized = true
    end
end

function CharacterStatFormatting:Enable()
    isEnabled = true
    -- Force update if Character Frame is open
    if PaperDollFrame and PaperDollFrame:IsVisible() then
        PaperDollFrame_UpdateStats()
    end
end

function CharacterStatFormatting:Disable()
    isEnabled = false
    -- Force update to revert to standard display if Character Frame is open
    if PaperDollFrame and PaperDollFrame:IsVisible() then
        PaperDollFrame_UpdateStats()
    end
end

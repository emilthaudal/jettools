-- JetTools Gear Upgrade Ranks Module
-- Modifies item tooltips to show better formatted upgrade ranks and required crests

local addonName, JT = ...

local GearUpgradeRanks = {}
JT:RegisterModule("GearUpgradeRanks", GearUpgradeRanks)

-- Get options configuration
function GearUpgradeRanks:GetOptions()
    return {
        { type = "header", label = "Gear Upgrade Ranks" },
        { type = "description", text = "Better formatted upgrade ranks and crests in tooltips" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = true }
    }
end

-- Module state
local isEnabled = false
local initialized = false

-- Expansion detection
local IS_MIDNIGHT = select(4, GetBuildInfo()) >= 120000

-- Crest Data
-- Used to identify crests by internal ID and provide display info
local CRESTS = IS_MIDNIGHT
        and {
            [1] = { shortName = "Veteran", color = ITEM_QUALITY_COLORS[2], achievement = 0 },  -- Green
            [2] = { shortName = "Champion", color = ITEM_QUALITY_COLORS[3], achievement = 0 }, -- Blue
            [3] = { shortName = "Hero", color = ITEM_QUALITY_COLORS[4], achievement = 0 },     -- Epic
            [4] = { shortName = "Myth", color = ITEM_QUALITY_COLORS[5], achievement = 0 },     -- Legendary
        }
    or {
        [0] = { shortName = "Valorstones", color = ITEM_QUALITY_COLORS[7] },                -- Heirloom/Account
        [1] = { shortName = "Weathered", color = ITEM_QUALITY_COLORS[2], achievement = 41886 }, -- Green
        [2] = { shortName = "Carved", color = ITEM_QUALITY_COLORS[3], achievement = 41887 },    -- Blue
        [3] = { shortName = "Runed", color = ITEM_QUALITY_COLORS[4], achievement = 41888 },     -- Epic
        [4] = { shortName = "Gilded", color = ITEM_QUALITY_COLORS[5], achievement = 41892 },    -- Legendary
    }

-- Upgrade Tiers Configuration
-- Defines ranges, max upgrades, and which crests are needed at which step
local UPGRADE_TIERS = IS_MIDNIGHT
        and {
            {
                name = "Adventurer",
                minIlvl = 220,
                maxIlvl = 237,
                maxUpgrade = 6,
                color = ITEM_QUALITY_COLORS[1], -- Common/White
                crestLevels = { [1] = CRESTS[0], [3] = CRESTS[0], [6] = nil },
            },
            {
                name = "Veteran",
                minIlvl = 233,
                maxIlvl = 250,
                maxUpgrade = 6,
                color = ITEM_QUALITY_COLORS[2], -- Green
                crestLevels = { [1] = CRESTS[0], [3] = CRESTS[0], [6] = nil },
            },
            {
                name = "Champion",
                minIlvl = 246,
                maxIlvl = 263,
                maxUpgrade = 6,
                color = ITEM_QUALITY_COLORS[3], -- Blue
                crestLevels = { [1] = CRESTS[0], [3] = CRESTS[0], [6] = nil },
            },
            {
                name = "Hero",
                minIlvl = 259,
                maxIlvl = 276,
                maxUpgrade = 6,
                color = ITEM_QUALITY_COLORS[4], -- Epic
                crestLevels = { [1] = CRESTS[0], [3] = CRESTS[0], [6] = nil },
            },
            {
                name = "Myth",
                minIlvl = 272,
                maxIlvl = 289,
                maxUpgrade = 6,
                color = ITEM_QUALITY_COLORS[5], -- Legendary
                crestLevels = { [1] = CRESTS[0], [3] = CRESTS[0], [6] = nil },
            },
        }
    or {
        {
            name = "Explorer",
            minIlvl = 642,
            maxIlvl = 665,
            maxUpgrade = 8,
            color = ITEM_QUALITY_COLORS[0], -- Poor/Gray (Matches reference)
            crestLevels = { [1] = CRESTS[0], [4] = CRESTS[0], [8] = nil },
        },
        {
            name = "Adventurer",
            minIlvl = 655,
            maxIlvl = 678,
            maxUpgrade = 8,
            color = ITEM_QUALITY_COLORS[1], -- White
            crestLevels = { [1] = CRESTS[0], [4] = CRESTS[1], [8] = nil },
        },
        {
            name = "Veteran",
            minIlvl = 668,
            maxIlvl = 691,
            maxUpgrade = 8,
            color = ITEM_QUALITY_COLORS[2], -- Green
            crestLevels = { [1] = CRESTS[1], [4] = CRESTS[2], [8] = nil },
        },
        {
            name = "Champion",
            minIlvl = 681,
            maxIlvl = 704,
            maxUpgrade = 8,
            color = ITEM_QUALITY_COLORS[3], -- Blue
            crestLevels = { [1] = CRESTS[2], [4] = CRESTS[3], [8] = nil },
        },
        {
            name = "Hero",
            minIlvl = 693,
            maxIlvl = 718,
            maxUpgrade = 8,
            color = ITEM_QUALITY_COLORS[4], -- Epic
            crestLevels = { [1] = CRESTS[3], [4] = CRESTS[4], [8] = nil },
        },
        {
            name = "Myth",
            minIlvl = 707,
            maxIlvl = 730,
            maxUpgrade = 8,
            color = ITEM_QUALITY_COLORS[5], -- Legendary
            crestLevels = { [1] = CRESTS[4], [8] = nil },
        },
    }

-- Helper: Get crest dynamically based on upgrade level
local function GetCrestForLevel(crestLevels, current, maxUpgrade)
    -- If at max upgrade, no crest is required
    if current == maxUpgrade then
        return nil
    end

    local selectedCrest = nil
    for level, crest in pairs(crestLevels) do
        if current >= level then
            selectedCrest = crest -- Update to highest applicable crest
        end
    end

    return selectedCrest
end

-- Helper: Get tier data based on item level, upgrade level, and name
local function GetUpgradeTierData(ilvl, current, total, tierName)
    local bestMatch = nil
    
    for _, tier in ipairs(UPGRADE_TIERS) do
        if ilvl >= tier.minIlvl and ilvl <= tier.maxIlvl and total == tier.maxUpgrade then
            -- Found a mathematical match
            local match = {
                name = tier.name,
                minIlvl = tier.minIlvl,
                maxIlvl = tier.maxIlvl,
                color = tier.color,
                crest = GetCrestForLevel(tier.crestLevels, current, tier.maxUpgrade),
            }
            
            -- If names match exactly, return immediately (Highest Priority)
            if tier.name == tierName then
                return match
            end
            
            -- Otherwise store as fallback
            if not bestMatch then
                bestMatch = match
            end
        end
    end
    
    return bestMatch
end

-- Tooltip Hook Function
local function OnTooltipSetItem(tooltip, data)
    if not isEnabled then return end
    
    local _, itemLink = TooltipUtil.GetDisplayedItem(tooltip)
    if not itemLink then return end

    -- Create ItemMixin to get precise level info
    local item = Item:CreateFromItemLink(itemLink)
    if item:IsItemEmpty() then return end

    local itemLevel = item:GetCurrentItemLevel()
    
    -- Scan tooltip lines to find the upgrade string
    -- Format: "Upgrade Level: Adventurer 4/8" or similar localized string
    -- We use the global format string to match it reliably
    for i = 1, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        local text = line:GetText()

        if text and text:match(ITEM_UPGRADE_TOOLTIP_FORMAT_STRING:gsub("%%s %%d/%%d", "(%%D+ %%d+/%%d+)")) then
            local tierName, current, total =
                text:match(ITEM_UPGRADE_TOOLTIP_FORMAT_STRING:gsub("%%s %%d/%%d", "(%%D+) (%%d+)/(%%d+)"))

            local tierData = GetUpgradeTierData(tonumber(itemLevel), tonumber(current), tonumber(total), tierName)
            if not tierData then return end

            -- 1. Modify the main upgrade text line
            -- Format: [Color]Rank X/Y|r (Min-Max)
            local minIlvl = tierData.minIlvl
            local maxIlvl = tierData.maxIlvl
            
            if minIlvl and maxIlvl and itemLevel >= minIlvl and itemLevel <= maxIlvl then
                local tierHexColorMarkup = tierData.color.hex
                local rangeHexColorMarkup = CreateColor(0.6, 0.6, 0.6):GenerateHexColorMarkup() -- Grey

                local newLineText = string.format(
                    "%s%d/%d %s|r %s(%d-%d)|r",
                    tierHexColorMarkup,
                    current,
                    total,
                    tierName, -- Use the localized name captured from tooltip
                    rangeHexColorMarkup,
                    minIlvl,
                    maxIlvl
                )

                line:SetText(newLineText)
                line:Show()
            end

            -- 2. Add crest info to the right side
            if tierData.crest then
                local crest = tierData.crest
                local crestName = crest.shortName
                local crestName_colored = crest.color.hex .. crestName .. "|r"
                local achievement = crest.achievement and select(13, GetAchievementInfo(crest.achievement))
                
                -- Add atlas icon
                local rightLineText = "|A:2329:20:20:1:-1|a" .. (not achievement and crestName_colored or "")
                local rightLine = _G[tooltip:GetName() .. "TextRight" .. i]
                
                if rightLine then
                    rightLine:SetText(rightLineText)
                    rightLine:Show()
                end
            end
        end
    end
end

-- Initialize the module
function GearUpgradeRanks:Init()
    -- Initialize hook once (global callback)
    -- Logic inside checks isEnabled
    if not initialized and TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
        initialized = true
    end
end

-- Enable the module
function GearUpgradeRanks:Enable()
    isEnabled = true
end

-- Disable the module
function GearUpgradeRanks:Disable()
    isEnabled = false
end

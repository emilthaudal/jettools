-- JetTools Combat Res Tracker Module
-- Tracks Rebirth (spell 20484) charges and cooldown for Druids in the group.
-- Displays charge count and remaining cooldown as a text overlay.
-- Hides when the player is not in a group or the spell is not known.

local addonName, JT = ...

local CombatRes = {}
JT:RegisterModule("CombatRes", CombatRes)

-- Upvalues
local GetTime        = GetTime
local IsInGroup      = IsInGroup
local IsInRaid       = IsInRaid
local floor          = math.floor

-- Rebirth spell ID (works for all Druid specs)
local REBIRTH_SPELL_ID = 20484

-- LibSharedMedia support
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local FALLBACK_FONTS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"]         = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]           = "Fonts\\SKURRI.TTF",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
}

local function GetFontPath(fontName)
    if LSM then
        return LSM:Fetch("font", fontName) or "Fonts\\FRIZQT__.TTF"
    end
    return FALLBACK_FONTS[fontName] or "Fonts\\FRIZQT__.TTF"
end

local function GetAvailableFonts()
    if LSM then
        local list = {}
        for _, name in ipairs(LSM:List("font")) do
            list[#list + 1] = { text = name, value = name }
        end
        return list
    end
    local list = {}
    for name in pairs(FALLBACK_FONTS) do
        list[#list + 1] = { text = name, value = name }
    end
    return list
end

-- ──────────────────────────────────────────────────────────────
-- Module state
-- ──────────────────────────────────────────────────────────────

local isEnabled  = false
local resFrame   = nil
local resText    = nil
local lastUpdate = 0
local UPDATE_INTERVAL = 0.1

-- ──────────────────────────────────────────────────────────────
-- Display update
-- ──────────────────────────────────────────────────────────────

local function UpdateDisplay()
    if not resFrame then return end

    if not isEnabled then
        resFrame:Hide()
        return
    end

    -- Only show when in a group (includes party and raid)
    if not IsInGroup() and not IsInRaid() then
        resFrame:Hide()
        return
    end

    -- Query spell charges
    local chargeTable = C_Spell.GetSpellCharges(REBIRTH_SPELL_ID)
    if not chargeTable then
        -- Spell not known by this player
        resFrame:Hide()
        return
    end

    local currentCharges = chargeTable.currentCharges or 0
    local maxCharges     = chargeTable.maxCharges or 0
    local cooldownStart  = chargeTable.cooldownStartTime or 0
    local cooldownDur    = chargeTable.cooldownDuration or 0

    local settings = JT:GetModuleSettings("CombatRes")
    local showLabel = settings and settings.showLabel

    -- Build the display string
    local parts = {}

    if showLabel then
        parts[#parts + 1] = "|cffaaaaff" .. "CR:" .. "|r "
    end

    -- Charge count colored by availability
    if currentCharges > 0 then
        parts[#parts + 1] = "|cff44ff44" .. currentCharges .. "/" .. maxCharges .. "|r"
    else
        parts[#parts + 1] = "|cffff4444" .. currentCharges .. "/" .. maxCharges .. "|r"
    end

    -- Cooldown timer (only when a charge is on cooldown and we're below max)
    if currentCharges < maxCharges and cooldownDur > 0 then
        local remaining = cooldownStart + cooldownDur - GetTime()
        if remaining > 0 then
            local m = floor(remaining / 60)
            local s = floor(remaining % 60)
            local cdStr
            if m > 0 then
                cdStr = string.format(" |cffcccccc%d:%02d|r", m, s)
            else
                cdStr = string.format(" |cffcccccc%ds|r", s)
            end
            parts[#parts + 1] = cdStr
        end
    end

    resText:SetText(table.concat(parts))
    resFrame:Show()
end

-- ──────────────────────────────────────────────────────────────
-- Frame creation
-- ──────────────────────────────────────────────────────────────

local function CreateResFrame()
    if resFrame then return end

    resFrame = CreateFrame("Frame", "JetToolsCombatRes", UIParent)
    resFrame:SetFrameStrata("MEDIUM")
    resFrame:SetClampedToScreen(true)
    resFrame:SetSize(200, 40)

    local settings = JT:GetModuleSettings("CombatRes")
    local x = (settings and settings.posX) or 0
    local y = (settings and settings.posY) or -250
    resFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)

    resText = resFrame:CreateFontString(nil, "OVERLAY")
    resText:SetPoint("CENTER")
    resText:SetJustifyH("CENTER")

    resFrame:SetScript("OnUpdate", function(self, elapsed)
        if not isEnabled then return end
        lastUpdate = lastUpdate + elapsed
        if lastUpdate < UPDATE_INTERVAL then return end
        lastUpdate = 0
        UpdateDisplay()
    end)

    resFrame:Hide()
    CombatRes:ApplySettings()
end

-- ──────────────────────────────────────────────────────────────
-- Settings application
-- ──────────────────────────────────────────────────────────────

function CombatRes:ApplySettings()
    if not resText then return end
    local settings = JT:GetModuleSettings("CombatRes")
    if not settings then return end
    local fontPath = GetFontPath(settings.fontFace or "Friz Quadrata TT")
    local fontSize = settings.fontSize or 18
    resText:SetFont(fontPath, fontSize, "OUTLINE")
    if resFrame then
        resFrame:SetHeight(math.max(30, fontSize + 12))
    end
end

function CombatRes:ApplyPosition()
    if not resFrame then return end
    local settings = JT:GetModuleSettings("CombatRes")
    if not settings then return end
    local anchorName = settings.anchorFrame
    local anchor = (anchorName and anchorName ~= "" and _G[anchorName]) or UIParent
    resFrame:ClearAllPoints()
    resFrame:SetPoint("CENTER", anchor, "CENTER", settings.posX or 0, settings.posY or -250)
end

-- ──────────────────────────────────────────────────────────────
-- Options
-- ──────────────────────────────────────────────────────────────

function CombatRes:GetOptions()
    return {
        { type = "header",   label = "Combat Res Tracker" },
        { type = "description", text = "Tracks Rebirth charges and cooldown. Only visible while in a group." },
        { type = "checkbox", label = "Enabled",      key = "enabled",   default = false },
        { type = "checkbox", label = "Show 'CR:' label", key = "showLabel", default = true },
        { type = "dropdown", label = "Font",          key = "fontFace",  options = GetAvailableFonts(), default = "Friz Quadrata TT" },
        { type = "slider",   label = "Font Size",     key = "fontSize",  min = 10, max = 64, step = 1,   default = 18  },
        { type = "input",    label = "Anchor Frame (leave blank for screen centre)", key = "anchorFrame", width = 200 },
        { type = "slider",   label = "Position X",    key = "posX",      min = -900, max = 900, step = 1, default = 0    },
        { type = "slider",   label = "Position Y",    key = "posY",      min = -500, max = 500, step = 1, default = -250 },
    }
end

-- ──────────────────────────────────────────────────────────────
-- Event handler
-- ──────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not isEnabled then return end

    if event == "SPELL_UPDATE_CHARGES" then
        -- Delayed so that charge counts have settled
        C_Timer.After(0, UpdateDisplay)
    elseif event == "GROUP_ROSTER_UPDATE"
          or event == "PLAYER_ENTERING_WORLD"
          or event == "CHALLENGE_MODE_START" then
        UpdateDisplay()
    end
end)

-- ──────────────────────────────────────────────────────────────
-- Module interface
-- ──────────────────────────────────────────────────────────────

function CombatRes:Init()
    CreateResFrame()
end

function CombatRes:Enable()
    isEnabled  = true
    lastUpdate = 0
    eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CHALLENGE_MODE_START")
    UpdateDisplay()
end

function CombatRes:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:UnregisterEvent("CHALLENGE_MODE_START")
    if resFrame then resFrame:Hide() end
end

function CombatRes:OnSettingChanged(key, value)
    if key == "fontSize" or key == "fontFace" then
        self:ApplySettings()
    elseif key == "posX" or key == "posY" or key == "anchorFrame" then
        self:ApplyPosition()
    end
    -- Keep preview live while options panel is open
    if _G["JetToolsOptionsFrame"] and _G["JetToolsOptionsFrame"]:IsShown() then
        self:ShowPreview()
    else
        UpdateDisplay()
    end
end

function CombatRes:ShowPreview()
    if not resFrame then CreateResFrame() end
    self:ApplySettings()
    self:ApplyPosition()
    if resText then
        local settings = JT:GetModuleSettings("CombatRes")
        local label = (settings and settings.showLabel) and "|cffaaaaff" .. "CR:|r " or ""
        resText:SetText(label .. "|cff44ff442/2|r |cffcccccc0:30|r")
    end
    if resFrame then resFrame:Show() end
end

function CombatRes:HidePreview()
    if not isEnabled and resFrame then
        resFrame:Hide()
    end
end

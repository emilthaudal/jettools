-- JetTools Combat Timer Module
-- Displays elapsed combat time as a text overlay.
-- Format options: "MM:SS" (updated every 0.25s) or "MM:SS.d" (every 0.1s).
-- When out of combat, shows the last combat duration until the next combat starts.

local addonName, JT = ...

local CombatTimer = {}
JT:RegisterModule("CombatTimer", CombatTimer)

-- Upvalues
local GetTime = GetTime
local floor   = math.floor

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

local isEnabled      = false
local timerFrame     = nil
local timerText      = nil
local startTime      = nil   -- GetTime() when combat started
local running        = false -- true while in combat
local lastDuration   = nil   -- seconds of last finished combat (nil if never seen one)
local lastUpdate     = 0
local UPDATE_FAST    = 0.1
local UPDATE_NORMAL  = 0.25

-- ──────────────────────────────────────────────────────────────
-- Formatting helpers
-- ──────────────────────────────────────────────────────────────

local function FormatTime(seconds, fmt)
    local m = floor(seconds / 60)
    local s = floor(seconds % 60)
    if fmt == "MM:SS.d" then
        local d = floor((seconds % 1) * 10)
        return string.format("%d:%02d.%d", m, s, d)
    end
    return string.format("%d:%02d", m, s)
end

-- ──────────────────────────────────────────────────────────────
-- Frame creation
-- ──────────────────────────────────────────────────────────────

local function CreateTimerFrame()
    if timerFrame then return end

    timerFrame = CreateFrame("Frame", "JetToolsCombatTimer", UIParent)
    timerFrame:SetFrameStrata("MEDIUM")
    timerFrame:SetClampedToScreen(true)
    timerFrame:SetSize(200, 50)

    local settings = JT:GetModuleSettings("CombatTimer")
    local x = (settings and settings.posX) or 0
    local y = (settings and settings.posY) or -200
    timerFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)

    timerText = timerFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("CENTER")
    timerText:SetJustifyH("CENTER")

    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        if not isEnabled then return end

        lastUpdate = lastUpdate + elapsed
        local settings = JT:GetModuleSettings("CombatTimer")
        local fmt = (settings and settings.format) or "MM:SS"
        local interval = (fmt == "MM:SS.d") and UPDATE_FAST or UPDATE_NORMAL

        if lastUpdate < interval then return end
        lastUpdate = 0

        if running and startTime then
            local elapsed_time = GetTime() - startTime
            timerText:SetText(FormatTime(elapsed_time, fmt))
            timerText:SetTextColor(1, 0.3, 0.3)  -- red while in combat
        elseif lastDuration then
            timerText:SetText(FormatTime(lastDuration, fmt))
            timerText:SetTextColor(0.7, 0.7, 0.7)  -- gray when out of combat
        else
            timerText:SetText("")
        end
    end)

    timerFrame:Hide()
    CombatTimer:ApplySettings()
end

-- ──────────────────────────────────────────────────────────────
-- Settings application
-- ──────────────────────────────────────────────────────────────

function CombatTimer:ApplySettings()
    if not timerText then return end
    local settings = JT:GetModuleSettings("CombatTimer")
    if not settings then return end
    local fontPath = GetFontPath(settings.fontFace or "Friz Quadrata TT")
    local fontSize = settings.fontSize or 24
    timerText:SetFont(fontPath, fontSize, "OUTLINE")
    if timerFrame then
        timerFrame:SetHeight(math.max(30, fontSize + 12))
    end
end

function CombatTimer:ApplyPosition()
    if not timerFrame then return end
    local settings = JT:GetModuleSettings("CombatTimer")
    if not settings then return end
    local anchorName = settings.anchorFrame
    local anchor = (anchorName and anchorName ~= "" and _G[anchorName]) or UIParent
    local pt     = (settings.anchorPoint   and settings.anchorPoint   ~= "") and settings.anchorPoint   or "CENTER"
    local relPt  = (settings.relativePoint and settings.relativePoint ~= "") and settings.relativePoint or "CENTER"
    timerFrame:ClearAllPoints()
    timerFrame:SetPoint(pt, anchor, relPt, settings.posX or 0, settings.posY or -200)
end

-- ──────────────────────────────────────────────────────────────
-- Anchor point options (shared)
-- ──────────────────────────────────────────────────────────────

local ANCHOR_POINTS = {
    { text = "Center",       value = "CENTER" },
    { text = "Top",          value = "TOP" },
    { text = "Bottom",       value = "BOTTOM" },
    { text = "Left",         value = "LEFT" },
    { text = "Right",        value = "RIGHT" },
    { text = "Top Left",     value = "TOPLEFT" },
    { text = "Top Right",    value = "TOPRIGHT" },
    { text = "Bottom Left",  value = "BOTTOMLEFT" },
    { text = "Bottom Right", value = "BOTTOMRIGHT" },
}

-- ──────────────────────────────────────────────────────────────
-- Options
-- ──────────────────────────────────────────────────────────────

function CombatTimer:GetOptions()
    return {
        { type = "header",   label = "Combat Timer" },
        { type = "checkbox", label = "Enabled",            key = "enabled",       default = false },
        { type = "dropdown", label = "Font",               key = "fontFace",      options = GetAvailableFonts(), default = "Friz Quadrata TT" },
        { type = "slider",   label = "Font Size",          key = "fontSize",      min = 10, max = 64, step = 1, default = 24 },
        { type = "dropdown", label = "Format",             key = "format",        options = {
            { text = "M:SS",   value = "MM:SS" },
            { text = "M:SS.d", value = "MM:SS.d" },
        }, default = "MM:SS" },
        { type = "checkbox", label = "Print duration to chat on combat end", key = "printOnEnd", default = false },
        { type = "header",   label = "Position" },
        { type = "input",    label = "Anchor Frame (leave blank for screen centre)", key = "anchorFrame", width = 200 },
        { type = "dropdown", label = "Anchor Point (text)",   key = "anchorPoint",   options = ANCHOR_POINTS, default = "CENTER" },
        { type = "dropdown", label = "Relative Point (frame)", key = "relativePoint", options = ANCHOR_POINTS, default = "CENTER" },
        { type = "slider",   label = "Position X",            key = "posX",          min = -2000, max = 2000, step = 1, default = 0    },
        { type = "slider",   label = "Position Y",            key = "posY",          min = -1200, max = 1200, step = 1, default = -200 },
    }
end

-- ──────────────────────────────────────────────────────────────
-- Event handler
-- ──────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event)
    if not isEnabled then return end

    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat
        startTime  = GetTime()
        running    = true
        lastUpdate = 0
        if timerFrame then timerFrame:Show() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat
        running = false
        if startTime then
            lastDuration = GetTime() - startTime
            startTime    = nil

            local settings = JT:GetModuleSettings("CombatTimer")
            if settings and settings.printOnEnd then
                local fmt = settings.format or "MM:SS"
                print("|cff00aaffJetTools|r Combat: " .. FormatTime(lastDuration, fmt))
            end
        end
        -- Keep frame visible to display the last duration
    end
end)

-- ──────────────────────────────────────────────────────────────
-- Module interface
-- ──────────────────────────────────────────────────────────────

function CombatTimer:Init()
    CreateTimerFrame()
end

function CombatTimer:Enable()
    isEnabled  = true
    lastUpdate = 0
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    if timerFrame then
        -- Show if we have something to display
        if running or lastDuration then
            timerFrame:Show()
        end
    end
end

function CombatTimer:Disable()
    isEnabled = false
    running   = false
    startTime = nil
    eventFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if timerFrame then timerFrame:Hide() end
end

function CombatTimer:OnSettingChanged(key, value)
    if key == "fontSize" or key == "fontFace" then
        self:ApplySettings()
    elseif key == "posX" or key == "posY" or key == "anchorFrame"
        or key == "anchorPoint" or key == "relativePoint" then
        self:ApplyPosition()
    end
    -- Keep preview live while options panel is open
    if _G["JetToolsOptionsFrame"] and _G["JetToolsOptionsFrame"]:IsShown() then
        self:ShowPreview()
    end
end

function CombatTimer:ShowPreview()
    if not timerFrame then CreateTimerFrame() end
    self:ApplySettings()
    self:ApplyPosition()
    if timerText then
        timerText:SetText("0:00")
        timerText:SetTextColor(0.7, 0.7, 0.7)
    end
    if timerFrame then timerFrame:Show() end
end

function CombatTimer:HidePreview()
    -- Only hide if the module is not actively enabled (leave combat display running)
    if not isEnabled and timerFrame then
        timerFrame:Hide()
    end
end

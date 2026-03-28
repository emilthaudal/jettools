-- JetTools Buff Bar Styling Module
-- Styles and repositions BuffBarCooldownViewer bars (Cooldown Manager buff bars)
-- Supports texture, dimensions, font, icon visibility, border, and anchor positioning

local addonName, JT = ...

local BuffBarStyling = {}
JT:RegisterModule("BuffBarStyling", BuffBarStyling)

-- LibSharedMedia support (optional)
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Fallback fonts (for when LSM is absent)
local FALLBACK_FONTS = {
    ["Friz Quadrata TT"] = "Fonts\\FRIZQT__.TTF",
    ["Morpheus"]         = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]           = "Fonts\\SKURRI.TTF",
    ["Arial Narrow"]     = "Fonts\\ARIALN.TTF",
}

-- Upvalues
local pcall     = pcall
local pairs     = pairs
local ipairs    = ipairs
local C_Timer   = C_Timer
local _G        = _G

-- Module state
local isEnabled  = false
local ticker     = nil

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function GetSettings()
    return JT:GetModuleSettings("BuffBarStyling")
end

---@param name string
---@return string
local function ResolveFontPath(name)
    if LSM then
        local path = LSM:Fetch("font", name)
        if path then return path end
    end
    return FALLBACK_FONTS[name] or "Fonts\\FRIZQT__.TTF"
end

---@param name string
---@return string
local function ResolveTexturePath(name)
    if name == "Solid" then
        return "Interface\\Buttons\\WHITE8X8"
    end
    if LSM then
        local path = LSM:Fetch("statusbar", name)
        if path then return path end
    end
    return "Interface\\Buttons\\WHITE8X8"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Border helpers (4-strip 1px black border)
-- ─────────────────────────────────────────────────────────────────────────────

local function EnsureBorder(frame)
    if frame._jtBorderTop then return end

    local function MakeStrip(layer)
        local t = frame:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end

    frame._jtBorderTop    = MakeStrip()
    frame._jtBorderBottom = MakeStrip()
    frame._jtBorderLeft   = MakeStrip()
    frame._jtBorderRight  = MakeStrip()
end

local function UpdateBorder(frame, h, w)
    if not frame._jtBorderTop then return end
    -- Top
    frame._jtBorderTop:SetHeight(1)
    frame._jtBorderTop:SetPoint("TOPLEFT",     frame, "TOPLEFT",     0,  0)
    frame._jtBorderTop:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0,  0)
    -- Bottom
    frame._jtBorderBottom:SetHeight(1)
    frame._jtBorderBottom:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0,  0)
    frame._jtBorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  0)
    -- Left
    frame._jtBorderLeft:SetWidth(1)
    frame._jtBorderLeft:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0,  0)
    frame._jtBorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0,  0)
    -- Right
    frame._jtBorderRight:SetWidth(1)
    frame._jtBorderRight:SetPoint("TOPRIGHT",  frame, "TOPRIGHT",   0,  0)
    frame._jtBorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Style a single buff bar frame
-- ─────────────────────────────────────────────────────────────────────────────

local function StyleBuffBar(frame, settings)
    if not frame then return end

    local ok = pcall(function()
        local barH    = settings.barHeight or 26
        local barW    = settings.barWidth  or 200
        local tex     = ResolveTexturePath(settings.texture or "Solid")
        local showIcon = settings.showIcon ~= false

        -- Size the bar itself
        frame:SetHeight(barH)
        frame:SetWidth(barW)

        -- Apply texture to any StatusBar child named "bar" or matching typical CDM names
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            local childType = child:GetObjectType()

            if childType == "StatusBar" then
                local ok2 = pcall(function()
                    child:SetStatusBarTexture(tex)
                    child:GetStatusBarTexture():SetHorizTile(false)
                    child:GetStatusBarTexture():SetVertTile(false)
                end)
            end

            -- Icon container: typically a Frame or Texture named "icon" or similar
            -- Hide/show based on setting
            local childName = child:GetName() or ""
            if childName:find("icon") or childName:find("Icon") then
                if showIcon then
                    child:Show()
                else
                    child:Hide()
                end
            end
        end

        -- Apply font to FontString regions
        local fontPath = ResolveFontPath(settings.fontFace or "Friz Quadrata TT")
        local fontSize = settings.fontSize or 13
        local regions  = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if region:GetObjectType() == "FontString" then
                local fok = pcall(function()
                    region:SetFont(fontPath, fontSize, "OUTLINE")
                end)
            end
        end

        -- Ensure and update border
        EnsureBorder(frame)
        UpdateBorder(frame, barH, barW)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Iterate and style all children of BuffBarCooldownViewer
-- ─────────────────────────────────────────────────────────────────────────────

local function SkinAllBars(settings)
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then return end

    local ok = pcall(function()
        local children = { viewer:GetChildren() }
        for _, child in ipairs(children) do
            StyleBuffBar(child, settings)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Anchor / position BuffBarCooldownViewer
-- ─────────────────────────────────────────────────────────────────────────────

local function UpdatePosition(settings)
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then return end

    local anchorName    = settings.anchorFrame or ""
    local point         = settings.anchorPoint    or "TOPLEFT"
    local relPoint      = settings.relativePoint  or "BOTTOMLEFT"
    local offX          = settings.offsetX or 0
    local offY          = settings.offsetY or 0
    local matchWidth    = settings.matchAnchorWidth

    local ok = pcall(function()
        local relativeTo = UIParent
        if anchorName ~= "" then
            local found = _G[anchorName]
            if found and found.GetWidth then
                relativeTo = found

                -- Match width of anchor frame
                if matchWidth then
                    local w = found:GetWidth()
                    if w and w > 0 then
                        local barW = settings.barWidth or 200
                        -- Store original barWidth and override viewer width
                        viewer:SetWidth(w)
                    end
                end
            end
        end

        viewer:ClearAllPoints()
        viewer:SetPoint(point, relativeTo, relPoint, offX, offY)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tick function (runs every 0.1s while enabled)
-- ─────────────────────────────────────────────────────────────────────────────

local function OnTick()
    if not isEnabled then return end

    local settings = GetSettings()
    if not settings then return end

    SkinAllBars(settings)
    UpdatePosition(settings)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module interface
-- ─────────────────────────────────────────────────────────────────────────────

function BuffBarStyling:GetOptions()
    local lsmTextures = { "Solid" }
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do
            table.insert(lsmTextures, name)
        end
    end

    local lsmFonts = { "Friz Quadrata TT", "Morpheus", "Skurri", "Arial Narrow" }
    if LSM then
        for _, name in ipairs(LSM:List("font")) do
            -- Avoid duplicates
            local found = false
            for _, existing in ipairs(lsmFonts) do
                if existing == name then found = true; break end
            end
            if not found then
                table.insert(lsmFonts, name)
            end
        end
    end

    local ANCHOR_POINTS = {
        "TOPLEFT", "TOP", "TOPRIGHT",
        "LEFT", "CENTER", "RIGHT",
        "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
    }

    return {
        { type = "header",      label = "Buff Bar Styling" },
        { type = "description", text = "Styles and repositions BuffBarCooldownViewer (Cooldown Manager buff bars). Requires the Cooldown Manager addon." },
        { type = "checkbox",    label = "Enabled", key = "enabled", default = false },

        { type = "group", label = "Appearance", expanded = false, children = {
            { type = "dropdown", label = "Texture",    key = "texture",   options = lsmTextures, default = "Solid" },
            { type = "slider",   label = "Bar Height", key = "barHeight", min = 10, max = 60,  step = 1, default = 26 },
            { type = "slider",   label = "Bar Width",  key = "barWidth",  min = 80, max = 600, step = 1, default = 200 },
            { type = "checkbox", label = "Show Icon",  key = "showIcon",  default = true },
        }},

        { type = "group", label = "Font", expanded = false, children = {
            { type = "dropdown", label = "Font Face", key = "fontFace", options = lsmFonts, default = "Friz Quadrata TT" },
            { type = "slider",   label = "Font Size", key = "fontSize", min = 8, max = 32, step = 1, default = 13 },
        }},

        { type = "group", label = "Positioning", expanded = false, children = {
            { type = "input",    label = "Anchor Frame Name", key = "anchorFrame",    width = 200,    default = "" },
            { type = "dropdown", label = "Anchor Point",      key = "anchorPoint",    options = ANCHOR_POINTS, default = "TOPLEFT" },
            { type = "dropdown", label = "Relative Point",    key = "relativePoint",  options = ANCHOR_POINTS, default = "BOTTOMLEFT" },
            { type = "checkbox", label = "Match Anchor Width", key = "matchAnchorWidth", default = false },
            { type = "slider",   label = "X Offset", key = "offsetX", min = -1000, max = 1000, step = 1, default = 0 },
            { type = "slider",   label = "Y Offset", key = "offsetY", min = -1000, max = 1000, step = 1, default = 0 },
        }},
    }
end

function BuffBarStyling:Init()
    -- Nothing to do at init time; styling starts on Enable
end

function BuffBarStyling:Enable()
    if isEnabled then return end
    isEnabled = true

    -- Start the periodic styling ticker
    if not ticker then
        ticker = C_Timer.NewTicker(0.1, OnTick)
    end

    -- Run immediately
    OnTick()
end

function BuffBarStyling:Disable()
    if not isEnabled then return end
    isEnabled = false

    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function BuffBarStyling:OnSettingChanged(key, value)
    -- Any setting change takes effect on the next tick automatically.
    -- For position/size changes, force an immediate update.
    if isEnabled then
        OnTick()
    end
end

local addonName, JT = ...

-- Module: CursorGCD
-- Description: Adds a circular GCD indicator around the cursor
-- Implements a custom quadrant-based renderer for smoother cursor tracking
local CursorGCD = {}
JT:RegisterModule("CursorGCD", CursorGCD)

-- Configuration
local TEXTURE_PATH = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

-- Frame references
local frame = nil
local textures = {}

-- State
local isAnimating = false
local currentGCDDuration = 0
local currentGCDStartTime = 0

-- Quadrant Definitions
-- 1: Top-Right, 2: Bottom-Right, 3: Bottom-Left, 4: Top-Left
local QUADRANTS = {
    { point = "BOTTOMLEFT", coord = {0.5, 1.0, 0.0, 0.5} }, -- Q1
    { point = "TOPLEFT",    coord = {0.5, 1.0, 0.5, 1.0} }, -- Q2
    { point = "TOPRIGHT",   coord = {0.0, 0.5, 0.5, 1.0} }, -- Q3
    { point = "BOTTOMRIGHT",coord = {0.0, 0.5, 0.0, 0.5} }  -- Q4
}

function CursorGCD:Init()
    frame = CreateFrame("Frame", "JetToolsCursorGCDFrame", UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetSize(64, 64)
    frame:SetIgnoreParentScale(true) -- Important for cursor tracking accuracy
    frame:Hide()

    -- Create background ring (static alpha)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture(TEXTURE_PATH)
    frame.bg:SetBlendMode("ADD")
    frame.bg:SetAlpha(0.2)

    -- Create 4 quadrant textures for the progress animation
    for i, data in ipairs(QUADRANTS) do
        local t = frame:CreateTexture(nil, "ARTWORK")
        t:SetTexture(TEXTURE_PATH)
        t:SetBlendMode("ADD")
        
        -- Anchor the quadrant's specific corner to the center of the frame
        t:SetPoint(data.point, frame, "CENTER", 0, 0)
        
        -- We'll size them dynamically in ApplySettings/OnUpdate
        textures[i] = t
    end
    frame.textures = textures

    -- OnUpdate handler
    frame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)

    -- Event registration
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "SPELL_UPDATE_COOLDOWN" then
            self:CheckGCD()
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            self:UpdateState()
        end
    end)
    
    self:ApplySettings()
end

function CursorGCD:Enable()
    self:CheckGCD()
    self:UpdateState()
    frame:Show()
end

function CursorGCD:Disable()
    frame:Hide()
end

function CursorGCD:ApplySettings()
    local settings = JT:GetModuleSettings("CursorGCD")
    if not settings or not frame then return end

    -- Size
    local size = settings.size or 64
    frame:SetSize(size, size)
    
    -- Quadrant sizes (half the total size)
    local halfSize = size / 2
    for _, t in ipairs(textures) do
        t:SetSize(halfSize, halfSize)
    end

    -- Color
    local c = settings.color or {r=1, g=1, b=1, a=1}
    for _, t in ipairs(textures) do
        t:SetVertexColor(c.r, c.g, c.b, c.a)
    end
    frame.bg:SetVertexColor(c.r, c.g, c.b, c.a * 0.3) -- Fainter BG
end

function CursorGCD:OnSettingChanged(key, value)
    self:ApplySettings()
    if key == "enabled" then
        if value then self:Enable() else self:Disable() end
    end
end

function CursorGCD:GetOptions()
    return {
        { type = "header", label = "Cursor GCD Ring" },
        { type = "description", text = "Shows a ring around the cursor indicating the Global Cooldown." },
        { type = "checkbox", key = "enabled", label = "Enable Cursor GCD", default = true },
        { type = "slider", key = "size", label = "Size", min = 32, max = 128, step = 2, default = 64 },
        { type = "color", key = "color", label = "Ring Color", default = {r=1, g=1, b=1, a=1} },
        { type = "checkbox", key = "animate", label = "Animate Fill", default = true },
    }
end

function CursorGCD:CheckGCD()
    -- GCD spell ID is 61304
    local start, duration = GetSpellCooldown(61304)
    
    -- Check if valid GCD (usually 0.75s to 1.5s)
    if duration > 0 and duration <= 1.5 then
        currentGCDStartTime = start
        currentGCDDuration = duration
        isAnimating = true
        frame:Show()
    else
        isAnimating = false
        self:UpdateState()
    end
end

function CursorGCD:UpdateState()
    local settings = JT:GetModuleSettings("CursorGCD")
    if not settings.enabled then 
        frame:Hide()
        return 
    end

    if isAnimating then
        frame:Show()
        frame.bg:Show()
    elseif InCombatLockdown() then
        -- Static combat state: Show full ring
        frame:Show()
        frame.bg:Show()
        self:SetProgress(1)
    else
        -- Out of combat, not animating
        frame:Hide()
    end
end

-- Update the visual progress of the ring (0 to 1)
function CursorGCD:SetProgress(percent)
    -- percent: 0 = Empty, 1 = Full
    
    for i, t in ipairs(textures) do
        local qStart = (i - 1) * 0.25
        local qEnd = i * 0.25
        
        local qData = QUADRANTS[i]
        local baseCoords = qData.coord
        local x1, x2, y1, y2 = unpack(baseCoords)
        
        if percent >= qEnd then
            -- Fully visible
            t:SetTexCoord(x1, x2, y1, y2)
            t:SetSize(frame:GetWidth()/2, frame:GetHeight()/2)
            t:Show()
        elseif percent <= qStart then
            -- Fully hidden
            t:Hide()
        else
            -- Partially visible (Linear Wipe approximation)
            t:Show()
            local qProgress = (percent - qStart) / 0.25
            
            -- Dynamic wipe logic per quadrant
            if i == 1 then -- Top Right (Growth: Bottom to Top)
                -- y2=0.5 (bottom), y1 varies (0.5 -> 0.0)
                local partialY = 0.5 - (0.5 * qProgress)
                t:SetTexCoord(x1, x2, partialY, y2)
                t:SetHeight((frame:GetHeight()/2) * qProgress)
                
            elseif i == 2 then -- Btm Right (Growth: Top to Bottom)
                -- y1=0.5 (top), y2 varies (0.5 -> 1.0)
                local partialY = 0.5 + (0.5 * qProgress)
                t:SetTexCoord(x1, x2, y1, partialY)
                t:SetHeight((frame:GetHeight()/2) * qProgress)
                
            elseif i == 3 then -- Btm Left (Growth: Right to Left)
                -- x2=0.5 (right), x1 varies (0.5 -> 0.0)
                local centerX = 0.5
                local partialX = centerX - (0.5 * qProgress)
                -- Note: Q3 base X range is 0.0 -> 0.5.
                -- We want to display the RIGHTmost portion (near center) first?
                -- Radial goes 6 -> 9 o'clock.
                -- That is Right to Left (from center outwards left? No, circular).
                -- 6 is Bottom Center. 9 is Left Center.
                -- So we fill from x=0.5 (center) to x=0.0 (left).
                t:SetTexCoord(partialX, x2, y1, y2)
                t:SetWidth((frame:GetWidth()/2) * qProgress)
                
            elseif i == 4 then -- Top Left (Growth: Bottom to Top)
                -- 9 to 12 o'clock.
                -- Fills from y=0.5 (bottom/center) to y=0.0 (top).
                local partialY = 0.5 - (0.5 * qProgress)
                t:SetTexCoord(x1, x2, partialY, y2)
                t:SetHeight((frame:GetHeight()/2) * qProgress)
            end
        end
    end
end

function CursorGCD:OnUpdate(elapsed)
    -- 1. Position
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    
    -- 2. Animation
    if isAnimating then
        local now = GetTime()
        local endTime = currentGCDStartTime + currentGCDDuration
        local settings = JT:GetModuleSettings("CursorGCD")
        
        if now >= endTime then
            isAnimating = false
            self:UpdateState()
        else
            if settings.animate then
                local progress = (now - currentGCDStartTime) / currentGCDDuration
                self:SetProgress(progress)
            else
                self:SetProgress(1) -- Full ring if animation disabled but on GCD
            end
        end
    end
end

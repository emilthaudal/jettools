-- JetTools BuffBar Styling Module
-- Reskins and positions the Cooldown Manager buff bars
-- Based on user-provided CooldownManager.lua example

local addonName, JT = ...

local BuffBarStyling = {}
JT:RegisterModule("BuffBarStyling", BuffBarStyling)

-- LibSharedMedia support
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Defaults
local DEFAULT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local DEFAULT_BORDER_COLOR = {r=0, g=0, b=0, a=1}

-- ---------------------------------------------------------------------------
-- Helper Functions
-- ---------------------------------------------------------------------------

local function safeIsForbidden(f)
    if not f then return false end
    return (f.IsForbidden and f:IsForbidden()) or false
end

local function safeIsProtected(f)
    if not f then return false end
    if f.IsProtected then
        local ok, val = pcall(f.IsProtected, f)
        if ok then return val end
    end
    return false
end

local function RoundPixel(value)
    if not value or type(value) ~= "number" then return 0 end
    return math.floor(value + 0.5)
end

local function GetSafeChildren(frame)
    if not frame or not frame.GetChildren then return {} end
    
    local ok, children = pcall(function() return {frame:GetChildren()} end)
    if not ok or not children then return {} end
    
    local valid = {}
    for _, child in ipairs(children) do
        if child and child:IsShown() and not safeIsForbidden(child) then
            table.insert(valid, child)
        end
    end
    
    -- Sort by ID if available (usually consistent for bars)
    table.sort(valid, function(a, b)
        local aOrder = 0
        local bOrder = 0
        
        if a.GetID then
            local ok, val = pcall(a.GetID, a)
            if ok and type(val) == "number" then aOrder = val end
        end
        
        if b.GetID then
            local ok, val = pcall(b.GetID, b)
            if ok and type(val) == "number" then bOrder = val end
        end
        
        return aOrder < bOrder
    end)
    
    return valid
end

-- ---------------------------------------------------------------------------
-- Styling Logic
-- ---------------------------------------------------------------------------

function BuffBarStyling:CreateBorder(frame)
    if frame.borderTop then return end -- Already created
    
    local function CreateStrip(parent)
        local t = parent:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(0, 0, 0, 1)
        return t
    end
    
    frame.borderTop = CreateStrip(frame)
    frame.borderBottom = CreateStrip(frame)
    frame.borderLeft = CreateStrip(frame)
    frame.borderRight = CreateStrip(frame)
    
    -- Positioning
    -- Outside border
    frame.borderTop:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", -1, 0)
    frame.borderTop:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 1, 0)
    frame.borderTop:SetHeight(1)
    
    frame.borderBottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -1, 0)
    frame.borderBottom:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 1, 0)
    frame.borderBottom:SetHeight(1)
    
    frame.borderLeft:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, 0)
    frame.borderLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
    frame.borderLeft:SetWidth(1)
    
    frame.borderRight:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0)
    frame.borderRight:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 0, 0)
    frame.borderRight:SetWidth(1)
end

function BuffBarStyling:StyleBuffBar(frame)
    if not frame then return end
    if InCombatLockdown() then return end
    if safeIsForbidden(frame) then return end
    
    local settings = JT:GetModuleSettings("BuffBarStyling")
    if not settings then return end

    local barFrame = frame.Bar or frame
    local iconContainer = frame.Icon
    local iconTexture = iconContainer and (iconContainer.Icon or iconContainer.icon)
    
    -- 1. Set Height
    local barHeight = settings.barHeight or 18
    if frame.SetHeight then pcall(frame.SetHeight, frame, barHeight) end
    if barFrame and barFrame.SetHeight then pcall(barFrame.SetHeight, barFrame, barHeight) end
    
    -- Icon Handling
    if iconContainer then
        if settings.showIcon ~= false then -- Default true
             iconContainer:Show()
             if iconContainer.SetSize then pcall(iconContainer.SetSize, iconContainer, barHeight, barHeight) end
        else
             iconContainer:Hide()
             if iconContainer.SetSize then pcall(iconContainer.SetSize, iconContainer, 0.1, barHeight) end
        end
    end
    
    -- 2. Style Status Bar (Texture & Color & Border)
    if barFrame and barFrame.IsObjectType and barFrame:IsObjectType("StatusBar") then
        pcall(function()
            -- Texture
            local texturePath = DEFAULT_TEXTURE
            if LSM and settings.texture then
                texturePath = LSM:Fetch("statusbar", settings.texture) or DEFAULT_TEXTURE
            end
            
            if barFrame.SetStatusBarTexture then
                barFrame:SetStatusBarTexture(texturePath)
            end
            
            -- Class Color
            local r, g, b = 0.5, 0.5, 0.5
            if JT.GetPlayerClassColor then
                -- Assuming Core might have this helper
                local _, class = UnitClass("player")
                local color = C_ClassColor.GetClassColor(class)
                if color then r, g, b = color.r, color.g, color.b end
            else
                 local _, class = UnitClass("player")
                 local color = C_ClassColor.GetClassColor(class)
                 if color then r, g, b = color.r, color.g, color.b end
            end
            
            if barFrame.SetStatusBarColor then
                barFrame:SetStatusBarColor(r, g, b, 1)
            end
            
            -- Hide other regions
            local numRegions = barFrame.GetNumRegions and barFrame:GetNumRegions() or 0
            for i = 1, numRegions do
                local ok2, region = pcall(select, i, barFrame:GetRegions())
                if ok2 and region and region.IsObjectType and region:IsObjectType("Texture") then
                    local statusTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
                    if region ~= statusTex and region ~= barFrame.borderTop and region ~= barFrame.borderBottom and region ~= barFrame.borderLeft and region ~= barFrame.borderRight then
                        if region.SetTexture then pcall(region.SetTexture, region, nil) end
                        if region.Hide then pcall(region.Hide, region) end
                    end
                end
            end
            
            -- Apply Border
            self:CreateBorder(barFrame)
        end)
    end
    
    -- 3. Style Icon
    if iconTexture and not safeIsForbidden(iconTexture) then
        pcall(function()
            -- Simple icon crop/style
            if iconTexture.SetTexCoord then
                iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            
             -- Border for Icon
             if iconContainer then
                 self:CreateBorder(iconContainer)
             end
        end)
    end
    
    -- 4. Style Font Strings
    local function ApplyFont(fs)
        if not fs or not fs.SetFont then return end
        local fontPath = DEFAULT_FONT
        if LSM and settings.fontFace then
            fontPath = LSM:Fetch("font", settings.fontFace) or DEFAULT_FONT
        end
        local fontSize = settings.fontSize or 12
        fs:SetFont(fontPath, fontSize, "OUTLINE")
    end

    if barFrame and not safeIsForbidden(barFrame) then
        if barFrame.Name or barFrame.Text then
            pcall(ApplyFont, barFrame.Name or barFrame.Text)
        end
        if barFrame.TimeLeft or barFrame.Duration then
            pcall(ApplyFont, barFrame.TimeLeft or barFrame.Duration)
        end
    end
end

function BuffBarStyling:SkinAllBars()
    if not self.isEnabled then return end
    if not BuffBarCooldownViewer then return end
    if InCombatLockdown() then return end

    local frames = {}

    if BuffBarCooldownViewer.GetItemFrames then
        local ok, itemFrames = pcall(BuffBarCooldownViewer.GetItemFrames, BuffBarCooldownViewer)
        if ok and itemFrames then
            frames = itemFrames
        end
    end

    if #frames == 0 and BuffBarCooldownViewer.GetChildren then
        local ok, children = pcall(BuffBarCooldownViewer.GetChildren, BuffBarCooldownViewer)
        if ok and children then
            for _, child in pairs({children}) do
                if child and child:IsObjectType("Frame") then
                    table.insert(frames, child)
                end
            end
        end
    end

    for _, frame in ipairs(frames) do
        self:StyleBuffBar(frame)
    end
end

-- ---------------------------------------------------------------------------
-- Positioning Logic
-- ---------------------------------------------------------------------------

function BuffBarStyling:UpdatePosition()
    if InCombatLockdown() then return end
    if not BuffBarCooldownViewer then return end
    
    local settings = JT:GetModuleSettings("BuffBarStyling")
    if not settings then return end
    
    -- 1. Anchor Parent
    local anchorName = settings.anchorParent
    if not anchorName or anchorName == "" then anchorName = "UIParent" end

    local parent = _G[anchorName]
    if parent then
        BuffBarCooldownViewer:ClearAllPoints()
        
        -- Use specific anchor points if available, otherwise default
        local point = settings.anchorPoint or "TOPLEFT"
        local relativePoint = settings.relativePoint or "BOTTOMLEFT"
        
        BuffBarCooldownViewer:SetPoint(point, parent, relativePoint, settings.xOffset or 0, settings.yOffset or 0)
    end

    -- 2. Layout Children (Width & Vertical Stacking)
    local bars = GetSafeChildren(BuffBarCooldownViewer)
    if #bars > 0 then
        local barWidth = settings.barWidth or 200
        
        -- Match Anchor Width override
        if settings.matchAnchorWidth and parent then
            barWidth = parent:GetWidth()
        end
        
        local barHeight = settings.barHeight or 18
        local spacing = 1 -- Hardcoded or add setting later
        
        for index, bar in ipairs(bars) do
             if bar.SetPoint then
                local offsetIndex = index - 1
                local y = offsetIndex * (barHeight + spacing)
                y = RoundPixel(y)
                
                pcall(function()
                    bar:ClearAllPoints()
                    -- Stack downwards
                    bar:SetPoint("TOP", BuffBarCooldownViewer, "TOP", 0, -y)
                    bar:SetWidth(barWidth)
                end)
             end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function BuffBarStyling:Init()
    self.isEnabled = false
    self.updateTicker = nil
end

function BuffBarStyling:Enable()
    self.isEnabled = true
    
    -- Initial Update
    C_Timer.After(1, function() self:OnUpdate() end)
    
    -- Start Ticker (100ms)
    self.updateTicker = C_Timer.NewTicker(0.1, function()
        self:OnUpdate()
    end)
end

function BuffBarStyling:Disable()
    self.isEnabled = false
    if self.updateTicker then
        self.updateTicker:Cancel()
        self.updateTicker = nil
    end
end

function BuffBarStyling:OnUpdate()
    if InCombatLockdown() then return end
    
    -- Even in Edit Mode, we want to enforce position to prevent the "fly away" bug.
    -- If the user wants to drag it via Edit Mode, they should probably disable the positioning override
    -- or we'd need a more complex "Manual" mode.
    -- Given the prompt "It goes back to the anchored position when leaving editmode... hides in corner... unclickable",
    -- locking it to our settings is the correct fix for now.
    
    self:SkinAllBars()
    self:UpdatePosition()
end

function BuffBarStyling:OnSettingChanged(key, value)
    if not self.isEnabled then return end
    self:OnUpdate()
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

function BuffBarStyling:GetOptions()
    local textureOptions = {}
    local fontOptions = {}
    
    if LSM then
        for _, name in ipairs(LSM:List("statusbar")) do textureOptions[name] = name end
        for _, name in ipairs(LSM:List("font")) do fontOptions[name] = name end
    else
        textureOptions["Default"] = "Default"
        fontOptions["Default"] = "Default"
    end
    
    local anchorPoints = {
        ["TOPLEFT"] = "TOPLEFT",
        ["TOP"] = "TOP",
        ["TOPRIGHT"] = "TOPRIGHT",
        ["LEFT"] = "LEFT",
        ["CENTER"] = "CENTER",
        ["RIGHT"] = "RIGHT",
        ["BOTTOMLEFT"] = "BOTTOMLEFT",
        ["BOTTOM"] = "BOTTOM",
        ["BOTTOMRIGHT"] = "BOTTOMRIGHT",
    }

    return {
        { type = "header", label = "Buff Bar Styling" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = false },
        
        { 
            type = "group", 
            label = "Appearance", 
            children = {
                { type = "dropdown", label = "Texture", key = "texture", options = textureOptions, default = "Blizzard" },
                { type = "slider", label = "Bar Height", key = "barHeight", min = 10, max = 50, step = 1, default = 18 },
                { type = "slider", label = "Bar Width", key = "barWidth", min = 50, max = 400, step = 5, default = 200 },
                { type = "checkbox", label = "Show Icon", key = "showIcon", default = true },
            }
        },
        
        {
            type = "group",
            label = "Font",
            children = {
                { type = "dropdown", label = "Font Face", key = "fontFace", options = fontOptions, default = "Friz Quadrata TT" },
                { type = "slider", label = "Font Size", key = "fontSize", min = 8, max = 32, step = 1, default = 12 },
            }
        },
        
        {
            type = "group",
            label = "Positioning",
            children = {
                { type = "input", label = "Anchor Frame Name", key = "anchorParent", width = 200, default = "UIParent" },
                { type = "dropdown", label = "Anchor Point", key = "anchorPoint", options = anchorPoints, default = "TOPLEFT" },
                { type = "dropdown", label = "Relative Point", key = "relativePoint", options = anchorPoints, default = "BOTTOMLEFT" },
                { type = "checkbox", label = "Match Anchor Width", key = "matchAnchorWidth", default = false },
                { type = "slider", label = "X Offset", key = "xOffset", min = -500, max = 500, step = 1, default = 0 },
                { type = "slider", label = "Y Offset", key = "yOffset", min = -500, max = 500, step = 1, default = 0 },
                { type = "description", text = "Note: Position is enforced even in Edit Mode to prevent bugs." }
            }
        }
    }
end

-- JetTools Options Panel
-- Simple draggable frame for configuring modules

local addonName, JT = ...

local optionsFrame = nil

-- Create the options frame
local function CreateOptionsFrame()
    local frame = CreateFrame("Frame", "JetToolsOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(300, 250)
    frame:SetPoint("CENTER")
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    -- Make closeable with Escape
    table.insert(UISpecialFrames, "JetToolsOptionsFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff00ff00JetTools|r Options")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    
    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 15, -40)
    content:SetPoint("BOTTOMRIGHT", -15, 15)
    frame.content = content
    
    return frame
end

-- Create a checkbox
local function CreateCheckbox(parent, label, x, y, checked, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb:SetChecked(checked)
    cb:SetScript("OnClick", function(self)
        onChange(self:GetChecked())
    end)
    
    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    text:SetText(label)
    
    cb.label = text
    return cb
end

-- Create a slider
local function CreateSlider(parent, label, x, y, min, max, step, value, onChange)
    local sliderFrame = CreateFrame("Frame", nil, parent)
    sliderFrame:SetSize(200, 40)
    sliderFrame:SetPoint("TOPLEFT", x, y)
    
    local text = sliderFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    
    local slider = CreateFrame("Slider", nil, sliderFrame, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -15)
    slider:SetSize(180, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(value)
    
    slider.Low:SetText(min)
    slider.High:SetText(max)
    slider.Text:SetText(value)
    
    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        self.Text:SetText(val)
        onChange(val)
    end)
    
    sliderFrame.slider = slider
    return sliderFrame
end

-- Build UI for Range Indicator module
local function BuildRangeIndicatorOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("RangeIndicator")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Range Indicator")
    header:SetTextColor(1, 0.82, 0)
    yOffset = yOffset - 25
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("RangeIndicator", checked)
    end)
    yOffset = yOffset - 30
    
    -- Font size slider
    local fontSlider = CreateSlider(parent, "Font Size", 0, yOffset, 12, 48, 2, settings.fontSize, function(val)
        JT:SetModuleSetting("RangeIndicator", "fontSize", val)
    end)
    yOffset = yOffset - 55
    
    return yOffset
end

-- Populate the options frame with module controls
local function PopulateOptions()
    if not optionsFrame then return end
    
    local content = optionsFrame.content
    local yOffset = 0
    
    -- Build options for each module
    yOffset = BuildRangeIndicatorOptions(content, yOffset)
    
    -- Add more modules here in the future
end

-- Toggle options visibility
function JT:ToggleOptions()
    if not optionsFrame then
        optionsFrame = CreateOptionsFrame()
        PopulateOptions()
    end
    
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

-- Show options
function JT:ShowOptions()
    if not optionsFrame then
        optionsFrame = CreateOptionsFrame()
        PopulateOptions()
    end
    optionsFrame:Show()
end

-- Hide options
function JT:HideOptions()
    if optionsFrame then
        optionsFrame:Hide()
    end
end

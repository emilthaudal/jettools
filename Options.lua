-- JetTools Options Panel
-- Simple draggable frame for configuring modules
-- Refactored to be data-driven

local addonName, JT = ...

local optionsFrame = nil

-- Defined order for modules in the options panel
local MODULE_ORDER = {
    "RangeIndicator",
    "CurrentExpansionFilter",
    "AutoRoleQueue",
    "CharacterSheet",
    "GearUpgradeRanks",
    "CDMAuraRemover",
    "CharacterStatFormatting",
    "SlashCommands",
    "CombatStatus",
}

-- Create the options frame
local function CreateOptionsFrame()
    local frame = CreateFrame("Frame", "JetToolsOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 600) -- Wider for 2 columns, shorter height
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
    frame:SetBackdropBorderColor(0.3, 0.4, 0.6)
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
    title:SetText("|cff00aaffJet|r|cffaa66ffTools|r Options")
    
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

-- Create a horizontal separator line
local function CreateSeparator(parent, xOffset, yOffset, width)
    local separator = parent:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", xOffset, yOffset - 5)
    separator:SetSize(width or 270, 1)
    separator:SetColorTexture(0.3, 0.4, 0.6, 0.8)
    return yOffset - 15
end

-- Create a text input field
local function CreateTextInput(parent, label, x, y, width, value, onChange)
    local inputFrame = CreateFrame("Frame", nil, parent)
    inputFrame:SetSize(width, 40)
    inputFrame:SetPoint("TOPLEFT", x, y)
    
    -- Label
    local text = inputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    
    -- EditBox with backdrop
    local editBox = CreateFrame("EditBox", nil, inputFrame, "BackdropTemplate")
    editBox:SetPoint("TOPLEFT", 0, -15)
    editBox:SetSize(width, 22)
    editBox:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    editBox:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    editBox:SetBackdropBorderColor(0.3, 0.4, 0.6)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:SetText(value or "")
    editBox:SetTextInsets(8, 8, 0, 0)
    
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        onChange(self:GetText())
    end)
    
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    
    inputFrame.editBox = editBox
    return inputFrame
end

-- Create a simple push button
local function CreateButton(parent, label, x, y, width, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(width, 24)
    btn:SetText(label)
    
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)
    
    return btn
end

-- Create a scrollable dropdown
local function CreateDropdown(parent, label, x, y, width, options, selectedValue, onChange)
    local dropdownFrame = CreateFrame("Frame", nil, parent)
    dropdownFrame:SetSize(width, 45)
    dropdownFrame:SetPoint("TOPLEFT", x, y)
    
    -- Label
    local text = dropdownFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    
    -- Button (shows current selection)
    local button = CreateFrame("Button", nil, dropdownFrame, "BackdropTemplate")
    button:SetPoint("TOPLEFT", 0, -15)
    button:SetSize(width, 22)
    button:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    button:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    button:SetBackdropBorderColor(0.3, 0.4, 0.6)
    
    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buttonText:SetPoint("LEFT", 8, 0)
    buttonText:SetPoint("RIGHT", -20, 0)
    buttonText:SetJustifyH("LEFT")
    buttonText:SetText(selectedValue or "Select...")
    button.text = buttonText
    
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetSize(12, 12)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    
    -- Dropdown list frame
    local listFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    listFrame:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    listFrame:SetSize(width, 150)
    listFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    listFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    listFrame:SetBackdropBorderColor(0.3, 0.4, 0.6)
    listFrame:SetFrameStrata("TOOLTIP")
    listFrame:Hide()
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(width - 30, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Populate options
    local function RefreshOptions()
        -- Clear existing buttons
        for _, child in ipairs({scrollChild:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        
        local itemHeight = 18
        local yPos = 0
        
        -- Sort options alphabetically
        local sortedOptions = {}
        for name, _ in pairs(options) do
            table.insert(sortedOptions, name)
        end
        table.sort(sortedOptions)
        
        for _, name in ipairs(sortedOptions) do
            local itemBtn = CreateFrame("Button", nil, scrollChild)
            itemBtn:SetSize(width - 35, itemHeight)
            itemBtn:SetPoint("TOPLEFT", 0, -yPos)
            
            local itemText = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            itemText:SetPoint("LEFT", 5, 0)
            itemText:SetPoint("RIGHT", -5, 0)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(name)
            
            local highlight = itemBtn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0.2)
            
            itemBtn:SetScript("OnClick", function()
                buttonText:SetText(name)
                listFrame:Hide()
                onChange(name)
            end)
            
            yPos = yPos + itemHeight
        end
        
        scrollChild:SetHeight(math.max(yPos, 1))
    end
    
    RefreshOptions()
    
    -- Toggle dropdown on button click
    button:SetScript("OnClick", function()
        if listFrame:IsShown() then
            listFrame:Hide()
        else
            RefreshOptions()
            listFrame:Show()
        end
    end)
    
    -- Close dropdown when clicking elsewhere
    listFrame:SetScript("OnShow", function()
        listFrame:SetScript("OnUpdate", function()
            if not button:IsMouseOver() and not listFrame:IsMouseOver() then
                if IsMouseButtonDown("LeftButton") then
                    listFrame:Hide()
                end
            end
        end)
    end)
    
    listFrame:SetScript("OnHide", function()
        listFrame:SetScript("OnUpdate", nil)
    end)
    
    dropdownFrame.button = button
    dropdownFrame.Refresh = function(newOptions)
        options = newOptions
        RefreshOptions()
    end
    dropdownFrame.SetValue = function(self, value)
        buttonText:SetText(value or "Select...")
    end
    
    return dropdownFrame
end


-- Build a single option control based on schema
local function BuildOptionControl(parent, moduleName, schema, xOffset, yOffset)
    local settings = JT:GetModuleSettings(moduleName)
    if not settings then 
        -- Fallback for safety, though settings should exist if module is registered
        settings = {}
    end

    local type = schema.type
    local key = schema.key
    local default = schema.default
    
    -- Get current value safely
    local currentValue = default
    if key and settings[key] ~= nil then
        currentValue = settings[key]
    end

    if type == "header" then
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", xOffset, yOffset)
        header:SetText(schema.label)
        header:SetTextColor(0.67, 0.4, 1) -- Purple-ish theme
        return yOffset - 25
        
    elseif type == "subheader" then
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", xOffset + 10, yOffset)
        header:SetText(schema.label)
        header:SetTextColor(0.8, 0.8, 0.8)
        return yOffset - 20
        
    elseif type == "description" then
        local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", xOffset, yOffset)
        desc:SetText(schema.text)
        desc:SetTextColor(0.7, 0.7, 0.7)
        desc:SetWidth(280) -- Constrain width for columns
        desc:SetJustifyH("LEFT")
        return yOffset - 20
        
    elseif type == "checkbox" then
        -- Handle special "enabled" key separately to use JT:SetModuleEnabled
        local onChange
        if key == "enabled" then
            onChange = function(checked)
                JT:SetModuleEnabled(moduleName, checked)
            end
        else
            onChange = function(checked)
                JT:SetModuleSetting(moduleName, key, checked)
            end
        end
        
        -- Indent if it's not a main toggle or if it follows a subheader
        local indent = (key == "enabled") and 0 or 20
        
        CreateCheckbox(parent, schema.label, xOffset + indent, yOffset, currentValue, onChange)
        return yOffset - 30
        
    elseif type == "slider" then
        CreateSlider(parent, schema.label, xOffset, yOffset, schema.min, schema.max, schema.step, currentValue, function(val)
            JT:SetModuleSetting(moduleName, key, val)
        end)
        return yOffset - 50 -- Sliders are taller
        
    elseif type == "input" then
        CreateTextInput(parent, schema.label, xOffset, yOffset, schema.width or 150, currentValue, function(val)
            JT:SetModuleSetting(moduleName, key, val)
        end)
        return yOffset - 40
        
    elseif type == "dropdown" then
        CreateDropdown(parent, schema.label, xOffset, yOffset, schema.width or 200, schema.options, currentValue, function(val)
            JT:SetModuleSetting(moduleName, key, val)
        end)
        return yOffset - 55
        
    elseif type == "button" then
        CreateButton(parent, schema.label, xOffset, yOffset, schema.width or 120, schema.func)
        return yOffset - 40
        
    elseif type == "color" then
        local btn = CreateButton(parent, schema.label, xOffset, yOffset, 150, function()
            local info = UIDropDownMenu_CreateInfo()
            info.r = currentValue.r
            info.g = currentValue.g
            info.b = currentValue.b
            info.opacity = currentValue.a
            info.hasOpacity = true
            
            info.swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = OpacitySliderFrame:GetValue()
                JT:SetModuleSetting(moduleName, key, {r=r, g=g, b=b, a=a})
            end
            
            info.opacityFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = OpacitySliderFrame:GetValue()
                JT:SetModuleSetting(moduleName, key, {r=r, g=g, b=b, a=a})
            end
            
            info.cancelFunc = function(restore)
                if restore then
                    JT:SetModuleSetting(moduleName, key, {r=restore.r, g=restore.g, b=restore.b, a=restore.opacity})
                end
            end
            
            ColorPickerFrame:SetupColorPickerAndShow(info)
        end)
        
        -- Preview swatch
        local swatch = btn:CreateTexture(nil, "OVERLAY")
        swatch:SetSize(20, 20)
        swatch:SetPoint("RIGHT", -5, 0)
        swatch:SetColorTexture(currentValue.r, currentValue.g, currentValue.b, currentValue.a or 1)
        
        return yOffset - 40
    end
    
    return yOffset
end

-- Populate the options frame with module controls
local function PopulateOptions()
    if not optionsFrame then return end
    
    local content = optionsFrame.content
    
    -- Clear existing children if repopulating
    -- Note: This simplistic "create new" approach works for static options. 
    -- If we refreshed often we'd leak memory without proper cleanup/pool.
    -- Assuming one-time populate for now.
    
    -- Two-column layout
    local leftY = 0
    local rightY = 0
    local COL_WIDTH = 280
    local COL_GAP = 40
    local RIGHT_X_OFFSET = COL_WIDTH + COL_GAP
    
    -- Iterate through modules in defined order
    -- Using a "masonry" fill: add to whichever column is shorter
    for _, moduleName in ipairs(MODULE_ORDER) do
        local module = JT.modules[moduleName]
        if module and module.GetOptions then
            local optionsSchema = module:GetOptions()
            
            -- Decide column
            local isLeft = (leftY >= rightY) -- Actually, typically 0 is top, negative is down. 
            -- If leftY is 0 and rightY is 0, start left.
            -- If leftY is -100 and rightY is -20, left is "taller" (more negative), so put next in right.
            -- We want to put into the SHORTER column (closest to 0).
            
            local useLeft = (leftY >= rightY) 
            local currentY = useLeft and leftY or rightY
            local currentX = useLeft and 0 or RIGHT_X_OFFSET
            
            -- Build UI for this module
            for _, item in ipairs(optionsSchema) do
                currentY = BuildOptionControl(content, moduleName, item, currentX, currentY)
            end
            
            -- Add separator after each module
            currentY = CreateSeparator(content, currentX, currentY, COL_WIDTH)
            
            -- Update column cursor
            if useLeft then
                leftY = currentY - 15 -- Extra padding between modules
            else
                rightY = currentY - 15
            end
        end
    end
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

-- JetTools Options Panel
-- Simple draggable frame for configuring modules

local addonName, JT = ...

local optionsFrame = nil

-- Create the options frame
local function CreateOptionsFrame()
    local frame = CreateFrame("Frame", "JetToolsOptionsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(300, 1250)
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
local function CreateSeparator(parent, yOffset)
    local separator = parent:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", 0, yOffset - 5)
    separator:SetSize(270, 1)
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

-- Build UI for Range Indicator module
local function BuildRangeIndicatorOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("RangeIndicator")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Range Indicator")
    header:SetTextColor(0.67, 0.4, 1)
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
    
    -- Font face dropdown
    local RangeIndicator = JT.modules["RangeIndicator"]
    local fontOptions = RangeIndicator and RangeIndicator.GetAvailableFonts and RangeIndicator:GetAvailableFonts() or {}
    
    local fontDropdown = CreateDropdown(parent, "Font", 0, yOffset, 200, fontOptions, settings.fontFace, function(fontName)
        JT:SetModuleSetting("RangeIndicator", "fontFace", fontName)
    end)
    yOffset = yOffset - 55
    
    return yOffset
end

-- Build UI for Current Expansion Filter module
local function BuildCurrentExpansionFilterOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("CurrentExpansionFilter")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Current Expansion Filter")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 25
    
    -- Enable checkbox (master toggle)
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("CurrentExpansionFilter", checked)
    end)
    yOffset = yOffset - 30
    
    -- Crafting Orders subsection
    local craftHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    craftHeader:SetPoint("TOPLEFT", 10, yOffset)
    craftHeader:SetText("Crafting Orders")
    craftHeader:SetTextColor(0.8, 0.8, 0.8)
    yOffset = yOffset - 20
    
    local craftEnable = CreateCheckbox(parent, "Enable", 20, yOffset, settings.craftingOrdersEnabled, function(checked)
        JT:SetModuleSetting("CurrentExpansionFilter", "craftingOrdersEnabled", checked)
    end)
    yOffset = yOffset - 25
    
    local craftFocus = CreateCheckbox(parent, "Auto-focus search bar", 20, yOffset, settings.craftingOrdersFocusSearch, function(checked)
        JT:SetModuleSetting("CurrentExpansionFilter", "craftingOrdersFocusSearch", checked)
    end)
    yOffset = yOffset - 30
    
    -- Auction House subsection
    local ahHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ahHeader:SetPoint("TOPLEFT", 10, yOffset)
    ahHeader:SetText("Auction House")
    ahHeader:SetTextColor(0.8, 0.8, 0.8)
    yOffset = yOffset - 20
    
    local ahEnable = CreateCheckbox(parent, "Enable", 20, yOffset, settings.auctionHouseEnabled, function(checked)
        JT:SetModuleSetting("CurrentExpansionFilter", "auctionHouseEnabled", checked)
    end)
    yOffset = yOffset - 25
    
    local ahFocus = CreateCheckbox(parent, "Auto-focus search bar", 20, yOffset, settings.auctionHouseFocusSearch, function(checked)
        JT:SetModuleSetting("CurrentExpansionFilter", "auctionHouseFocusSearch", checked)
    end)
    yOffset = yOffset - 30
    
    return yOffset
end

-- Build UI for Auto Role Queue module
local function BuildAutoRoleQueueOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("AutoRoleQueue")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Auto Role Queue")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Automatically accepts role checks when queuing")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("AutoRoleQueue", checked)
    end)
    yOffset = yOffset - 30
    
    return yOffset
end

-- Build UI for Character Stats module
local function BuildCharacterStatsOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("CharacterStats")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Character Stats")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Show item levels, enchants, and gems on gear")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("CharacterStats", checked)
    end)
    yOffset = yOffset - 30
    
    return yOffset
end

-- Build UI for Focus Castbar module
local function BuildFocusCastbarOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("FocusCastbar")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Focus Castbar")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Enhanced focus castbar with interrupt tracking")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("FocusCastbar", checked)
    end)
    yOffset = yOffset - 30
    
    -- Position X slider
    local posXSlider = CreateSlider(parent, "Position X", 0, yOffset, -500, 500, 10, settings.positionX, function(val)
        JT:SetModuleSetting("FocusCastbar", "positionX", val)
    end)
    yOffset = yOffset - 50
    
    -- Position Y slider
    local posYSlider = CreateSlider(parent, "Position Y", 0, yOffset, -500, 500, 10, settings.positionY, function(val)
        JT:SetModuleSetting("FocusCastbar", "positionY", val)
    end)
    yOffset = yOffset - 50
    
    -- Preview Button
    local previewBtn = CreateButton(parent, "Test / Preview Mode", 0, yOffset, 160, function()
        local module = JT.modules["FocusCastbar"]
        if module and module.TogglePreview then
            module:TogglePreview()
        end
    end)
    yOffset = yOffset - 40
    
    return yOffset
end

-- Build UI for Focus Marker Announcement module
local function BuildFocusMarkerAnnouncementOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("FocusMarkerAnnouncement")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Focus Marker Announcement")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Announces your focus marker to party on ready check")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("FocusMarkerAnnouncement", checked)
    end)
    yOffset = yOffset - 30
    
    -- Macro name input
    local macroInput = CreateTextInput(parent, "Macro Name", 0, yOffset, 150, settings.macroName, function(val)
        JT:SetModuleSetting("FocusMarkerAnnouncement", "macroName", val)
    end)
    yOffset = yOffset - 40
    
    return yOffset
end

-- Build UI for Gear Upgrade Ranks module
local function BuildGearUpgradeRanksOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("GearUpgradeRanks")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Gear Upgrade Ranks")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Better formatted upgrade ranks and crests in tooltips")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("GearUpgradeRanks", checked)
    end)
    yOffset = yOffset - 30
    
    return yOffset
end

-- Build UI for Character Stat Formatting module
local function BuildCharacterStatFormattingOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("CharacterStatFormatting")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Character Stat Formatting")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Detailed stats with raw numbers and %")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("CharacterStatFormatting", checked)
    end)
    yOffset = yOffset - 30
    
    return yOffset
end

-- Build UI for Slash Commands module
local function BuildSlashCommandsOptions(parent, yOffset)
    local settings = JT:GetModuleSettings("SlashCommands")
    if not settings then return yOffset end
    
    -- Section header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, yOffset)
    header:SetText("Slash Commands")
    header:SetTextColor(0.67, 0.4, 1)
    yOffset = yOffset - 20
    
    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, yOffset)
    desc:SetText("Adds /rl (reload) and /wa (cooldowns)")
    desc:SetTextColor(0.7, 0.7, 0.7)
    yOffset = yOffset - 20
    
    -- Enable checkbox
    local enableCb = CreateCheckbox(parent, "Enabled", 0, yOffset, settings.enabled, function(checked)
        JT:SetModuleEnabled("SlashCommands", checked)
    end)
    yOffset = yOffset - 30
    
    return yOffset
end

-- Populate the options frame with module controls
local function PopulateOptions()
    if not optionsFrame then return end
    
    local content = optionsFrame.content
    local yOffset = 0
    
    -- Build options for each module
    yOffset = BuildRangeIndicatorOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildCurrentExpansionFilterOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildAutoRoleQueueOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildCharacterStatsOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildFocusCastbarOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildFocusMarkerAnnouncementOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildGearUpgradeRanksOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildCharacterStatFormattingOptions(content, yOffset)
    yOffset = CreateSeparator(content, yOffset)
    yOffset = BuildSlashCommandsOptions(content, yOffset)
    
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

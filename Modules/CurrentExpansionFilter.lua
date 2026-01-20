-- JetTools Current Expansion Filter Module
-- Automatically sets the "Current Expansion Only" filter for Crafting Orders and Auction House
-- Optionally auto-focuses the search bar when these frames open

local addonName, JT = ...

local CurrentExpansionFilter = {}
JT:RegisterModule("CurrentExpansionFilter", CurrentExpansionFilter)

-- Get options configuration
function CurrentExpansionFilter:GetOptions()
    return {
        { type = "header", label = "Current Expansion Filter" },
        { type = "checkbox", label = "Enabled", key = "enabled", default = true },
        
        { type = "subheader", label = "Crafting Orders" },
        { type = "checkbox", label = "Enable", key = "craftingOrdersEnabled", default = true },
        { type = "checkbox", label = "Auto-focus search bar", key = "craftingOrdersFocusSearch", default = false },
        
        { type = "subheader", label = "Auction House" },
        { type = "checkbox", label = "Enable", key = "auctionHouseEnabled", default = true },
        { type = "checkbox", label = "Auto-focus search bar", key = "auctionHouseFocusSearch", default = false }
    }
end

-- Module state
local isEnabled = false
local hookStates = {}

-- Helper: Check if a hook has been set
local function IsHookSet(key)
    return hookStates[key]
end

-- Helper: Mark a hook as set
local function MarkHookSet(key)
    hookStates[key] = true
end

-- Helper: Manage search bar focus state
local function FocusSearchBar(editBox, shouldFocus)
    if not editBox then return end
    shouldFocus = shouldFocus or false
    
    if not shouldFocus and editBox:HasFocus() then
        editBox:ClearFocus()
    end
    if shouldFocus and not editBox:HasFocus() then
        editBox:SetFocus()
    end
end

-- Setup hook for Crafting Orders (Customer Orders frame)
local function SetupCraftingOrdersHook()
    if IsHookSet("CraftingOrdersFilterDropdown") then return end
    
    local frame = ProfessionsCustomerOrdersFrame
    if not frame then return end
    
    local filterDropdown = frame.BrowseOrders and frame.BrowseOrders.SearchBar and frame.BrowseOrders.SearchBar.FilterDropdown
    local searchBox = frame.BrowseOrders and frame.BrowseOrders.SearchBar and frame.BrowseOrders.SearchBar.SearchBox
    
    if not filterDropdown then return end
    
    local function onShow()
        local settings = JT:GetModuleSettings("CurrentExpansionFilter")
        if not settings or not settings.craftingOrdersEnabled then return end
        
        filterDropdown.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
        filterDropdown:ValidateResetState()
        FocusSearchBar(searchBox, settings.craftingOrdersFocusSearch)
    end
    
    -- Hook OnShow to enforce filter state on tab switch
    filterDropdown:HookScript("OnShow", function()
        -- Schedule to run after current event and all OnShow callbacks
        C_Timer.After(0, onShow)
    end)
    
    MarkHookSet("CraftingOrdersFilterDropdown")
    
    -- For the first time it's too late for the hook to trigger, so run it explicitly
    C_Timer.After(0, onShow)
end

-- Setup hook for Auction House
local function SetupAuctionHouseHook()
    if IsHookSet("AuctionHouseSearchBar") then return end
    
    local frame = AuctionHouseFrame
    if not frame then return end
    
    local searchBar = frame.SearchBar
    local searchBox = searchBar and searchBar.SearchBox
    
    if not searchBar or not searchBar.FilterButton then return end
    
    local function onShow()
        local settings = JT:GetModuleSettings("CurrentExpansionFilter")
        if not settings or not settings.auctionHouseEnabled then return end
        
        searchBar.FilterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
        searchBar:UpdateClearFiltersButton()
        FocusSearchBar(searchBox, settings.auctionHouseFocusSearch)
    end
    
    -- Hook OnShow to enforce filter state on tab switch
    searchBar:HookScript("OnShow", function()
        -- Schedule to run after current event and all OnShow callbacks
        C_Timer.After(0, onShow)
    end)
    
    MarkHookSet("AuctionHouseSearchBar")
    
    -- For the first time it's too late for the hook to trigger, so run it explicitly
    C_Timer.After(0, onShow)
end

-- Event handler
local function OnEvent(self, event, ...)
    if not isEnabled then return end
    
    local settings = JT:GetModuleSettings("CurrentExpansionFilter")
    if not settings then return end
    
    if event == "CRAFTINGORDERS_SHOW_CUSTOMER" then
        if not settings.craftingOrdersEnabled then return end
        SetupCraftingOrdersHook()
        
    elseif event == "AUCTION_HOUSE_SHOW" then
        if not settings.auctionHouseEnabled then return end
        SetupAuctionHouseHook()
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", OnEvent)

-- Initialize the module
function CurrentExpansionFilter:Init()
    -- Nothing special needed for init
end

-- Enable the module
function CurrentExpansionFilter:Enable()
    isEnabled = true
    
    eventFrame:RegisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER")
    eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
end

-- Disable the module
function CurrentExpansionFilter:Disable()
    isEnabled = false
    
    eventFrame:UnregisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER")
    eventFrame:UnregisterEvent("AUCTION_HOUSE_SHOW")
    
    -- Note: Hooks cannot be removed once set, but they check settings before applying
end

-- Handle setting changes
function CurrentExpansionFilter:OnSettingChanged(key, value)
    -- Settings are checked dynamically when hooks fire, no immediate action needed
end

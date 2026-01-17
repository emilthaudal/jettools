I want to add a current expansion filter module to the addon for crafting orders and the AH. I have an existing Weakaura with the functionality. I'll show the LUA here:

Init code:

local ownerId = "WA_OWNER_ID_ALTER_DEFAULT_SEARCH_FILTER_VALUES"
local filterUpdater = \_G[ownerId]
if(not filterUpdater) then
\_G[ownerId] = {
hookStates = {},
config = {},
}
filterUpdater = \_G[ownerId]
end
function filterUpdater:isHookSet(key)
return self.hookStates[key]
end
function filterUpdater:markHookSet(key)
self.hookStates[key] = true
end
function filterUpdater:refreshConfig(currentConfig)
self.config = currentConfig
end
function filterUpdater:focusSearchBar(editBox, shouldFocus)
shouldFocus = shouldFocus or false
if(not shouldFocus and editBox:HasFocus()) then
editBox:ClearFocus()
end
if(shouldFocus and not editBox:HasFocus()) then
editBox:SetFocus()
end
end
aura_env.FilterUpdater = filterUpdater

Trigger events:
CRAFTINGORDERS_SHOW_CUSTOMER,AUCTION_HOUSE_SHOW,PLAYER_INTERACTION_MANAGER_FRAME_SHOW

Trigger code:
function(event, ...)
-- closure should capture FilterUpdater because it is made as a static updatable instance unlike aura_env
local filterUpdater = aura_env.FilterUpdater
-- this fires after any hooked "OnShow", but also fires on WA "OPTIONS" event to update before the "OnShow"s
-- aura_env value is recreated on config change, so pass current instance config
filterUpdater:refreshConfig(aura_env.config)
if(event == "CRAFTINGORDERS_SHOW_CUSTOMER") then
if(not filterUpdater.config.forCraftOrdersOverwrite) then return end
-- Filter state is preserved on tab switch, but let's still enforce filter state in case a user has cleared it
if(not filterUpdater:isHookSet("CraftOrdersFilterDropdown")) then
local filterDropdown = ProfessionsCustomerOrdersFrame.BrowseOrders.SearchBar.FilterDropdown
local searchBox = ProfessionsCustomerOrdersFrame.BrowseOrders.SearchBar.SearchBox
local function onShow()
local config = filterUpdater.config -- use our updatable config, do not capture transient aura_env.config.
if(not config.forCraftOrdersOverwrite) then return end -- keep disablable even when hooked
filterDropdown.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = config.forCraftOrdersValue or false
filterDropdown:ValidateResetState()
filterUpdater:focusSearchBar(searchBox, config.forCraftOrdersFocusSearchBar)
end
-- this enforces filter and focus state on tab switch
filterDropdown:HookScript("OnShow", function(filterDropdown)
-- schedule to run after current event and all OnShow callbacks
C_Timer.After(0, onShow)
end)
filterUpdater:markHookSet("CraftOrdersFilterDropdown")
-- for the first time it's too late for the hook to trigger, so run it explicitly
C_Timer.After(0, onShow)
end
elseif(event == "AUCTION_HOUSE_SHOW") then
if(not filterUpdater.config.forAuctionHouseOverwrite) then return end
if(not filterUpdater:isHookSet("AuctionHouseSearchBar")) then
-- this enforces filter state on tab switch
local searchBar = AuctionHouseFrame.SearchBar
local searchBox = AuctionHouseFrame.SearchBar.SearchBox
local function onShow()
local config = filterUpdater.config -- use our updatable config, do not capture transient aura_env.config.
if(not config.forAuctionHouseOverwrite) then return end -- keep disablable even when hooked
searchBar.FilterButton.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = config.forAuctionHouseValue or false
searchBar:UpdateClearFiltersButton()
filterUpdater:focusSearchBar(searchBox, config.forAuctionHouseFocusSearchBar)
end
-- this enforces filter and focus state on tab switch
searchBar:HookScript("OnShow", function(searchBar)
-- schedule to run after current event and all OnShow callbacks
C_Timer.After(0, onShow)
end)
filterUpdater:markHookSet("AuctionHouseSearchBar")
-- for the first time it's too late for the hook to trigger, so run it explicitly
C_Timer.After(0, onShow)
end
elseif(event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW") then
local type = ...
if(type ~= Enum.PlayerInteractionType.Auctioneer) then return end
if(not filterUpdater.config.forAuctionatorOverwrite) then return end
if(not C_AddOns.IsAddOnLoaded("Auctionator")) then return end
if(not filterUpdater:isHookSet("AuctionatorShoppingTabItemFrame")) then
local function hookAuctionator()
if(not filterUpdater:isHookSet("AuctionatorShoppingTabItemFrame")) then
local shoppingTabItem = AuctionatorShoppingTabItemFrame
local function onShow()
local config = filterUpdater.config -- use our updatable config, do not capture transient aura_env.config.
if(not config.forAuctionatorOverwrite) then return end -- keep disablable even when hooked
local value = config.forAuctionatorValue and tostring(LE_EXPANSION_LEVEL_CURRENT) or ""
shoppingTabItem.ExpansionContainer.DropDown:SetValue(value)
end
shoppingTabItem:HookScript("OnShow", function(shoppingTabItem)
-- schedule to run after current event and all OnShow callbacks
C_Timer.After(0, onShow)
end)
filterUpdater:markHookSet("AuctionatorShoppingTabItemFrame")
end
end
C_Timer.After(0, hookAuctionator) -- delay until Actionator has finished initializing its frames
end
end
end

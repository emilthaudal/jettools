AutoQueue WA information as inspiration:

We don't want to copy it 1-1, we want to have an option in in the existing JetTools options menu to enable/disable auto queue.

The main thing here is the usage of the CompleteLFGRoleCheck function on the WoW API. We also want that. The minimap button we don't need.

Trigger:
function(event )
    if event ~= "OPTIONS" and _G.AQ.active then 
        CompleteLFGRoleCheck(true)
        print("|cffb048f8AutoQueue:|r Rolecheck accepted.")
    end
end

Action init:

local function ToggleMode(self)  
    if _G.AQ.active then
        _G.AQ.active = false        
        --print("Not active")
        self.icon:SetTexture("Interface/COMMON/Indicator-Red.png")
    else 
        _G.AQ.active = true            
        --print("Active")
        self.icon:SetTexture("Interface/COMMON/Indicator-Green.png")
    end        
end


if _G.AQ == nil then
    setglobal('AQ', {
            active = true
    })
    
    local img = "Interface/COMMON/Indicator-Red.png"
    if _G.AQ.active then
        img = "Interface/COMMON/Indicator-Green.png"
    end
    
    
    
    
    local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("AutoQueueWA", {
            
            type = "data source",        
            text = "AutoQueueWA",        
            icon = img,
            
            OnClick = function(self, btn)     
                if btn =='LeftButton' then
                    ToggleMode(self)
                    
                end
            end,
            
            --        OnTooltipShow = function(tooltip)
            --            if not tooltip or not tooltip.AddLine then return end
            --            if _G.AQ == nil then
            --                _G.AQ = {
            --                    active = false,
            --                }
            --            end
            
            
            --            if _G.AQ.active then                
            --                tooltip:AddLine("Active")
            --            else
            --                tooltip:AddLine("Disabled")
            --            end            
            --        end,
            
            OnInitialize = function(tooltip)
                if _G.AQ == nil then
                    _G.AQ = {
                        active = true,
                    }
                end
            end
            
    })
    
    local icon = LibStub("LibDBIcon-1.0", true)
    
    icon:Register("AutoQueueWA", miniButton, {})
    icon:Show("AutoQueueWA")
    
    
end


-- JetTools External Cooldowns Module
-- Tracks external defensive cooldowns used by group members
-- Uses COMBAT_LOG_EVENT_UNFILTERED for cast detection and group roster scanning
-- for pre-population. Shows always-on display with live timers.

local addonName, JT = ...

local ExternalCooldowns = {}
JT:RegisterModule("ExternalCooldowns", ExternalCooldowns)

-- ──────────────────────────────────────────────────────────────
-- Upvalues
-- ──────────────────────────────────────────────────────────────

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local GetTime                      = GetTime
local UnitGUID                     = UnitGUID
local UnitName                     = UnitName
local UnitClass                    = UnitClass
local UnitExists                   = UnitExists
local GetNumGroupMembers           = GetNumGroupMembers
local IsInRaid                     = IsInRaid
local C_Timer                      = C_Timer
local C_ClassColor                 = C_ClassColor
local math_floor                   = math.floor
local string_format                = string.format

-- ──────────────────────────────────────────────────────────────
-- Constants
-- ──────────────────────────────────────────────────────────────

-- spellID -> { name, icon, cooldown (seconds), class (file name) }
-- Base cooldown durations — talents may reduce these; a future cast self-corrects.
local TRACKED_SPELLS = {
    -- ── Holy Priest ──────────────────────────────────────────
    [47788]  = { name = "Guardian Spirit",      icon = 237542,  cooldown = 180, class = "PRIEST"      },
    -- ── Discipline Priest ────────────────────────────────────
    [33206]  = { name = "Pain Suppression",     icon = 135936,  cooldown = 180, class = "PRIEST"      },
    [62618]  = { name = "Power Word: Barrier",  icon = 236229,  cooldown = 180, class = "PRIEST"      },
    -- ── Resto Shaman ─────────────────────────────────────────
    [98008]  = { name = "Spirit Link Totem",    icon = 237586,  cooldown = 180, class = "SHAMAN"      },
    -- ── Warrior ──────────────────────────────────────────────
    [97462]  = { name = "Rallying Cry",         icon = 132351,  cooldown = 180, class = "WARRIOR"     },
    -- ── Paladin ──────────────────────────────────────────────
    [1022]   = { name = "Blessing of Protection", icon = 135964, cooldown = 300, class = "PALADIN"   },
    [6940]   = { name = "Blessing of Sacrifice",  icon = 135966, cooldown = 120, class = "PALADIN"   },
    [31821]  = { name = "Aura Mastery",           icon = 135872, cooldown = 180, class = "PALADIN"   },
    -- ── Demon Hunter ─────────────────────────────────────────
    [196718] = { name = "Darkness",             icon = 1305155, cooldown = 300, class = "DEMONHUNTER" },
    -- ── Death Knight ─────────────────────────────────────────
    [51052]  = { name = "Anti-Magic Zone",      icon = 135806,  cooldown = 120, class = "DEATHKNIGHT" },
    -- ── Druid ────────────────────────────────────────────────
    [106898] = { name = "Stampeding Roar",      icon = 464343,  cooldown = 120, class = "DRUID"       },
}

-- Which spells each class can provide (derived from TRACKED_SPELLS above,
-- built once at load time so RebuildRoster() is a simple lookup)
local CLASS_SPELLS = {}
do
    for spellID, data in pairs(TRACKED_SPELLS) do
        local cls = data.class
        if not CLASS_SPELLS[cls] then
            CLASS_SPELLS[cls] = {}
        end
        table.insert(CLASS_SPELLS[cls], spellID)
    end
end

-- Display constants
local ROW_HEIGHT    = 22
local ICON_SIZE     = 20
local FRAME_PADDING = 8
local READY_COLOR   = { r = 0.4, g = 1, b = 0.4 }
local OCD_COLOR     = { r = 1,   g = 0.7, b = 0.1 }
local DIM_ALPHA     = 0.5
local TICKER_RATE   = 0.5  -- seconds between display refreshes
local MODULE_NAME   = "ExternalCooldowns"

-- ──────────────────────────────────────────────────────────────
-- Module state
-- ──────────────────────────────────────────────────────────────

local isEnabled  = false
local ticker     = nil   -- C_Timer.NewTicker handle

-- displayFrame and its row frames (created lazily in Init)
local displayFrame = nil
local rowFrames    = {}  -- pool of row frames, re-used each redraw

-- Tracked rows: the single source of truth.
-- Each entry: { casterGUID, casterName, casterClass, spellID, expireAt }
--   expireAt == nil  => ready (not yet on CD this session or CD has expired)
--   expireAt == number => on CD, ready at that GetTime() value
local trackedRows = {}

-- GUID -> classFilename lookup (rebuilt from roster)
local guidToClass = {}

-- ──────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────

---@param seconds number
---@return string
local function FormatTime(seconds)
    if seconds <= 0 then
        return "Ready"
    end
    local m = math_floor(seconds / 60)
    local s = math_floor(seconds % 60)
    return string_format("%d:%02d", m, s)
end

-- Iterate all current group unit tokens
local function IterateGroup(callback)
    if IsInRaid() then
        local count = GetNumGroupMembers()
        for i = 1, count do
            callback("raid" .. i)
        end
    else
        -- Party (includes "player" token at index 0, others at party1–4)
        callback("player")
        local count = GetNumGroupMembers()
        for i = 1, count do
            callback("party" .. i)
        end
    end
end

-- Rebuild trackedRows from current group composition.
-- Preserves expireAt for rows that already exist (same casterGUID+spellID).
local function RebuildRoster()
    -- Snapshot current expireAt values by key so we can preserve them
    local existing = {}
    for _, row in ipairs(trackedRows) do
        local key = row.casterGUID .. "_" .. row.spellID
        existing[key] = row.expireAt
    end

    -- Rebuild guidToClass
    guidToClass = {}
    local newRows = {}

    IterateGroup(function(unit)
        if not UnitExists(unit) then return end

        local guid = UnitGUID(unit)
        if not guid then return end

        local name = UnitName(unit) or "Unknown"
        local _, classFile = UnitClass(unit)
        if not classFile then return end

        guidToClass[guid] = classFile

        local spells = CLASS_SPELLS[classFile]
        if not spells then return end

        for _, spellID in ipairs(spells) do
            local key = guid .. "_" .. spellID
            table.insert(newRows, {
                casterGUID  = guid,
                casterName  = name,
                casterClass = classFile,
                spellID     = spellID,
                expireAt    = existing[key] or nil,
            })
        end
    end)

    trackedRows = newRows
end

-- ──────────────────────────────────────────────────────────────
-- Display
-- ──────────────────────────────────────────────────────────────

-- Sort order: on-CD rows first (soonest-ready last), then ready rows
local function SortRows(a, b)
    local aOnCD = a.expireAt ~= nil and a.expireAt > GetTime()
    local bOnCD = b.expireAt ~= nil and b.expireAt > GetTime()
    if aOnCD and not bOnCD then return true  end
    if bOnCD and not aOnCD then return false end
    if aOnCD and bOnCD     then return a.expireAt < b.expireAt end
    -- Both ready: sort by class then spell name
    local aName = TRACKED_SPELLS[a.spellID].name
    local bName = TRACKED_SPELLS[b.spellID].name
    return aName < bName
end

-- Get or create a pooled row frame at the given index
local function GetRowFrame(index, parent)
    if rowFrames[index] then
        return rowFrames[index]
    end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    -- Spell icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    -- Name + spell label
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    row.label = label

    -- Timer text (right-aligned)
    local timer = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timer:SetPoint("RIGHT", 0, 0)
    timer:SetJustifyH("RIGHT")
    row.timer = timer

    rowFrames[index] = row
    return row
end

local function UpdateDisplay()
    if not displayFrame then return end

    local settings = JT:GetModuleSettings(MODULE_NAME)
    local now = GetTime()

    -- Sort a copy so we don't mutate trackedRows order
    local sorted = {}
    for _, row in ipairs(trackedRows) do
        table.insert(sorted, row)
    end
    table.sort(sorted, SortRows)

    local fontSize  = (settings and settings.fontSize) or 13
    local frameWidth = 280  -- fixed width; rows stretch to fill

    local visibleCount = #sorted
    local frameHeight  = FRAME_PADDING * 2 + visibleCount * ROW_HEIGHT + math.max(0, visibleCount - 1) * 2

    -- Hide extra pooled rows
    for i = visibleCount + 1, #rowFrames do
        rowFrames[i]:Hide()
    end

    -- Size the frame to fit content (minimum height when empty)
    displayFrame:SetWidth(frameWidth)
    displayFrame:SetHeight(math.max(ROW_HEIGHT + FRAME_PADDING * 2, frameHeight))

    if visibleCount == 0 then
        displayFrame:Hide()
        return
    end

    -- Populate rows
    for i, data in ipairs(sorted) do
        local row  = GetRowFrame(i, displayFrame)
        local spell = TRACKED_SPELLS[data.spellID]

        -- Position
        row:SetWidth(frameWidth - FRAME_PADDING * 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", displayFrame, "TOPLEFT",
                     FRAME_PADDING,
                     -(FRAME_PADDING + (i - 1) * (ROW_HEIGHT + 2)))

        -- Icon
        row.icon:SetTexture(spell.icon)

        -- Label: [ClassColor]Name|r — SpellName
        local classColor = C_ClassColor.GetClassColor(data.casterClass)
        local nameHex    = classColor and string_format("|cff%02x%02x%02x",
                               math_floor(classColor.r * 255),
                               math_floor(classColor.g * 255),
                               math_floor(classColor.b * 255))
                           or "|cffcccccc"
        local labelText  = nameHex .. data.casterName .. "|r - " .. spell.name

        row.label:SetText(labelText)
        row.label:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

        -- Timer
        row.timer:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

        local onCD = data.expireAt ~= nil and data.expireAt > now
        if onCD then
            local remaining = data.expireAt - now
            row.timer:SetText(FormatTime(remaining))
            row.timer:SetTextColor(OCD_COLOR.r, OCD_COLOR.g, OCD_COLOR.b)
            row.icon:SetAlpha(1)
            row.label:SetAlpha(1)
            row.timer:SetAlpha(1)
        else
            row.timer:SetText("Ready")
            row.timer:SetTextColor(READY_COLOR.r, READY_COLOR.g, READY_COLOR.b)
            row.icon:SetAlpha(DIM_ALPHA)
            row.label:SetAlpha(DIM_ALPHA)
            row.timer:SetAlpha(1)
        end

        row:Show()
    end

    displayFrame:Show()
end

-- ──────────────────────────────────────────────────────────────
-- Frame creation
-- ──────────────────────────────────────────────────────────────

local function CreateDisplayFrame()
    if displayFrame then return end

    local settings = JT:GetModuleSettings(MODULE_NAME)
    local posX = (settings and settings.posX) or -750
    local posY = (settings and settings.posY) or  300

    local f = CreateFrame("Frame", "JetToolsExternalCDs", UIParent, "BackdropTemplate")
    f:SetSize(280, ROW_HEIGHT + FRAME_PADDING * 2)
    f:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Persist dragged position
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        JT:SetModuleSetting(MODULE_NAME, "posX", math_floor(x - ux))
        JT:SetModuleSetting(MODULE_NAME, "posY", math_floor(y - uy))
    end)

    -- Subtle dark backdrop so the frame is legible without being intrusive
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    f:Hide()
    displayFrame = f
end

-- ──────────────────────────────────────────────────────────────
-- Event handler
-- ──────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not isEnabled then return end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, sourceGUID, _, _, _,
              _, _, _, _,
              spellID = CombatLogGetCurrentEventInfo()

        if subEvent ~= "SPELL_CAST_SUCCESS" then return end

        local spell = TRACKED_SPELLS[spellID]
        if not spell then return end

        local settings = JT:GetModuleSettings(MODULE_NAME)
        if settings and settings.debugMode then
            print(string_format("|cff00aaffJetTools EC|r: CLEU SPELL_CAST_SUCCESS spellID %d (%s) sourceGUID %s",
                spellID, spell.name, sourceGUID))
        end

        -- Update expireAt for the matching row(s)
        local now = GetTime()
        local matched = false
        for _, row in ipairs(trackedRows) do
            if row.casterGUID == sourceGUID and row.spellID == spellID then
                row.expireAt = now + spell.cooldown
                matched = true
            end
        end

        -- Caster not yet in tracked list (joined after roster build?)
        -- Add them if they're currently in the group.
        if not matched then
            local classFile = guidToClass[sourceGUID]
            if classFile then
                -- Find their unit token to get the name
                local casterName = nil
                IterateGroup(function(unit)
                    if casterName then return end
                    if UnitExists(unit) and UnitGUID(unit) == sourceGUID then
                        casterName = UnitName(unit)
                    end
                end)
                if casterName then
                    table.insert(trackedRows, {
                        casterGUID  = sourceGUID,
                        casterName  = casterName,
                        casterClass = classFile,
                        spellID     = spellID,
                        expireAt    = now + spell.cooldown,
                    })
                end
            end
        end

        -- Immediately refresh display so the countdown appears without
        -- waiting for the next ticker cycle (which may be skipped solo).
        UpdateDisplay()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Handles casts for "player" and group tokens (party1-4, raid1-40).
        -- More reliable than CLEU for out-of-combat and city scenarios.
        local unit, _, spellID = ...

        local spell = TRACKED_SPELLS[spellID]
        if not spell then return end

        local guid = UnitGUID(unit)
        if not guid then return end

        local settings = JT:GetModuleSettings(MODULE_NAME)
        if settings and settings.debugMode then
            local name = UnitName(unit) or unit
            print(string_format("|cff00aaffJetTools EC|r: %s cast %s (spellID %d) via UNIT_SPELLCAST_SUCCEEDED",
                name, spell.name, spellID))
        end

        local now = GetTime()
        local matched = false
        for _, row in ipairs(trackedRows) do
            if row.casterGUID == guid and row.spellID == spellID then
                row.expireAt = now + spell.cooldown
                matched = true
            end
        end

        if not matched then
            -- Unit not yet in roster; add if they're a known group member.
            local _, classFile = UnitClass(unit)
            if classFile then
                local name = UnitName(unit) or "Unknown"
                guidToClass[guid] = classFile
                table.insert(trackedRows, {
                    casterGUID  = guid,
                    casterName  = name,
                    casterClass = classFile,
                    spellID     = spellID,
                    expireAt    = now + spell.cooldown,
                })
            end
        end

        UpdateDisplay()

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        RebuildRoster()
        UpdateDisplay()
    end
end)

-- ──────────────────────────────────────────────────────────────
-- Options
-- ──────────────────────────────────────────────────────────────

function ExternalCooldowns:GetOptions()
    return {
        { type = "header",      label = "External Cooldowns" },
        { type = "description", text = "Tracks defensive cooldowns used by group members. Pre-populates from group composition." },
        { type = "checkbox",    label = "Enabled",            key = "enabled",         default = false },
        { type = "checkbox",    label = "Show only in group", key = "showOnlyInGroup", default = true  },
        { type = "checkbox",    label = "Debug logging",      key = "debugMode",       default = false },
        { type = "slider",      label = "Font Size",          key = "fontSize",        min = 10, max = 20, step = 1, default = 13 },
        { type = "slider",      label = "Position X",         key = "posX",            min = -900, max = 900, step = 1, default = -750 },
        { type = "slider",      label = "Position Y",         key = "posY",            min = -500, max = 500, step = 1, default = 300  },
    }
end

-- ──────────────────────────────────────────────────────────────
-- Module interface
-- ──────────────────────────────────────────────────────────────

function ExternalCooldowns:Init()
    CreateDisplayFrame()
end

function ExternalCooldowns:Enable()
    if isEnabled then return end
    isEnabled = true

    RebuildRoster()

    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Ticker: refresh visible timers without waiting for an event
    if not ticker then
        ticker = C_Timer.NewTicker(TICKER_RATE, function()
            if not isEnabled then return end

            -- Respect showOnlyInGroup setting: hide frame but still run
            -- UpdateDisplay so timer state stays current for when we rejoin.
            local settings = JT:GetModuleSettings(MODULE_NAME)
            local inGroup = GetNumGroupMembers() > 0
            local hideForSolo = settings and settings.showOnlyInGroup and not inGroup

            UpdateDisplay()

            if hideForSolo and displayFrame then
                displayFrame:Hide()
            end
        end)
    end

    UpdateDisplay()
end

function ExternalCooldowns:Disable()
    if not isEnabled then return end
    isEnabled = false

    eventFrame:UnregisterAllEvents()

    if ticker then
        ticker:Cancel()
        ticker = nil
    end

    if displayFrame then
        displayFrame:Hide()
    end
end

function ExternalCooldowns:ApplyPosition()
    if not displayFrame then return end
    local settings = JT:GetModuleSettings(MODULE_NAME)
    if not settings then return end
    local x = settings.posX or -750
    local y = settings.posY or 300
    displayFrame:ClearAllPoints()
    displayFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function ExternalCooldowns:OnSettingChanged(key, value)
    if key == "posX" or key == "posY" then
        self:ApplyPosition()
    elseif key == "showOnlyInGroup" or key == "fontSize" then
        UpdateDisplay()
    elseif key == "debugMode" then
        if value then
            print("|cff00aaffJetTools EC|r: Debug logging enabled. Cast events will print to chat.")
        end
    end
end

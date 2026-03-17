-- JetTools External Cooldowns Module
-- Tracks external defensive cooldowns used by group members.
--
-- Architecture (12.0 / Midnight compatible):
--   Primary detection: C_UnitAuras.GetUnitAuras() with EXTERNAL_DEFENSIVE and
--   BIG_DEFENSIVE filters on UNIT_AURA events. Aura appear/expire drives
--   "active" and "recovering" phase transitions.
--
--   Cast detection: UNIT_SPELLCAST_SUCCEEDED for all group tokens.
--   Out of combat: spellID is plain, used for direct lookup.
--   During encounter/M+ (C_Secrets active): spellID is Secret — we do NOT
--   compare it. Instead we immediately scan the caster's auras to confirm
--   and attribute the cast via unit token (NeverSecret).
--
--   Recovery timer: GetTime() + hardcoded cooldown. Never touches Secret values.
--
--   COMBAT_LOG_EVENT_UNFILTERED is NOT used (blocked during encounters in 12.0).

local addonName, JT = ...

local ExternalCooldowns = {}
JT:RegisterModule("ExternalCooldowns", ExternalCooldowns)

-- ──────────────────────────────────────────────────────────────
-- Upvalues
-- ──────────────────────────────────────────────────────────────

local GetTime          = GetTime
local UnitExists       = UnitExists
local UnitGUID         = UnitGUID
local UnitName         = UnitName
local UnitClass        = UnitClass
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid         = IsInRaid
local C_Timer          = C_Timer
local C_ClassColor     = C_ClassColor
local C_UnitAuras      = C_UnitAuras
local C_RestrictedActions = C_RestrictedActions
local math_floor       = math.floor
local string_format    = string.format
local table_insert     = table.insert
local table_sort       = table.sort
local ipairs           = ipairs
local pairs            = pairs

-- ──────────────────────────────────────────────────────────────
-- Constants
-- ──────────────────────────────────────────────────────────────

-- spellID -> { name, icon, cooldown (seconds), class (file), aoe }
-- aoe=true: ability affects the whole raid/area, not a single target
-- Keep hardcoded CD durations — no API exposes them for other players.
local TRACKED_SPELLS = {
    -- ── Holy Priest ────────────────────────────────────────────
    [47788]  = { name = "Guardian Spirit",            icon = 237542,  cooldown = 180, class = "PRIEST",      aoe = false },
    -- ── Discipline Priest ──────────────────────────────────────
    [33206]  = { name = "Pain Suppression",            icon = 135936,  cooldown = 180, class = "PRIEST",      aoe = false },
    [62618]  = { name = "Power Word: Barrier",         icon = 236229,  cooldown = 180, class = "PRIEST",      aoe = true  },
    -- ── Resto / Elemental Shaman ───────────────────────────────
    [98008]  = { name = "Spirit Link Totem",           icon = 237586,  cooldown = 180, class = "SHAMAN",      aoe = true  },
    [108280] = { name = "Healing Tide Totem",          icon = 538569,  cooldown = 180, class = "SHAMAN",      aoe = true  },
    [207399] = { name = "Ancestral Protection Totem",  icon = 511726,  cooldown = 300, class = "SHAMAN",      aoe = true  },
    -- ── Warrior ────────────────────────────────────────────────
    [97462]  = { name = "Rallying Cry",                icon = 132351,  cooldown = 180, class = "WARRIOR",     aoe = true  },
    [12975]  = { name = "Last Stand",                  icon = 135871,  cooldown = 180, class = "WARRIOR",     aoe = false },
    -- ── Paladin ────────────────────────────────────────────────
    [1022]   = { name = "Blessing of Protection",      icon = 135964,  cooldown = 300, class = "PALADIN",     aoe = false },
    [6940]   = { name = "Blessing of Sacrifice",       icon = 135966,  cooldown = 120, class = "PALADIN",     aoe = false },
    [31821]  = { name = "Aura Mastery",                icon = 135872,  cooldown = 180, class = "PALADIN",     aoe = true  },
    [204018] = { name = "Blessing of Spellwarding",    icon = 135964,  cooldown = 180, class = "PALADIN",     aoe = false },
    -- ── Demon Hunter ───────────────────────────────────────────
    [196718] = { name = "Darkness",                    icon = 1305155, cooldown = 300, class = "DEMONHUNTER", aoe = true  },
    -- ── Death Knight ───────────────────────────────────────────
    [51052]  = { name = "Anti-Magic Zone",             icon = 135806,  cooldown = 120, class = "DEATHKNIGHT", aoe = true  },
    -- ── Druid ──────────────────────────────────────────────────
    [106898] = { name = "Stampeding Roar",             icon = 464343,  cooldown = 120, class = "DRUID",       aoe = true  },
    [740]    = { name = "Tranquility",                 icon = 136107,  cooldown = 180, class = "DRUID",       aoe = true  },
    [29166]  = { name = "Innervate",                   icon = 136048,  cooldown = 180, class = "DRUID",       aoe = false },
    -- ── Mistweaver Monk ────────────────────────────────────────
    [116849] = { name = "Life Cocoon",                 icon = 704992,  cooldown = 120, class = "MONK",        aoe = false },
    [115310] = { name = "Revival",                     icon = 1020466, cooldown = 180, class = "MONK",        aoe = true  },
    [243435] = { name = "Fortifying Brew",             icon = 1028045, cooldown = 420, class = "MONK",        aoe = true  },
    -- ── Hunter ─────────────────────────────────────────────────
    [186265] = { name = "Aspect of the Turtle",        icon = 1418423, cooldown = 180, class = "HUNTER",      aoe = false },
    -- ── Evoker ─────────────────────────────────────────────────
    [360823] = { name = "Rewind",                      icon = 4667426, cooldown = 240, class = "EVOKER",      aoe = true  },
    [357170] = { name = "Time Dilation",               icon = 4667421, cooldown = 60,  class = "EVOKER",      aoe = false },
    [374227] = { name = "Zephyr",                      icon = 4622462, cooldown = 120, class = "EVOKER",      aoe = true  },
}

-- Name -> { spellID, cooldown } — built once at load for aura-name-based fallback
-- Used when spellID was Secret during encounter detection and we only have aura.name.
local SPELL_NAME_TO_DATA = {}
do
    for spellID, data in pairs(TRACKED_SPELLS) do
        SPELL_NAME_TO_DATA[data.name] = { spellID = spellID, cooldown = data.cooldown }
    end
end

-- Which spellIDs each class can provide — for roster pre-population
local CLASS_SPELLS = {}
do
    for spellID, data in pairs(TRACKED_SPELLS) do
        local cls = data.class
        if not CLASS_SPELLS[cls] then CLASS_SPELLS[cls] = {} end
        table_insert(CLASS_SPELLS[cls], spellID)
    end
end

-- Aura filter: scan both EXTERNAL_DEFENSIVE (targeted) and BIG_DEFENSIVE (AoE) on every unit
local AURA_FILTER_EXTERNAL = "EXTERNAL_DEFENSIVE HELPFUL"
local AURA_FILTER_BIG      = "BIG_DEFENSIVE HELPFUL"

-- Display constants
local ROW_HEIGHT    = 22
local ICON_SIZE     = 20
local FRAME_PADDING = 8
local READY_COLOR   = { r = 0.4, g = 1,   b = 0.4 }
local OCD_COLOR     = { r = 1,   g = 0.7, b = 0.1 }
local ACTIVE_COLOR  = { r = 1,   g = 1,   b = 1   }
local DIM_ALPHA     = 0.5
local TICKER_RATE   = 0.5
local MODULE_NAME   = "ExternalCooldowns"

-- ──────────────────────────────────────────────────────────────
-- Module state
-- ──────────────────────────────────────────────────────────────

local isEnabled        = false
local ticker           = nil
local restrictionActive = false  -- true during encounter / M+ / PvP match

local displayFrame = nil
local rowFrames    = {}

-- Single source of truth for what to display.
-- Each entry: { casterUnit, casterName, casterClass, spellID, spellName, spellIcon,
--               auraInstanceID, phase, expireAt }
-- phase: "ready" | "active" | "recovering"
local trackedRows = {}

-- Per-unit aura cache for diffing: [unit][auraInstanceID] = { name, icon }
local lastSeenAuras = {}

-- ──────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────

---@param seconds number
---@return string
local function FormatTime(seconds)
    if seconds <= 0 then return "Ready" end
    local m = math_floor(seconds / 60)
    local s = math_floor(seconds % 60)
    return string_format("%d:%02d", m, s)
end

local function DebugPrint(msg)
    local settings = JT:GetModuleSettings(MODULE_NAME)
    if settings and settings.debugMode then
        print("|cff00aaffJetTools EC|r: " .. msg)
    end
end

-- Iterate all current group unit tokens (including player)
local function IterateGroup(callback)
    if IsInRaid() then
        local count = GetNumGroupMembers()
        for i = 1, count do
            callback("raid" .. i)
        end
    else
        callback("player")
        local count = GetNumGroupMembers()
        for i = 1, count do
            callback("party" .. i)
        end
    end
end

-- Find the row matching casterUnit + spellName (or casterUnit + auraInstanceID)
local function FindRow(casterUnit, spellName, auraInstanceID)
    for _, row in ipairs(trackedRows) do
        if row.casterUnit == casterUnit then
            if auraInstanceID and row.auraInstanceID == auraInstanceID then
                return row
            end
            if spellName and row.spellName == spellName then
                return row
            end
        end
    end
    return nil
end

-- ──────────────────────────────────────────────────────────────
-- Aura detection
-- ──────────────────────────────────────────────────────────────

local function OnAuraAppeared(unit, auraData)
    local name       = auraData.name
    local icon       = auraData.icon
    local instanceID = auraData.auraInstanceID

    DebugPrint(string_format("AURA APPEARED on %s: %s (instanceID %s)",
        unit, tostring(name), tostring(instanceID)))

    -- Look up spell data by name
    local cdData = SPELL_NAME_TO_DATA[name]
    if not cdData then
        -- Not a spell we track — ignore
        return
    end

    -- Find the existing "ready" or "recovering" row for this caster+spell
    local row = FindRow(unit, name, nil)
    if not row then
        -- Caster not yet in tracked list (joined mid-fight? AoE on non-caster unit?)
        -- We only create caster rows from the roster; skip non-caster aura appearances.
        DebugPrint("No row found for " .. unit .. " / " .. tostring(name) .. " — skipping")
        return
    end

    row.phase          = "active"
    row.auraInstanceID = instanceID
    row.spellName      = name
    row.spellIcon      = icon
    if not row.spellID then
        row.spellID = cdData.spellID
    end
    row.expireAt = nil  -- clear any prior recovery timer

    DebugPrint(string_format("Row updated: %s cast %s -> phase=active", row.casterName, name))
end

local function OnAuraExpired(unit, instanceID, savedName, savedIcon)
    DebugPrint(string_format("AURA EXPIRED on %s: %s (instanceID %s)",
        unit, tostring(savedName), tostring(instanceID)))

    local row = FindRow(unit, nil, instanceID)
    if not row then
        DebugPrint("No row found for expired aura instanceID " .. tostring(instanceID))
        return
    end

    -- Determine cooldown duration
    local cdData = row.spellID and TRACKED_SPELLS[row.spellID]
    if not cdData then
        cdData = savedName and SPELL_NAME_TO_DATA[savedName]
    end
    local cooldown = cdData and cdData.cooldown or 120  -- fallback 2 min

    row.phase          = "recovering"
    row.auraInstanceID = nil
    row.expireAt       = GetTime() + cooldown

    DebugPrint(string_format("Row updated: %s %s -> phase=recovering, expires in %ds",
        row.casterName, tostring(row.spellName), cooldown))
end

-- Scan a single unit's auras and diff against last known state
local function ScanUnitAuras(unit)
    if not UnitExists(unit) then return end

    local prev = lastSeenAuras[unit] or {}
    local curr = {}

    -- Query both filter types
    local function ProcessAura(auraData)
        if not auraData then return end
        local instanceID = auraData.auraInstanceID
        if not instanceID then return end
        -- Only process auras for spells we actually track (by name)
        if not SPELL_NAME_TO_DATA[auraData.name] then return end
        curr[instanceID] = { name = auraData.name, icon = auraData.icon }
        if not prev[instanceID] then
            -- New aura appeared
            OnAuraAppeared(unit, auraData)
        end
    end

    local externalAuras = C_UnitAuras.GetUnitAuras(unit, { filter = AURA_FILTER_EXTERNAL })
    if externalAuras then
        for _, auraData in ipairs(externalAuras) do
            ProcessAura(auraData)
        end
    end

    local bigAuras = C_UnitAuras.GetUnitAuras(unit, { filter = AURA_FILTER_BIG })
    if bigAuras then
        for _, auraData in ipairs(bigAuras) do
            -- Avoid double-processing if same instanceID already seen via EXTERNAL filter
            if auraData and auraData.auraInstanceID and not curr[auraData.auraInstanceID] then
                ProcessAura(auraData)
            end
        end
    end

    -- Detect expired auras (were in prev, not in curr)
    for instanceID, saved in pairs(prev) do
        if not curr[instanceID] then
            OnAuraExpired(unit, instanceID, saved.name, saved.icon)
        end
    end

    lastSeenAuras[unit] = curr
end

-- Scan all group members
local function ScanAllUnits()
    IterateGroup(ScanUnitAuras)
end

-- ──────────────────────────────────────────────────────────────
-- Roster management
-- ──────────────────────────────────────────────────────────────

local function RebuildRoster()
    -- Preserve existing phase/expireAt for rows we're keeping
    local existing = {}
    for _, row in ipairs(trackedRows) do
        local key = row.casterUnit .. "_" .. (row.spellName or tostring(row.spellID))
        existing[key] = {
            phase          = row.phase,
            expireAt       = row.expireAt,
            auraInstanceID = row.auraInstanceID,
            spellID        = row.spellID,
        }
    end

    -- Clear aura cache for units no longer in group
    lastSeenAuras = {}

    local newRows = {}
    IterateGroup(function(unit)
        if not UnitExists(unit) then return end
        local name = UnitName(unit) or "Unknown"
        local _, classFile = UnitClass(unit)
        if not classFile then return end

        local spells = CLASS_SPELLS[classFile]
        if not spells then return end

        for _, spellID in ipairs(spells) do
            local spell = TRACKED_SPELLS[spellID]
            local key = unit .. "_" .. spell.name
            local prev = existing[key]
            table_insert(newRows, {
                casterUnit     = unit,
                casterName     = name,
                casterClass    = classFile,
                spellID        = spellID,
                spellName      = spell.name,
                spellIcon      = spell.icon,
                auraInstanceID = prev and prev.auraInstanceID or nil,
                phase          = prev and prev.phase or "ready",
                expireAt       = prev and prev.expireAt or nil,
            })
        end
    end)

    trackedRows = newRows
end

-- ──────────────────────────────────────────────────────────────
-- Display
-- ──────────────────────────────────────────────────────────────

local function SortRows(a, b)
    -- recovering first (soonest ready first), then active, then ready
    local phaseOrder = { recovering = 0, active = 1, ready = 2 }
    local pa = phaseOrder[a.phase] or 2
    local pb = phaseOrder[b.phase] or 2
    if pa ~= pb then return pa < pb end
    if a.phase == "recovering" and b.phase == "recovering" then
        return (a.expireAt or 0) < (b.expireAt or 0)
    end
    return (a.spellName or "") < (b.spellName or "")
end

local function GetRowFrame(index, parent)
    if rowFrames[index] then return rowFrames[index] end

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    row.label = label

    local timer = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timer:SetPoint("RIGHT", 0, 0)
    timer:SetJustifyH("RIGHT")
    row.timer = timer

    rowFrames[index] = row
    return row
end

local function UpdateDisplay()
    if not displayFrame then return end

    local settings    = JT:GetModuleSettings(MODULE_NAME)
    local now         = GetTime()
    local fontSize    = (settings and settings.fontSize) or 13
    local frameWidth  = 280

    -- Expire "recovering" rows whose timer is up — transition back to "ready"
    for _, row in ipairs(trackedRows) do
        if row.phase == "recovering" and row.expireAt and row.expireAt <= now then
            row.phase    = "ready"
            row.expireAt = nil
        end
    end

    local sorted = {}
    for _, row in ipairs(trackedRows) do
        table_insert(sorted, row)
    end
    table_sort(sorted, SortRows)

    local visibleCount = #sorted
    local frameHeight  = FRAME_PADDING * 2 + visibleCount * ROW_HEIGHT
                         + math.max(0, visibleCount - 1) * 2

    for i = visibleCount + 1, #rowFrames do
        rowFrames[i]:Hide()
    end

    displayFrame:SetWidth(frameWidth)
    displayFrame:SetHeight(math.max(ROW_HEIGHT + FRAME_PADDING * 2, frameHeight))

    if visibleCount == 0 then
        displayFrame:Hide()
        return
    end

    for i, data in ipairs(sorted) do
        local row = GetRowFrame(i, displayFrame)

        row:SetWidth(frameWidth - FRAME_PADDING * 2)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", displayFrame, "TOPLEFT",
                     FRAME_PADDING,
                     -(FRAME_PADDING + (i - 1) * (ROW_HEIGHT + 2)))

        -- Icon
        row.icon:SetTexture(data.spellIcon)

        -- Label: [ClassColor]CasterName|r - SpellName
        local classColor = C_ClassColor.GetClassColor(data.casterClass)
        local nameHex = classColor
            and string_format("|cff%02x%02x%02x",
                    math_floor(classColor.r * 255),
                    math_floor(classColor.g * 255),
                    math_floor(classColor.b * 255))
            or "|cffcccccc"
        local labelText = nameHex .. data.casterName .. "|r - " .. (data.spellName or "Unknown")
        row.label:SetText(labelText)
        row.label:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

        -- Timer text and colors per phase
        row.timer:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")

        if data.phase == "active" then
            row.timer:SetText("ACTIVE")
            row.timer:SetTextColor(ACTIVE_COLOR.r, ACTIVE_COLOR.g, ACTIVE_COLOR.b)
            row.icon:SetAlpha(1)
            row.label:SetAlpha(1)
            row.timer:SetAlpha(1)
        elseif data.phase == "recovering" then
            local remaining = (data.expireAt or now) - now
            row.timer:SetText(FormatTime(remaining))
            row.timer:SetTextColor(OCD_COLOR.r, OCD_COLOR.g, OCD_COLOR.b)
            row.icon:SetAlpha(1)
            row.label:SetAlpha(1)
            row.timer:SetAlpha(1)
        else -- "ready"
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
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        JT:SetModuleSetting(MODULE_NAME, "posX", math_floor(x - ux))
        JT:SetModuleSetting(MODULE_NAME, "posY", math_floor(y - uy))
    end)

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

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...

        if restrictionActive then
            -- spellID is Secret — do NOT compare it.
            -- Immediately scan the caster's auras; UNIT_AURA may lag behind the cast.
            DebugPrint(string_format("USS (restricted) unit=%s — scanning auras", unit))
            ScanUnitAuras(unit)
        else
            -- spellID is plain — direct lookup
            local spell = TRACKED_SPELLS[spellID]
            if not spell then return end

            DebugPrint(string_format("USS unit=%s spellID=%d (%s)",
                unit, spellID, spell.name))

            -- Find the row and set recovering.
            -- If the aura appears moments later, OnAuraAppeared will flip to "active".
            -- When the aura expires, OnAuraExpired will flip back to "recovering".
            local now = GetTime()
            local matched = false
            for _, row in ipairs(trackedRows) do
                if row.casterUnit == unit and row.spellID == spellID then
                    row.phase    = "recovering"
                    row.expireAt = now + spell.cooldown
                    matched      = true
                end
            end

            if not matched then
                -- Unit not pre-populated (e.g. joined after roster build) — add ad-hoc row
                if UnitExists(unit) then
                    local name = UnitName(unit) or "Unknown"
                    local _, classFile = UnitClass(unit)
                    if classFile then
                        table_insert(trackedRows, {
                            casterUnit     = unit,
                            casterName     = name,
                            casterClass    = classFile,
                            spellID        = spellID,
                            spellName      = spell.name,
                            spellIcon      = spell.icon,
                            auraInstanceID = nil,
                            phase          = "recovering",
                            expireAt       = now + spell.cooldown,
                        })
                    end
                end
            end

            UpdateDisplay()
        end

    elseif event == "UNIT_AURA" then
        local unit, isFullUpdate = ...
        -- unit is the token whose auras changed — scan it directly
        ScanUnitAuras(unit)
        UpdateDisplay()

    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local _, restrictionType, state = ...
        -- state: 0=Inactive, 1=Activating, 2=Active
        if state == 1 then
            -- Restriction about to activate
            restrictionActive = true
            DebugPrint("Restriction ACTIVATING — switching to aura-only detection")
        elseif state == 0 then
            -- Restriction lifted — spellIDs are plain again; re-sync full state
            restrictionActive = false
            DebugPrint("Restriction INACTIVE — re-scanning all units")
            ScanAllUnits()
            UpdateDisplay()
        end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        RebuildRoster()
        ScanAllUnits()
        UpdateDisplay()
    end
end)

-- ──────────────────────────────────────────────────────────────
-- Options
-- ──────────────────────────────────────────────────────────────

function ExternalCooldowns:GetOptions()
    return {
        { type = "header",      label = "External Cooldowns" },
        { type = "description", text = "Tracks defensive cooldowns used by group members. Works during encounters via aura detection (Midnight-compatible)." },
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

    -- Check if we're already in a restricted state (e.g. module enabled mid-encounter)
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        local enc = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Encounter
        if enc and C_RestrictedActions.IsAddOnRestrictionActive(enc) then
            restrictionActive = true
        end
    end

    eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    eventFrame:RegisterEvent("UNIT_AURA")
    eventFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    RebuildRoster()
    ScanAllUnits()

    if not ticker then
        ticker = C_Timer.NewTicker(TICKER_RATE, function()
            if not isEnabled then return end

            local settings = JT:GetModuleSettings(MODULE_NAME)
            local inGroup  = GetNumGroupMembers() > 0
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

    if displayFrame then displayFrame:Hide() end
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
            print("|cff00aaffJetTools EC|r: Debug logging enabled. Cast/aura events will print to chat.")
        end
    end
end

# AGENTS.md — JetTools Coding Agent Guide

This file provides instructions for AI coding agents working in this repository.

---

## Project Overview

**JetTools** is a World of Warcraft addon written in **Lua 5.1** targeting Interface `120000`
(The War Within / early Midnight). It runs inside the WoW game client's sandboxed Lua
environment — there is no Node.js, browser, or server runtime involved.

The addon is structured as a core module registry (`Core.lua`) plus feature modules in
`Modules/`. External libraries (LibStub, LibSharedMedia-3.0) are fetched at release time
by the BigWigs packager and are not committed to the repo.

---

## Build & Release

There is **no local build step**. The release pipeline is fully CI-driven:

- Releases are triggered by pushing a git tag (any tag pattern `**`)
- `.github/workflows/release.yml` runs the `BigWigsMods/packager@v2` action
- The packager fetches external libs declared in `.pkgmeta`, zips the addon, and publishes
  to CurseForge, Wago.io, and GitHub Releases

To cut a release: push a version tag (`git tag v1.2.3 && git push origin v1.2.3`).

---

## Testing

**There is no automated test framework.** WoW addon testing is done live inside the game.

Workflow:
1. Edit Lua files
2. In-game, run `/reload` (or type `/reload ui`) to reload all addon code
3. Reproduce the scenario and observe behavior
4. Use `print(...)` or `DEFAULT_CHAT_FRAME:AddMessage(...)` for debug output in-game
5. Lua errors surface as in-game error dialogs with stack traces

There are no test files to create or maintain.

---

## Linting

No CLI linter is configured. The project uses the **Lua Language Server** (`sumneko/lua-language-server`)
for IDE-level static analysis via the `ketho.wow-api` VS Code extension, which provides
WoW API type annotations and global declarations.

Key LSP settings (`.vscode/settings.json`):
- `"Lua.runtime.version": "Lua 5.1"`
- WoW API globals are declared to suppress false-positive warnings
- Standard Lua libraries (io, os, etc.) are disabled — WoW's Lua environment is sandboxed
- `"Lua.type.weakUnionCheck": true`

Avoid introducing standard Lua library calls (`io.open`, `os.time`, `require`, etc.) —
they do not exist in the WoW runtime.

---

## Module Architecture

Every module must follow this exact structure:

```lua
local addonName, JT = ...           -- receive addon name and shared namespace
local MyModule = {}
JT:RegisterModule("MyModule", MyModule)

-- Module-local state (never exposed on JT directly)
local isEnabled = false

-- Required: returns the declarative options schema table (may return {} if no options)
function MyModule:GetOptions()
    return {
        { type = "header", label = "My Module" },
        { type = "checkbox", label = "Enable", key = "enabled", default = true },
    }
end

-- Required: one-time setup (create frames, install hooks). Runs regardless of enabled state.
function MyModule:Init()
    -- hooksecurefunc, CreateFrame, etc.
end

-- Required: called when the module is turned on; register events, set isEnabled = true
function MyModule:Enable()
    isEnabled = true
    eventFrame:RegisterEvent("SOME_EVENT")
end

-- Required: called when the module is turned off; unregister events, set isEnabled = false
function MyModule:Disable()
    isEnabled = false
    eventFrame:UnregisterEvent("SOME_EVENT")
end

-- Optional: called by Core when a saved setting changes
function MyModule:OnSettingChanged(key, value)
    -- react to setting changes
end
```

**Core.lua** calls `Init()` on all modules at `ADDON_LOADED`, then `Enable()` or `Disable()`
based on saved variables. Do not call `Init`/`Enable`/`Disable` manually.

---

## Load Order

Load order is declared in `JetTools.toc` — files are executed sequentially by the WoW
client. There is no `require`. To add a new module:

1. Create `Modules/MyModule.lua`
2. Add the path to `JetTools.toc` after existing module entries
3. That's it — Core.lua auto-discovers all registered modules

---

## Naming Conventions

| Construct                        | Convention        | Example                                      |
|----------------------------------|-------------------|----------------------------------------------|
| Module tables                    | `PascalCase`      | `RangeIndicator`, `CDMAuraRemover`           |
| Module methods (colon syntax)    | `PascalCase`      | `MyModule:Enable()`, `MyModule:GetOptions()` |
| Local functions                  | `PascalCase`      | `CreateIndicator()`, `UpdateAllSlots()`      |
| Local variables                  | `camelCase`       | `isEnabled`, `lastUpdateTime`, `messageFrame`|
| Constants / config tables        | `UPPER_SNAKE_CASE`| `UPDATE_INTERVAL`, `CLASS_RANGE_ABILITIES`   |
| WoW frame/FontString locals      | `PascalCase`      | `LevelText`, `EnchantText`, `GemFrames`      |
| Event handler functions          | `PascalCase`      | `OnEvent()`                                  |

---

## Type Annotations

Use **EmmyLua / LuaLS** annotations selectively — on complex data structures and any
function that is non-obvious. Do not annotate every local variable.

```lua
---@type table<number, { unit: string, slot: number }>
local itemInfoRequested = {}

---@param level number
---@return string
local function GetRarityColor(level)
    ...
end

---@type FontString|nil
local AverageItemLevelText = nil
```

---

## Error Handling

WoW addons must not crash. Prefer silent/graceful failure over raising errors.

**Rules:**
- Use guard clauses with early `return` rather than deep nesting
- Always nil-check before indexing a potentially-nil value
- Use `pcall` for any WoW API call that may fail on protected/nil frames
- Gate all event handlers with `if not isEnabled then return end` at the top
- Use lazy initialization: `if not myFrame then ... create it ... end`
- Use `print("|cff00aaffJetTools|r: " .. msg)` for non-fatal user-facing warnings
- **Never use `error()` or `assert()`** — these throw Lua errors that surface as disruptive
  in-game error dialogs

```lua
-- Good
local ok, result = pcall(C_Spell.GetSpellChargeDuration, spellID)
if ok and result then
    -- use result
end

-- Good
if not frame or not frame:IsShown() then return end

-- Bad — will crash and show an error dialog
assert(frame ~= nil, "frame must exist")
```

---

## WoW API Conventions

**Upvalue locals for performance** — localize frequently called globals at the top of a file:
```lua
local UnitExists = UnitExists
local UnitClass  = UnitClass
local GetTime    = GetTime
```

**Post-hooking Blizzard UI** — use `hooksecurefunc` to run after a Blizzard function
without replacing it (avoids tainting the protected execution environment):
```lua
hooksecurefunc("SomeBlizzardFunction", function(arg1, arg2)
    -- runs after the original
end)
```

**Deferred execution** — use `C_Timer.After(0, fn)` to schedule work after the current
event frame completes (useful when item/unit data is not yet available):
```lua
C_Timer.After(0, function()
    UpdateSlot(slot)
end)
```

**WoW color markup** — use the `|cAARRGGBB...text...|r` format for colored chat/UI text:
```lua
print("|cff00aaffJetTools|r: some message")   -- blue "JetTools" prefix
```

**Expansion detection** — detect expansion at module load time, not at runtime:
```lua
local IS_MIDNIGHT = select(4, GetBuildInfo()) > 120000
```

---

## Options Schema (GetOptions)

Options.lua reads each module's `GetOptions()` return value and builds the UI generically.
Supported entry types:

```lua
{ type = "header",      label = "Section Title" }
{ type = "subheader",   label = "Subsection" }
{ type = "description", text = "Explanatory text." }
{ type = "checkbox",    label = "...", key = "settingKey", default = true }
{ type = "slider",      label = "...", key = "settingKey", min = 12, max = 48, step = 2, default = 24 }
{ type = "dropdown",    label = "...", key = "settingKey", options = { "A", "B" }, default = "A" }
{ type = "input",       label = "...", key = "settingKey", width = 150 }
{ type = "button",      label = "...", width = 120, func = function() ... end }
```

`key` maps directly to the saved variable key in `JetToolsDB[moduleName][key]`.
`default` is used when no saved value exists.

---

## Adding a New Module — Checklist

- [ ] Create `Modules/MyModule.lua`
- [ ] Start with `local addonName, JT = ...`
- [ ] Create and register the module table: `JT:RegisterModule("MyModule", MyModule)`
- [ ] Implement `GetOptions()`, `Init()`, `Enable()`, `Disable()`
- [ ] Add `Modules/MyModule.lua` to `JetTools.toc` (after existing module lines)
- [ ] Test in-game with `/reload`

<!-- BEGIN BEADS INTEGRATION -->
## Issue Tracking with bd (beads)

**IMPORTANT**: This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown TODOs, task lists, or other tracking methods.

### Why bd?

- Dependency-aware: Track blockers and relationships between issues
- Git-friendly: Dolt-powered version control with native sync
- Agent-optimized: JSON output, ready work detection, discovered-from links
- Prevents duplicate tracking systems and confusion

### Quick Start

**Check for ready work:**

```bash
bd ready --json
```

**Create new issues:**

```bash
bd create "Issue title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd create "Issue title" --description="What this issue is about" -p 1 --deps discovered-from:bd-123 --json
```

**Claim and update:**

```bash
bd update <id> --claim --json
bd update bd-42 --priority 1 --json
```

**Complete work:**

```bash
bd close bd-42 --reason "Completed" --json
```

### Issue Types

- `bug` - Something broken
- `feature` - New functionality
- `task` - Work item (tests, docs, refactoring)
- `epic` - Large feature with subtasks
- `chore` - Maintenance (dependencies, tooling)

### Priorities

- `0` - Critical (security, data loss, broken builds)
- `1` - High (major features, important bugs)
- `2` - Medium (default, nice-to-have)
- `3` - Low (polish, optimization)
- `4` - Backlog (future ideas)

### Workflow for AI Agents

1. **Check ready work**: `bd ready` shows unblocked issues
2. **Claim your task atomically**: `bd update <id> --claim`
3. **Work on it**: Implement, test, document
4. **Discover new work?** Create linked issue:
   - `bd create "Found bug" --description="Details about what was found" -p 1 --deps discovered-from:<parent-id>`
5. **Complete**: `bd close <id> --reason "Done"`

### Auto-Sync

bd automatically syncs via Dolt:

- Each write auto-commits to Dolt history
- Use `bd dolt push`/`bd dolt pull` for remote sync
- No manual export/import needed!

### Important Rules

- ✅ Use bd for ALL task tracking
- ✅ Always use `--json` flag for programmatic use
- ✅ Link discovered work with `discovered-from` dependencies
- ✅ Check `bd ready` before asking "what should I work on?"
- ❌ Do NOT create markdown TODO lists
- ❌ Do NOT use external issue trackers
- ❌ Do NOT duplicate tracking systems

For more details, see README.md and docs/QUICKSTART.md.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds

<!-- END BEADS INTEGRATION -->

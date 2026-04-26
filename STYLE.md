# Booshie's Lua Coding Style Guide

Conventions for `.lua` files in this repository.

## File Structure

Large overloaded files should be avoided in favor of structured files that each relate to a specific set of responsibilities and expose a minimal, focused public surface via `addon`.

While the decision to add a new file should be done thoughtfully, the cost of a new file is one `.toc` entry and a few lines of boilerplate. The cost of mixing concerns in one giant file is code that is hard to read, maintain, and is riddled with technical debt.

### Decomposition

Create a new file when any of the following is true:

- **The code could plausibly be reused.** Even before a second consumer exists, code with the potential to be reused should go in its own file. Extract a reusable widget or capability the moment the design suggests a second consumer might exist. Pulling apart the code later when it already has multiple consumers will be far more expensive then one additional `.toc` entry.

- **The code owns state that no one else should touch.** Lua's `local` scope is the strongest privacy boundary the language offers, and it is scoped to the file. State that holds invariants — caches, dedup tables, singleton settings — belongs as `local`s in its own file, where it is physically unreachable from the rest of the addon. All access then has to flow through a deliberate public API that enforces the contract you actually want to govern how the addon is used.

- **Abstraction would minimise the impact of change.** If you can encapsulate a capability in a way that consumers of that capability can be isolated from changes in the underlying data, events, or API calls the capability is dependent on, your code will be significantly easier to maintain and you will be able to respond to changes faster.

- **The file has grown too large to hold in your head.** If you can't keep a working model of a file in your head, the file is almost certainly doing too much. You don't need to be able to internalise what every line of code does or know exactly where it is within a file, but you should be able to develop a strong intuition based on a single read through of a file. A multi-thousand-line file with UI construction, refresh orchestration, event dispatch, and who knows whatelse is resistant to refactoring and hard to maintain because no one can hold all of it in mind at once.

### Modules vs Classes

The logic in most files should be encapsulated as either modules or classes.

A **module** is exposed as a single shared instance (singleton). Other files access the shared instance via `addon.ModuleName`.

Modules enable the strongest protections for internal state, but the trade-off is that there can only be one version of that state.

```lua
local addonName, addon = ...

local EventCapture = {}
addon.EventCapture = EventCapture


-- registerDefaults if the module persists state
addon.Core.registerDefaults("eventCapture", { ... })


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

-- ...


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

-- module-private tables and flags


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- private helpers, optionally split into themed subsections


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function EventCapture.someThing() ... end


--------------------------------------------------------------------------------
-- WIRING
--------------------------------------------------------------------------------

-- event subscriptions, slash commands, anything that activates the module
```

A **class** exposes a constructor that allow other files to create instances via `Class.new(...)` and call methods that operate on a specific/dedicated instance of the class rather than a single shared instance.

Classes are great for things like UI widgets where you may have multiple instances operating at the same time, each performing a similar function but with slightly different goals. The major downside of classes (in `lua`) is that they offer weaker protections for the state within the class, meaning that consumers of the class may modify or access the state in ways that you did not intend.

```lua
local addonName, addon = ...

local ListPanel = {}
ListPanel.__index = ListPanel
addon.UI.ListPanel = ListPanel


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

-- ...


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- file-local helpers (NOT methods on the class)
-- either pure (state independent), or take an instance as the first argument


--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function ListPanel.new(parent, opts)
    local self = setmetatable({}, ListPanel)
    -- ...
    return self
end


--------------------------------------------------------------------------------
-- PUBLIC METHODS
--------------------------------------------------------------------------------

function ListPanel:setItems(items) ... end
```

The standard top-to-bottom order is: boilerplate → constants → state → local functions → constructor → public API → wiring. Order *inside* a section is a readability decision — table-attached functions (`function Module.foo`, `function Class:bar`) have no load-time dependency on each other, so they can appear in whatever sequence is easiest to understand.

Use sections and sub-section banners (see Comments) to help clarify the structure of the file and group common logic.

### Naming and privacy

| Kind | Shape | Example | Privacy |
|---|---|---|---|
| Module / class name | `PascalCase` | `EventCapture`, `ListPanel` | — |
| Constants | `UPPER_SNAKE` | `ROW_HEIGHT`, `NOTIFY_INTERVAL` | file-local, enforced |
| File-local function | `camelCase` | `local function notify()` | file-local, enforced |
| File-local value | `camelCase` | `local hideOlder = false` | file-local, enforced |
| Public function or method | `camelCase` | `EventCapture.exclude`, `panel:setItems` | exposed |
| Class field | `self.field` | `self.frame` | no privacy |

`PascalCase` is reserved for module and class names. Functions and values are always `camelCase`. The call site already distinguishes file-local from table-attached: an unqualified call (`notify(...)`) is file-local, a qualified call (`Module.foo(...)`) or method call (`obj:bar(...)`) is table-attached, so the case doesn't need to repeat that signal.

Default to file-local for anything that isn't part of the public API — Lua's `local` scope is real, language-enforced privacy. If a piece of behaviour shouldn't be callable from outside the file, write it as a `local function` that takes the instance as its first argument, not as a class method. Don't rely on naming conventions to mark methods "private" — if it's on the class table, it's public.

Use the metatable pattern (a class) only when more than one instance will exist. A singleton with `:method()` syntax is a module written as a class for no benefit.

---

## Whitespace & Visual Layout

We should organise our code logically into paragraphs that are visually separated from their neighbours, in the same way we organise our ideas in to paragraphs when writing. This allows the reader to easily identify related code/ideas without re-reading.

---

### 1. Function bodies breathe

Add a blank line after the function signature, and before the closing `end`. Applies to any function with a real body. Skip for trivial one-line accessors (e.g. `local function isFoo(x) return x.y end`).

```lua
-- Avoid
local function ScrollIntoView(child)
    if not child then return end
    -- ...
end

-- Prefer
local function ScrollIntoView(child)

    if not child then
        return
    end
    -- ...

end
```

---

### 2. Branches: compact only when simple

A branch may stay on one line when **both**:

1. Its body is a single statement.
2. Its condition is short enough to read at a glance.

Expand onto multiple lines if either side gets complex: multiple statements in the body, or a long / deeply combined condition.

```lua
-- OK: simple condition, single statement
if not row then return end
if target < 0 then target = 0 end
if a or b then doThing() end

-- Borderline: a few simple checks can stay compact if
-- the line still reads at a glance (use your judgement)
if not cTop or not rTop or not rBottom then return end

-- Avoid: multiple actions crammed onto one line
if reset then target = 0; pendingScrollKey = nil end

-- Prefer: expanded
if reset then
    target = 0
    pendingScrollKey = nil
end
```

The same rule applies per branch in `elseif` / `else` chains — count statements and condition complexity for each branch independently, not across the whole `if`/`end` block.

---

### 3. Logical paragraphs separated by blank lines

Inside a function, group related ideas and statements that 'do one thing together' in to paragraphs, with a blank line between each paragraph. A paragraph with one line is fine when the line is load-bearing — early returns, key state mutations, the function's primary side-effect.

This doesn't just apply to the top-level logic in a function, but also to logic within if-blocks, for-blocks, and so forth.

```lua
local cTop = content:GetTop()
local rTop = child:GetTop()
local rBottom = child:GetBottom()

if not cTop or not rTop or not rBottom then
    return
end

padding = padding or ROW_GAP

local y = cTop - rTop
local h = rTop - rBottom
```

---

### 4. Variable declarations are their own paragraph

A run of `local` declarations is a paragraph in its own right. When the next chunk of code tests, validates, or otherwise operates on them, put a blank line between the declarations and that logic.

The exception: a single declaration paired tightly with something like a simple clamp or normalisation that mutates *that same variable* reads as one unit and may stay together with no blank line.

```lua
-- OK: single declaration + immediate clamp on the same variable
local cTop = content:GetTop()
if cTop < minTop then cTop = minTop end

-- Avoid: declarations followed by logic with no break
local cTop = content:GetTop()
local rTop = child:GetTop()
local rBottom = child:GetBottom()
if not cTop or not rTop or not rBottom then
    return
end

-- Prefer: blank line before the logic paragraph
local cTop = content:GetTop()
local rTop = child:GetTop()
local rBottom = child:GetBottom()

if not cTop or not rTop or not rBottom then
    return
end

-- Avoid: multiple declarations + clamp on only one of them
local cTop = content:GetTop()
local rTop = child:GetTop()
local rBottom = child:GetBottom()
if rBottom < maxBottom then rBottom = maxBottom end

-- Prefer: blank line first
local cTop = content:GetTop()
local rTop = child:GetTop()
local rBottom = child:GetBottom()

if rBottom < maxBottom then rBottom = maxBottom end
```

---

### 5. Compact forms that stay compact

Use commonsense when applying these rules. Creatin structures make more sense compact:

- Lookup tables (`CLASSIFICATION_NAMES`, `REQUIRED_EVENTS`) — they're scannable as flat lists.
- Trivial one-line accessors and predicates.
- Short loop bodies where expanding hurts more than it helps.

Rule of thumb: **expand when it aids readability**. If a compact form is already easy to parse at a glance, leave it alone.

---

## Comments

Comments exist to add information that isn't obvious from the code itself. The code shows *what*, comments should explain *why* (a constraint, a quirk, a non-obvious decision). But you should only feel the need to explain *why* if it is not obvious from the code.

A comment is only worth keeping if removing it would leave a future reader with a question they can't answer by reading the code alone. Any comment that can be removed without confuse anyone should be deleted.

### Worthwhile Comments

- Bug workarounds, API quirks, version-dependent behaviour.
- Non-obvious design decisions (why X over Y).
- Contracts the code can't enforce on its own.
- External context (a Blizzard event firing twice, a race condition, a load order dependency).

### Worthless Comments

- Restating the function signature ("Returns the value of X").
- Narrating obvious code ("Loops over each item").
- Lead-in sentences that summarise the very next line.
- Pointers to "the recent X change" which rot fast and are already covered by the commit history.

```lua
-- Avoid: restates what the table name and contents already convey
-- All texture asset paths used by the addon. Centralised so a future
-- skin override is a one-line change.
local UI_TEXTURES = { ... }

-- Prefer: drop the comment entirely
local UI_TEXTURES = { ... }

-- Good: external context that isn't visible from the code
-- Blizzard returns an empty `cstr` for single-step achievements; the
-- achievement-level `description` field is the human-readable label.
local function GetAchievementHeader(achID) ... end
```

### Concise inline commments beat lengthy exposition

When a comment explains something specific to a particular line or block of code, place it at that line. Lengthy exposition at the top of a function that bundles several unrelated WHYs is harder to understand than the same facts placed inline at their respective points.

A top-of-function comment is fine for an invariant that genuinely spans the whole function. It is wrong for a collection of unrelated point-comments to be dressed up as a header.

```lua
-- Avoid: lenghty exposition at top of function that mixes unrelated WHYs
-- First refresh after load is treated as a baseline so we do not fire
-- for every existing tracked item. Items hidden by the zone filter
-- still get marked expanded, and the scroll pin silently no-ops since
-- they will not be in activeRows.
local function DetectAndShowNewlyTracked(currentKeys)
    -- ...
end

-- Prefer: each WHY at the line or block of code it explains
local function DetectAndShowNewlyTracked(currentKeys)

    if not previousTrackedKeys then
        -- First refresh after load: capture baseline silently so we
        -- do not fire for every already-tracked item.
        previousTrackedKeys = currentKeys
        return
    end

    -- Mark expanded even if the zone filter is hiding this item.
    expandedKeys[key] = true

    -- Hidden-by-filter items have no matching row in activeRows, so
    -- ApplyPendingScroll naturally no-ops for them.
    if lastNewKey then ... end

end
```

### Dividers in tables

Short labels grouping entries inside a table or list aren't really comments — they're visual aids. Use **Title Case** for short headers.

```lua
local UI_COLORS = {
    -- Row Backgrounds
    superTrackBg = { 1.0,  0.82, 0.0,  0.12 },
    completedBg  = { 0.12, 0.35, 0.15, 0.45 },

    -- Progress Bar
    barBg        = { 0.22, 0.22, 0.24, 0.95 },
    -- ...
}
```

---

### Section headers

Section headers should be used to help break up large files and keep them easy to navigate.

Section headers should be a three line banner padded to exactly 80 columns. There should be two blank lines above the banner (an extra blank line beyond the usual single blank between top-level declarations) and one blank line below it before the first declaration in the section.

Section names should be CAPITLISED.

```lua


--------------------------------------------------------------------------------
-- SECTION NAME
--------------------------------------------------------------------------------

local function FirstThingInSection()
```

The two blank lines above are the rule that distinguishes a section break from an ordinary declaration break. A reader scrolling the file sees the extra space before they see the banner itself.

---

### Sub-Section Headers

Sub-Sectiom headers should follow similar rules to section headers, but used to break up the code within a section in to logical groupings.

Sub-Section headers should be a single line banners padded to exactly 80 columns. There should only be a single blank link about to banner.

Sub-Section names should be CAPITLISED.

```lua

-- SUB-SECTION NAME ------------------------------------------------------------

local function FirstThingInSubSection()
```
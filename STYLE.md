# Booshie's Lua Coding Style Guide

Conventions for `.lua` files in this repository.

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


-- =============================================================================
-- SECTION NAME
-- =============================================================================

local function FirstThingInSection()
```

The two blank lines above are the rule that distinguishes a section break from an ordinary declaration break. A reader scrolling the file sees the extra space before they see the banner itself.

---
local addonName, addon = ...

local BooshiesTracker = {}
addon.BooshiesTracker = BooshiesTracker


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local ROW_HEIGHT = addon.UI.TrackerEntry.ROW_HEIGHT
local ROW_GAP    = addon.UI.TrackerEntry.ROW_GAP

-- After an entry click, debounced WoW events (QUEST_LOG_UPDATE, BAG_UPDATE_DELAYED,
-- etc.) often trigger another refresh ~50ms later, and the second layout pass
-- can shift content slightly (lazy text measurement, scrollbar appear/disappear).
-- We pin the click target by key for a short window and re-apply scrollIntoView
-- at the end of each refresh within that window.
local SCROLL_PIN_WINDOW = 0.3

-- Render order for sections. Composed from each Data module's quest-classification
-- order (currently only Quests has internal grouping) plus the singular section
-- each non-quest module produces.
local SECTION_ORDER = {}

local function buildSectionOrder()

    local seen = {}

    for _, name in ipairs(addon.Data.Quests.SECTION_ORDER) do
        SECTION_ORDER[#SECTION_ORDER + 1] = name
        seen[name] = true
    end

    for _, sectionName in ipairs({ "Achievements", "Crafting", "Monthly", "Endeavours" }) do
        if not seen[sectionName] then
            SECTION_ORDER[#SECTION_ORDER + 1] = sectionName
        end
    end

end

buildSectionOrder()


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local window
local frame, titleText, zoneText, content, scrollFrame

local pendingScrollKey, pendingScrollExpiresAt
local previousTrackedKeys
local pendingFlashKeys = {}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local DATA_MODULES = {
    "Quests", "Achievements", "Recipes", "JournalActivities", "NeighbourhoodActivities",
}


-- LAYOUT & SCROLL --------------------------------------------------------------

local function relayoutLayout(layout)

    layout = layout or {}

    local y = 0
    local trailingGap = 0

    for i, item in ipairs(layout) do
        local isSection = item.itemKind == "section"

        if not isSection and not item.expanded then item:SetHeight(ROW_HEIGHT) end

        if item.separator then
            if isSection then
                local nextItem = layout[i + 1]
                local hasContentBelow = nextItem and nextItem.itemKind ~= "section"
                item.separator:SetShown(hasContentBelow)
            else
                item.separator:SetShown(true)
            end
        end

        -- Sections after the first get a small gap above them.
        local gapBefore = 0
        if isSection and i > 1 then gapBefore = 4 end
        y = y + gapBefore

        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        item:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

        trailingGap = isSection and 2 or ROW_GAP
        y = y + item:GetHeight() + trailingGap
    end

    local contentHeight = math.max(y - trailingGap, 1)
    content:SetHeight(contentHeight)

    local maxH = addon.Core.getDB().maxHeight or 300
    local finalHeight = math.max(maxH, window.minMaxHeight)
    frame:SetHeight(finalHeight)

    local viewport = finalHeight - window.headerOffset - window.bottomPad
    local bar = scrollFrame.ScrollBar or _G["BooshiesQuestLogScrollScrollBar"]
    local barVisible = false

    if bar then
        barVisible = contentHeight > viewport + 0.5

        if barVisible then
            scrollFrame._bqlForceHidden = false
            bar:Show()
            scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, window.bottomPad)
        else
            scrollFrame._bqlForceHidden = true
            bar:Hide()
            scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, window.bottomPad)
            if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(0) end
        end
    end

    local frameWidth = frame:GetWidth() or (addon.Core.getDB().width or 280)
    local contentWidth = frameWidth - 8 - (barVisible and 26 or 8)
    content:SetWidth(math.max(contentWidth, 1))

    if scrollFrame.UpdateScrollChildRect then scrollFrame:UpdateScrollChildRect() end

end

-- Aligns to the top edge if scrolling up, bottom if down. No-op if the child
-- is already fully visible.
local function scrollIntoView(child, padding)

    if not child or not scrollFrame or not content then return end
    if not scrollFrame.SetVerticalScroll then return end

    local cTop = content:GetTop()
    local rTop = child:GetTop()
    local rBottom = child:GetBottom()
    if not cTop or not rTop or not rBottom then return end

    padding = padding or ROW_GAP

    local y = cTop - rTop                -- child's top offset within content
    local h = rTop - rBottom             -- child's height
    local viewport = scrollFrame:GetHeight() or 0
    local scroll = scrollFrame:GetVerticalScroll() or 0
    local maxScroll = scrollFrame:GetVerticalScrollRange() or 0

    local target

    if y - padding < scroll - 0.5 then
        target = y - padding
    elseif y + h + padding > scroll + viewport + 0.5 then
        target = y + h + padding - viewport
    else
        return
    end

    if target < 0 then target = 0 end
    if target > maxScroll then target = maxScroll end

    scrollFrame:SetVerticalScroll(target)

end


-- COLLECT ----------------------------------------------------------------------

local function collectVisibleItems()

    local items = {}

    for _, name in ipairs(DATA_MODULES) do
        for _, item in ipairs(addon.Data[name].collect()) do
            table.insert(items, item)
        end
    end

    return items

end

local function collectAllTrackedKeys()

    local keys = {}

    for _, name in ipairs(DATA_MODULES) do
        for _, item in ipairs(addon.Data[name].collectAll()) do
            keys[item.key] = true
        end
    end

    return keys

end

local function groupBySection(items)

    local grouped = {}

    for _, item in ipairs(items) do
        grouped[item.section] = grouped[item.section] or {}
        table.insert(grouped[item.section], item)
    end

    for _, list in pairs(grouped) do
        table.sort(list, function(a, b) return (a.title or "") < (b.title or "") end)
    end

    return grouped

end

local function countQuests(items)

    local n = 0
    for _, item in ipairs(items) do
        if item.kind == "quest" then n = n + 1 end
    end
    return n

end


-- TRACKED-KEY DETECTION --------------------------------------------------------

local function detectAndShowNewlyTracked(currentKeys)

    if not previousTrackedKeys then
        -- First refresh after load. Capture the baseline silently so we do
        -- not fire for every already-tracked item.
        previousTrackedKeys = currentKeys
        return
    end

    local db = addon.Core.getDB()
    db.expandedKeys      = db.expandedKeys      or {}
    db.collapsedSections = db.collapsedSections or {}

    local lastNewKey
    for key in pairs(currentKeys) do
        if not previousTrackedKeys[key] then
            -- Mark expanded even if the zone filter is currently hiding this
            -- item, so it appears expanded next time it becomes visible.
            db.expandedKeys[key] = true

            -- We do not know which section this key belongs to without
            -- iterating the collected items, but the next render pass will
            -- naturally ensure its section is uncollapsed via a scan. To keep
            -- the previous behaviour (uncollapse the receiving section) we
            -- need the item itself; defer that to applyNewlyTrackedSections
            -- once we have visible items in hand.
            pendingFlashKeys[key] = true
            lastNewKey = key
        end
    end

    -- Hidden-by-filter items have no matching entry in active, so the
    -- pending-scroll naturally no-ops for them.
    if lastNewKey then
        pendingScrollKey = lastNewKey
        pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW
    end

    previousTrackedKeys = currentKeys

end

-- Uncollapse the section that contains a freshly-tracked item. Runs after the
-- visible items are gathered so we can map key → section directly.
local function uncollapseSectionsForFlashKeys(items)

    local db = addon.Core.getDB()
    db.collapsedSections = db.collapsedSections or {}

    for _, item in ipairs(items) do
        if pendingFlashKeys[item.key] then
            db.collapsedSections[item.section] = nil
        end
    end

end


-- CHROME -----------------------------------------------------------------------

local function applyCollapsedChrome()

    if scrollFrame then scrollFrame:Hide() end
    if frame.filterBtn then frame.filterBtn:Hide() end
    if frame.cogBtn then frame.cogBtn:Hide() end
    if frame.collapseAllBtn then frame.collapseAllBtn:Hide() end
    if zoneText then zoneText:Hide() end
    if frame.resizer then frame.resizer:Hide() end

    local titleW = (titleText:GetStringWidth() or 80) + 20
    frame:SetSize(math.max(titleW, 100), 30)

end

local function applyExpandedChrome()

    if scrollFrame and not scrollFrame:IsShown() then scrollFrame:Show() end
    if frame.filterBtn and not frame.filterBtn:IsShown() then frame.filterBtn:Show() end
    if frame.cogBtn and not frame.cogBtn:IsShown() then frame.cogBtn:Show() end
    if frame.collapseAllBtn and not frame.collapseAllBtn:IsShown() then frame.collapseAllBtn:Show() end
    if zoneText and not zoneText:IsShown() then zoneText:Show() end
    if frame.resizer and not frame.resizer:IsShown() then frame.resizer:Show() end

    frame:SetWidth(addon.Core.getDB().width or 280)

end


-- RENDER -----------------------------------------------------------------------

local function populateEntry(item)

    local entry = addon.UI.TrackerEntry.acquire()
    entry.item = item
    entry.title:SetText(item.title)
    entry.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

    if entry.SetComplete then entry:SetComplete(item.isComplete) end
    if entry.SetProgress then entry:SetProgress(item.progress, item.hasProgress, item.isComplete) end

    if item.kind == "quest" then
        if entry.trackCheck then
            entry.trackCheck:Show()
            entry.trackCheck:SetChecked(item.isSuperTracked and true or false)
        end
        if entry.superBg then entry.superBg:SetShown(item.isSuperTracked and true or false) end
    else
        if entry.trackCheck then entry.trackCheck:Hide() end
        if entry.superBg then entry.superBg:Hide() end
    end

    return entry

end

local function releaseAllRowsAndSections()

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        addon.UI.TrackerEntry.release(entry)
    end
    wipe(addon.UI.TrackerEntry.active)

    addon.UI.TrackerSection.releaseAll()

end


-- POST-LAYOUT PASSES -----------------------------------------------------------

local function applyExpansionState(layout)

    local expandedKeys = addon.Core.getDB().expandedKeys or {}
    if not next(expandedKeys) then return end

    -- First layout pass so ObjectivePanel.expand has resolved frame positions
    -- to measure from before it computes objective wraps and final row heights.
    relayoutLayout(layout)

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        if entry.item and expandedKeys[entry.item.key] then
            addon.UI.ObjectivePanel.expand(entry)
        end
    end

end

local function applyPendingScroll()

    if not pendingScrollKey then return end

    if pendingScrollExpiresAt and GetTime() > pendingScrollExpiresAt then
        pendingScrollKey, pendingScrollExpiresAt = nil, nil
        return
    end

    local target

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        if entry.item and entry.item.key == pendingScrollKey then
            target = entry
            break
        end
    end

    if not target then
        for _, header in ipairs(addon.UI.TrackerSection.active) do
            if header.key == pendingScrollKey then
                target = header
                break
            end
        end
    end

    if target then scrollIntoView(target) end

end

local function applyPendingFlashes()

    if not next(pendingFlashKeys) then return end

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        if entry.item and pendingFlashKeys[entry.item.key] and entry.FlashAttention then
            entry:FlashAttention()
        end
    end

    -- Items hidden by the zone filter never matched an entry above and are
    -- intentionally dropped here. Anything pending now is stale.
    pendingFlashKeys = {}

end


-- MAIN PIPELINE ----------------------------------------------------------------

local function refreshUI()

    if not frame then return end
    if not addon.Core.getDB().enabled then frame:Hide(); return end
    if addon.UI.SettingsWindow.isShown() then return end

    frame:Show()

    local mapID = addon.Util.getPlayerZoneMapID()
    local mapName = addon.Util.getMapName(mapID) or "Unknown"

    local items = collectVisibleItems()
    titleText:SetText(("Quests (%d)"):format(countQuests(items)))

    if addon.Core.getDB().collapsed then
        releaseAllRowsAndSections()
        applyCollapsedChrome()
        return
    end

    detectAndShowNewlyTracked(collectAllTrackedKeys())
    uncollapseSectionsForFlashKeys(items)

    applyExpandedChrome()
    zoneText:SetText(mapName)

    releaseAllRowsAndSections()

    local bySection = groupBySection(items)
    local layout = {}

    for _, sectionName in ipairs(SECTION_ORDER) do
        local sectionItems = bySection[sectionName]
        if sectionItems and #sectionItems > 0 then
            addon.UI.TrackerSection.render({
                section       = sectionName,
                title         = sectionName,
                items         = sectionItems,
                layout        = layout,
                populateEntry = populateEntry,
            })
        end
    end

    applyExpansionState(layout)
    relayoutLayout(layout)
    applyPendingScroll()
    applyPendingFlashes()

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function BooshiesTracker.init(opts)

    window      = opts.window
    frame       = window.frame
    titleText   = window.titleText
    zoneText    = window.zoneText
    content     = window.content
    scrollFrame = window.scrollFrame

end

function BooshiesTracker.refresh()
    addon.Util.safeCall("Refresh", refreshUI)
end

function BooshiesTracker.handleEntryClick(entry)

    local item = entry.item
    if not item then return end

    addon.Core.getDB().expandedKeys = addon.Core.getDB().expandedKeys or {}
    if addon.Core.getDB().expandedKeys[item.key] then
        addon.Core.getDB().expandedKeys[item.key] = nil
    else
        addon.Core.getDB().expandedKeys[item.key] = true
    end

    pendingScrollKey = item.key
    pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW

    BooshiesTracker.refresh()

end

function BooshiesTracker.handleSectionClick(header)

    local sectionName = header.section
    if not sectionName then return end

    addon.Core.getDB().collapsedSections = addon.Core.getDB().collapsedSections or {}
    addon.Core.getDB().collapsedSections[sectionName] = not addon.Core.getDB().collapsedSections[sectionName]

    pendingScrollKey = header.key
    pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW

    BooshiesTracker.refresh()

end

function BooshiesTracker.toggleCollapsedTitlebar()

    addon.Core.getDB().collapsed = not addon.Core.getDB().collapsed
    BooshiesTracker.refresh()

end

function BooshiesTracker.collapseAll()

    addon.Core.getDB().expandedKeys = {}
    addon.Core.getDB().collapsedSections = addon.Core.getDB().collapsedSections or {}

    for _, sectionName in ipairs(SECTION_ORDER) do
        addon.Core.getDB().collapsedSections[sectionName] = true
    end

    BooshiesTracker.refresh()

end

function BooshiesTracker.updateSuperTrack()

    local current = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        local item = entry.item
        local isSuper = item and item.kind == "quest" and item.id == current and current ~= 0
        if entry.trackCheck then entry.trackCheck:SetChecked(isSuper and true or false) end
        if entry.superBg then entry.superBg:SetShown(isSuper and true or false) end
        if item and item.kind == "quest" then
            item.isSuperTracked = isSuper and true or false
        end
    end

end

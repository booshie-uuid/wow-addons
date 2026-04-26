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

local CLASSIFICATION_NAMES = {
    [0]  = "Important",
    [1]  = "Legendary",
    [2]  = "Campaign",
    [3]  = "Calling",
    [4]  = "Special",
    [5]  = "Recurring",
    [6]  = "Questline",
    [7]  = "Normal",
    [8]  = "Bonus",
    [9]  = "Threat",
    [10] = "World Quests",
}

local CLASSIFICATION_ORDER = { 2, 0, 4, 5, 1, 6, 9, 7, 3, 10, 8 }

local NON_QUEST_SECTION_KEYS = { "achievements", "recipes", "activities", "initiatives" }


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


-- BUILD QUEST GROUPS -----------------------------------------------------------

local function buildQuestGroups(mapID, mapName)

    local snapshot = addon.Data.Quests.snapshot()
    addon.Data.Quests.addTaskQuests(snapshot, mapID)
    local poiSet = addon.Data.Quests.buildPOISet(mapID)

    local groups = {}
    local total = 0

    for qid, info in pairs(snapshot) do
        if addon.Data.Quests.shouldShow(qid, snapshot, poiSet, mapID, mapName) then
            local cls = addon.Data.Quests.getClassification(qid)
            groups[cls] = groups[cls] or {}
            table.insert(groups[cls], {
                questID = qid,
                title = info.title or ("Quest " .. qid),
                isComplete = info.isComplete,
                classification = cls,
            })
            total = total + 1
        end
    end

    return groups, total, snapshot

end

local function collectTrackedKeys(snapshot)

    local set = {}

    for qid in pairs(snapshot) do
        if addon.Data.Quests.isWatched(qid) then
            set["quest:" .. qid] = true
        end
    end

    for _, id in ipairs(addon.Data.Achievements.getTracked())             do set["ach:"        .. id] = true end
    for _, id in ipairs(addon.Data.Recipes.getTracked())                  do set["recipe:"     .. id] = true end
    for _, id in ipairs(addon.Data.JournalActivities.getTracked())        do set["activity:"   .. id] = true end
    for _, id in ipairs(addon.Data.NeighbourhoodActivities.getTracked())  do set["initiative:" .. id] = true end

    return set

end

local function detectAndShowNewlyTracked(currentKeys)

    if not previousTrackedKeys then
        -- First refresh after load. Capture the baseline silently so we do
        -- not fire for every already-tracked item.
        previousTrackedKeys = currentKeys
        return
    end

    addon.Core.getDB().expandedKeys      = addon.Core.getDB().expandedKeys      or {}
    addon.Core.getDB().collapsedSections = addon.Core.getDB().collapsedSections or {}

    local lastNewKey
    for key in pairs(currentKeys) do
        if not previousTrackedKeys[key] then
            -- Mark expanded even if the zone filter is currently hiding this
            -- item, so it appears expanded next time it becomes visible.
            addon.Core.getDB().expandedKeys[key] = true

            local section = addon.UI.TrackerEntry.sectionFor(key)
            if section ~= nil then
                addon.Core.getDB().collapsedSections[section] = nil
            end

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

local function sortQuestGroups(groups)

    for _, list in pairs(groups) do
        table.sort(list, function(a, b) return (a.title or "") < (b.title or "") end)
    end

end

local function releaseAllRowsAndSections()

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        addon.UI.TrackerEntry.release(entry)
    end
    wipe(addon.UI.TrackerEntry.active)

    addon.UI.TrackerSection.releaseAll()

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


-- SECTION RENDERERS ------------------------------------------------------------

local function renderQuestSections(layout, groups, superTracked)

    for _, cls in ipairs(CLASSIFICATION_ORDER) do
        addon.UI.TrackerSection.render({
            classification = cls,
            title          = CLASSIFICATION_NAMES[cls] or ("Class " .. cls),
            items          = groups[cls],
            layout         = layout,
            populateEntry  = function(q)

                local entry = addon.UI.TrackerEntry.acquire()
                entry.itemKind = "quest"
                entry.questID  = q.questID
                entry.title:SetText(q.title)
                entry.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

                if entry.SetComplete then entry:SetComplete(q.isComplete) end

                local isSuper = superTracked == q.questID and superTracked ~= 0
                if entry.trackCheck then
                    entry.trackCheck:Show()
                    entry.trackCheck:SetChecked(isSuper)
                end
                if entry.superBg then entry.superBg:SetShown(isSuper) end

                local pct, hasObj = addon.Data.Quests.getProgress(q.questID)
                if entry.SetProgress then entry:SetProgress(pct, hasObj, q.isComplete) end

                return entry

            end,
        })
    end

end

local function renderAchievementSection(layout)

    local hideAchievements = addon.Core.getDB().filterByZone and not addon.Core.getDB().alwaysShowAchievements

    addon.UI.TrackerSection.render({
        classification = "achievements",
        title          = "Achievements",
        items          = hideAchievements and {} or addon.Data.Achievements.getTracked(),
        layout         = layout,
        populateEntry  = function(achID)

            local id, name, _, completed
            if GetAchievementInfo then
                id, name, _, completed = GetAchievementInfo(achID)
            end
            if not id then return nil end

            local entry = addon.UI.TrackerEntry.acquire()
            entry.itemKind      = "achievement"
            entry.achievementID = achID
            entry.title:SetText(name or ("Achievement " .. achID))
            entry.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if entry.SetComplete then entry:SetComplete(completed) end
            if entry.trackCheck then entry.trackCheck:Hide() end

            local pct, hasAny = addon.Data.Achievements.getProgress(achID)
            if entry.SetProgress then entry:SetProgress(pct, hasAny, completed) end

            return entry

        end,
    })

end

local function renderRecipeSection(layout)

    addon.UI.TrackerSection.render({
        classification = "recipes",
        title          = "Crafting",
        items          = addon.Core.getDB().filterByZone and {} or addon.Data.Recipes.getTracked(),
        layout         = layout,
        populateEntry  = function(recipeID)

            local entry = addon.UI.TrackerEntry.acquire()
            entry.itemKind = "recipe"
            entry.recipeID = recipeID
            entry.title:SetText(addon.Data.Recipes.getName(recipeID))
            entry.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if entry.SetComplete then entry:SetComplete(false) end
            if entry.trackCheck then entry.trackCheck:Hide() end

            local pct, hasAny = addon.Data.Recipes.getProgress(recipeID)
            if entry.SetProgress then entry:SetProgress(pct, hasAny, false) end

            return entry

        end,
    })

end

local function renderActivitySection(layout)

    addon.UI.TrackerSection.render({
        classification = "activities",
        title          = "Monthly",
        items          = addon.Core.getDB().filterByZone and {} or addon.Data.JournalActivities.getTracked(),
        layout         = layout,
        populateEntry  = function(actID)

            local info = addon.Data.JournalActivities.getInfo(actID)
            if not info then return nil end

            local entry = addon.UI.TrackerEntry.acquire()
            entry.itemKind   = "activity"
            entry.activityID = actID
            entry.title:SetText(info.activityName or info.name or ("Activity " .. actID))
            entry.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if entry.SetComplete then entry:SetComplete(info.completed) end
            if entry.trackCheck then entry.trackCheck:Hide() end

            local pct, hasAny = addon.Data.JournalActivities.getProgress(actID)
            if entry.SetProgress then entry:SetProgress(pct, hasAny, info.completed) end

            return entry

        end,
    })

end

local function renderInitiativeSection(layout)

    addon.UI.TrackerSection.render({
        classification = "initiatives",
        title          = "Endeavours",
        items          = addon.Core.getDB().filterByZone and {} or addon.Data.NeighbourhoodActivities.getTracked(),
        layout         = layout,
        populateEntry  = function(taskID)

            local info = addon.Data.NeighbourhoodActivities.getInfo(taskID)

            local entry = addon.UI.TrackerEntry.acquire()
            entry.itemKind     = "initiative"
            entry.initiativeID = taskID
            entry.title:SetText(addon.Data.NeighbourhoodActivities.getName(taskID))
            entry.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if entry.SetComplete then entry:SetComplete(info and info.completed) end
            if entry.trackCheck then entry.trackCheck:Hide() end

            local pct, hasAny = addon.Data.NeighbourhoodActivities.getProgress(taskID)
            if entry.SetProgress then entry:SetProgress(pct, hasAny, info and info.completed) end

            return entry

        end,
    })

end


-- POST-LAYOUT PASSES -----------------------------------------------------------

local function applyExpansionState(layout)

    local expandedKeys = addon.Core.getDB().expandedKeys or {}
    if not next(expandedKeys) then return end

    -- First layout pass so ObjectivePanel.expand has resolved frame positions
    -- to measure from before it computes objective wraps and final row heights.
    relayoutLayout(layout)

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        if expandedKeys[addon.UI.TrackerEntry.keyFor(entry)] then
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
        if addon.UI.TrackerEntry.keyFor(entry) == pendingScrollKey then
            target = entry
            break
        end
    end

    if not target then
        for _, header in ipairs(addon.UI.TrackerSection.active) do
            if addon.UI.TrackerEntry.keyFor(header) == pendingScrollKey then
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
        local key = addon.UI.TrackerEntry.keyFor(entry)
        if key and pendingFlashKeys[key] and entry.FlashAttention then
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

    local groups, total, snapshot = buildQuestGroups(mapID, mapName)
    titleText:SetText(("Quests (%d)"):format(total))

    if addon.Core.getDB().collapsed then
        releaseAllRowsAndSections()
        applyCollapsedChrome()
        return
    end

    detectAndShowNewlyTracked(collectTrackedKeys(snapshot))

    applyExpandedChrome()
    zoneText:SetText(mapName)

    sortQuestGroups(groups)
    releaseAllRowsAndSections()

    local layout = {}
    local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    renderQuestSections(layout, groups, superTracked)
    renderAchievementSection(layout)
    renderRecipeSection(layout)
    renderActivitySection(layout)
    renderInitiativeSection(layout)

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

    local key = addon.UI.TrackerEntry.keyFor(entry)
    if not key then return end

    addon.Core.getDB().expandedKeys = addon.Core.getDB().expandedKeys or {}
    if addon.Core.getDB().expandedKeys[key] then
        addon.Core.getDB().expandedKeys[key] = nil
    else
        addon.Core.getDB().expandedKeys[key] = true
    end

    pendingScrollKey = key
    pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW

    BooshiesTracker.refresh()

end

function BooshiesTracker.handleSectionClick(header)

    addon.Core.getDB().collapsedSections = addon.Core.getDB().collapsedSections or {}
    addon.Core.getDB().collapsedSections[header.classification] =
        not addon.Core.getDB().collapsedSections[header.classification]

    pendingScrollKey = addon.UI.TrackerEntry.keyFor(header)
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

    for _, cls in ipairs(CLASSIFICATION_ORDER) do
        addon.Core.getDB().collapsedSections[cls] = true
    end

    for _, k in ipairs(NON_QUEST_SECTION_KEYS) do
        addon.Core.getDB().collapsedSections[k] = true
    end

    BooshiesTracker.refresh()

end

function BooshiesTracker.updateSuperTrack()

    local current = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    for _, entry in ipairs(addon.UI.TrackerEntry.active) do
        local isSuper = entry.questID and entry.questID == current and current ~= 0
        if entry.trackCheck then entry.trackCheck:SetChecked(isSuper) end
        if entry.superBg then entry.superBg:SetShown(isSuper and true or false) end
    end

end

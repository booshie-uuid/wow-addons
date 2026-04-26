local addonName, addon = ...


--------------------------------------------------------------------------------
-- LOOKUPS
--------------------------------------------------------------------------------

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


--------------------------------------------------------------------------------
-- UI CONSTANTS & STATE
--------------------------------------------------------------------------------

-- Row Layout (shared with UI.TrackerEntry which owns the row geometry).
local ROW_HEIGHT = addon.UI.TrackerEntry.ROW_HEIGHT
local ROW_GAP    = addon.UI.TrackerEntry.ROW_GAP

-- TrackerWindow instance plus convenience aliases for its child frames.
-- Assigned in BuildUI; the rest of the file reads them as if they were locals.
local window
local frame, titleText, zoneText, content, scrollFrame

-- Forward declaration - earlier-defined functions close over Refresh and
-- resolve it at call time, so the actual value can be assigned later.
local Refresh

-- Scroll Pin
-- After an entry click, debounced WoW events (QUEST_LOG_UPDATE, BAG_UPDATE_DELAYED,
-- etc.) often trigger another Refresh ~50ms later, and the second layout pass
-- can shift content slightly (lazy text measurement, scrollbar appear/disappear).
-- We pin the click target by key for a short window and re-apply ScrollIntoView
-- at the end of each refresh within that window.
local pendingScrollKey, pendingScrollExpiresAt
local SCROLL_PIN_WINDOW = 0.3

-- Newly-Tracked Detection
local previousTrackedKeys
local pendingFlashKeys = {}


--------------------------------------------------------------------------------
-- LAYOUT & SCROLL
--------------------------------------------------------------------------------

local function RelayoutLayout(layout)

    layout = layout or {}

    local y = 0
    local count = #layout
    local trailingGap = 0

    for i, item in ipairs(layout) do
        local isSection = item.itemKind == "section"

        if not isSection and not item.expanded then item:SetHeight(ROW_HEIGHT) end

        if item.separator then
            if item.itemKind == "section" then
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
local function ScrollIntoView(child, padding)

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


--------------------------------------------------------------------------------
-- ENTRY CLICK
--------------------------------------------------------------------------------

local function onEntryClick(entry)

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

    Refresh()

end


--------------------------------------------------------------------------------
-- SECTION CLICK
--------------------------------------------------------------------------------

local function onSectionClick(header)

    addon.Core.getDB().collapsedSections = addon.Core.getDB().collapsedSections or {}
    addon.Core.getDB().collapsedSections[header.classification] =
        not addon.Core.getDB().collapsedSections[header.classification]

    pendingScrollKey = addon.UI.TrackerEntry.keyFor(header)
    pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW

    Refresh()

end


--------------------------------------------------------------------------------
-- REFRESH PIPELINE
--------------------------------------------------------------------------------

local function BuildQuestGroups(mapID, mapName)

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

local function CollectTrackedKeys(snapshot)

    local set = {}

    for qid in pairs(snapshot) do
        if addon.Data.Quests.isWatched(qid) then
            set["quest:" .. qid] = true
        end
    end

    for _, id in ipairs(addon.Data.Achievements.getTracked())   do set["ach:"        .. id] = true end
    for _, id in ipairs(addon.Data.Recipes.getTracked())        do set["recipe:"     .. id] = true end
    for _, id in ipairs(addon.Data.JournalActivities.getTracked()) do set["activity:"   .. id] = true end
    for _, id in ipairs(addon.Data.NeighbourhoodActivities.getTracked())   do set["initiative:" .. id] = true end

    return set

end

local function DetectAndShowNewlyTracked(currentKeys)

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

    -- Hidden-by-filter items have no matching row in addon.UI.TrackerEntry.active, so
    -- ApplyPendingScroll naturally no-ops for them.
    if lastNewKey then
        pendingScrollKey = lastNewKey
        pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW
    end

    previousTrackedKeys = currentKeys

end

local function SortQuestGroups(groups)

    for _, list in pairs(groups) do
        table.sort(list, function(a, b) return (a.title or "") < (b.title or "") end)
    end

end

local function ReleaseAllRowsAndSections()

    for _, row in ipairs(addon.UI.TrackerEntry.active) do addon.UI.TrackerEntry.release(row) end
    wipe(addon.UI.TrackerEntry.active)

    addon.UI.TrackerSection.releaseAll()

end

local function ApplyCollapsedChrome()

    if scrollFrame then scrollFrame:Hide() end
    if frame.filterBtn then frame.filterBtn:Hide() end
    if frame.cogBtn then frame.cogBtn:Hide() end
    if frame.collapseAllBtn then frame.collapseAllBtn:Hide() end
    if zoneText then zoneText:Hide() end
    if frame.resizer then frame.resizer:Hide() end

    local titleW = (titleText:GetStringWidth() or 80) + 20
    frame:SetSize(math.max(titleW, 100), 30)

end

local function ApplyExpandedChrome()

    if scrollFrame and not scrollFrame:IsShown() then scrollFrame:Show() end
    if frame.filterBtn and not frame.filterBtn:IsShown() then frame.filterBtn:Show() end
    if frame.cogBtn and not frame.cogBtn:IsShown() then frame.cogBtn:Show() end
    if frame.collapseAllBtn and not frame.collapseAllBtn:IsShown() then frame.collapseAllBtn:Show() end
    if zoneText and not zoneText:IsShown() then zoneText:Show() end
    if frame.resizer and not frame.resizer:IsShown() then frame.resizer:Show() end

    frame:SetWidth(addon.Core.getDB().width or 280)

end

local function RenderQuestSections(layout, groups, superTracked)

    for _, cls in ipairs(CLASSIFICATION_ORDER) do
        addon.UI.TrackerSection.render({
            classification = cls,
            title          = CLASSIFICATION_NAMES[cls] or ("Class " .. cls),
            items          = groups[cls],
            layout         = layout,
            populateEntry    = function(q)

                local row = addon.UI.TrackerEntry.acquire()
                row.itemKind = "quest"
                row.questID = q.questID
                row.title:SetText(q.title)
                row.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

                if row.SetComplete then row:SetComplete(q.isComplete) end

                local isSuper = superTracked == q.questID and superTracked ~= 0
                if row.trackCheck then
                    row.trackCheck:Show()
                    row.trackCheck:SetChecked(isSuper)
                end
                if row.superBg then row.superBg:SetShown(isSuper) end

                local pct, hasObj = addon.Data.Quests.getProgress(q.questID)
                if row.SetProgress then row:SetProgress(pct, hasObj, q.isComplete) end

                return row

            end,
        })
    end

end

local function RenderAchievementSection(layout)

    local hideAchievements = addon.Core.getDB().filterByZone and not addon.Core.getDB().alwaysShowAchievements

    addon.UI.TrackerSection.render({
        classification = "achievements",
        title          = "Achievements",
        items          = hideAchievements and {} or addon.Data.Achievements.getTracked(),
        layout         = layout,
        populateEntry    = function(achID)

            local id, name, _, completed
            if GetAchievementInfo then
                id, name, _, completed = GetAchievementInfo(achID)
            end
            if not id then return nil end

            local row = addon.UI.TrackerEntry.acquire()
            row.itemKind = "achievement"
            row.achievementID = achID
            row.title:SetText(name or ("Achievement " .. achID))
            row.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if row.SetComplete then row:SetComplete(completed) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = addon.Data.Achievements.getProgress(achID)
            if row.SetProgress then row:SetProgress(pct, hasAny, completed) end

            return row

        end,
    })

end

local function RenderRecipeSection(layout)

    addon.UI.TrackerSection.render({
        classification = "recipes",
        title          = "Crafting",
        items          = addon.Core.getDB().filterByZone and {} or addon.Data.Recipes.getTracked(),
        layout         = layout,
        populateEntry    = function(recipeID)

            local row = addon.UI.TrackerEntry.acquire()
            row.itemKind = "recipe"
            row.recipeID = recipeID
            row.title:SetText(addon.Data.Recipes.getName(recipeID))
            row.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if row.SetComplete then row:SetComplete(false) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = addon.Data.Recipes.getProgress(recipeID)
            if row.SetProgress then row:SetProgress(pct, hasAny, false) end

            return row

        end,
    })

end

local function RenderActivitySection(layout)

    addon.UI.TrackerSection.render({
        classification = "activities",
        title          = "Monthly",
        items          = addon.Core.getDB().filterByZone and {} or addon.Data.JournalActivities.getTracked(),
        layout         = layout,
        populateEntry    = function(actID)

            local info = addon.Data.JournalActivities.getInfo(actID)
            if not info then return nil end

            local row = addon.UI.TrackerEntry.acquire()
            row.itemKind = "activity"
            row.activityID = actID
            row.title:SetText(info.activityName or info.name or ("Activity " .. actID))
            row.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if row.SetComplete then row:SetComplete(info.completed) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = addon.Data.JournalActivities.getProgress(actID)
            if row.SetProgress then row:SetProgress(pct, hasAny, info.completed) end

            return row

        end,
    })

end

local function RenderInitiativeSection(layout)

    addon.UI.TrackerSection.render({
        classification = "initiatives",
        title          = "Endeavours",
        items          = addon.Core.getDB().filterByZone and {} or addon.Data.NeighbourhoodActivities.getTracked(),
        layout         = layout,
        populateEntry    = function(taskID)

            local info = addon.Data.NeighbourhoodActivities.getInfo(taskID)

            local row = addon.UI.TrackerEntry.acquire()
            row.itemKind = "initiative"
            row.initiativeID = taskID
            row.title:SetText(addon.Data.NeighbourhoodActivities.getName(taskID))
            row.title:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))

            if row.SetComplete then row:SetComplete(info and info.completed) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = addon.Data.NeighbourhoodActivities.getProgress(taskID)
            if row.SetProgress then row:SetProgress(pct, hasAny, info and info.completed) end

            return row

        end,
    })

end

local function ApplyExpansionState(layout)

    local expandedKeys = addon.Core.getDB().expandedKeys or {}
    if not next(expandedKeys) then return end

    -- First layout pass so ObjectivePanel.expand has resolved frame positions to measure from
    -- before it computes objective wraps and final row heights.
    RelayoutLayout(layout)

    for _, row in ipairs(addon.UI.TrackerEntry.active) do
        if expandedKeys[addon.UI.TrackerEntry.keyFor(row)] then
            addon.UI.ObjectivePanel.expand(row)
        end
    end

end

local function ApplyPendingScroll()

    if not pendingScrollKey then return end

    if pendingScrollExpiresAt and GetTime() > pendingScrollExpiresAt then
        pendingScrollKey, pendingScrollExpiresAt = nil, nil
        return
    end

    local target
    for _, r in ipairs(addon.UI.TrackerEntry.active) do
        if addon.UI.TrackerEntry.keyFor(r) == pendingScrollKey then
            target = r
            break
        end
    end
    if not target then
        for _, h in ipairs(addon.UI.TrackerSection.active) do
            if addon.UI.TrackerEntry.keyFor(h) == pendingScrollKey then
                target = h
                break
            end
        end
    end

    if target then ScrollIntoView(target) end

end

local function ApplyPendingFlashes()

    if not next(pendingFlashKeys) then return end

    for _, row in ipairs(addon.UI.TrackerEntry.active) do
        local key = addon.UI.TrackerEntry.keyFor(row)
        if key and pendingFlashKeys[key] and row.FlashAttention then
            row:FlashAttention()
        end
    end

    -- Items hidden by the zone filter never matched a row above and are
    -- intentionally dropped here. Anything pending now is stale.
    pendingFlashKeys = {}

end

local function RefreshUI()

    if not frame then return end
    if not addon.Core.getDB().enabled then frame:Hide(); return end
    if addon.UI.SettingsWindow.isShown() then return end

    frame:Show()

    local mapID = addon.Util.getPlayerZoneMapID()
    local mapName = addon.Util.getMapName(mapID) or "Unknown"

    local groups, total, snapshot = BuildQuestGroups(mapID, mapName)
    titleText:SetText(("Quests (%d)"):format(total))

    if addon.Core.getDB().collapsed then
        ReleaseAllRowsAndSections()
        ApplyCollapsedChrome()
        return
    end

    DetectAndShowNewlyTracked(CollectTrackedKeys(snapshot))

    ApplyExpandedChrome()
    zoneText:SetText(mapName)

    SortQuestGroups(groups)
    ReleaseAllRowsAndSections()

    local layout = {}
    local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    RenderQuestSections(layout, groups, superTracked)
    RenderAchievementSection(layout)
    RenderRecipeSection(layout)
    RenderActivitySection(layout)
    RenderInitiativeSection(layout)

    ApplyExpansionState(layout)
    RelayoutLayout(layout)
    ApplyPendingScroll()
    ApplyPendingFlashes()

end

Refresh = function() addon.Util.safeCall("Refresh", RefreshUI) end


--------------------------------------------------------------------------------
-- MAIN UI CONSTRUCTION
--------------------------------------------------------------------------------

local function BuildUI()

    if frame then return end

    window = addon.UI.TrackerWindow.new({
        name            = "BooshiesQuestLogFrame",
        title           = "Quests",
        width           = addon.Core.getDB().width,
        loadPosition    = function() return addon.Core.getDB().point end,
        savePosition    = function(p) addon.Core.getDB().point = p end,
        defaultPosition = addon.Core.getDefaults().point,
        isLocked        = function() return addon.Core.getDB().lockPosition end,
        getMaxHeight    = function() return addon.Core.getDB().maxHeight end,
        isZoneFilterChecked = function() return addon.Core.getDB().filterByZone end,

        onTitleClick = function()
            addon.Core.getDB().collapsed = not addon.Core.getDB().collapsed
            Refresh()
        end,

        onSettings = function() addon.UI.SettingsWindow.show() end,

        onZoneFilterChange = function(checked)
            addon.Core.getDB().filterByZone = checked
            Refresh()
        end,

        onCollapseAll = function()
            addon.Core.getDB().expandedKeys = {}
            addon.Core.getDB().collapsedSections = addon.Core.getDB().collapsedSections or {}
            for _, cls in ipairs(CLASSIFICATION_ORDER) do
                addon.Core.getDB().collapsedSections[cls] = true
            end
            for _, k in ipairs({ "achievements", "recipes", "activities", "initiatives" }) do
                addon.Core.getDB().collapsedSections[k] = true
            end
            Refresh()
        end,

        onResize = function(newMax)
            addon.Core.getDB().maxHeight = newMax
            Refresh()
        end,
    })

    frame       = window.frame
    titleText   = window.titleText
    zoneText    = window.zoneText
    content     = window.content
    scrollFrame = window.scrollFrame

    addon.UI.TrackerEntry.init({
        content   = content,
        onClick   = onEntryClick,
        onRelease = addon.UI.ObjectivePanel.collapse,
    })

    addon.UI.TrackerSection.init({
        content = content,
        onClick = onSectionClick,
    })

    addon.UI.SettingsWindow.init({
        getTrackerFrame = function() return frame end,
        onApply         = function() Refresh() end,
    })

end


--------------------------------------------------------------------------------
-- SUPER-TRACK STATE
--------------------------------------------------------------------------------

local function UpdateSuperTrackState()

    local current = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    for _, row in ipairs(addon.UI.TrackerEntry.active) do
        local isSuper = row.questID and row.questID == current and current ~= 0
        if row.trackCheck then row.trackCheck:SetChecked(isSuper) end
        if row.superBg then row.superBg:SetShown(isSuper and true or false) end
    end

end


--------------------------------------------------------------------------------
-- EVENTS
--------------------------------------------------------------------------------

local pending = false

local function Reschedule()

    if pending then return end
    pending = true

    C_Timer.After(0.05, function()
        pending = false
        addon.Util.safeCall("Reschedule", Refresh)
    end)

end

local REQUIRED_EVENTS = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED",
    "ZONE_CHANGED_INDOORS",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "UNIT_QUEST_LOG_CHANGED",
    "SUPER_TRACKING_CHANGED",
}

-- Events that may not exist on every client version. Registered via pcall so
-- a missing one does not break addon load on older clients.
local OPTIONAL_EVENTS = {
    "WORLD_QUEST_WATCH_LIST_CHANGED",
    "TRACKED_ACHIEVEMENT_UPDATE",
    "TRACKED_ACHIEVEMENT_LIST_CHANGED",
    "CONTENT_TRACKING_UPDATE",
    "CONTENT_TRACKING_LIST_UPDATE",
    "TRACKED_RECIPE_UPDATE",
    "TRADE_SKILL_LIST_UPDATE",
    "BAG_UPDATE_DELAYED",
    "PERKS_ACTIVITIES_UPDATED",
    "TRACKED_PERKS_ACTIVITY_LIST_CHANGED",
    "PERKS_ACTIVITIES_TRACKED_LIST_CHANGED",
    "PERKS_ACTIVITY_COMPLETED",
    "INITIATIVE_TASKS_TRACKED_LIST_CHANGED",
    "INITIATIVE_ACTIVITY_LOG_UPDATED",
}

local ev = CreateFrame("Frame")
for _, e in ipairs(REQUIRED_EVENTS) do ev:RegisterEvent(e) end
for _, e in ipairs(OPTIONAL_EVENTS) do pcall(ev.RegisterEvent, ev, e) end

ev:SetScript("OnEvent", function(self, event, arg1)
    addon.Util.safeCall("OnEvent:" .. tostring(event), function()

        if event == "ADDON_LOADED" then
            if arg1 == addonName then
                if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo then
                    pcall(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo)
                end
            end

        elseif event == "PLAYER_LOGIN" then
            BuildUI()
            addon.BlizzardTracker.applyState()
            Reschedule()

            if not addon.Core.getDB().helpShown then addon.UI.HelpWindow.show() end

        elseif event == "PLAYER_ENTERING_WORLD" then
            addon.BlizzardTracker.applyState()
            Reschedule()

        elseif event == "UNIT_QUEST_LOG_CHANGED" then
            if arg1 == "player" then Reschedule() end

        elseif event == "SUPER_TRACKING_CHANGED" then
            UpdateSuperTrackState()

        else
            Reschedule()
        end

    end)
end)


--------------------------------------------------------------------------------
-- SLASH COMMANDS
--------------------------------------------------------------------------------

local function PrintStatus(label, value)
    print(("|cff4fc3f7BQL:|r %s %s"):format(label, value and "|cff00ff00on|r" or "|cffff6666off|r"))
end

SLASH_BOOSHIESQUESTLOG1 = "/bql"
SLASH_BOOSHIESQUESTLOG2 = "/booshiesquestlog"
SlashCmdList["BOOSHIESQUESTLOG"] = function(msg)

    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "toggle" then
        addon.Core.getDB().enabled = not addon.Core.getDB().enabled
        PrintStatus("tracker", addon.Core.getDB().enabled)
        Refresh()
    elseif msg == "reset" then
        addon.Core.getDB().point = addon.Core.getDefaults().point
        addon.Core.getDB().maxHeight = addon.Core.getDefaults().maxHeight
        addon.Core.getDB().helpShown = false
        if window then window:restorePosition() end
        Refresh()
        addon.UI.HelpWindow.show()
        print("|cff4fc3f7BQL:|r position + height reset")
    elseif msg == "refresh" then
        Refresh()
    else
        print("|cff4fc3f7BQL:|r /bql [toggle||reset||refresh]")
    end

end

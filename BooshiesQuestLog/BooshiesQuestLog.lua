local addonName, addon = ...


--------------------------------------------------------------------------------
-- MAIN UI CONSTRUCTION
--------------------------------------------------------------------------------

local window

local function BuildUI()

    if window then return end

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

        onTitleClick  = addon.BooshiesTracker.toggleCollapsedTitlebar,
        onSettings    = function() addon.UI.SettingsWindow.show() end,
        onCollapseAll = addon.BooshiesTracker.collapseAll,

        onZoneFilterChange = function(checked)
            addon.Core.getDB().filterByZone = checked
            addon.BooshiesTracker.refresh()
        end,

        onResize = function(newMax)
            addon.Core.getDB().maxHeight = newMax
            addon.BooshiesTracker.refresh()
        end,
    })

    addon.BooshiesTracker.init({ window = window })

    addon.UI.TrackerEntry.init({
        content   = window.content,
        onClick   = addon.BooshiesTracker.handleEntryClick,
        onRelease = addon.UI.ObjectivePanel.collapse,
    })

    addon.UI.TrackerSection.init({
        content = window.content,
        onClick = addon.BooshiesTracker.handleSectionClick,
    })

    addon.UI.SettingsWindow.init({
        getTrackerFrame = function() return window.frame end,
        onApply         = addon.BooshiesTracker.refresh,
    })

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
        addon.Util.safeCall("Reschedule", addon.BooshiesTracker.refresh)
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
            addon.BooshiesTracker.updateSuperTrack()

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
        addon.BooshiesTracker.refresh()
    elseif msg == "reset" then
        addon.Core.getDB().point = addon.Core.getDefaults().point
        addon.Core.getDB().maxHeight = addon.Core.getDefaults().maxHeight
        addon.Core.getDB().helpShown = false
        if window then window:restorePosition() end
        addon.BooshiesTracker.refresh()
        addon.UI.HelpWindow.show()
        print("|cff4fc3f7BQL:|r position + height reset")
    elseif msg == "refresh" then
        addon.BooshiesTracker.refresh()
    else
        print("|cff4fc3f7BQL:|r /bql [toggle||reset||refresh]")
    end

end

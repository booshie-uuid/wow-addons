local addonName, addon = ...


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local REFRESH_DEBOUNCE = 0.05

local REQUIRED_EVENTS = {
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
    "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED",
}


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local pending = false


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- Coalesce bursts of WoW events into a single refresh on the next tick.
local function reschedule()

    if pending then return end
    pending = true

    C_Timer.After(REFRESH_DEBOUNCE, function()
        pending = false
        addon.Util.safeCall("Reschedule", addon.BooshiesTracker.refresh)
    end)

end

local function dispatch(event, arg1, arg2)

    if event == "PLAYER_LOGIN" then
        addon.BooshiesTracker.init()
        addon.BlizzardTracker.applyState()
        reschedule()

        if not addon.Core.getDB().helpShown then addon.UI.HelpWindow.show() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        addon.BlizzardTracker.applyState()
        reschedule()

    elseif event == "UNIT_QUEST_LOG_CHANGED" then
        if arg1 == "player" then reschedule() end

    elseif event == "SUPER_TRACKING_CHANGED" then
        -- Update the super-track UI on existing entries immediately for snappy
        -- feedback, then debounce a full refresh too. Untracking a world quest
        -- from the map only fires SUPER_TRACKING_CHANGED (no watch-list event),
        -- so this is also our cue to re-snapshot the watch list and let any
        -- WQ that Blizzard removed disappear from the tracker.
        addon.BooshiesTracker.updateSuperTrack()
        reschedule()

    elseif event == "PLAYER_INSIDE_QUEST_BLOB_STATE_CHANGED" then
        -- arg1 = questID, arg2 = isInside. Definitive proximity signal —
        -- when the player crosses into a quest's active area we want that
        -- quest to surface immediately, without waiting for the slower
        -- QUEST_DATA_LOAD_RESULT cascade to populate the local quest log.
        addon.Data.Quests.setInsideBlob(arg1, arg2)
        reschedule()

    else
        reschedule()
    end

end


--------------------------------------------------------------------------------
-- WIRING
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")

for _, e in ipairs(REQUIRED_EVENTS) do frame:RegisterEvent(e) end
for _, e in ipairs(OPTIONAL_EVENTS) do pcall(frame.RegisterEvent, frame, e) end

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    addon.Util.safeCall("OnEvent:" .. tostring(event), function()
        dispatch(event, arg1, arg2)
    end)
end)


--------------------------------------------------------------------------------
-- ADDON_LOADED
--------------------------------------------------------------------------------

-- A separate frame so the main dispatcher can stay single-purpose. The
-- neighborhood-initiative request is the only thing the addon needs to do
-- on ADDON_LOADED beyond what Core.lua already handles (defaults merge).
local addonLoaded = CreateFrame("Frame")
addonLoaded:RegisterEvent("ADDON_LOADED")
addonLoaded:SetScript("OnEvent", function(self, event, name)

    if name ~= addonName then return end

    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo then
        pcall(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo)
    end

    self:UnregisterEvent("ADDON_LOADED")

end)

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

local function dispatch(event, arg1)

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
        addon.BooshiesTracker.updateSuperTrack()

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

frame:SetScript("OnEvent", function(self, event, arg1)
    addon.Util.safeCall("OnEvent:" .. tostring(event), function()
        dispatch(event, arg1)
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

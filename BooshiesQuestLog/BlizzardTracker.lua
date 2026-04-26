local addonName, addon = ...

local BlizzardTracker = {}
addon.BlizzardTracker = BlizzardTracker


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local TRACKER_MODULES = {
    "QuestObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "AchievementObjectiveTracker",
    "ProfessionsRecipeTracker",
    "WorldQuestObjectiveTracker",
    "BonusObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
}


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local hookedModules = {}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function attachSquashHooks(m)

    if hookedModules[m] then return end
    hookedModules[m] = true

    local function squash(self)
        if self._bqlForceHidden then
            self:Hide()
            pcall(self.SetHeight, self, 0.01)
        end
    end

    if m.HookScript then
        m:HookScript("OnShow", squash)
        m:HookScript("OnSizeChanged", squash)
    end

end

local function relayoutTracker()

    if _G.ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then
        pcall(ObjectiveTrackerManager.UpdateAll, ObjectiveTrackerManager)
    elseif ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update then
        pcall(ObjectiveTrackerFrame.Update, ObjectiveTrackerFrame)
    end

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function BlizzardTracker.applyState()

    local shouldHide = addon.Core.getDB().hideBlizzardTracker and true or false

    for _, name in ipairs(TRACKER_MODULES) do
        local m = _G[name]
        if m then
            m._bqlForceHidden = shouldHide
            attachSquashHooks(m)
            if shouldHide then
                if m.Hide then pcall(m.Hide, m) end
                if m.SetHeight then pcall(m.SetHeight, m, 0.0) end
            else
                if m.Show then pcall(m.Show, m) end
            end
        end
    end

    relayoutTracker()

end

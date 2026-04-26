local addonName, addon = ...

addon.Data = addon.Data or {}

local Achievements = {}
addon.Data.Achievements = Achievements


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local SECTION = "Achievements"


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- Blizzard's `GetAchievementCriteriaInfo` returns an empty `cstr` for single-
-- step achievements (e.g. raid boss kills). The achievement-level `description`
-- is the human-readable label in those cases, with `name` as a last-resort
-- fallback.
local function getHeader(achID)

    if not GetAchievementInfo then return "", false end

    local _, name, _, completed, _, _, _, description = GetAchievementInfo(achID)
    local text = (description and description ~= "" and description) or name or ""

    return text, completed and true or false

end

local function getTrackedIDs()

    local list = {}

    if _G.GetTrackedAchievements then
        addon.Util.tryAppendIDs(list, nil, function() return { GetTrackedAchievements() } end)
    end

    if #list == 0 and C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        local t = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        if t ~= nil then
            addon.Util.tryAppendIDs(list, nil, C_ContentTracking.GetTrackedIDs, t)
        end
    end

    return list

end

local function getCriteria(achID)

    local list = {}
    if not _G.GetAchievementNumCriteria or not _G.GetAchievementCriteriaInfo then return list end

    local num = GetAchievementNumCriteria(achID) or 0
    local headerText

    for i = 1, num do
        local cstr, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achID, i)

        if not cstr or cstr == "" then
            headerText = headerText or getHeader(achID)
            cstr = headerText
        end

        list[i] = {
            text = cstr or "",
            finished = completed and true or false,
            numFulfilled = quantity or 0,
            numRequired = reqQuantity or 0,
        }
    end

    -- No criteria returned at all: synthesise one entry from the achievement
    -- header so single-step achievements still have something to display.
    if #list == 0 then
        local text, completed = getHeader(achID)
        if text ~= "" then
            list[1] = { text = text, finished = completed, numFulfilled = 0, numRequired = 0 }
        end
    end

    return list

end

local function getProgress(achID, criteria)

    -- Zero-criteria achievements report (1, true) when complete, (0, false)
    -- when not, so the progress bar stays hidden on incomplete single-step
    -- achievements.
    local rawNum = (_G.GetAchievementNumCriteria and GetAchievementNumCriteria(achID)) or 0

    if rawNum == 0 then
        local _, completed = getHeader(achID)
        return completed and 1 or 0, completed
    end

    return addon.Util.computeProgress(criteria)

end

local function untrackAchievement(id)

    local t = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
    local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Player) or 2

    if C_ContentTracking and C_ContentTracking.StopTracking and t then
        pcall(C_ContentTracking.StopTracking, t, id, stopType)
    end

    if _G.RemoveTrackedAchievement then
        pcall(_G.RemoveTrackedAchievement, id)
    end

end

local function buildItem(achID)

    local _, name, _, completed = GetAchievementInfo and GetAchievementInfo(achID)
    if not name then return nil end

    local objectives = getCriteria(achID)
    local progress, hasProgress = getProgress(achID, objectives)

    return {
        kind        = "achievement",
        id          = achID,
        key         = "ach:" .. achID,
        title       = name,
        section     = SECTION,
        isComplete  = completed and true or false,
        progress    = progress,
        hasProgress = hasProgress,
        objectives  = objectives,

        openDetails = function() addon.BlizzardInterface.openAchievement(achID) end,
        untrack     = function() untrackAchievement(achID) end,
        dump        = function() addon.Debug.dumpAchievement(achID) end,
    }

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Achievements.collectAll()

    local items = {}

    for _, achID in ipairs(getTrackedIDs()) do
        local item = buildItem(achID)
        if item then table.insert(items, item) end
    end

    return items

end

function Achievements.collect()

    local db = addon.Core.getDB()
    if db.filterByZone and not db.alwaysShowAchievements then return {} end

    return Achievements.collectAll()

end

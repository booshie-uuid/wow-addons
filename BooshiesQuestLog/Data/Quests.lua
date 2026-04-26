local addonName, addon = ...

addon.Data = addon.Data or {}

local Quests = {}
addon.Data.Quests = Quests


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

-- Quest classification → display name. The display name doubles as the
-- TrackedItem.section value, the bySection grouping key, and the
-- collapsedSections DB key.
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

-- Render order for the quest section names. Other Data modules contribute
-- their own section names to the master SECTION_ORDER in BooshiesTracker.
Quests.SECTION_ORDER = {
    "Campaign",
    "Important",
    "Special",
    "Recurring",
    "Legendary",
    "Questline",
    "Threat",
    "Normal",
    "Calling",
    "World Quests",
    "Bonus",
}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function addTaskEntry(snapshot, qid, source)

    if not qid or snapshot[qid] then return end

    local title = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)) or ("Quest " .. qid)

    snapshot[qid] = {
        title = title,
        isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid) or false,
        isTask = true,
        [source] = true,
    }

end

local function isCampaign(info)
    return info and info.campaignID and info.campaignID > 0
end

local function buildSnapshot(mapID)

    local snapshot, headerName = {}, nil
    local count = C_QuestLog.GetNumQuestLogEntries() or 0

    for i = 1, count do
        local info = C_QuestLog.GetInfo(i)

        if info then
            if info.isHeader then
                headerName = info.title
            elseif info.questID and (info.isTask or not info.isHidden) then
                snapshot[info.questID] = {
                    campaignID = info.campaignID,
                    header = headerName,
                    title = info.title,
                    questLogIndex = i,
                    level = info.level,
                    isComplete = C_QuestLog.IsComplete(info.questID),
                    isTask = info.isTask,
                }
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        local ok, n = pcall(C_QuestLog.GetNumWorldQuestWatches)

        if ok and type(n) == "number" then
            for i = 1, n do
                local ok2, qid = pcall(C_QuestLog.GetQuestIDForWorldQuestWatchIndex, i)
                if ok2 then addTaskEntry(snapshot, qid, "fromWorldWatch") end
            end
        end
    end

    if mapID then
        if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
            local ok, list = pcall(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)

            if ok and type(list) == "table" then
                for _, t in ipairs(list) do
                    addTaskEntry(snapshot, t.questId or t.questID, "fromTaskAPI")
                end
            end
        end

        if C_QuestLog and C_QuestLog.GetQuestsOnMap then
            local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)

            if ok and type(list) == "table" then
                for _, t in ipairs(list) do
                    addTaskEntry(snapshot, t.questID, "fromPOI")
                end
            end
        end
    end

    return snapshot

end

local function buildPOISet(mapID)

    local set = {}
    if not mapID then return set end

    local quests = C_QuestLog.GetQuestsOnMap(mapID)

    if quests then
        for _, q in ipairs(quests) do
            if q.questID then set[q.questID] = true end
        end
    end

    return set

end

local function getClassification(questID)

    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local v = C_QuestInfoSystem.GetQuestClassification(questID)
        if v then return v end
    end

    -- Default to 7 ("Normal") when the API does not classify this quest.
    return 7

end

local function isWatched(questID)

    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        local wt = C_QuestLog.GetQuestWatchType(questID)
        if wt and wt ~= 0 then return true end
    end

    return false

end

local function shouldShow(questID, snapshot, poiSet)

    local info = snapshot[questID]
    if not info then return false end
    if not isWatched(questID) then return false end

    local db = addon.Core.getDB()

    if not db.filterByZone then return true end
    if poiSet[questID] then return true end
    if db.alwaysShowCampaign and isCampaign(info) then return true end

    return false

end

local function untrackQuest(questID)

    if not C_QuestLog then return end

    pcall(C_QuestLog.RemoveQuestWatch, questID)
    pcall(C_QuestLog.RemoveWorldQuestWatch, questID)

end

local function buildItem(questID, info, superTrackedID)

    local cls = getClassification(questID)
    local section = CLASSIFICATION_NAMES[cls] or "Normal"

    local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
    local progress, hasProgress = addon.Util.computeProgress(objectives)

    return {
        kind        = "quest",
        id          = questID,
        key         = "quest:" .. questID,
        title       = info.title or ("Quest " .. questID),
        section     = section,
        isComplete  = info.isComplete and true or false,
        progress    = progress,
        hasProgress = hasProgress,
        objectives  = objectives,

        isSuperTracked = superTrackedID == questID and superTrackedID ~= 0,

        openDetails = function() addon.BlizzardInterface.openQuest(questID) end,
        untrack     = function() untrackQuest(questID) end,
        dump        = function() addon.Debug.dumpQuest(questID) end,
    }

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Quests.collectAll()

    local mapID = addon.Util.getPlayerZoneMapID()
    local snapshot = buildSnapshot(mapID)
    local superTrackedID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    local items = {}

    for qid, info in pairs(snapshot) do
        if isWatched(qid) then
            table.insert(items, buildItem(qid, info, superTrackedID))
        end
    end

    return items

end

function Quests.collect()

    local mapID = addon.Util.getPlayerZoneMapID()
    local snapshot = buildSnapshot(mapID)
    local poiSet = buildPOISet(mapID)
    local superTrackedID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    local items = {}

    for qid, info in pairs(snapshot) do
        if shouldShow(qid, snapshot, poiSet) then
            table.insert(items, buildItem(qid, info, superTrackedID))
        end
    end

    return items

end

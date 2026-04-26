local addonName, addon = ...

addon.Data = addon.Data or {}

local Quests = {}
addon.Data.Quests = Quests


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


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Quests.snapshot()

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

    return snapshot

end

function Quests.addTaskQuests(snapshot, mapID)

    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        local ok, n = pcall(C_QuestLog.GetNumWorldQuestWatches)

        if ok and type(n) == "number" then
            for i = 1, n do
                local ok2, qid = pcall(C_QuestLog.GetQuestIDForWorldQuestWatchIndex, i)
                if ok2 then addTaskEntry(snapshot, qid, "fromWorldWatch") end
            end
        end
    end

    if not mapID then return end

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

function Quests.buildPOISet(mapID)

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

function Quests.getClassification(questID)

    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local v = C_QuestInfoSystem.GetQuestClassification(questID)
        if v then return v end
    end

    -- Default to 7 ("Normal") when the API does not classify this quest.
    return 7

end

function Quests.getProgress(questID)
    return addon.Util.computeProgress(C_QuestLog.GetQuestObjectives(questID))
end

function Quests.isWatched(questID)

    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        local wt = C_QuestLog.GetQuestWatchType(questID)
        if wt and wt ~= 0 then return true end
    end

    return false

end

function Quests.shouldShow(questID, snapshot, poiSet, currentMapID, currentMapName)

    local info = snapshot[questID]
    if not info then return false end
    if not Quests.isWatched(questID) then return false end

    local db = addon.Core.getDB()

    if not db.filterByZone then return true end
    if poiSet[questID] then return true end
    if db.alwaysShowCampaign and isCampaign(info) then return true end

    return false

end

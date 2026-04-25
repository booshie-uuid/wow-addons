-- =============================================================================
-- BOOTSTRAP & CORE UTILITIES
-- =============================================================================

local ADDON_NAME = ...

BooshiesQuestLogDB = BooshiesQuestLogDB or {}

local observedErrors = {}
local function SafeCall(label, fn, ...)

    local ok, err = pcall(fn, ...)

    if not ok and err then
        local msg = tostring(err)
        if not observedErrors[msg] then
            observedErrors[msg] = true
            print(("|cffff6666BQL error [%s]:|r %s"):format(label or "?", msg))
        end
    end

    return ok

end

-- Entries lacking progress info still count toward the denominator so the
-- average matches what a user would expect ("3 of 5 done" with 2 unknowns
-- reads as 3/5, not 3/3).
local function ComputeProgress(list)

    if not list or #list == 0 then return 0, false end

    local sum, count = 0, 0

    for _, item in ipairs(list) do
        if item.finished then
            sum = sum + 1
            count = count + 1
        elseif item.numRequired and item.numRequired > 0 then
            local f = (item.numFulfilled or 0) / item.numRequired
            if f > 1 then f = 1 elseif f < 0 then f = 0 end

            sum = sum + f
            count = count + 1
        else
            count = count + 1
        end
    end

    if count == 0 then return 0, false end
    return sum / count, true

end

-- Probes WoW API records that ship the same data under different field
-- names across game versions.
local function FirstNonEmptyField(obj, keys)

    if type(obj) ~= "table" then return nil end

    for _, k in ipairs(keys) do
        local v = obj[k]
        if type(v) == "table" and #v > 0 then return v end
    end

    return nil

end

local function TryAppendIDs(list, seen, fn, ...)

    local ok, ids = pcall(fn, ...)
    if not ok or type(ids) ~= "table" then return false end

    local appended = false
    for _, id in ipairs(ids) do
        if id and id ~= 0 and (not seen or not seen[id]) then
            list[#list + 1] = id
            if seen then seen[id] = true end
            appended = true
        end
    end

    return appended

end


-- =============================================================================
-- DEFAULTS & LOOKUPS
-- =============================================================================

local DEFAULTS = {
    enabled = true,
    filterByZone = false,
    alwaysShowCampaign = true,
    alwaysShowAchievements = true,
    debug = false,
    includeWorldQuests = false,
    hideBlizzardTracker = true,
    point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -20, -200 },
    width = 280,
    maxHeight = 300,
    expandedKeys = {},
    collapsedSections = {},
    collapsed = false,
    helpShown = false,
    lockPosition = false,
}

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

local UI_TEXTURES = {
    plusButton  = "Interface\\Buttons\\UI-PlusButton-Up",
    minusButton = "Interface\\Buttons\\UI-MinusButton-Up",
    checkmark   = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    radioButton = "Interface\\Buttons\\UI-RadioButton",
    cog         = "Interface\\Buttons\\UI-OptionsButton",
}

-- RGBA for fills, RGB for text. Use unpack at call sites.
local UI_COLORS = {
    -- Row Backgrounds
    superTrackBg     = { 1.0,  0.82, 0.0,  0.12 },
    completedBg      = { 0.12, 0.35, 0.15, 0.45 },
    flashHighlight   = { 1.0,  0.85, 0.3,  0.6  },

    -- Progress Bar
    barBg            = { 0.22, 0.22, 0.24, 0.95 },
    barFill          = { 0.95, 0.82, 0.36, 0.9  },
    barFillComplete  = { 0.35, 0.9,  0.35, 0.9  },

    -- Separators / Overlays
    rowSeparator     = { 1, 1, 1, 0.07 },
    rowHover         = { 1, 1, 1, 0.06 },
    sectionStripe    = { 1, 1, 1, 0.14 },
    sectionSeparator = { 1, 1, 1, 0.07 },
    sectionHover     = { 1, 1, 1, 0.07 },
    cogHover         = { 1, 1, 1, 0.2  },

    -- Settings Dialog
    dialogBackdrop   = { 0,    0,    0,    0.78 },
    dialogBorder     = { 0.25, 0.25, 0.27, 1    },

    -- Resize Grip
    resizeGrip       = { 0.45, 0.45, 0.48, 0.55 },
    resizeGripHover  = { 1,    1,    1,    0.25 },

    -- Text
    sectionTitle        = { 1.0,  0.82, 0.0  },
    itemTitle           = { 1,    1,    1    },
    sectionCount        = { 0.85, 0.85, 0.85 },
    zoneText            = { 0.7,  0.7,  0.7  },
    collapseAllText     = { 0.55, 0.55, 0.6  },
    collapseAllHover    = { 1,    1,    1    },
    objectiveDot        = { 0.75, 0.75, 0.75 },
    objectiveFinished   = { 0.55, 0.9,  0.55 },
    objectiveUnfinished = { 0.95, 0.82, 0.36 },
}

-- Converts a UI_COLORS entry (RGB 0-1 floats) into a WoW chat colour escape
-- like "|cffRRGGBB". Use with `|r` to reset back to the FontString's default.
local function ColorToEscape(rgb)
    return string.format("|cff%02x%02x%02x",
        math.floor(rgb[1] * 255 + 0.5),
        math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5))
end


-- =============================================================================
-- INIT
-- =============================================================================

local function InitDB()

    for k, v in pairs(DEFAULTS) do
        if BooshiesQuestLogDB[k] == nil then BooshiesQuestLogDB[k] = v end
    end

    -- Migration from earlier single-key form to the expandedKeys set.
    if type(BooshiesQuestLogDB.expandedKey) == "string" then
        BooshiesQuestLogDB.expandedKeys = BooshiesQuestLogDB.expandedKeys or {}
        BooshiesQuestLogDB.expandedKeys[BooshiesQuestLogDB.expandedKey] = true
        BooshiesQuestLogDB.expandedKey = nil
    end

    -- Clamp maxHeight if the screen is now smaller than a previously saved value.
    local screenH = UIParent and UIParent:GetHeight() or 768
    if BooshiesQuestLogDB.maxHeight and BooshiesQuestLogDB.maxHeight > screenH - 60 then
        BooshiesQuestLogDB.maxHeight = math.max(DEFAULTS.maxHeight, math.floor(screenH * 0.5))
    end

end


-- =============================================================================
-- MAP & ZONE HELPERS
-- =============================================================================

local function GetPlayerZoneMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function GetMapName(mapID)

    if not mapID then return nil end

    local info = C_Map.GetMapInfo(mapID)
    return info and info.name

end


-- =============================================================================
-- QUEST DATA
-- =============================================================================

local function SnapshotQuestLog()

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

local function AddTaskEntry(snapshot, qid, source)

    if not qid or snapshot[qid] then return end

    local title = (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)) or ("Quest " .. qid)

    snapshot[qid] = {
        title = title,
        isComplete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(qid) or false,
        isTask = true,
        [source] = true,
    }

end

local function AddTaskQuestsToSnapshot(snapshot, mapID)

    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        local ok, n = pcall(C_QuestLog.GetNumWorldQuestWatches)

        if ok and type(n) == "number" then
            for i = 1, n do
                local ok2, qid = pcall(C_QuestLog.GetQuestIDForWorldQuestWatchIndex, i)
                if ok2 then AddTaskEntry(snapshot, qid, "fromWorldWatch") end
            end
        end
    end

    if not mapID then return end

    if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
        local ok, list = pcall(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)

        if ok and type(list) == "table" then
            for _, t in ipairs(list) do
                AddTaskEntry(snapshot, t.questId or t.questID, "fromTaskAPI")
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetQuestsOnMap then
        local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)

        if ok and type(list) == "table" then
            for _, t in ipairs(list) do
                AddTaskEntry(snapshot, t.questID, "fromPOI")
            end
        end
    end

end

local function BuildPOISet(mapID)

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

local function IsCampaign(info) return info and info.campaignID and info.campaignID > 0 end

local function GetClassification(questID)

    if C_QuestInfoSystem and C_QuestInfoSystem.GetQuestClassification then
        local v = C_QuestInfoSystem.GetQuestClassification(questID)
        if v then return v end
    end

    -- Default to 7 ("Normal") when the API does not classify this quest.
    return 7

end


-- =============================================================================
-- QUEST VISIBILITY & PROGRESS
-- =============================================================================

local function GetQuestProgress(questID)
    return ComputeProgress(C_QuestLog.GetQuestObjectives(questID))
end

local function IsQuestWatched(questID)

    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        local wt = C_QuestLog.GetQuestWatchType(questID)
        if wt and wt ~= 0 then return true end
    end

    return false

end

local function ShouldShow(questID, snapshot, poiSet, currentMapID, currentMapName)

    local info = snapshot[questID]
    if not info then return false end
    if not IsQuestWatched(questID) then return false end

    if not BooshiesQuestLogDB.filterByZone then return true end
    if poiSet[questID] then return true end
    if BooshiesQuestLogDB.alwaysShowCampaign and IsCampaign(info) then return true end

    return false

end


-- =============================================================================
-- ACHIEVEMENT DATA
-- =============================================================================

local function GetTrackedAchievementList()

    local list = {}

    if _G.GetTrackedAchievements then
        TryAppendIDs(list, nil, function() return { GetTrackedAchievements() } end)
    end

    if #list == 0 and C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        local t = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        if t ~= nil then
            TryAppendIDs(list, nil, C_ContentTracking.GetTrackedIDs, t)
        end
    end

    return list

end

-- Blizzard's `GetAchievementCriteriaInfo` returns an empty `cstr` for single-
-- step achievements (e.g. raid boss kills). The achievement-level `description`
-- is the human-readable label in those cases, with `name` as a last-resort
-- fallback.
local function GetAchievementHeader(achID)

    if not GetAchievementInfo then return "", false end

    local _, name, _, completed, _, _, _, description = GetAchievementInfo(achID)
    local text = (description and description ~= "" and description) or name or ""

    return text, completed and true or false

end

local function GetAchievementCriteriaList(achID)

    local list = {}
    if not _G.GetAchievementNumCriteria or not _G.GetAchievementCriteriaInfo then return list end

    local num = GetAchievementNumCriteria(achID) or 0
    local headerText

    for i = 1, num do
        local cstr, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achID, i)

        if not cstr or cstr == "" then
            headerText = headerText or GetAchievementHeader(achID)
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
        local text, completed = GetAchievementHeader(achID)
        if text ~= "" then
            list[1] = { text = text, finished = completed, numFulfilled = 0, numRequired = 0 }
        end
    end

    return list

end

local function GetAchievementProgress(achID)

    -- Zero-criteria achievements report (1, true) when complete, (0, false)
    -- when not, so the progress bar stays hidden on incomplete single-step
    -- achievements.
    local rawNum = (_G.GetAchievementNumCriteria and GetAchievementNumCriteria(achID)) or 0
    if rawNum == 0 then
        local _, completed = GetAchievementHeader(achID)
        return completed and 1 or 0, completed
    end

    return ComputeProgress(GetAchievementCriteriaList(achID))

end


-- =============================================================================
-- RECIPE DATA
-- =============================================================================

local function GetTrackedRecipeList()

    local list = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked then return list end

    local seen = {}
    TryAppendIDs(list, seen, C_TradeSkillUI.GetRecipesTracked, false)
    TryAppendIDs(list, seen, C_TradeSkillUI.GetRecipesTracked, true)

    return list

end

local function GetRecipeName(recipeID)

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and info and info.name then return info.name end
    end

    return "Recipe " .. tostring(recipeID)

end

-- Args after itemID: includeBank, includeCharges, includeReagentBank.
-- Bank is included so reagents stashed there still count toward recipe progress,
-- matching what Blizzard's own recipe tracker shows.
local function ItemCount(itemID)

    if not itemID then return 0 end

    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true)
        if ok and n then return n end
    end

    if _G.GetItemCount then
        local ok, n = pcall(GetItemCount, itemID, true, false, true)
        if ok and n then return n end
    end

    return 0

end

local function ItemName(itemID)

    if not itemID then return "?" end

    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemID)
        if n then return n end
    end

    if _G.GetItemInfo then
        local n = GetItemInfo(itemID)
        if n then return n end
    end

    return "Item " .. itemID

end

local function GetRecipeReagents(recipeID)

    local reagents = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return reagents end

    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not ok or not schematic or not schematic.reagentSlotSchematics then return reagents end

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local needed = slot.quantityRequired or 0

        if needed > 0 and slot.reagents and slot.reagents[1] and slot.reagents[1].itemID then
            -- A slot's `reagents` list holds every quality variant that fills it
            -- (q1/q2/q3 of the same base item). Sum across all variants so a
            -- player holding only q3 still sees their stockpile count.
            local have = 0
            for _, reagent in ipairs(slot.reagents) do
                if reagent.itemID then
                    have = have + ItemCount(reagent.itemID)
                end
            end

            reagents[#reagents + 1] = {
                text = ItemName(slot.reagents[1].itemID),
                numFulfilled = have,
                numRequired = needed,
                finished = have >= needed,
            }
        end
    end

    return reagents

end

local function GetRecipeProgress(recipeID)
    return ComputeProgress(GetRecipeReagents(recipeID))
end


-- =============================================================================
-- ACTIVITY & INITIATIVE DATA
-- =============================================================================

local function IterateActivities(callback)

    if not C_PerksActivities or not C_PerksActivities.GetPerksActivitiesInfo then return end

    local ok, info = pcall(C_PerksActivities.GetPerksActivitiesInfo)
    if not ok or type(info) ~= "table" then return end

    local activities = info.activities or info
    if type(activities) ~= "table" then return end

    for _, activity in ipairs(activities) do
        if type(activity) == "table" then
            if callback(activity) == false then return end
        end
    end

end

local function ActivityID(activity)
    return activity and (activity.ID or activity.activityID or activity.perksActivityID)
end

local function GetTrackedMonthlyActivities()

    local list = {}

    if C_PerksActivities and C_PerksActivities.GetTrackedPerksActivities then
        if TryAppendIDs(list, nil, C_PerksActivities.GetTrackedPerksActivities) then
            return list
        end
    end

    IterateActivities(function(activity)
        if activity.tracked then
            local id = ActivityID(activity)
            if id then list[#list + 1] = id end
        end
    end)

    return list

end

local function GetActivityInfo(id)

    if not C_PerksActivities then return nil end

    if C_PerksActivities.GetPerksActivityInfo then
        local ok, info = pcall(C_PerksActivities.GetPerksActivityInfo, id)
        if ok and info then return info end
    end

    local found
    IterateActivities(function(activity)
        if ActivityID(activity) == id then
            found = activity
            return false
        end
    end)

    return found

end

local function GetNeighborhoodTasks()

    if not C_NeighborhoodInitiative or not C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo then return nil end

    local ok, info = pcall(C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo)
    if ok and type(info) == "table" and type(info.tasks) == "table" then
        return info.tasks
    end

    return nil

end

local function TaskID(t)
    return t and (t.id or t.taskID or t.ID or t.initiativeTaskID)
end

local function GetTrackedInitiativeTasks()

    local list = {}
    if not C_NeighborhoodInitiative then return list end

    if C_NeighborhoodInitiative.GetTrackedInitiativeTasks then
        if TryAppendIDs(list, nil, C_NeighborhoodInitiative.GetTrackedInitiativeTasks) then
            return list
        end
    end

    local tasks = GetNeighborhoodTasks()
    if tasks then
        for _, t in ipairs(tasks) do
            if type(t) == "table" and t.tracked then
                local id = TaskID(t)
                if id then list[#list + 1] = id end
            end
        end
    end

    return list

end

local function GetInitiativeTaskInfo(id)

    if not C_NeighborhoodInitiative then return nil end

    if C_NeighborhoodInitiative.GetInitiativeTaskInfo then
        local ok, info = pcall(C_NeighborhoodInitiative.GetInitiativeTaskInfo, id)
        if ok and type(info) == "table" then return info end
    end

    local tasks = GetNeighborhoodTasks()
    if tasks then
        for _, t in ipairs(tasks) do
            if type(t) == "table" and TaskID(t) == id then return t end
        end
    end

    return nil

end

local function GetInitiativeTaskObjectives(id)

    local info = GetInitiativeTaskInfo(id)
    if not info then return {} end

    local list = {}
    local criteria = FirstNonEmptyField(info, { "criteriaList", "requirementsList", "objectives", "conditions" })

    if criteria then
        for _, c in ipairs(criteria) do
            if type(c) == "table" then
                local text = c.requirementText or c.description or c.text or c.name or c.title or "?"
                if type(text) == "string" then text = text:gsub("^%s*%-%s*", "") end

                local finished = c.completed or c.finished or c.isComplete or false
                local have = c.quantity or c.numFulfilled or c.progress or c.current or 0
                local need = c.required or c.numRequired or c.requiredQuantity or c.quantityRequired or 0

                if need == 0 and type(text) == "string" then
                    local n, m = text:match("(%d+)%s*/%s*(%d+)")
                    if n and m then
                        have = tonumber(n) or 0
                        need = tonumber(m) or 0
                    end
                end

                list[#list + 1] = {
                    text = text,
                    finished = finished and true or false,
                    numFulfilled = have,
                    numRequired = need,
                }
            end
        end
    end

    if #list == 0 and info.description and info.description ~= "" then
        list[#list + 1] = {
            text = info.description,
            finished = info.completed and true or false,
            numFulfilled = 0,
            numRequired = 0,
        }
    end

    return list

end

local function GetInitiativeTaskProgress(id)

    local info = GetInitiativeTaskInfo(id)
    if not info then return 0, false end
    if info.completed then return 1, true end

    return ComputeProgress(GetInitiativeTaskObjectives(id))

end

local function GetInitiativeTaskName(id)

    local info = GetInitiativeTaskInfo(id)
    if info then return info.taskName or info.name or info.activityName or info.title or ("Endeavour " .. id) end

    return "Endeavour " .. id

end

local function GetActivityObjectives(id)

    local info = GetActivityInfo(id)
    if not info then return {} end

    local list = {}
    local criteria = FirstNonEmptyField(info, { "criteriaList", "requirementsList", "conditions" })

    if criteria then
        for _, c in ipairs(criteria) do
            if type(c) == "table" then
                local text = c.requirementText or c.description or c.text or c.name or c.title or c.criteriaString or "?"
                if type(text) == "string" then
                    text = text:gsub("^%s*%-%s*", "")
                end

                local finished = c.completed or c.finished or c.isComplete or false
                local have = c.quantity or c.numFulfilled or c.progress or c.current or 0
                local need = c.required or c.numRequired or c.requiredQuantity or c.quantityRequired or c.needed or 0

                if need == 0 and type(text) == "string" then
                    local n, m = text:match("(%d+)%s*/%s*(%d+)")
                    if n and m then
                        have = tonumber(n) or 0
                        need = tonumber(m) or 0
                    end
                end

                list[#list + 1] = {
                    text = text,
                    finished = finished and true or false,
                    numFulfilled = have,
                    numRequired = need,
                }
            end
        end
    end

    if #list == 0 and info.description and info.description ~= "" then
        list[#list + 1] = {
            text = info.description,
            finished = info.completed and true or false,
            numFulfilled = info.thresholdContributionAmount or 0,
            numRequired = info.thresholdMax or 0,
        }
    end

    return list

end

local function GetActivityProgress(id)

    local info = GetActivityInfo(id)
    if not info then return 0, false end
    if info.completed then return 1, true end

    local objs = GetActivityObjectives(id)
    if #objs > 0 then return ComputeProgress(objs) end

    local have = info.thresholdContributionAmount or 0
    local need = info.thresholdMax or info.requiredContributionAmount or 0
    if need <= 0 then return 0, false end

    local f = have / need
    if f > 1 then f = 1 elseif f < 0 then f = 0 end

    return f, true

end


-- =============================================================================
-- UI CONSTANTS & STATE
-- =============================================================================

-- Row Layout
local ROW_HEIGHT = 26
local ROW_GAP = 6
local BAR_HEIGHT = 3
local BAR_BOTTOM_PAD = 3
local TOP_CLUSTER_Y = 3   -- vertical offset for arrow + track + completion icon

-- Frame Chrome
local HEADER_OFFSET = 46
local BOTTOM_PAD = 16

-- Resize Limits
local MIN_MAX_HEIGHT = 150
local MAX_RESIZE_HEIGHT = 2000
local DEFAULT_MAX_HEIGHT = 500

-- Frame References (assigned in BuildUI)
local frame, titleText, zoneText, content, scrollFrame, settingsFrame

-- Forward declarations - earlier-defined functions close over these and
-- resolve them at call time, so the actual values can be assigned later.
local ToggleSuperTrack
local Refresh

-- Row Pool
local activeRows, rowPool = {}, {}

-- Scroll Pin
-- After a row click, debounced WoW events (QUEST_LOG_UPDATE, BAG_UPDATE_DELAYED,
-- etc.) often trigger another Refresh ~50ms later, and the second layout pass
-- can shift content slightly (lazy text measurement, scrollbar appear/disappear).
-- We pin the click target by key for a short window and re-apply ScrollIntoView
-- at the end of each refresh within that window.
local pendingScrollKey, pendingScrollExpiresAt
local SCROLL_PIN_WINDOW = 0.3

-- Newly-Tracked Detection
local previousTrackedKeys
local pendingFlashKeys = {}
local FLASH_DURATION = 0.8


-- =============================================================================
-- FRAME POSITION
-- =============================================================================

local function SavePosition()

    if not frame then return end

    local right = frame:GetRight()
    local top = frame:GetTop()
    if not right or not top then return end

    local parent = UIParent
    local uiRight = parent:GetRight() or 0
    local uiTop = parent:GetTop() or 0

    local x = right - uiRight
    local y = top - uiTop

    BooshiesQuestLogDB.point = { "TOPRIGHT", "UIParent", "TOPRIGHT", x, y }

    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)

end

local function RestorePosition()

    frame:ClearAllPoints()

    local p = BooshiesQuestLogDB.point or DEFAULTS.point
    local rel = _G[p[2]] or UIParent

    frame:SetPoint(p[1], rel, p[3], p[4], p[5])

end


-- =============================================================================
-- LAYOUT & SCROLL
-- =============================================================================

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

    local maxH = BooshiesQuestLogDB.maxHeight or 300
    local finalHeight = math.max(maxH, MIN_MAX_HEIGHT)
    frame:SetHeight(finalHeight)

    local viewport = finalHeight - HEADER_OFFSET - BOTTOM_PAD
    local bar = scrollFrame.ScrollBar or _G["BooshiesQuestLogScrollScrollBar"]
    local barVisible = false

    if bar then
        barVisible = contentHeight > viewport + 0.5

        if barVisible then
            scrollFrame._bqlForceHidden = false
            bar:Show()
            scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, BOTTOM_PAD)
        else
            scrollFrame._bqlForceHidden = true
            bar:Hide()
            scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, BOTTOM_PAD)
            if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(0) end
        end
    end

    local frameWidth = frame:GetWidth() or (BooshiesQuestLogDB.width or 280)
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


-- =============================================================================
-- ROW EXPAND/COLLAPSE
-- =============================================================================

local function CollapseRow(row)

    row.expanded = false
    row.arrow:SetTexture(UI_TEXTURES.plusButton)
    if row.objFrame then row.objFrame:Hide() end
    row:SetHeight(ROW_HEIGHT)

end

-- Objective Layout
local OBJ_LEFT_INDENT = 3
local OBJ_RIGHT_MARGIN = 26
local COL_MARKER_W = 14
local COL_GAP = 4
local OBJ_TOP_PAD = 5
local OBJ_BOTTOM_PAD = 5
local OBJ_LINE_GAP = 3
local LINE_VCENTER = 5

local function SplitObjective(obj)

    local text = obj.text or ""

    -- "5/10 Slay Murlocs" form: pull the count off the front and return the
    -- remainder as the description.
    local n, m, rest = text:match("^(%d+)%s*/%s*(%d+)%s+(.*)$")
    if n and m and rest and rest ~= "" then
        return rest, n .. "/" .. m
    end

    -- Otherwise synthesise "have/need" from the structured fields if present.
    if obj.numRequired and obj.numRequired > 0 then
        return text, (obj.numFulfilled or 0) .. "/" .. obj.numRequired
    end

    return text, nil

end

local measureFS
local function MeasureText(text)

    if not measureFS then
        measureFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        measureFS:Hide()
    end

    measureFS:SetText(text or "")
    return measureFS:GetStringWidth() or 0

end

local function FetchObjectivesFor(row)

    if row.itemKind == "achievement" then
        return GetAchievementCriteriaList(row.achievementID)
    elseif row.itemKind == "recipe" then
        return GetRecipeReagents(row.recipeID)
    elseif row.itemKind == "activity" then
        return GetActivityObjectives(row.activityID)
    elseif row.itemKind == "initiative" then
        return GetInitiativeTaskObjectives(row.initiativeID)
    end

    return C_QuestLog.GetQuestObjectives(row.questID) or {}

end

-- The widest count string is tracked so descriptions align in a column.
local function MeasureObjectiveParts(objectives)

    local parts = {}
    local maxCountW = 0

    for i, obj in ipairs(objectives) do
        local desc, count = SplitObjective(obj)

        parts[i] = { desc = desc, count = count, finished = obj.finished }

        if count and count ~= "" then
            local w = MeasureText(count)
            if w > maxCountW then maxCountW = w end
        end
    end

    return parts, maxCountW

end

local function ComputeObjectiveColumns(objW, maxCountW)

    local countColW = math.ceil(maxCountW)
    local hasCountCol = countColW > 0
    local descX = COL_MARKER_W + COL_GAP + (hasCountCol and (countColW + COL_GAP) or 0)
    local descW = math.max(objW - descX, 40)

    return {
        countColW   = countColW,
        hasCountCol = hasCountCol,
        descX       = descX,
        descW       = descW,
    }

end

-- Synthetic objective appended to a complete quest's expansion, telling the
-- player there's nothing left to do but hand it in.
local READY_TO_TURN_IN_PART = { desc = "Ready to turn in", count = nil, finished = true }

-- Returns the y position for the next row to use.
local function LayoutObjectiveRow(row, e, y, part, cols)

    local isFinished = part.finished
    local color = isFinished and UI_COLORS.objectiveFinished or UI_COLORS.objectiveUnfinished

    e.tex:ClearAllPoints()
    e.dot:ClearAllPoints()

    if isFinished then
        e.tex:SetPoint("CENTER", row.objFrame, "TOPLEFT", COL_MARKER_W / 2, -y - LINE_VCENTER)
        e.tex:SetTexture(UI_TEXTURES.checkmark)
        e.tex:Show()
        e.dot:Hide()
    else
        e.dot:SetPoint("CENTER", row.objFrame, "TOPLEFT", COL_MARKER_W / 2, -y - LINE_VCENTER)
        e.dot:SetJustifyH("CENTER")
        e.dot:SetText("•")
        e.dot:SetTextColor(unpack(UI_COLORS.objectiveDot))
        e.dot:Show()
        e.tex:Hide()
    end

    e.count:ClearAllPoints()
    if cols.hasCountCol and part.count then
        e.count:SetPoint("TOPLEFT", row.objFrame, "TOPLEFT", COL_MARKER_W + COL_GAP, -y)
        e.count:SetWidth(cols.countColW)
        e.count:SetText(part.count)
        e.count:SetTextColor(color[1], color[2], color[3])
        e.count:Show()
    else
        e.count:Hide()
    end

    e.desc:ClearAllPoints()
    e.desc:SetPoint("TOPLEFT", row.objFrame, "TOPLEFT", cols.descX, -y)
    e.desc:SetWidth(cols.descW)
    e.desc:SetWordWrap(true)
    e.desc:SetTextColor(color[1], color[2], color[3])
    e.desc:SetText(part.desc)
    e.desc:Show()

    return y + e.desc:GetStringHeight() + OBJ_LINE_GAP

end

-- Each entry holds a texture + dot/count/desc font strings, pooled by index
-- per row.
local function EnsureObjEntry(row, i)

    local e = row.objLines[i]

    if not (type(e) == "table" and e.desc) then
        if e and type(e.Hide) == "function" then pcall(e.Hide, e) end

        e = {}
        e.tex = row.objFrame:CreateTexture(nil, "OVERLAY")
        e.tex:SetSize(10, 10)
        e.dot = row.objFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e.count = row.objFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e.count:SetJustifyH("LEFT")
        e.desc = row.objFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e.desc:SetJustifyH("LEFT")
        e.desc:SetWordWrap(true)
        row.objLines[i] = e
    end

    return e

end

-- Initialises the empty `row.objLines` pool on first expansion as a side effect.
local function EnsureObjFrame(row, objW)

    if not row.objFrame then
        row.objFrame = CreateFrame("Frame", nil, row)
        row.objLines = {}
    end

    row.objFrame:ClearAllPoints()
    row.objFrame:SetPoint("TOPLEFT", row, "TOPLEFT", OBJ_LEFT_INDENT, -(ROW_HEIGHT + OBJ_TOP_PAD))
    row.objFrame:SetWidth(objW)
    row.objFrame:Show()

end

-- Called after rendering so a previously-larger row doesn't leave stale
-- entries visible.
local function HideTrailingObjLines(row, fromIdx)

    for i = fromIdx + 1, #row.objLines do
        local e = row.objLines[i]
        if type(e) == "table" then
            if e.tex then e.tex:Hide() end
            if e.dot then e.dot:Hide() end
            if e.count then e.count:Hide() end
            if e.desc then e.desc:Hide() end
        end
    end

end

local function ExpandRow(row)

    row.expanded = true
    row.arrow:SetTexture(UI_TEXTURES.minusButton)

    local contentW = (content and content:GetWidth()) or ((BooshiesQuestLogDB.width or 280) - 40)
    local objW = math.max(contentW - OBJ_LEFT_INDENT - OBJ_RIGHT_MARGIN, 60)

    local objectives = FetchObjectivesFor(row)
    local parts, maxCountW = MeasureObjectiveParts(objectives)
    local cols = ComputeObjectiveColumns(objW, maxCountW)

    EnsureObjFrame(row, objW)

    local y, idx = 0, 0
    for i, part in ipairs(parts) do
        idx = i
        y = LayoutObjectiveRow(row, EnsureObjEntry(row, i), y, part, cols)
    end

    -- Quests get an extra "Ready to turn in" line once their objectives are all done.
    if row.itemKind ~= "achievement" and row.questID and C_QuestLog.IsComplete(row.questID) then
        idx = idx + 1
        y = LayoutObjectiveRow(row, EnsureObjEntry(row, idx), y, READY_TO_TURN_IN_PART, cols)
    end

    HideTrailingObjLines(row, idx)

    local totalY = math.max(y - OBJ_LINE_GAP, 1)
    row.objFrame:SetHeight(totalY)
    row:SetHeight(ROW_HEIGHT + OBJ_TOP_PAD + totalY + OBJ_BOTTOM_PAD)

end


-- =============================================================================
-- DETAILS DIALOGS
-- =============================================================================

local function OpenQuestDetails(questID)

    if not questID then return end

    if _G.QuestMapFrame_OpenToQuestDetails then
        pcall(_G.QuestMapFrame_OpenToQuestDetails, questID)
        return
    end

    if _G.QuestMapFrame_ShowQuestDetails then
        if WorldMapFrame and not WorldMapFrame:IsShown() then
            pcall(ShowUIPanel, WorldMapFrame)
        end
        pcall(_G.QuestMapFrame_ShowQuestDetails, questID)
        return
    end

    local logIndex = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
        and C_QuestLog.GetLogIndexForQuestID(questID) or nil
    if logIndex and _G.QuestLogPopupDetailFrame_Show then
        pcall(_G.QuestLogPopupDetailFrame_Show, logIndex)
    end

end

local function OpenMonthlyActivities()

    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    elseif _G.LoadAddOn then
        pcall(_G.LoadAddOn, "Blizzard_EncounterJournal")
    end

    if _G.EncounterJournal and not EncounterJournal:IsShown() then
        pcall(ShowUIPanel, EncounterJournal)
    elseif _G.ToggleEncounterJournal then
        pcall(_G.ToggleEncounterJournal)
    end

end

local function OpenEndeavours(taskID)

    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_HousingDashboard")
    elseif _G.LoadAddOn then
        pcall(_G.LoadAddOn, "Blizzard_HousingDashboard")
    end

    local f = _G.HousingDashboardFrame
    if not f or not f.Show then return end

    pcall(ShowUIPanel, f)

    if taskID and f.OpenInitiativesFrameToTaskID then
        pcall(f.OpenInitiativesFrameToTaskID, f, taskID)
    end

end

local function OpenRecipeDetails(recipeID)

    if not recipeID then return end

    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        pcall(C_TradeSkillUI.OpenRecipe, recipeID)
    end

end

local function OpenAchievementDetails(achID)

    if not achID then return end

    if _G.AchievementFrame_LoadUI then
        pcall(_G.AchievementFrame_LoadUI)
    end

    if _G.AchievementFrame and not AchievementFrame:IsShown() then
        pcall(ShowUIPanel, AchievementFrame)
    end

    if _G.AchievementFrame_SelectAchievement then
        pcall(_G.AchievementFrame_SelectAchievement, achID)
    elseif _G.OpenAchievementFrameToAchievement then
        pcall(_G.OpenAchievementFrameToAchievement, achID)
    end

end


-- =============================================================================
-- UNTRACK
-- =============================================================================

local function TryCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, ...)
    return ok
end

local function UntrackRow(row)

    if not row then return end

    if row.questID then
        if C_QuestLog then
            TryCall(C_QuestLog.RemoveQuestWatch, row.questID)
            TryCall(C_QuestLog.RemoveWorldQuestWatch, row.questID)
        end

    elseif row.achievementID then
        local id = row.achievementID
        local t = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Player) or 2

        if C_ContentTracking and C_ContentTracking.StopTracking and t then
            TryCall(C_ContentTracking.StopTracking, t, id, stopType)
        end
        TryCall(_G.RemoveTrackedAchievement, id)

    elseif row.recipeID then
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
            TryCall(C_TradeSkillUI.SetRecipeTracked, row.recipeID, false, false)
            TryCall(C_TradeSkillUI.SetRecipeTracked, row.recipeID, false, true)
        end

    elseif row.activityID then
        if C_PerksActivities then
            -- Probe API for an explicit untrack/remove function and stop on first
            -- success, since the exact name varies across game versions.
            for fname, fn in pairs(C_PerksActivities) do
                if type(fn) == "function" then
                    local lk = fname:lower()
                    if lk:find("untrack") or (lk:find("remove") and (lk:find("track") or lk:find("activit"))) then
                        if TryCall(fn, row.activityID) then break end
                    end
                end
            end

            -- Also call any SetXxxTracked-style toggle with false, in case the API
            -- exposes a setter rather than a remove.
            for fname, fn in pairs(C_PerksActivities) do
                if type(fn) == "function" then
                    local lk = fname:lower()
                    if lk:find("^set") and lk:find("track") then
                        TryCall(fn, row.activityID, false)
                    end
                end
            end
        end

    elseif row.initiativeID then
        if C_NeighborhoodInitiative then
            TryCall(C_NeighborhoodInitiative.RemoveTrackedInitiativeTask, row.initiativeID)
        end
    end

end


-- =============================================================================
-- DEBUG DUMPS
-- =============================================================================

local function DumpQuestMetadata(questID)

    if not questID then return end

    local function p(fmt, ...) print(("|cff4fc3f7BQL|r " .. fmt):format(...)) end

    p("--- Quest %d ---", questID)
    p("title: %s", tostring(C_QuestLog.GetTitleForQuestID(questID)))

    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    p("logIndex: %s", tostring(logIndex))

    if logIndex then
        local info = C_QuestLog.GetInfo(logIndex)
        if info then
            local keys = {}
            for k in pairs(info) do table.insert(keys, k) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                p("  info.%s = %s", k, tostring(info[k]))
            end
        end
    end

    p("isComplete: %s", tostring(C_QuestLog.IsComplete(questID)))
    p("isOnMap: %s", tostring(C_QuestLog.IsOnMap and C_QuestLog.IsOnMap(questID)))
    p("watchType: %s", tostring(C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID)))
    p("superTracked: %s", tostring(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID() == questID))

    local mapID = GetPlayerZoneMapID()
    local mapName = GetMapName(mapID) or "?"
    p("player map: %s (%s)", tostring(mapID), mapName)

    local onThisMap = false
    local questsOnMap = mapID and C_QuestLog.GetQuestsOnMap(mapID) or nil

    if questsOnMap then
        for _, q in ipairs(questsOnMap) do
            if q.questID == questID then
                onThisMap = true
                break
            end
        end
    end
    p("POI on current map: %s", tostring(onThisMap))

    local objs = C_QuestLog.GetQuestObjectives(questID) or {}
    p("objectives: %d", #objs)
    for i, o in ipairs(objs) do
        p("  [%d] %s (%s/%s, finished=%s, type=%s)",
            i, tostring(o.text), tostring(o.numFulfilled), tostring(o.numRequired),
            tostring(o.finished), tostring(o.type))
    end

    local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
    if tagInfo then
        local keys = {}
        for k in pairs(tagInfo) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            p("  tag.%s = %s", k, tostring(tagInfo[k]))
        end
    end

end

local function DumpAchievementMetadata(achID)

    if not achID then return end

    local function p(fmt, ...) print(("|cff4fc3f7BQL|r " .. fmt):format(...)) end

    p("--- Achievement %d ---", achID)

    if GetAchievementInfo then
        local id, name, points, completed, month, day, year, description,
              flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy,
              isStatistic = GetAchievementInfo(achID)
        p("id: %s", tostring(id))
        p("name: %s", tostring(name))
        p("description: %s", tostring(description))
        p("points: %s", tostring(points))
        p("completed: %s", tostring(completed))
        p("earned: %s/%s/%s", tostring(month), tostring(day), tostring(year))
        p("flags: %s", tostring(flags))
        p("icon: %s", tostring(icon))
        p("rewardText: %s", tostring(rewardText))
        p("isGuild: %s, wasEarnedByMe: %s, earnedBy: %s, isStatistic: %s",
            tostring(isGuild), tostring(wasEarnedByMe), tostring(earnedBy), tostring(isStatistic))
    end

    local num = (_G.GetAchievementNumCriteria and GetAchievementNumCriteria(achID)) or 0
    p("criteria count: %d", num)
    for i = 1, num do
        local criteriaString, criteriaType, ccompleted, quantity, reqQuantity,
              charName, cflags, assetID, quantityString, criteriaID, eligible
              = GetAchievementCriteriaInfo(achID, i)
        p("  [%d] criteriaString: %q", i, tostring(criteriaString or ""))
        p("       criteriaType: %s, criteriaID: %s, assetID: %s",
            tostring(criteriaType), tostring(criteriaID), tostring(assetID))
        p("       quantity: %s/%s, quantityString: %s",
            tostring(quantity), tostring(reqQuantity), tostring(quantityString))
        p("       completed: %s, eligible: %s, charName: %s, flags: %s",
            tostring(ccompleted), tostring(eligible), tostring(charName), tostring(cflags))

        -- Newer asset-based lookup: if criterion references a quest, spell, or
        -- achievement asset, those names are often the human-readable label.
        if assetID and assetID ~= 0 then
            local assetName
            if criteriaType == 27 and C_QuestLog and C_QuestLog.GetTitleForQuestID then
                assetName = C_QuestLog.GetTitleForQuestID(assetID)
                if assetName then p("       quest asset name: %s", tostring(assetName)) end
            elseif criteriaType == 8 and _G.GetAchievementInfo then
                assetName = select(2, GetAchievementInfo(assetID))
                if assetName then p("       achievement asset name: %s", tostring(assetName)) end
            elseif _G.GetSpellInfo then
                local ok, spellName = pcall(GetSpellInfo, assetID)
                if ok and spellName then p("       spell asset name: %s", tostring(spellName)) end
            end
        end

        -- Newer table-shaped API (if present on this client)
        if criteriaID and C_AchievementInfo and C_AchievementInfo.GetCriteriaInfo then
            local ok, infoTbl = pcall(C_AchievementInfo.GetCriteriaInfo, criteriaID)
            if ok and type(infoTbl) == "table" then
                local keys = {}
                for k in pairs(infoTbl) do table.insert(keys, k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    p("       C_AI.%s = %s", k, tostring(infoTbl[k]))
                end
            end
        end
    end

end

local function DumpRecipeMetadata(recipeID)

    if not recipeID then return end

    local function p(fmt, ...) print(("|cff4fc3f7BQL|r " .. fmt):format(...)) end

    p("--- Recipe %d ---", recipeID)

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" then
            local keys = {}
            for k in pairs(info) do table.insert(keys, k) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                p("  info.%s = %s", k, tostring(info[k]))
            end
        else
            p("  (no recipe info)")
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if ok and type(schematic) == "table" then
            p("schematic.recipeID: %s", tostring(schematic.recipeID))
            p("schematic.name: %s", tostring(schematic.name))

            local slots = schematic.reagentSlotSchematics
            if type(slots) == "table" then
                p("reagentSlotSchematics: %d slots", #slots)
                for si, slot in ipairs(slots) do
                    p("  slot[%d] quantityRequired=%s, dataSlotType=%s, reagentType=%s",
                        si,
                        tostring(slot.quantityRequired),
                        tostring(slot.dataSlotType),
                        tostring(slot.reagentType))

                    if type(slot.reagents) == "table" then
                        for ri, reagent in ipairs(slot.reagents) do
                            local name = reagent.itemID and ItemName(reagent.itemID) or "?"
                            local count = reagent.itemID and ItemCount(reagent.itemID) or 0
                            p("    reagent[%d] itemID=%s (%s), have=%d",
                                ri, tostring(reagent.itemID), tostring(name), count)
                        end
                    end
                end
            end
        else
            p("  (no schematic)")
        end
    end

end


-- =============================================================================
-- ROW LIFECYCLE
-- =============================================================================

-- Prefixes for the strings returned by RowKey, used to identify a row across
-- pool recycles (e.g. for the scroll pin and newly-tracked detection).
local KEY_PREFIXES = {
    quest       = "quest:",
    achievement = "ach:",
    recipe      = "recipe:",
    activity    = "activity:",
    initiative  = "initiative:",
    section     = "section:",
}

local function RowKey(row)

    if not row then return nil end

    if row.itemKind == "achievement" and row.achievementID then
        return KEY_PREFIXES.achievement .. row.achievementID
    end
    if row.itemKind == "recipe" and row.recipeID then
        return KEY_PREFIXES.recipe .. row.recipeID
    end
    if row.itemKind == "activity" and row.activityID then
        return KEY_PREFIXES.activity .. row.activityID
    end
    if row.itemKind == "initiative" and row.initiativeID then
        return KEY_PREFIXES.initiative .. row.initiativeID
    end
    if row.questID then
        return KEY_PREFIXES.quest .. row.questID
    end
    if row.itemKind == "section" and row.classification ~= nil then
        return KEY_PREFIXES.section .. tostring(row.classification)
    end

    return nil

end

local function SectionForRowKey(key)

    if not key then return nil end

    if key:sub(1, #KEY_PREFIXES.achievement) == KEY_PREFIXES.achievement then return "achievements" end
    if key:sub(1, #KEY_PREFIXES.recipe)      == KEY_PREFIXES.recipe      then return "recipes"      end
    if key:sub(1, #KEY_PREFIXES.activity)    == KEY_PREFIXES.activity    then return "activities"   end
    if key:sub(1, #KEY_PREFIXES.initiative)  == KEY_PREFIXES.initiative  then return "initiatives"  end

    if key:sub(1, #KEY_PREFIXES.quest) == KEY_PREFIXES.quest then
        local qid = tonumber(key:sub(#KEY_PREFIXES.quest + 1))
        if qid then return GetClassification(qid) end
    end

    return nil

end

local function OnRowClick(row)

    local key = RowKey(row)
    if not key then return end

    BooshiesQuestLogDB.expandedKeys = BooshiesQuestLogDB.expandedKeys or {}
    if BooshiesQuestLogDB.expandedKeys[key] then
        BooshiesQuestLogDB.expandedKeys[key] = nil
    else
        BooshiesQuestLogDB.expandedKeys[key] = true
    end

    pendingScrollKey = key
    pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW

    Refresh()

end

-- Three full-row textures (super-track tint, completed tint, flash overlay)
-- plus the flash AnimationGroup and the row:FlashAttention method.
local function BuildRowBackgrounds(row)

    local superBg = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    superBg:SetAllPoints(row)
    superBg:SetColorTexture(unpack(UI_COLORS.superTrackBg))
    superBg:Hide()
    row.superBg = superBg

    local completeBg = row:CreateTexture(nil, "BACKGROUND")
    completeBg:SetAllPoints(row)
    completeBg:SetColorTexture(unpack(UI_COLORS.completedBg))
    completeBg:Hide()
    row.completeBg = completeBg

    local flashBg = row:CreateTexture(nil, "OVERLAY")
    flashBg:SetAllPoints(row)
    flashBg:SetColorTexture(unpack(UI_COLORS.flashHighlight))
    flashBg:Hide()
    row.flashBg = flashBg

    local flashAnim = flashBg:CreateAnimationGroup()
    local fade = flashAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(FLASH_DURATION)
    fade:SetSmoothing("OUT")
    flashAnim:SetScript("OnFinished", function() flashBg:Hide() end)
    row.flashAnim = flashAnim

    function row:FlashAttention()
        self.flashAnim:Stop()
        self.flashBg:SetAlpha(1)
        self.flashBg:Show()
        self.flashAnim:Play()
    end

end

local function BuildRowSeparator(row)

    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(unpack(UI_COLORS.rowSeparator))
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
    row.separator = sep

end

-- Defines `row.btn` (the clickable area covering the title row) and `row.hover`
-- (the highlight texture, shown by WireRowClick on enter/leave).
local function BuildRowButton(row)

    local btn = CreateFrame("Button", nil, row)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    btn:SetHeight(ROW_HEIGHT)
    btn:RegisterForClicks("LeftButtonUp")
    row.btn = btn

    local hover = btn:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(btn)
    hover:SetColorTexture(unpack(UI_COLORS.rowHover))
    hover:Hide()
    row.hover = hover

end

local function BuildRowArrow(row)

    local arrow = row.btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(14, 14)
    arrow:SetPoint("LEFT", row.btn, "LEFT", 3, TOP_CLUSTER_Y)
    arrow:SetTexture(UI_TEXTURES.plusButton)
    row.arrow = arrow

end

-- Radio-style super-track button on the right edge. The OnClick handler reads
-- row.questID at click time so it stays current as the row gets recycled across
-- different quests by the row pool.
local function BuildRowSuperTrackBtn(row)

    local track = CreateFrame("Button", nil, row.btn)
    track:SetSize(18, 18)
    track:SetPoint("RIGHT", row.btn, "RIGHT", -2, TOP_CLUSTER_Y)
    track:SetHitRectInsets(-4, -4, -4, -4)

    local ring = track:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints(track)
    ring:SetTexture(UI_TEXTURES.radioButton)
    ring:SetTexCoord(0, 0.25, 0, 1)
    ring:SetVertexColor(0.75, 0.75, 0.78)

    local fill = track:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(track)
    fill:SetTexture(UI_TEXTURES.radioButton)
    fill:SetTexCoord(0.25, 0.5, 0, 1)
    fill:SetVertexColor(1.0, 0.82, 0.0)
    fill:Hide()

    local trackHover = track:CreateTexture(nil, "HIGHLIGHT")
    trackHover:SetAllPoints(track)
    trackHover:SetTexture(UI_TEXTURES.radioButton)
    trackHover:SetTexCoord(0.5, 0.75, 0, 1)
    trackHover:SetBlendMode("ADD")

    track._checked = false
    function track:SetChecked(v)
        self._checked = v and true or false
        fill:SetShown(self._checked)
    end
    function track:GetChecked() return self._checked end

    track:SetScript("OnClick", function(self)
        local qid = row.questID
        if not qid or not C_SuperTrack then return end
        if self:GetChecked() then
            C_SuperTrack.SetSuperTrackedQuestID(0)
        else
            C_SuperTrack.SetSuperTrackedQuestID(qid)
        end
    end)
    track:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Super Track")
        GameTooltip:AddLine("Place a waypoint arrow on the map for this quest.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    track:SetScript("OnLeave", GameTooltip_Hide)

    row.trackCheck = track

end

local function BuildRowCompletionIcon(row)

    local completionIcon = row.btn:CreateTexture(nil, "OVERLAY")
    completionIcon:SetSize(14, 14)
    completionIcon:SetPoint("RIGHT", row.trackCheck, "LEFT", -4, 0)
    completionIcon:SetTexture(UI_TEXTURES.checkmark)
    completionIcon:Hide()
    row.completionIcon = completionIcon

end

-- Background bar + foreground fill, plus row:SetProgress(pct, hasAny, complete)
-- which clamps to [0, 1], picks the appropriate fill colour, and falls back to
-- a sensible width when the bar hasn't been measured yet.
local function BuildRowProgressBar(row)

    local barBg = row:CreateTexture(nil, "ARTWORK")
    barBg:SetColorTexture(unpack(UI_COLORS.barBg))
    barBg:SetHeight(BAR_HEIGHT)
    barBg:SetPoint("BOTTOMLEFT", row.btn, "BOTTOMLEFT", 4, BAR_BOTTOM_PAD)
    barBg:SetPoint("BOTTOMRIGHT", row.btn, "BOTTOMRIGHT", -4, BAR_BOTTOM_PAD)
    barBg:Hide()
    row.barBg = barBg

    local barFill = row:CreateTexture(nil, "OVERLAY")
    barFill:SetColorTexture(unpack(UI_COLORS.barFill))
    barFill:SetHeight(BAR_HEIGHT)
    barFill:SetPoint("LEFT", barBg, "LEFT", 0, 0)
    barFill:SetPoint("TOP", barBg, "TOP", 0, 0)
    barFill:SetPoint("BOTTOM", barBg, "BOTTOM", 0, 0)
    barFill:SetWidth(1)
    barFill:Hide()
    row.barFill = barFill

    function row:SetProgress(pct, hasAny, complete)
        if not hasAny then
            self.barBg:Hide()
            self.barFill:Hide()
            return
        end
        self.barBg:Show()
        self.barFill:Show()
        local w = self.barBg:GetWidth()
        if not w or w <= 1 then
            local cw = (content and content:GetWidth()) or ((BooshiesQuestLogDB.width or 280) - 40)
            w = cw - 8
        end
        local clamped = math.min(math.max(pct or 0, 0), 1)
        self.barFill:SetWidth(math.max(1, w * clamped))
        if complete or clamped >= 1 then
            self.barFill:SetColorTexture(unpack(UI_COLORS.barFillComplete))
        else
            self.barFill:SetColorTexture(unpack(UI_COLORS.barFill))
        end
    end

end

-- Title font string + row:SetComplete(flag), which re-anchors the title's right
-- edge to the completion icon when complete (so the icon is visible to its
-- right) or to the track button when not.
local function BuildRowTitle(row)

    local title = row.btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", row.arrow, "RIGHT", 4, 0)
    title:SetPoint("RIGHT", row.trackCheck, "LEFT", -2, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    row.title = title

    function row:SetComplete(flag)
        flag = flag and true or false
        self.completeBg:SetShown(flag)
        self.completionIcon:SetShown(flag)
        self.title:ClearAllPoints()
        self.title:SetPoint("LEFT", self.arrow, "RIGHT", 4, 0)
        if flag then
            self.title:SetPoint("RIGHT", self.completionIcon, "LEFT", -2, 0)
        else
            self.title:SetPoint("RIGHT", self.trackCheck, "LEFT", -2, 0)
        end
    end

end

local function WireRowClick(row)

    local btn = row.btn
    local hover = row.hover

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function() hover:Show() end)
    btn:SetScript("OnLeave", function() hover:Hide() end)

    btn:SetScript("OnClick", function(self, button)

        if not row.questID and not row.achievementID and not row.recipeID and not row.activityID and not row.initiativeID then return end

        -- Ctrl+Left: super-track this quest.
        if IsControlKeyDown() and button == "LeftButton" then
            if row.questID then ToggleSuperTrack(row.questID) end
            return
        end

        -- Ctrl+Right: dump debug metadata (debug mode only).
        if IsControlKeyDown() and button == "RightButton" then
            if BooshiesQuestLogDB.debug then
                if row.questID then
                    DumpQuestMetadata(row.questID)
                elseif row.achievementID then
                    DumpAchievementMetadata(row.achievementID)
                elseif row.recipeID then
                    DumpRecipeMetadata(row.recipeID)
                end
            end
            return
        end

        -- Shift+Left: untrack.
        if IsShiftKeyDown() and button == "LeftButton" then
            UntrackRow(row)
            return
        end

        -- Right: open the appropriate details dialog for this row's kind.
        if button == "RightButton" then
            if row.questID then
                OpenQuestDetails(row.questID)
            elseif row.achievementID then
                OpenAchievementDetails(row.achievementID)
            elseif row.recipeID then
                OpenRecipeDetails(row.recipeID)
            elseif row.activityID then
                OpenMonthlyActivities()
            elseif row.initiativeID then
                OpenEndeavours(row.initiativeID)
            end
            return
        end

        -- Plain left click: toggle expand/collapse.
        OnRowClick(row)

    end)

end

local function CreateRow()

    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)

    BuildRowBackgrounds(row)
    BuildRowSeparator(row)
    BuildRowButton(row)
    BuildRowArrow(row)
    BuildRowSuperTrackBtn(row)
    BuildRowCompletionIcon(row)
    BuildRowProgressBar(row)
    BuildRowTitle(row)
    WireRowClick(row)

    return row

end

local function AcquireRow()
    local row = table.remove(rowPool) or CreateRow()
    row:Show()
    return row
end

local function ReleaseRow(row)

    CollapseRow(row)
    row:Hide()

    if row.superBg then row.superBg:Hide() end
    if row.flashAnim then row.flashAnim:Stop() end
    if row.flashBg then row.flashBg:Hide() end

    row.questID = nil
    row.achievementID = nil
    row.recipeID = nil
    row.activityID = nil
    row.initiativeID = nil
    row.itemKind = nil

    table.insert(rowPool, row)

end


-- =============================================================================
-- SECTION LIFECYCLE
-- =============================================================================

local sectionPool, activeSections = {}, {}
local SECTION_HEIGHT = 22

local function CreateSectionHeader()

    local hdr = CreateFrame("Button", nil, content)
    hdr:SetHeight(SECTION_HEIGHT)
    hdr.itemKind = "section"
    hdr:RegisterForClicks("LeftButtonUp")

    local stripe = hdr:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(hdr)
    stripe:SetColorTexture(unpack(UI_COLORS.sectionStripe))

    local hdrSep = hdr:CreateTexture(nil, "ARTWORK")
    hdrSep:SetColorTexture(unpack(UI_COLORS.sectionSeparator))
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
    hdrSep:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
    hdr.separator = hdrSep

    local hover = hdr:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(hdr)
    hover:SetColorTexture(unpack(UI_COLORS.sectionHover))

    local arrow = hdr:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    arrow:SetTexture(UI_TEXTURES.minusButton)
    hdr.arrow = arrow

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    hdr.title = title

    local count = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(unpack(UI_COLORS.sectionCount))
    hdr.count = count

    hdr:SetScript("OnClick", function(self)

        local cls = self.classification
        if cls == nil then return end

        BooshiesQuestLogDB.collapsedSections = BooshiesQuestLogDB.collapsedSections or {}
        BooshiesQuestLogDB.collapsedSections[cls] = not BooshiesQuestLogDB.collapsedSections[cls]

        pendingScrollKey = RowKey(self)
        pendingScrollExpiresAt = GetTime() + SCROLL_PIN_WINDOW

        Refresh()

    end)

    return hdr

end

local function AcquireSection()
    local hdr = table.remove(sectionPool) or CreateSectionHeader()
    hdr:Show()
    return hdr
end

local function ReleaseSection(hdr)

    hdr:Hide()
    hdr.classification = nil

    table.insert(sectionPool, hdr)

end

local function RenderSection(spec)

    if not spec.items or #spec.items == 0 then return end

    local hdr = AcquireSection()
    hdr.classification = spec.classification
    hdr.title:SetText(spec.title)
    hdr.title:SetTextColor(unpack(UI_COLORS.sectionTitle))

    local collapsed = (BooshiesQuestLogDB.collapsedSections or {})[spec.classification] and true or false

    hdr.count:SetText(#spec.items)
    hdr.arrow:SetTexture(collapsed and UI_TEXTURES.plusButton or UI_TEXTURES.minusButton)
    hdr:SetHeight(SECTION_HEIGHT)

    table.insert(activeSections, hdr)
    table.insert(spec.layout, hdr)

    if collapsed then return end

    for _, item in ipairs(spec.items) do
        local row = spec.populateRow(item)
        if row then
            row:SetHeight(ROW_HEIGHT)
            table.insert(activeRows, row)
            table.insert(spec.layout, row)
        end
    end

end


-- =============================================================================
-- REFRESH PIPELINE
-- =============================================================================

local function BuildQuestGroups(mapID, mapName)

    local snapshot = SnapshotQuestLog()
    AddTaskQuestsToSnapshot(snapshot, mapID)
    local poiSet = BuildPOISet(mapID)

    local groups = {}
    local total = 0

    for qid, info in pairs(snapshot) do
        if ShouldShow(qid, snapshot, poiSet, mapID, mapName) then
            local cls = GetClassification(qid)
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
        if IsQuestWatched(qid) then
            set["quest:" .. qid] = true
        end
    end

    for _, id in ipairs(GetTrackedAchievementList())   do set["ach:"        .. id] = true end
    for _, id in ipairs(GetTrackedRecipeList())        do set["recipe:"     .. id] = true end
    for _, id in ipairs(GetTrackedMonthlyActivities()) do set["activity:"   .. id] = true end
    for _, id in ipairs(GetTrackedInitiativeTasks())   do set["initiative:" .. id] = true end

    return set

end

local function DetectAndShowNewlyTracked(currentKeys)

    if not previousTrackedKeys then
        -- First refresh after load. Capture the baseline silently so we do
        -- not fire for every already-tracked item.
        previousTrackedKeys = currentKeys
        return
    end

    BooshiesQuestLogDB.expandedKeys      = BooshiesQuestLogDB.expandedKeys      or {}
    BooshiesQuestLogDB.collapsedSections = BooshiesQuestLogDB.collapsedSections or {}

    local lastNewKey
    for key in pairs(currentKeys) do
        if not previousTrackedKeys[key] then
            -- Mark expanded even if the zone filter is currently hiding this
            -- item, so it appears expanded next time it becomes visible.
            BooshiesQuestLogDB.expandedKeys[key] = true

            local section = SectionForRowKey(key)
            if section ~= nil then
                BooshiesQuestLogDB.collapsedSections[section] = nil
            end

            pendingFlashKeys[key] = true
            lastNewKey = key
        end
    end

    -- Hidden-by-filter items have no matching row in activeRows, so
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

    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    wipe(activeRows)

    for _, hdr in ipairs(activeSections) do ReleaseSection(hdr) end
    wipe(activeSections)

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

    frame:SetWidth(BooshiesQuestLogDB.width or 280)

end

local function RenderQuestSections(layout, groups, superTracked)

    for _, cls in ipairs(CLASSIFICATION_ORDER) do
        RenderSection({
            classification = cls,
            title          = CLASSIFICATION_NAMES[cls] or ("Class " .. cls),
            items          = groups[cls],
            layout         = layout,
            populateRow    = function(q)

                local row = AcquireRow()
                row.itemKind = "quest"
                row.questID = q.questID
                row.title:SetText(q.title)
                row.title:SetTextColor(unpack(UI_COLORS.itemTitle))

                if row.SetComplete then row:SetComplete(q.isComplete) end

                local isSuper = superTracked == q.questID and superTracked ~= 0
                if row.trackCheck then
                    row.trackCheck:Show()
                    row.trackCheck:SetChecked(isSuper)
                end
                if row.superBg then row.superBg:SetShown(isSuper) end

                local pct, hasObj = GetQuestProgress(q.questID)
                if row.SetProgress then row:SetProgress(pct, hasObj, q.isComplete) end

                return row

            end,
        })
    end

end

local function RenderAchievementSection(layout)

    local hideAchievements = BooshiesQuestLogDB.filterByZone and not BooshiesQuestLogDB.alwaysShowAchievements

    RenderSection({
        classification = "achievements",
        title          = "Achievements",
        items          = hideAchievements and {} or GetTrackedAchievementList(),
        layout         = layout,
        populateRow    = function(achID)

            local id, name, _, completed
            if GetAchievementInfo then
                id, name, _, completed = GetAchievementInfo(achID)
            end
            if not id then return nil end

            local row = AcquireRow()
            row.itemKind = "achievement"
            row.achievementID = achID
            row.title:SetText(name or ("Achievement " .. achID))
            row.title:SetTextColor(unpack(UI_COLORS.itemTitle))

            if row.SetComplete then row:SetComplete(completed) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = GetAchievementProgress(achID)
            if row.SetProgress then row:SetProgress(pct, hasAny, completed) end

            return row

        end,
    })

end

local function RenderRecipeSection(layout)

    RenderSection({
        classification = "recipes",
        title          = "Crafting",
        items          = BooshiesQuestLogDB.filterByZone and {} or GetTrackedRecipeList(),
        layout         = layout,
        populateRow    = function(recipeID)

            local row = AcquireRow()
            row.itemKind = "recipe"
            row.recipeID = recipeID
            row.title:SetText(GetRecipeName(recipeID))
            row.title:SetTextColor(unpack(UI_COLORS.itemTitle))

            if row.SetComplete then row:SetComplete(false) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = GetRecipeProgress(recipeID)
            if row.SetProgress then row:SetProgress(pct, hasAny, false) end

            return row

        end,
    })

end

local function RenderActivitySection(layout)

    RenderSection({
        classification = "activities",
        title          = "Monthly",
        items          = BooshiesQuestLogDB.filterByZone and {} or GetTrackedMonthlyActivities(),
        layout         = layout,
        populateRow    = function(actID)

            local info = GetActivityInfo(actID)
            if not info then return nil end

            local row = AcquireRow()
            row.itemKind = "activity"
            row.activityID = actID
            row.title:SetText(info.activityName or info.name or ("Activity " .. actID))
            row.title:SetTextColor(unpack(UI_COLORS.itemTitle))

            if row.SetComplete then row:SetComplete(info.completed) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = GetActivityProgress(actID)
            if row.SetProgress then row:SetProgress(pct, hasAny, info.completed) end

            return row

        end,
    })

end

local function RenderInitiativeSection(layout)

    RenderSection({
        classification = "initiatives",
        title          = "Endeavours",
        items          = BooshiesQuestLogDB.filterByZone and {} or GetTrackedInitiativeTasks(),
        layout         = layout,
        populateRow    = function(taskID)

            local info = GetInitiativeTaskInfo(taskID)

            local row = AcquireRow()
            row.itemKind = "initiative"
            row.initiativeID = taskID
            row.title:SetText(GetInitiativeTaskName(taskID))
            row.title:SetTextColor(unpack(UI_COLORS.itemTitle))

            if row.SetComplete then row:SetComplete(info and info.completed) end
            if row.trackCheck then row.trackCheck:Hide() end

            local pct, hasAny = GetInitiativeTaskProgress(taskID)
            if row.SetProgress then row:SetProgress(pct, hasAny, info and info.completed) end

            return row

        end,
    })

end

local function ApplyExpansionState(layout)

    local expandedKeys = BooshiesQuestLogDB.expandedKeys or {}
    if not next(expandedKeys) then return end

    -- First layout pass so ExpandRow has resolved frame positions to measure from
    -- before it computes objective wraps and final row heights.
    RelayoutLayout(layout)

    for _, row in ipairs(activeRows) do
        if expandedKeys[RowKey(row)] then
            ExpandRow(row)
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
    for _, r in ipairs(activeRows) do
        if RowKey(r) == pendingScrollKey then
            target = r
            break
        end
    end
    if not target then
        for _, h in ipairs(activeSections) do
            if RowKey(h) == pendingScrollKey then
                target = h
                break
            end
        end
    end

    if target then ScrollIntoView(target) end

end

local function ApplyPendingFlashes()

    if not next(pendingFlashKeys) then return end

    for _, row in ipairs(activeRows) do
        local key = RowKey(row)
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
    if not BooshiesQuestLogDB.enabled then frame:Hide(); return end
    if settingsFrame and settingsFrame:IsShown() then return end

    frame:Show()

    local mapID = GetPlayerZoneMapID()
    local mapName = GetMapName(mapID) or "Unknown"

    local groups, total, snapshot = BuildQuestGroups(mapID, mapName)
    titleText:SetText(("Quests (%d)"):format(total))

    if BooshiesQuestLogDB.collapsed then
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

Refresh = function() SafeCall("Refresh", RefreshUI) end


-- =============================================================================
-- BLIZZARD TRACKER INTEGRATION
-- =============================================================================

local BLIZZARD_QUEST_MODULES = {
    "QuestObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "AchievementObjectiveTracker",
    "ProfessionsRecipeTracker",
    "WorldQuestObjectiveTracker",
    "BonusObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
}

local hookedBlizzardModules = {}

local function AttachSquashHooks(m)

    if hookedBlizzardModules[m] then return end
    hookedBlizzardModules[m] = true

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

local function RelayoutBlizzardTracker()

    if _G.ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then
        pcall(ObjectiveTrackerManager.UpdateAll, ObjectiveTrackerManager)
    elseif ObjectiveTrackerFrame and ObjectiveTrackerFrame.Update then
        pcall(ObjectiveTrackerFrame.Update, ObjectiveTrackerFrame)
    end

end

local function ApplyBlizzardTrackerState()

    local shouldHide = BooshiesQuestLogDB.hideBlizzardTracker and true or false

    for _, name in ipairs(BLIZZARD_QUEST_MODULES) do
        local m = _G[name]
        if m then
            m._bqlForceHidden = shouldHide
            AttachSquashHooks(m)
            if shouldHide then
                if m.Hide then pcall(m.Hide, m) end
                if m.SetHeight then pcall(m.SetHeight, m, 0.0) end
            else
                if m.Show then pcall(m.Show, m) end
            end
        end
    end

    RelayoutBlizzardTracker()

end

local function ApplyFlatSkin(f)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(unpack(UI_COLORS.dialogBackdrop))

    local function edge(side)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(UI_COLORS.dialogBorder))
        if side == "top" then
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            t:SetHeight(1)
        elseif side == "bottom" then
            t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
            t:SetHeight(1)
        elseif side == "left" then
            t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
            t:SetWidth(1)
        elseif side == "right" then
            t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
            t:SetWidth(1)
        end
    end

    edge("top")
    edge("bottom")
    edge("left")
    edge("right")

end


-- =============================================================================
-- SETTINGS UI
-- =============================================================================

local SETTINGS_SPEC = {
    { key = "filterByZone",           label = "Filter Quests by Current Zone" },
    { key = "alwaysShowCampaign",     label = "Always Show Campaign Quests" },
    { key = "alwaysShowAchievements", label = "Always Show Achievements" },
    { key = "hideBlizzardTracker",    label = "Hide Blizzard Activity Tracker" },
    { key = "lockPosition",           label = "Lock Position" },
    { key = "debug",                  label = "Debug Mode" },
}

local function BuildSettingsUI()

    if settingsFrame then return end

    settingsFrame = CreateFrame("Frame", "BooshiesQuestLogSettingsFrame", UIParent)
    settingsFrame:SetFrameStrata("MEDIUM")
    settingsFrame:SetMovable(true)
    settingsFrame:EnableMouse(true)
    settingsFrame:SetClampedToScreen(true)
    settingsFrame:Hide()
    ApplyFlatSkin(settingsFrame)

    local title = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    title:SetPoint("LEFT", settingsFrame, "TOPLEFT", 8, -19)
    title:SetText("Settings")

    settingsFrame.pending = {}
    settingsFrame.rows = {}

    local y = HEADER_OFFSET
    for i, spec in ipairs(SETTINGS_SPEC) do
        local row = CreateFrame("Frame", nil, settingsFrame)
        row:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 10, -y)
        row:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -10, -y)
        row:SetHeight(22)

        local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetScript("OnClick", function(self)
            settingsFrame.pending[spec.key] = self:GetChecked() and true or false
        end)

        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(true)
        label:SetText(spec.label)

        row.checkbox = cb
        row.key = spec.key
        settingsFrame.rows[i] = row
        y = y + 24
    end

    local backBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    backBtn:SetSize(70, 22)
    backBtn:SetPoint("BOTTOMLEFT", settingsFrame, "BOTTOMLEFT", 10, 10)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function() HideSettings() end)

    local helpBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    helpBtn:SetSize(70, 22)
    helpBtn:SetPoint("BOTTOM", settingsFrame, "BOTTOM", 0, 10)
    helpBtn:SetText("Help")
    helpBtn:SetScript("OnClick", function() ShowHelp() end)

    local applyBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    applyBtn:SetSize(70, 22)
    applyBtn:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -10, 10)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function() ApplySettings() end)

    settingsFrame.backBtn = backBtn
    settingsFrame.helpBtn = helpBtn
    settingsFrame.applyBtn = applyBtn

    local totalHeight = HEADER_OFFSET + (#SETTINGS_SPEC * 24) + 44
    settingsFrame:SetSize(BooshiesQuestLogDB.width or 280, totalHeight)

end

function ShowSettings()

    BuildSettingsUI()
    if not frame then return end

    local right = frame:GetRight()
    local top = frame:GetTop()

    if right and top then
        local uiRight = UIParent:GetRight() or 0
        local uiTop = UIParent:GetTop() or 0
        settingsFrame:ClearAllPoints()
        settingsFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", right - uiRight, top - uiTop)
    end

    settingsFrame:SetWidth(frame:GetWidth())

    for _, row in ipairs(settingsFrame.rows) do
        row.checkbox:SetChecked(BooshiesQuestLogDB[row.key] and true or false)
    end

    wipe(settingsFrame.pending)
    frame:Hide()
    settingsFrame:Show()

end

function HideSettings()

    if settingsFrame then settingsFrame:Hide() end
    if frame then frame:Show() end
    if Refresh then Refresh() end

end

function ApplySettings()

    if not settingsFrame then
        HideSettings()
        return
    end

    for key, val in pairs(settingsFrame.pending) do
        BooshiesQuestLogDB[key] = val
    end
    wipe(settingsFrame.pending)

    if frame and frame.filterBtn then
        frame.filterBtn:SetChecked(BooshiesQuestLogDB.filterByZone)
    end

    ApplyBlizzardTrackerState()
    HideSettings()
    Refresh()

end


-- =============================================================================
-- HELP UI
-- =============================================================================

local helpFrame

-- Gold highlight derived from our central palette so the help cheatsheet
-- matches the section-title colour by reference, not coincidence.
local GOLD = ColorToEscape(UI_COLORS.sectionTitle)
local RESET = "|r"

local HELP_BODY_TEXT =
    "• " .. GOLD .. "Left Click:" .. RESET .. " Expand/Collapse the quest/activity.\n"
    .. "• " .. GOLD .. "Right Click:" .. RESET .. " Open quest/activity in relevant window.\n"
    .. "• " .. GOLD .. "Shift + Left Click:" .. RESET .. " Stop tracking quest/activity.\n"
    .. "• " .. GOLD .. "Ctrl + Left Click:" .. RESET .. " \"Super Track\" quest/activity (shows way point).\n"
    .. "• " .. GOLD .. "Ctrl + Right Click:" .. RESET .. " Dump debug information about quest/activity.\n"
    .. "\n"
    .. "You can shrink the entire quest log down by " .. GOLD .. "clicking on the title" .. RESET .. "."

local function BuildHelpUI()

    if helpFrame then return end

    helpFrame = CreateFrame("Frame", "BooshiesQuestLogHelpFrame", UIParent)
    helpFrame:SetSize(480, 260)
    helpFrame:SetFrameStrata("HIGH")
    helpFrame:EnableMouse(true)
    helpFrame:SetClampedToScreen(true)
    helpFrame:Hide()
    ApplyFlatSkin(helpFrame)

    -- Closes on Escape.
    tinsert(UISpecialFrames, "BooshiesQuestLogHelpFrame")

    local title = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    title:SetPoint("LEFT", helpFrame, "TOPLEFT", 8, -19)
    title:SetText("Booshie's Quest Log")

    -- Set the FontString's vertex colour from our palette so the inline
    -- |r resets in HELP_BODY_TEXT return to our white instead of GameFontNormal's
    -- default gold.
    local body = helpFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetTextColor(unpack(UI_COLORS.itemTitle))
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", helpFrame, "RIGHT", -12, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetWordWrap(true)
    body:SetText(HELP_BODY_TEXT)

    local closeBtn = CreateFrame("Button", nil, helpFrame, "UIPanelButtonTemplate")
    closeBtn:SetSize(70, 22)
    closeBtn:SetPoint("BOTTOM", helpFrame, "BOTTOM", 0, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() HideHelp() end)

    helpFrame.title = title
    helpFrame.body = body
    helpFrame.closeBtn = closeBtn

end

function ShowHelp()

    BuildHelpUI()

    helpFrame:ClearAllPoints()
    helpFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    helpFrame:Show()

end

function HideHelp()

    if helpFrame then helpFrame:Hide() end
    BooshiesQuestLogDB.helpShown = true

end


-- =============================================================================
-- MAIN UI CONSTRUCTION
-- =============================================================================

local function BuildMainFrame()

    frame = CreateFrame("Frame", "BooshiesQuestLogFrame", UIParent)
    frame:SetSize(BooshiesQuestLogDB.width or 280, 200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    ApplyFlatSkin(frame)

end

local function BuildHeader()

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    header:SetHeight(30)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not BooshiesQuestLogDB.lockPosition then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    frame.header = header

    titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    titleText:SetPoint("LEFT", header, "TOPLEFT", 4, -11)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("Quests")

    local titleBtn = CreateFrame("Button", nil, header)
    titleBtn:SetAllPoints(titleText)
    titleBtn:SetHitRectInsets(-3, -3, -2, -2)
    titleBtn:SetFrameLevel(header:GetFrameLevel() + 2)
    titleBtn:RegisterForClicks("LeftButtonUp")
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function()
        if not BooshiesQuestLogDB.lockPosition then frame:StartMoving() end
    end)
    titleBtn:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)
    titleBtn:SetScript("OnClick", function()
        BooshiesQuestLogDB.collapsed = not BooshiesQuestLogDB.collapsed
        Refresh()
    end)
    frame.titleBtn = titleBtn

    zoneText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetTextColor(unpack(UI_COLORS.zoneText))

end

local function BuildHeaderButtons()

    local header = frame.header

    local cogBtn = CreateFrame("Button", nil, header)
    cogBtn:SetSize(16, 16)
    cogBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -11)
    cogBtn:SetNormalTexture(UI_TEXTURES.cog)

    local cogHover = cogBtn:CreateTexture(nil, "HIGHLIGHT")
    cogHover:SetAllPoints(cogBtn)
    cogHover:SetColorTexture(unpack(UI_COLORS.cogHover))

    cogBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Settings")
        GameTooltip:Show()
    end)
    cogBtn:SetScript("OnLeave", GameTooltip_Hide)
    cogBtn:SetScript("OnClick", function() ShowSettings() end)
    frame.cogBtn = cogBtn

    local filterBtn = CreateFrame("CheckButton", "BooshiesQuestLogFilterToggle", header, "UICheckButtonTemplate")
    filterBtn:SetSize(18, 18)
    filterBtn:SetPoint("RIGHT", cogBtn, "LEFT", -6, 0)
    filterBtn:SetChecked(BooshiesQuestLogDB.filterByZone)
    filterBtn:SetHitRectInsets(-3, -3, -3, -3)

    local filterLabel = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("RIGHT", filterBtn, "LEFT", -2, 0)
    filterLabel:SetText("Zone")

    filterBtn:SetScript("OnClick", function(self)
        BooshiesQuestLogDB.filterByZone = self:GetChecked()
        Refresh()
    end)
    filterBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Zone Filter")
        GameTooltip:AddLine(self:GetChecked()
            and "Showing only quests in your current zone."
            or "Showing all quests in your log.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", GameTooltip_Hide)
    frame.filterBtn = filterBtn

    local collapseAllBtn = CreateFrame("Button", nil, frame)
    local collapseAllText = collapseAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collapseAllText:SetPoint("RIGHT", collapseAllBtn, "RIGHT", 0, 0)
    collapseAllText:SetText("collapse all")
    collapseAllText:SetTextColor(unpack(UI_COLORS.collapseAllText))

    collapseAllBtn:SetSize((collapseAllText:GetStringWidth() or 60) + 4, 14)
    collapseAllBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -22)
    collapseAllBtn:SetFrameLevel((header:GetFrameLevel() or frame:GetFrameLevel()) + 5)
    collapseAllBtn:SetHitRectInsets(-3, -3, -3, -3)

    collapseAllBtn:SetScript("OnEnter", function() collapseAllText:SetTextColor(unpack(UI_COLORS.collapseAllHover)) end)
    collapseAllBtn:SetScript("OnLeave", function() collapseAllText:SetTextColor(unpack(UI_COLORS.collapseAllText)) end)
    collapseAllBtn:SetScript("OnClick", function()
        BooshiesQuestLogDB.expandedKeys = {}
        BooshiesQuestLogDB.collapsedSections = BooshiesQuestLogDB.collapsedSections or {}
        for _, cls in ipairs(CLASSIFICATION_ORDER) do
            BooshiesQuestLogDB.collapsedSections[cls] = true
        end
        for _, k in ipairs({ "achievements", "recipes", "activities", "initiatives" }) do
            BooshiesQuestLogDB.collapsedSections[k] = true
        end
        Refresh()
    end)
    frame.collapseAllBtn = collapseAllBtn

end

local function BuildScrollArea()

    scrollFrame = CreateFrame("ScrollFrame", "BooshiesQuestLogScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -HEADER_OFFSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, BOTTOM_PAD)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize((BooshiesQuestLogDB.width or 280) - 40, 1)
    scrollFrame:SetScrollChild(content)

    local bar = scrollFrame.ScrollBar or _G["BooshiesQuestLogScrollScrollBar"]
    if bar then
        bar:HookScript("OnShow", function(self)
            if scrollFrame._bqlForceHidden then self:Hide() end
        end)
        if bar.SetValueStep then bar:SetValueStep(ROW_HEIGHT) end
        if bar.SetStepsPerPage then bar:SetStepsPerPage(4) end
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll() or 0
        local max = self:GetVerticalScrollRange() or 0
        local step = ROW_HEIGHT
        local new = cur - delta * step
        if new < 0 then new = 0 elseif new > max then new = max end
        self:SetVerticalScroll(new)
    end)

end

local function BuildResizer()

    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(44, 6)
    resizer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
    resizer:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizer:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

    local grip = resizer:CreateTexture(nil, "OVERLAY")
    grip:SetAllPoints(resizer)
    grip:SetColorTexture(unpack(UI_COLORS.resizeGrip))

    local gripHover = resizer:CreateTexture(nil, "HIGHLIGHT")
    gripHover:SetAllPoints(resizer)
    gripHover:SetColorTexture(unpack(UI_COLORS.resizeGripHover))

    local function dragUpdate(self)
        local cur = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local delta = self._dragStartY - cur
        local newMax = math.floor(self._dragStartMax + delta + 0.5)
        if newMax < MIN_MAX_HEIGHT then newMax = MIN_MAX_HEIGHT end
        if newMax > MAX_RESIZE_HEIGHT then newMax = MAX_RESIZE_HEIGHT end
        if newMax ~= BooshiesQuestLogDB.maxHeight then
            BooshiesQuestLogDB.maxHeight = newMax
            Refresh()
        end
    end

    resizer:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self._dragStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        self._dragStartMax = BooshiesQuestLogDB.maxHeight or DEFAULT_MAX_HEIGHT
        self:SetScript("OnUpdate", dragUpdate)
    end)

    resizer:SetScript("OnMouseUp", function(self)
        self._dragStartY = nil
        self:SetScript("OnUpdate", nil)
    end)

    frame.resizer = resizer

end

local function BuildUI()

    if frame then return end

    BuildMainFrame()
    BuildHeader()
    BuildHeaderButtons()
    BuildScrollArea()
    BuildResizer()

    RestorePosition()
    SavePosition()

end


-- =============================================================================
-- SUPER-TRACK STATE
-- =============================================================================

local function UpdateSuperTrackState()

    local current = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    for _, row in ipairs(activeRows) do
        local isSuper = row.questID and row.questID == current and current ~= 0
        if row.trackCheck then row.trackCheck:SetChecked(isSuper) end
        if row.superBg then row.superBg:SetShown(isSuper and true or false) end
    end

end

ToggleSuperTrack = function(questID)

    if not questID or not C_SuperTrack then return end

    local cur = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0

    if cur == questID then
        C_SuperTrack.SetSuperTrackedQuestID(0)
    else
        C_SuperTrack.SetSuperTrackedQuestID(questID)
    end

end


-- =============================================================================
-- EVENTS
-- =============================================================================

local pending = false

local function Reschedule()

    if pending then return end
    pending = true

    C_Timer.After(0.05, function()
        pending = false
        SafeCall("Reschedule", Refresh)
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
    SafeCall("OnEvent:" .. tostring(event), function()

        if event == "ADDON_LOADED" then
            if arg1 == ADDON_NAME then
                InitDB()
                if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo then
                    pcall(C_NeighborhoodInitiative.RequestNeighborhoodInitiativeInfo)
                end
            end

        elseif event == "PLAYER_LOGIN" then
            BuildUI()
            ApplyBlizzardTrackerState()
            Reschedule()

            if not BooshiesQuestLogDB.helpShown then ShowHelp() end

        elseif event == "PLAYER_ENTERING_WORLD" then
            ApplyBlizzardTrackerState()
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


-- =============================================================================
-- SLASH COMMANDS
-- =============================================================================

local function PrintStatus(label, value)
    print(("|cff4fc3f7BQL:|r %s %s"):format(label, value and "|cff00ff00on|r" or "|cffff6666off|r"))
end

SLASH_BOOSHIESQUESTLOG1 = "/bql"
SLASH_BOOSHIESQUESTLOG2 = "/booshiesquestlog"
SlashCmdList["BOOSHIESQUESTLOG"] = function(msg)

    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "toggle" then
        BooshiesQuestLogDB.enabled = not BooshiesQuestLogDB.enabled
        PrintStatus("tracker", BooshiesQuestLogDB.enabled)
        Refresh()
    elseif msg == "reset" then
        BooshiesQuestLogDB.point = DEFAULTS.point
        BooshiesQuestLogDB.maxHeight = DEFAULTS.maxHeight
        BooshiesQuestLogDB.helpShown = false
        RestorePosition()
        Refresh()
        ShowHelp()
        print("|cff4fc3f7BQL:|r position + height reset")
    elseif msg == "refresh" then
        Refresh()
    else
        print("|cff4fc3f7BQL:|r /bql [toggle||reset||refresh]")
    end

end

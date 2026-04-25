local ADDON_NAME = ...

BooshiesQuestLogDB = BooshiesQuestLogDB or {}

local _errSeen = {}
local function safeCall(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and err then
        local msg = tostring(err)
        if not _errSeen[msg] then
            _errSeen[msg] = true
            print(("|cffff6666BQL error [%s]:|r %s"):format(label or "?", msg))
        end
    end
    return ok
end

-- Averages progress across a list of objective-shaped entries.
-- Each entry may carry { finished, numFulfilled, numRequired }; entries lacking
-- progress info still count toward the denominator so the average matches what
-- a user would expect ("3 of 5 done" with 2 unknowns reads as 3/5, not 3/3).
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

-- Returns the first value at obj[k] (for k in keys) that is a non-empty table,
-- or nil. Used to probe WoW API records that ship the same data under different
-- field names across game versions.
local function firstNonEmptyField(obj, keys)
    if type(obj) ~= "table" then return nil end
    for _, k in ipairs(keys) do
        local v = obj[k]
        if type(v) == "table" and #v > 0 then return v end
    end
    return nil
end

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

local CLASSIFICATION_COLORS = {
    [0]  = { 1.00, 0.82, 0.25 },
    [1]  = { 1.00, 0.50, 1.00 },
    [2]  = { 0.40, 0.78, 1.00 },
    [3]  = { 0.70, 1.00, 0.70 },
    [4]  = { 0.90, 0.70, 1.00 },
    [5]  = { 0.70, 0.85, 0.85 },
    [6]  = { 0.55, 0.90, 0.55 },
    [7]  = { 1.00, 1.00, 1.00 },
    [8]  = { 0.90, 0.85, 0.55 },
    [9]  = { 1.00, 0.45, 0.45 },
    [10] = { 0.40, 0.90, 1.00 },
}

local CLASSIFICATION_ORDER = { 2, 0, 4, 5, 1, 6, 9, 7, 3, 10, 8 }

local function InitDB()
    for k, v in pairs(DEFAULTS) do
        if BooshiesQuestLogDB[k] == nil then BooshiesQuestLogDB[k] = v end
    end
    if type(BooshiesQuestLogDB.expandedKey) == "string" then
        BooshiesQuestLogDB.expandedKeys = BooshiesQuestLogDB.expandedKeys or {}
        BooshiesQuestLogDB.expandedKeys[BooshiesQuestLogDB.expandedKey] = true
        BooshiesQuestLogDB.expandedKey = nil
    end
    local screenH = UIParent and UIParent:GetHeight() or 768
    if BooshiesQuestLogDB.maxHeight and BooshiesQuestLogDB.maxHeight > screenH - 60 then
        BooshiesQuestLogDB.maxHeight = math.max(DEFAULTS.maxHeight, math.floor(screenH * 0.5))
    end
end

local function GetPlayerZoneMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

local function GetMapName(mapID)
    if not mapID then return nil end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name
end

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

local function AddTaskQuestsToSnapshot(snapshot, mapID)
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
    return 7
end

local function GetTrackedAchievementList()
    local list = {}
    if _G.GetTrackedAchievements then
        local packed = { GetTrackedAchievements() }
        for _, id in ipairs(packed) do
            if id and id ~= 0 then list[#list + 1] = id end
        end
    end
    if #list == 0 and C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        local t = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        if t ~= nil then
            local ok, ids = pcall(C_ContentTracking.GetTrackedIDs, t)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    if id and id ~= 0 then list[#list + 1] = id end
                end
            end
        end
    end
    return list
end

local function GetAchievementCriteriaList(achID)
    if not _G.GetAchievementNumCriteria or not _G.GetAchievementCriteriaInfo then return {} end
    local num = GetAchievementNumCriteria(achID) or 0
    local list = {}
    for i = 1, num do
        local cstr, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achID, i)
        list[i] = {
            text = cstr or "",
            finished = completed and true or false,
            numFulfilled = quantity or 0,
            numRequired = reqQuantity or 0,
        }
    end
    return list
end

local function GetAchievementProgress(achID)
    local list = GetAchievementCriteriaList(achID)
    if #list == 0 then
        local completed = false
        if GetAchievementInfo then
            local _, _, _, done = GetAchievementInfo(achID)
            completed = done and true or false
        end
        return completed and 1 or 0, completed
    end
    return ComputeProgress(list)
end

local function GetTrackedRecipeList()
    local list = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked then return list end
    local seen = {}
    local function collect(isRecraft)
        local ok, tracked = pcall(C_TradeSkillUI.GetRecipesTracked, isRecraft)
        if ok and type(tracked) == "table" then
            for _, id in ipairs(tracked) do
                if id and not seen[id] then
                    seen[id] = true
                    list[#list + 1] = id
                end
            end
        end
    end
    collect(false)
    collect(true)
    return list
end

local function GetRecipeName(recipeID)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and info and info.name then return info.name end
    end
    return "Recipe " .. tostring(recipeID)
end

local function ItemCount(itemID)
    if not itemID then return 0 end
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, itemID, false, false, true)
        if ok and n then return n end
    end
    if _G.GetItemCount then
        local ok, n = pcall(GetItemCount, itemID, false, false, true)
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
        local reagent = slot.reagents and slot.reagents[1]
        if needed > 0 and reagent and reagent.itemID then
            local have = ItemCount(reagent.itemID)
            reagents[#reagents + 1] = {
                text = ItemName(reagent.itemID),
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
        local ok, tracked = pcall(C_PerksActivities.GetTrackedPerksActivities)
        if ok and type(tracked) == "table" and #tracked > 0 then
            for _, id in ipairs(tracked) do
                if id then list[#list + 1] = id end
            end
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
        local ok, tracked = pcall(C_NeighborhoodInitiative.GetTrackedInitiativeTasks)
        if ok and type(tracked) == "table" and #tracked > 0 then
            for _, id in ipairs(tracked) do
                if id then list[#list + 1] = id end
            end
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
    local criteria = firstNonEmptyField(info, { "criteriaList", "requirementsList", "objectives", "conditions" })
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
                    if n and m then have = tonumber(n) or 0; need = tonumber(m) or 0 end
                end
                list[#list + 1] = { text = text, finished = finished and true or false, numFulfilled = have, numRequired = need }
            end
        end
    end
    if #list == 0 and info.description and info.description ~= "" then
        list[#list + 1] = { text = info.description, finished = info.completed and true or false, numFulfilled = 0, numRequired = 0 }
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

    local criteria = firstNonEmptyField(info, { "criteriaList", "requirementsList", "conditions" })

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
                    if n and m then have = tonumber(n) or 0; need = tonumber(m) or 0 end
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

local ROW_HEIGHT = 26
local ROW_GAP = 6
local BAR_HEIGHT = 3
local BAR_BOTTOM_PAD = 3
local MIN_MAX_HEIGHT = 150

local frame, titleText, zoneText, content, scrollFrame, settingsFrame
local ToggleSuperTrack
local activeRows, rowPool = {}, {}

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

local HEADER_OFFSET = 46
local BOTTOM_PAD = 16
local Refresh

local function RelayoutLayout(layout)
    layout = layout or {}
    local y = 0
    local count = #layout
    local trailingGap = 0
    for i, item in ipairs(layout) do
        local isSection = item._kind == "section"
        if not isSection and not item.expanded then item:SetHeight(ROW_HEIGHT) end
        if item.separator then
            if item._kind == "section" then
                local nextItem = layout[i + 1]
                local hasContentBelow = nextItem and nextItem._kind ~= "section"
                item.separator:SetShown(hasContentBelow)
            else
                item.separator:SetShown(true)
            end
        end
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

local function CollapseRow(row)
    row.expanded = false
    row.arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    if row.objFrame then row.objFrame:Hide() end
    row:SetHeight(ROW_HEIGHT)
end

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
    local n, m, rest = text:match("^(%d+)%s*/%s*(%d+)%s+(.*)$")
    if n and m and rest and rest ~= "" then
        return rest, n .. "/" .. m
    end
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

local function ExpandRow(row)
    row.expanded = true
    row.arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")

    local contentW = (content and content:GetWidth()) or ((BooshiesQuestLogDB.width or 280) - 40)
    local objW = math.max(contentW - OBJ_LEFT_INDENT - OBJ_RIGHT_MARGIN, 60)

    local objectives
    if row.itemKind == "achievement" then
        objectives = GetAchievementCriteriaList(row.achievementID)
    elseif row.itemKind == "recipe" then
        objectives = GetRecipeReagents(row.recipeID)
    elseif row.itemKind == "activity" then
        objectives = GetActivityObjectives(row.activityID)
    elseif row.itemKind == "initiative" then
        objectives = GetInitiativeTaskObjectives(row.initiativeID)
    else
        objectives = C_QuestLog.GetQuestObjectives(row.questID) or {}
    end

    local parts = {}
    local maxCountW = 0
    for i, obj in ipairs(objectives) do
        local desc, count = SplitObjective(obj)
        if obj.finished then count = nil end
        parts[i] = { desc = desc, count = count, finished = obj.finished }
        if count and count ~= "" then
            local w = MeasureText(count)
            if w > maxCountW then maxCountW = w end
        end
    end

    local countColW = math.ceil(maxCountW)
    local hasCountCol = countColW > 0
    local descX = COL_MARKER_W + COL_GAP + (hasCountCol and (countColW + COL_GAP) or 0)
    local descW = math.max(objW - descX, 40)

    if not row.objFrame then
        row.objFrame = CreateFrame("Frame", nil, row)
        row.objLines = {}
    end
    row.objFrame:ClearAllPoints()
    row.objFrame:SetPoint("TOPLEFT", row, "TOPLEFT", OBJ_LEFT_INDENT, -(ROW_HEIGHT + OBJ_TOP_PAD))
    row.objFrame:SetWidth(objW)
    row.objFrame:Show()

    local function getEntry(i)
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

    local function placeObj(i, y, part)
        local e = getEntry(i)
        local isFinished = part.finished
        local color = isFinished and { 0.55, 0.9, 0.55 } or { 0.95, 0.82, 0.36 }

        e.tex:ClearAllPoints()
        e.dot:ClearAllPoints()
        if isFinished then
            e.tex:SetPoint("CENTER", row.objFrame, "TOPLEFT", COL_MARKER_W / 2, -y - LINE_VCENTER)
            e.tex:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
            e.tex:Show()
            e.dot:Hide()
        else
            e.dot:SetPoint("CENTER", row.objFrame, "TOPLEFT", COL_MARKER_W / 2, -y - LINE_VCENTER)
            e.dot:SetJustifyH("CENTER")
            e.dot:SetText("•")
            e.dot:SetTextColor(0.75, 0.75, 0.75)
            e.dot:Show()
            e.tex:Hide()
        end

        e.count:ClearAllPoints()
        if hasCountCol and part.count then
            e.count:SetPoint("TOPLEFT", row.objFrame, "TOPLEFT", COL_MARKER_W + COL_GAP, -y)
            e.count:SetWidth(countColW)
            e.count:SetText(part.count)
            e.count:SetTextColor(color[1], color[2], color[3])
            e.count:Show()
        else
            e.count:Hide()
        end

        e.desc:ClearAllPoints()
        e.desc:SetPoint("TOPLEFT", row.objFrame, "TOPLEFT", descX, -y)
        e.desc:SetWidth(descW)
        e.desc:SetWordWrap(true)
        e.desc:SetTextColor(color[1], color[2], color[3])
        e.desc:SetText(part.desc)
        e.desc:Show()

        return y + e.desc:GetStringHeight() + OBJ_LINE_GAP
    end

    local y = 0
    local idx = 0
    for i, part in ipairs(parts) do
        idx = i
        y = placeObj(i, y, part)
    end

    if row.itemKind ~= "achievement" and row.questID and C_QuestLog.IsComplete(row.questID) then
        idx = idx + 1
        y = placeObj(idx, y, { desc = "Ready to turn in", count = nil, finished = true })
    end

    for i = idx + 1, #row.objLines do
        local e = row.objLines[i]
        if type(e) == "table" then
            if e.tex then e.tex:Hide() end
            if e.dot then e.dot:Hide() end
            if e.count then e.count:Hide() end
            if e.desc then e.desc:Hide() end
        end
    end

    local totalY = math.max(y - OBJ_LINE_GAP, 1)
    row.objFrame:SetHeight(totalY)
    row:SetHeight(ROW_HEIGHT + OBJ_TOP_PAD + totalY + OBJ_BOTTOM_PAD)
end

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

local function tryCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok = pcall(fn, ...)
    return ok
end

local function UntrackRow(row)
    if not row then return end
    if row.questID then
        if C_QuestLog then
            tryCall(C_QuestLog.RemoveQuestWatch, row.questID)
            tryCall(C_QuestLog.RemoveWorldQuestWatch, row.questID)
        end
    elseif row.achievementID then
        local id = row.achievementID
        local t = Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.Achievement
        local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Player) or 2
        if C_ContentTracking and C_ContentTracking.StopTracking and t then
            tryCall(C_ContentTracking.StopTracking, t, id, stopType)
        end
        tryCall(_G.RemoveTrackedAchievement, id)
    elseif row.recipeID then
        if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
            tryCall(C_TradeSkillUI.SetRecipeTracked, row.recipeID, false, false)
            tryCall(C_TradeSkillUI.SetRecipeTracked, row.recipeID, false, true)
        end
    elseif row.activityID then
        if C_PerksActivities then
            for fname, fn in pairs(C_PerksActivities) do
                if type(fn) == "function" then
                    local lk = fname:lower()
                    if lk:find("untrack") or (lk:find("remove") and (lk:find("track") or lk:find("activit"))) then
                        if tryCall(fn, row.activityID) then break end
                    end
                end
            end
            for fname, fn in pairs(C_PerksActivities) do
                if type(fn) == "function" then
                    local lk = fname:lower()
                    if lk:find("^set") and lk:find("track") then
                        tryCall(fn, row.activityID, false)
                    end
                end
            end
        end
    elseif row.initiativeID then
        if C_NeighborhoodInitiative then
            tryCall(C_NeighborhoodInitiative.RemoveTrackedInitiativeTask, row.initiativeID)
        end
    end
end

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
            if q.questID == questID then onThisMap = true; break end
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

local function RowKey(row)
    if not row then return nil end
    if row.itemKind == "achievement" and row.achievementID then
        return "ach:" .. row.achievementID
    end
    if row.itemKind == "recipe" and row.recipeID then
        return "recipe:" .. row.recipeID
    end
    if row.itemKind == "activity" and row.activityID then
        return "activity:" .. row.activityID
    end
    if row.itemKind == "initiative" and row.initiativeID then
        return "initiative:" .. row.initiativeID
    end
    if row.questID then
        return "quest:" .. row.questID
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
    Refresh()
end

local function CreateRow()
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_HEIGHT)

    local superBg = row:CreateTexture(nil, "BACKGROUND", nil, -2)
    superBg:SetAllPoints(row)
    superBg:SetColorTexture(1.0, 0.82, 0.0, 0.12)
    superBg:Hide()
    row.superBg = superBg

    local completeBg = row:CreateTexture(nil, "BACKGROUND")
    completeBg:SetAllPoints(row)
    completeBg:SetColorTexture(0.12, 0.35, 0.15, 0.45)
    completeBg:Hide()
    row.completeBg = completeBg

    local sep = row:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.07)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
    row.separator = sep

    local btn = CreateFrame("Button", nil, row)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    btn:SetHeight(ROW_HEIGHT)
    btn:RegisterForClicks("LeftButtonUp")
    row.btn = btn

    local hover = btn:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(btn)
    hover:SetColorTexture(1, 1, 1, 0.06)
    hover:Hide()

    local TOP_CLUSTER_Y = 3

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(14, 14)
    arrow:SetPoint("LEFT", btn, "LEFT", 3, TOP_CLUSTER_Y)
    arrow:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    row.arrow = arrow

    local track = CreateFrame("Button", nil, btn)
    track:SetSize(18, 18)
    track:SetPoint("RIGHT", btn, "RIGHT", -2, TOP_CLUSTER_Y)
    track:SetHitRectInsets(-4, -4, -4, -4)

    local ring = track:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints(track)
    ring:SetTexture("Interface\\Buttons\\UI-RadioButton")
    ring:SetTexCoord(0, 0.25, 0, 1)
    ring:SetVertexColor(0.75, 0.75, 0.78)

    local fill = track:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(track)
    fill:SetTexture("Interface\\Buttons\\UI-RadioButton")
    fill:SetTexCoord(0.25, 0.5, 0, 1)
    fill:SetVertexColor(1.0, 0.82, 0.0)
    fill:Hide()

    local trackHover = track:CreateTexture(nil, "HIGHLIGHT")
    trackHover:SetAllPoints(track)
    trackHover:SetTexture("Interface\\Buttons\\UI-RadioButton")
    trackHover:SetTexCoord(0.5, 0.75, 0, 1)
    trackHover:SetBlendMode("ADD")

    track._checked = false
    function track:SetChecked(v) self._checked = v and true or false; fill:SetShown(self._checked) end
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

    local completionIcon = btn:CreateTexture(nil, "OVERLAY")
    completionIcon:SetSize(14, 14)
    completionIcon:SetPoint("RIGHT", track, "LEFT", -4, 0)
    completionIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
    completionIcon:Hide()
    row.completionIcon = completionIcon

    local barBg = row:CreateTexture(nil, "ARTWORK")
    barBg:SetColorTexture(0.22, 0.22, 0.24, 0.95)
    barBg:SetHeight(BAR_HEIGHT)
    barBg:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 4, BAR_BOTTOM_PAD)
    barBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, BAR_BOTTOM_PAD)
    barBg:Hide()
    row.barBg = barBg

    local barFill = row:CreateTexture(nil, "OVERLAY")
    barFill:SetColorTexture(0.95, 0.82, 0.36, 0.9)
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
            self.barFill:SetColorTexture(0.35, 0.9, 0.35, 0.9)
        else
            self.barFill:SetColorTexture(0.95, 0.82, 0.36, 0.9)
        end
    end

    local title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    title:SetPoint("RIGHT", track, "LEFT", -2, 0)
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

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function() hover:Show() end)
    btn:SetScript("OnLeave", function() hover:Hide() end)
    btn:SetScript("OnClick", function(self, button)
        if not row.questID and not row.achievementID and not row.recipeID and not row.activityID and not row.initiativeID then return end
        if IsControlKeyDown() and button == "LeftButton" then
            if row.questID then ToggleSuperTrack(row.questID) end
            return
        end
        if IsControlKeyDown() and button == "RightButton" then
            if BooshiesQuestLogDB.debug and row.questID then
                DumpQuestMetadata(row.questID)
            end
            return
        end
        if IsShiftKeyDown() and button == "LeftButton" then
            UntrackRow(row)
            return
        end
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
        OnRowClick(row)
    end)

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
    row.questID = nil
    row.achievementID = nil
    row.recipeID = nil
    row.activityID = nil
    row.initiativeID = nil
    row.itemKind = nil
    table.insert(rowPool, row)
end

local sectionPool, activeSections = {}, {}
local SECTION_HEIGHT = 22

local function CreateSectionHeader()
    local hdr = CreateFrame("Button", nil, content)
    hdr:SetHeight(SECTION_HEIGHT)
    hdr._kind = "section"
    hdr:RegisterForClicks("LeftButtonUp")

    local stripe = hdr:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(hdr)
    stripe:SetColorTexture(1, 1, 1, 0.14)

    local hdrSep = hdr:CreateTexture(nil, "ARTWORK")
    hdrSep:SetColorTexture(1, 1, 1, 0.07)
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
    hdrSep:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
    hdr.separator = hdrSep

    local hover = hdr:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(hdr)
    hover:SetColorTexture(1, 1, 1, 0.07)

    local arrow = hdr:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    hdr.arrow = arrow

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    hdr.title = title

    local count = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(0.85, 0.85, 0.85)
    hdr.count = count

    hdr:SetScript("OnClick", function(self)
        local cls = self.classification
        if cls == nil then return end
        BooshiesQuestLogDB.collapsedSections = BooshiesQuestLogDB.collapsedSections or {}
        BooshiesQuestLogDB.collapsedSections[cls] = not BooshiesQuestLogDB.collapsedSections[cls]
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

local refreshImpl = function()
    if not frame then return end
    if not BooshiesQuestLogDB.enabled then frame:Hide(); return end
    if settingsFrame and settingsFrame:IsShown() then return end
    frame:Show()

    local mapID = GetPlayerZoneMapID()
    local mapName = GetMapName(mapID) or "Unknown"

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

    titleText:SetText(("Quests (%d)"):format(total))

    if BooshiesQuestLogDB.collapsed then
        for _, row in ipairs(activeRows) do ReleaseRow(row) end
        wipe(activeRows)
        for _, hdr in ipairs(activeSections) do ReleaseSection(hdr) end
        wipe(activeSections)
        if scrollFrame then scrollFrame:Hide() end
        if frame.filterBtn then frame.filterBtn:Hide() end
        if frame.cogBtn then frame.cogBtn:Hide() end
        if frame.collapseAllBtn then frame.collapseAllBtn:Hide() end
        if zoneText then zoneText:Hide() end
        if frame.resizer then frame.resizer:Hide() end
        local titleW = (titleText:GetStringWidth() or 80) + 20
        frame:SetSize(math.max(titleW, 100), 30)
        return
    end

    if scrollFrame and not scrollFrame:IsShown() then scrollFrame:Show() end
    if frame.filterBtn and not frame.filterBtn:IsShown() then frame.filterBtn:Show() end
    if frame.cogBtn and not frame.cogBtn:IsShown() then frame.cogBtn:Show() end
    if frame.collapseAllBtn and not frame.collapseAllBtn:IsShown() then frame.collapseAllBtn:Show() end
    if zoneText and not zoneText:IsShown() then zoneText:Show() end
    if frame.resizer and not frame.resizer:IsShown() then frame.resizer:Show() end
    frame:SetWidth(BooshiesQuestLogDB.width or 280)

    zoneText:SetText(mapName)

    for _, list in pairs(groups) do
        table.sort(list, function(a, b) return (a.title or "") < (b.title or "") end)
    end

    for _, row in ipairs(activeRows) do ReleaseRow(row) end
    wipe(activeRows)
    for _, hdr in ipairs(activeSections) do ReleaseSection(hdr) end
    wipe(activeSections)

    local layout = {}
    local superTracked = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0
    local collapsedMap = BooshiesQuestLogDB.collapsedSections or {}

    for _, cls in ipairs(CLASSIFICATION_ORDER) do
        local list = groups[cls]
        if list and #list > 0 then
            local hdr = AcquireSection()
            hdr.classification = cls
            hdr.title:SetText(CLASSIFICATION_NAMES[cls] or ("Class " .. cls))
            hdr.title:SetTextColor(1.0, 0.82, 0.0)
            local collapsed = collapsedMap[cls] and true or false
            hdr.count:SetText(#list)
            hdr.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            hdr:SetHeight(SECTION_HEIGHT)
            table.insert(activeSections, hdr)
            table.insert(layout, hdr)

            if not collapsed then
                for _, q in ipairs(list) do
                    local row = AcquireRow()
                    row.itemKind = "quest"
                    row.questID = q.questID
                    row.achievementID = nil
                    row.title:SetText(q.title)
                    row.title:SetTextColor(1, 1, 1)
                    if row.SetComplete then row:SetComplete(q.isComplete) end
                    local isSuper = superTracked == q.questID and superTracked ~= 0
                    if row.trackCheck then
                        row.trackCheck:Show()
                        row.trackCheck:SetChecked(isSuper)
                    end
                    if row.superBg then row.superBg:SetShown(isSuper) end
                    local pct, hasObj = GetQuestProgress(q.questID)
                    if row.SetProgress then row:SetProgress(pct, hasObj, q.isComplete) end
                    row:SetHeight(ROW_HEIGHT)
                    table.insert(activeRows, row)
                    table.insert(layout, row)
                end
            end
        end
    end

    local hideAchievements = BooshiesQuestLogDB.filterByZone and not BooshiesQuestLogDB.alwaysShowAchievements
    local trackedAch = hideAchievements and {} or GetTrackedAchievementList()
    if #trackedAch > 0 then
        local hdr = AcquireSection()
        hdr.classification = "achievements"
        hdr.title:SetText("Achievements")
        hdr.title:SetTextColor(1.0, 0.82, 0.0)
        local collapsed = collapsedMap["achievements"] and true or false
        hdr.count:SetText(#trackedAch)
        hdr.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        hdr:SetHeight(SECTION_HEIGHT)
        table.insert(activeSections, hdr)
        table.insert(layout, hdr)

        if not collapsed then
            for _, achID in ipairs(trackedAch) do
                local id, name, _, completed
                if GetAchievementInfo then
                    id, name, _, completed = GetAchievementInfo(achID)
                end
                if id then
                    local row = AcquireRow()
                    row.itemKind = "achievement"
                    row.achievementID = achID
                    row.questID = nil
                    row.title:SetText(name or ("Achievement " .. achID))
                    row.title:SetTextColor(1, 1, 1)
                    if row.SetComplete then row:SetComplete(completed) end
                    if row.trackCheck then row.trackCheck:Hide() end
                    local pct, hasAny = GetAchievementProgress(achID)
                    if row.SetProgress then row:SetProgress(pct, hasAny, completed) end
                    row:SetHeight(ROW_HEIGHT)
                    table.insert(activeRows, row)
                    table.insert(layout, row)
                end
            end
        end
    end

    local trackedRecipes = BooshiesQuestLogDB.filterByZone and {} or GetTrackedRecipeList()
    if #trackedRecipes > 0 then
        local hdr = AcquireSection()
        hdr.classification = "recipes"
        hdr.title:SetText("Crafting")
        hdr.title:SetTextColor(1.0, 0.82, 0.0)
        local collapsed = collapsedMap["recipes"] and true or false
        hdr.count:SetText(#trackedRecipes)
        hdr.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        hdr:SetHeight(SECTION_HEIGHT)
        table.insert(activeSections, hdr)
        table.insert(layout, hdr)

        if not collapsed then
            for _, recipeID in ipairs(trackedRecipes) do
                local row = AcquireRow()
                row.itemKind = "recipe"
                row.recipeID = recipeID
                row.questID = nil
                row.achievementID = nil
                row.activityID = nil
                row.title:SetText(GetRecipeName(recipeID))
                row.title:SetTextColor(1, 1, 1)
                if row.SetComplete then row:SetComplete(false) end
                if row.trackCheck then row.trackCheck:Hide() end
                local pct, hasAny = GetRecipeProgress(recipeID)
                if row.SetProgress then row:SetProgress(pct, hasAny, false) end
                row:SetHeight(ROW_HEIGHT)
                table.insert(activeRows, row)
                table.insert(layout, row)
            end
        end
    end

    local trackedActivities = BooshiesQuestLogDB.filterByZone and {} or GetTrackedMonthlyActivities()
    if #trackedActivities > 0 then
        local hdr = AcquireSection()
        hdr.classification = "activities"
        hdr.title:SetText("Monthly")
        hdr.title:SetTextColor(1.0, 0.82, 0.0)
        local collapsed = collapsedMap["activities"] and true or false
        hdr.count:SetText(#trackedActivities)
        hdr.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        hdr:SetHeight(SECTION_HEIGHT)
        table.insert(activeSections, hdr)
        table.insert(layout, hdr)

        if not collapsed then
            for _, actID in ipairs(trackedActivities) do
                local info = GetActivityInfo(actID)
                if info then
                    local row = AcquireRow()
                    row.itemKind = "activity"
                    row.activityID = actID
                    row.questID = nil
                    row.achievementID = nil
                    row.recipeID = nil
                    row.initiativeID = nil
                    local name = info.activityName or info.name or ("Activity " .. actID)
                    row.title:SetText(name)
                    row.title:SetTextColor(1, 1, 1)
                    if row.SetComplete then row:SetComplete(info.completed) end
                    if row.trackCheck then row.trackCheck:Hide() end
                    local pct, hasAny = GetActivityProgress(actID)
                    if row.SetProgress then row:SetProgress(pct, hasAny, info.completed) end
                    row:SetHeight(ROW_HEIGHT)
                    table.insert(activeRows, row)
                    table.insert(layout, row)
                end
            end
        end
    end

    local trackedInitiatives = BooshiesQuestLogDB.filterByZone and {} or GetTrackedInitiativeTasks()
    if #trackedInitiatives > 0 then
        local hdr = AcquireSection()
        hdr.classification = "initiatives"
        hdr.title:SetText("Endeavours")
        hdr.title:SetTextColor(1.0, 0.82, 0.0)
        local collapsed = collapsedMap["initiatives"] and true or false
        hdr.count:SetText(#trackedInitiatives)
        hdr.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        hdr:SetHeight(SECTION_HEIGHT)
        table.insert(activeSections, hdr)
        table.insert(layout, hdr)

        if not collapsed then
            for _, taskID in ipairs(trackedInitiatives) do
                local row = AcquireRow()
                row.itemKind = "initiative"
                row.initiativeID = taskID
                row.questID = nil
                row.achievementID = nil
                row.recipeID = nil
                row.activityID = nil
                local info = GetInitiativeTaskInfo(taskID)
                row.title:SetText(GetInitiativeTaskName(taskID))
                row.title:SetTextColor(1, 1, 1)
                if row.SetComplete then row:SetComplete(info and info.completed) end
                if row.trackCheck then row.trackCheck:Hide() end
                local pct, hasAny = GetInitiativeTaskProgress(taskID)
                if row.SetProgress then row:SetProgress(pct, hasAny, info and info.completed) end
                row:SetHeight(ROW_HEIGHT)
                table.insert(activeRows, row)
                table.insert(layout, row)
            end
        end
    end

    local expandedKeys = BooshiesQuestLogDB.expandedKeys or {}
    if next(expandedKeys) then
        RelayoutLayout(layout)
        for _, row in ipairs(activeRows) do
            if expandedKeys[RowKey(row)] then
                ExpandRow(row)
            end
        end
    end

    RelayoutLayout(layout)
end

Refresh = function() safeCall("Refresh", refreshImpl) end

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

local function attachSquashHooks(m)
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
            attachSquashHooks(m)
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
    bg:SetColorTexture(0, 0, 0, 0.78)

    local function edge(side)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.25, 0.25, 0.27, 1)
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
    edge("top"); edge("bottom"); edge("left"); edge("right")
end

local SETTINGS_SPEC = {
    { key = "filterByZone",           label = "Filter Quests by Current Zone" },
    { key = "alwaysShowCampaign",     label = "Always Show Campaign Quests" },
    { key = "alwaysShowAchievements", label = "Always Show Achievements" },
    { key = "hideBlizzardTracker",    label = "Hide Blizzard Activity Tracker" },
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

    local applyBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
    applyBtn:SetSize(70, 22)
    applyBtn:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -10, 10)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function() ApplySettings() end)

    settingsFrame.backBtn = backBtn
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
    if not settingsFrame then HideSettings(); return end
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

local function BuildUI()
    if frame then return end
    frame = CreateFrame("Frame", "BooshiesQuestLogFrame", UIParent)
    frame:SetSize(BooshiesQuestLogDB.width or 280, 200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    ApplyFlatSkin(frame)

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    header:SetHeight(30)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePosition() end)
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
    titleBtn:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBtn:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePosition() end)
    titleBtn:SetScript("OnClick", function()
        BooshiesQuestLogDB.collapsed = not BooshiesQuestLogDB.collapsed
        Refresh()
    end)
    frame.titleBtn = titleBtn

    zoneText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetTextColor(0.7, 0.7, 0.7)

    local cogBtn = CreateFrame("Button", nil, header)
    cogBtn:SetSize(16, 16)
    cogBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -11)
    cogBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    local cogHover = cogBtn:CreateTexture(nil, "HIGHLIGHT")
    cogHover:SetAllPoints(cogBtn)
    cogHover:SetColorTexture(1, 1, 1, 0.2)
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
    collapseAllText:SetTextColor(0.55, 0.55, 0.6)
    collapseAllBtn:SetSize((collapseAllText:GetStringWidth() or 60) + 4, 14)
    collapseAllBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -22)
    collapseAllBtn:SetFrameLevel((header:GetFrameLevel() or frame:GetFrameLevel()) + 5)
    collapseAllBtn:SetHitRectInsets(-3, -3, -3, -3)
    collapseAllBtn:SetScript("OnEnter", function() collapseAllText:SetTextColor(1, 1, 1) end)
    collapseAllBtn:SetScript("OnLeave", function() collapseAllText:SetTextColor(0.55, 0.55, 0.6) end)
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

    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(44, 6)
    resizer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
    resizer:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizer:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

    local grip = resizer:CreateTexture(nil, "OVERLAY")
    grip:SetAllPoints(resizer)
    grip:SetColorTexture(0.45, 0.45, 0.48, 0.55)

    local gripHover = resizer:CreateTexture(nil, "HIGHLIGHT")
    gripHover:SetAllPoints(resizer)
    gripHover:SetColorTexture(1, 1, 1, 0.25)

    local function dragUpdate(self)
        local cur = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local delta = self._dragStartY - cur
        local newMax = math.floor(self._dragStartMax + delta + 0.5)
        if newMax < MIN_MAX_HEIGHT then newMax = MIN_MAX_HEIGHT end
        if newMax > 2000 then newMax = 2000 end
        if newMax ~= BooshiesQuestLogDB.maxHeight then
            BooshiesQuestLogDB.maxHeight = newMax
            Refresh()
        end
    end

    resizer:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self._dragStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        self._dragStartMax = BooshiesQuestLogDB.maxHeight or 500
        self:SetScript("OnUpdate", dragUpdate)
    end)

    resizer:SetScript("OnMouseUp", function(self)
        self._dragStartY = nil
        self:SetScript("OnUpdate", nil)
    end)

    frame.resizer = resizer

    RestorePosition()
    SavePosition()
end

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

local pending = false
local function Reschedule()
    if pending then return end
    pending = true
    C_Timer.After(0.05, function()
        pending = false
        safeCall("Reschedule", Refresh)
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("ZONE_CHANGED")
ev:RegisterEvent("ZONE_CHANGED_INDOORS")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
pcall(ev.RegisterEvent, ev, "WORLD_QUEST_WATCH_LIST_CHANGED")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
ev:RegisterEvent("SUPER_TRACKING_CHANGED")
pcall(ev.RegisterEvent, ev, "TRACKED_ACHIEVEMENT_UPDATE")
pcall(ev.RegisterEvent, ev, "TRACKED_ACHIEVEMENT_LIST_CHANGED")
pcall(ev.RegisterEvent, ev, "CONTENT_TRACKING_UPDATE")
pcall(ev.RegisterEvent, ev, "TRACKED_RECIPE_UPDATE")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_LIST_UPDATE")
pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED")
pcall(ev.RegisterEvent, ev, "CONTENT_TRACKING_LIST_UPDATE")
pcall(ev.RegisterEvent, ev, "PERKS_ACTIVITIES_UPDATED")
pcall(ev.RegisterEvent, ev, "TRACKED_PERKS_ACTIVITY_LIST_CHANGED")
pcall(ev.RegisterEvent, ev, "PERKS_ACTIVITIES_TRACKED_LIST_CHANGED")
pcall(ev.RegisterEvent, ev, "PERKS_ACTIVITY_COMPLETED")
pcall(ev.RegisterEvent, ev, "INITIATIVE_TASKS_TRACKED_LIST_CHANGED")
pcall(ev.RegisterEvent, ev, "INITIATIVE_ACTIVITY_LOG_UPDATED")

ev:SetScript("OnEvent", function(self, event, arg1)
    safeCall("OnEvent:" .. tostring(event), function()
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

local function PrintStatus(label, value)
    print(("|cff4fc3f7BQL:|r %s %s"):format(label, value and "|cff00ff00on|r" or "|cffff6666off|r"))
end

SLASH_BOOSHIESQUESTLOG1 = "/bql"
SLASH_BOOSHIESQUESTLOG2 = "/sql"
SLASH_BOOSHIESQUESTLOG3 = "/booshiesquestlog"
SlashCmdList["BOOSHIESQUESTLOG"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "toggle" then
        BooshiesQuestLogDB.enabled = not BooshiesQuestLogDB.enabled
        PrintStatus("tracker", BooshiesQuestLogDB.enabled)
        Refresh()
    elseif msg == "reset" then
        BooshiesQuestLogDB.point = DEFAULTS.point
        BooshiesQuestLogDB.maxHeight = DEFAULTS.maxHeight
        RestorePosition()
        Refresh()
        print("|cff4fc3f7BQL:|r position + height reset")
    elseif msg == "refresh" then
        Refresh()
    elseif msg == "evdbg" then
        BooshiesQuestLog_EvDbg = BooshiesQuestLog_EvDbg or CreateFrame("Frame")
        if BooshiesQuestLog_EvDbg._on then
            BooshiesQuestLog_EvDbg:UnregisterAllEvents()
            BooshiesQuestLog_EvDbg._on = false
            print("|cff4fc3f7BQL|r event debug OFF")
        else
            BooshiesQuestLog_EvDbg:RegisterAllEvents()
            BooshiesQuestLog_EvDbg:SetScript("OnEvent", function(self, event, a1, a2, a3)
                print(("|cff4fc3f7BQL ev|r %s %s %s %s"):format(event, tostring(a1), tostring(a2), tostring(a3)))
            end)
            BooshiesQuestLog_EvDbg._on = true
            print("|cff4fc3f7BQL|r event debug ON - interact in-game and watch chat. /bql evdbg to stop.")
        end
    elseif msg == "capture" then
        if not BooshiesQuestLog_CaptureHooked then
            BooshiesQuestLog_CaptureHooked = true
            BooshiesQuestLog_CaptureSeen = {}
            local function argstr(...)
                local n = select("#", ...)
                local t = {}
                for i = 1, n do t[i] = tostring(select(i, ...)) end
                return table.concat(t, ", ")
            end
            local function logOnce(key, label)
                if not BooshiesQuestLog_CaptureSeen[key] then
                    BooshiesQuestLog_CaptureSeen[key] = true
                    print("|cff4fc3f7cap|r " .. label)
                end
            end
            local hooked, skipped = 0, 0
            for gname, gval in pairs(_G) do
                if type(gname) == "string" and gname:sub(1, 2) == "C_" and type(gval) == "table" then
                    for fname, fn in pairs(gval) do
                        if type(fn) == "function" then
                            local ns, nm = gname, fname
                            local ok = pcall(hooksecurefunc, gval, nm, function(...)
                                if BooshiesQuestLogDB.capture then
                                    logOnce(ns .. "." .. nm, ("%s.%s(%s)"):format(ns, nm, argstr(...)))
                                end
                            end)
                            if ok then hooked = hooked + 1 else skipped = skipped + 1 end
                        end
                    end
                end
            end
            for _, gname in ipairs({
                "RemoveTrackedAchievement", "AddTrackedAchievement",
                "SetSuperTrackedQuestID", "RemoveQuestWatch", "AddQuestWatch",
                "RemoveWorldQuestWatch", "AddWorldQuestWatch",
            }) do
                if _G[gname] then
                    pcall(hooksecurefunc, gname, function(...)
                        if BooshiesQuestLogDB.capture then
                            logOnce(gname, ("%s(%s)"):format(gname, argstr(...)))
                        end
                    end)
                end
            end
            print(("|cff4fc3f7BQL|r hooked %d C_* functions (%d skipped)"):format(hooked, skipped))
        end
        BooshiesQuestLogDB.capture = not BooshiesQuestLogDB.capture
        if BooshiesQuestLogDB.capture then
            BooshiesQuestLog_CaptureSeen = {}
        end
        print("|cff4fc3f7BQL|r capture: " .. (BooshiesQuestLogDB.capture and "|cff00ff00ON|r (dedupe reset)" or "|cffff6666OFF|r"))
    else
        print("|cff4fc3f7BQL:|r /bql [toggle|reset|refresh|evdbg|capture]")
    end
end

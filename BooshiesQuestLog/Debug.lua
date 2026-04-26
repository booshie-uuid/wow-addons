local addonName, addon = ...

local Debug = {}
addon.Debug = Debug


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function p(fmt, ...)
    print(("|cff4fc3f7BQL|r " .. fmt):format(...))
end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Debug.dumpQuest(questID)

    if not questID then return end

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

    local mapID = addon.Util.getPlayerZoneMapID()
    local mapName = addon.Util.getMapName(mapID) or "?"
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

function Debug.dumpAchievement(achID)

    if not achID then return end

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

        if assetID and assetID ~= 0 then
            -- Newer asset-based lookup: when criterion references a quest, spell,
            -- or achievement asset, those names are often the human-readable label.
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

        if criteriaID and C_AchievementInfo and C_AchievementInfo.GetCriteriaInfo then
            -- Newer table-shaped API (if present on this client).
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

function Debug.dumpRecipe(recipeID)

    if not recipeID then return end

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
                            local name = reagent.itemID and addon.Util.itemName(reagent.itemID) or "?"
                            local count = reagent.itemID and addon.Util.itemCount(reagent.itemID) or 0
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

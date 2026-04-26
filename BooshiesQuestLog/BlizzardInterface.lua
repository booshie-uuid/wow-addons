local addonName, addon = ...

local BlizzardInterface = {}
addon.BlizzardInterface = BlizzardInterface


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function BlizzardInterface.openQuest(questID)

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

function BlizzardInterface.openAchievement(achID)

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

function BlizzardInterface.openRecipe(recipeID)

    if not recipeID then return end

    if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
        pcall(C_TradeSkillUI.OpenRecipe, recipeID)
    end

end

function BlizzardInterface.openJournalActivities()

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

function BlizzardInterface.openNeighbourhoodActivities(taskID)

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

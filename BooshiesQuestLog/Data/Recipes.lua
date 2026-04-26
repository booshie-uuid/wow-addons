local addonName, addon = ...

addon.Data = addon.Data or {}

local Recipes = {}
addon.Data.Recipes = Recipes


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local SECTION = "Crafting"


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function getTrackedIDs()

    local list = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked then return list end

    local seen = {}
    addon.Util.tryAppendIDs(list, seen, C_TradeSkillUI.GetRecipesTracked, false)
    addon.Util.tryAppendIDs(list, seen, C_TradeSkillUI.GetRecipesTracked, true)

    return list

end

local function getName(recipeID)

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and info and info.name then return info.name end
    end

    return "Recipe " .. tostring(recipeID)

end

local function getReagents(recipeID)

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
                    have = have + addon.Util.itemCount(reagent.itemID)
                end
            end

            reagents[#reagents + 1] = {
                text = addon.Util.itemName(slot.reagents[1].itemID),
                numFulfilled = have,
                numRequired = needed,
                finished = have >= needed,
            }
        end
    end

    return reagents

end

local function untrackRecipe(recipeID)

    if not C_TradeSkillUI or not C_TradeSkillUI.SetRecipeTracked then return end

    pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, false, false)
    pcall(C_TradeSkillUI.SetRecipeTracked, recipeID, false, true)

end

local function buildItem(recipeID)

    local objectives = getReagents(recipeID)
    local progress, hasProgress = addon.Util.computeProgress(objectives)

    return {
        kind        = "recipe",
        id          = recipeID,
        key         = "recipe:" .. recipeID,
        title       = getName(recipeID),
        section     = SECTION,
        isComplete  = false,
        progress    = progress,
        hasProgress = hasProgress,
        objectives  = objectives,

        openDetails = function() addon.BlizzardInterface.openRecipe(recipeID) end,
        untrack     = function() untrackRecipe(recipeID) end,
        dump        = function() addon.Debug.dumpRecipe(recipeID) end,
    }

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Recipes.collectAll()

    local items = {}

    for _, recipeID in ipairs(getTrackedIDs()) do
        local item = buildItem(recipeID)
        if item then table.insert(items, item) end
    end

    return items

end

function Recipes.collect()

    if addon.Core.getDB().filterByZone then return {} end

    return Recipes.collectAll()

end

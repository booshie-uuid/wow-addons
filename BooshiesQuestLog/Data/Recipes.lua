local addonName, addon = ...

addon.Data = addon.Data or {}

local Recipes = {}
addon.Data.Recipes = Recipes


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Recipes.getTracked()

    local list = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked then return list end

    local seen = {}
    addon.Util.tryAppendIDs(list, seen, C_TradeSkillUI.GetRecipesTracked, false)
    addon.Util.tryAppendIDs(list, seen, C_TradeSkillUI.GetRecipesTracked, true)

    return list

end

function Recipes.getName(recipeID)

    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and info and info.name then return info.name end
    end

    return "Recipe " .. tostring(recipeID)

end

function Recipes.getReagents(recipeID)

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

function Recipes.getProgress(recipeID)
    return addon.Util.computeProgress(Recipes.getReagents(recipeID))
end

local addonName, addon = ...

addon.Data = addon.Data or {}

local NeighbourhoodActivities = {}
addon.Data.NeighbourhoodActivities = NeighbourhoodActivities


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local SECTION = "Endeavours"


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function getTasks()

    if not C_NeighborhoodInitiative or not C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo then return nil end

    local ok, info = pcall(C_NeighborhoodInitiative.GetNeighborhoodInitiativeInfo)
    if ok and type(info) == "table" and type(info.tasks) == "table" then
        return info.tasks
    end

    return nil

end

local function taskID(t)
    return t and (t.id or t.taskID or t.ID or t.initiativeTaskID)
end

local function getTrackedIDs()

    local list = {}
    if not C_NeighborhoodInitiative then return list end

    if C_NeighborhoodInitiative.GetTrackedInitiativeTasks then
        if addon.Util.tryAppendIDs(list, nil, C_NeighborhoodInitiative.GetTrackedInitiativeTasks) then
            return list
        end
    end

    local tasks = getTasks()

    if tasks then
        for _, t in ipairs(tasks) do
            if type(t) == "table" and t.tracked then
                local id = taskID(t)
                if id then list[#list + 1] = id end
            end
        end
    end

    return list

end

local function getInfo(id)

    if not C_NeighborhoodInitiative then return nil end

    if C_NeighborhoodInitiative.GetInitiativeTaskInfo then
        local ok, info = pcall(C_NeighborhoodInitiative.GetInitiativeTaskInfo, id)
        if ok and type(info) == "table" then return info end
    end

    local tasks = getTasks()

    if tasks then
        for _, t in ipairs(tasks) do
            if type(t) == "table" and taskID(t) == id then return t end
        end
    end

    return nil

end

local function getObjectives(info)

    if not info then return {} end

    local list = {}
    local criteria = addon.Util.firstNonEmptyField(info, { "criteriaList", "requirementsList", "objectives", "conditions" })

    if criteria then
        for _, c in ipairs(criteria) do
            if type(c) == "table" then
                local text = c.requirementText or c.description or c.text or c.name or c.title or "?"
                if type(text) == "string" then text = text:gsub("^%s*%-%s*", "") end

                local finished = c.completed or c.finished or c.isComplete or false
                local have = c.quantity or c.numFulfilled or c.progress or c.current or 0
                local need = c.required or c.numRequired or c.requiredQuantity or c.quantityRequired or 0

                -- Some clients only ship a free-form "5/10" string; parse it
                -- when the structured numeric fields are absent.
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

local function getName(info, id)

    if info then return info.taskName or info.name or info.activityName or info.title or ("Endeavour " .. id) end
    return "Endeavour " .. id

end

local function untrackTask(id)

    if C_NeighborhoodInitiative and C_NeighborhoodInitiative.RemoveTrackedInitiativeTask then
        pcall(C_NeighborhoodInitiative.RemoveTrackedInitiativeTask, id)
    end

end

local function buildItem(taskID)

    local info = getInfo(taskID)
    local objectives = getObjectives(info)

    local progress, hasProgress
    if info and info.completed then
        progress, hasProgress = 1, true
    else
        progress, hasProgress = addon.Util.computeProgress(objectives)
    end

    return {
        kind        = "neighbourhoodActivity",
        id          = taskID,
        key         = "initiative:" .. taskID,
        title       = getName(info, taskID),
        section     = SECTION,
        isComplete  = info and info.completed and true or false,
        progress    = progress,
        hasProgress = hasProgress,
        objectives  = objectives,

        openDetails = function() addon.BlizzardInterface.openNeighbourhoodActivities(taskID) end,
        untrack     = function() untrackTask(taskID) end,
    }

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function NeighbourhoodActivities.collectAll()

    local items = {}

    for _, taskID in ipairs(getTrackedIDs()) do
        local item = buildItem(taskID)
        if item then table.insert(items, item) end
    end

    return items

end

function NeighbourhoodActivities.collect()

    if addon.Core.getDB().filterByZone then return {} end

    return NeighbourhoodActivities.collectAll()

end

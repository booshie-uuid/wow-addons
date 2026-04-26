local addonName, addon = ...

addon.Data = addon.Data or {}

local NeighbourhoodActivities = {}
addon.Data.NeighbourhoodActivities = NeighbourhoodActivities


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


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function NeighbourhoodActivities.getTracked()

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

function NeighbourhoodActivities.getInfo(id)

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

function NeighbourhoodActivities.getObjectives(id)

    local info = NeighbourhoodActivities.getInfo(id)
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

function NeighbourhoodActivities.getProgress(id)

    local info = NeighbourhoodActivities.getInfo(id)
    if not info then return 0, false end
    if info.completed then return 1, true end

    return addon.Util.computeProgress(NeighbourhoodActivities.getObjectives(id))

end

function NeighbourhoodActivities.getName(id)

    local info = NeighbourhoodActivities.getInfo(id)
    if info then return info.taskName or info.name or info.activityName or info.title or ("Endeavour " .. id) end

    return "Endeavour " .. id

end

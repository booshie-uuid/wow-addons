local addonName, addon = ...

addon.Data = addon.Data or {}

local JournalActivities = {}
addon.Data.JournalActivities = JournalActivities


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local SECTION = "Monthly"


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function iterate(callback)

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

local function activityID(activity)
    return activity and (activity.ID or activity.activityID or activity.perksActivityID)
end

local function getTrackedIDs()

    local list = {}

    if C_PerksActivities and C_PerksActivities.GetTrackedPerksActivities then
        if addon.Util.tryAppendIDs(list, nil, C_PerksActivities.GetTrackedPerksActivities) then
            return list
        end
    end

    iterate(function(activity)
        if activity.tracked then
            local id = activityID(activity)
            if id then list[#list + 1] = id end
        end
    end)

    return list

end

local function getInfo(id)

    if not C_PerksActivities then return nil end

    if C_PerksActivities.GetPerksActivityInfo then
        local ok, info = pcall(C_PerksActivities.GetPerksActivityInfo, id)
        if ok and info then return info end
    end

    local found
    iterate(function(activity)
        if activityID(activity) == id then
            found = activity
            return false
        end
    end)

    return found

end

local function getObjectives(info)

    if not info then return {} end

    local list = {}
    local criteria = addon.Util.firstNonEmptyField(info, { "criteriaList", "requirementsList", "conditions" })

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
            numFulfilled = info.thresholdContributionAmount or 0,
            numRequired = info.thresholdMax or 0,
        }
    end

    return list

end

local function getProgress(info, objectives)

    if not info then return 0, false end
    if info.completed then return 1, true end

    if #objectives > 0 then return addon.Util.computeProgress(objectives) end

    -- Fall back to the activity-level threshold counter (some activities
    -- do not expose objective rows, only an aggregate progress number).
    local have = info.thresholdContributionAmount or 0
    local need = info.thresholdMax or info.requiredContributionAmount or 0
    if need <= 0 then return 0, false end

    local f = have / need
    if f > 1 then f = 1 elseif f < 0 then f = 0 end

    return f, true

end

local function untrackActivity(id)

    if not C_PerksActivities then return end

    -- Probe API for an explicit untrack/remove function and stop on first
    -- success, since the exact name varies across game versions.
    for fname, fn in pairs(C_PerksActivities) do
        if type(fn) == "function" then
            local lk = fname:lower()
            if lk:find("untrack") or (lk:find("remove") and (lk:find("track") or lk:find("activit"))) then
                local ok = pcall(fn, id)
                if ok then break end
            end
        end
    end

    -- Also call any SetXxxTracked-style toggle with false, in case the API
    -- exposes a setter rather than a remove.
    for fname, fn in pairs(C_PerksActivities) do
        if type(fn) == "function" then
            local lk = fname:lower()
            if lk:find("^set") and lk:find("track") then
                pcall(fn, id, false)
            end
        end
    end

end

local function buildItem(actID)

    local info = getInfo(actID)
    if not info then return nil end

    local objectives = getObjectives(info)
    local progress, hasProgress = getProgress(info, objectives)

    return {
        kind        = "journalActivity",
        id          = actID,
        key         = "activity:" .. actID,
        title       = info.activityName or info.name or ("Activity " .. actID),
        section     = SECTION,
        isComplete  = info.completed and true or false,
        progress    = progress,
        hasProgress = hasProgress,
        objectives  = objectives,

        openDetails = function() addon.BlizzardInterface.openJournalActivities() end,
        untrack     = function() untrackActivity(actID) end,
    }

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function JournalActivities.collectAll()

    local items = {}

    for _, actID in ipairs(getTrackedIDs()) do
        local item = buildItem(actID)
        if item then table.insert(items, item) end
    end

    return items

end

function JournalActivities.collect()

    if addon.Core.getDB().filterByZone then return {} end

    return JournalActivities.collectAll()

end

local addonName, addon = ...

local Util = {}
addon.Util = Util


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local observedErrors = {}


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Util.safeCall(label, fn, ...)

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

function Util.computeProgress(list)

    if not list or #list == 0 then return 0, false end

    local sum, count = 0, 0

    for _, item in ipairs(list) do
        if item.finished then
            sum = sum + 1
            count = count + 1
        elseif item.numRequired and item.numRequired > 0 then
            -- Entries lacking progress info still count toward the
            -- denominator so the average matches what a user expects
            -- ("3 of 5 done" with 2 unknowns reads as 3/5, not 3/3).
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
function Util.firstNonEmptyField(obj, keys)

    if type(obj) ~= "table" then return nil end

    for _, k in ipairs(keys) do
        local v = obj[k]
        if type(v) == "table" and #v > 0 then return v end
    end

    return nil

end

function Util.tryAppendIDs(list, seen, fn, ...)

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

function Util.getPlayerZoneMapID()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
end

function Util.getMapName(mapID)

    if not mapID then return nil end

    local info = C_Map.GetMapInfo(mapID)
    return info and info.name

end

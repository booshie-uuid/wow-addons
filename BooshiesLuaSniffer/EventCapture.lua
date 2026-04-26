local addonName, addon = ...

local EventCapture = {}
addon.EventCapture = EventCapture


local NS = "eventCapture"

addon.Core.registerDefaults(NS, {
    excluded       = {},
    hideOlder      = false,
    executionOrder = false,
})


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local NOTIFY_INTERVAL = 0.1
local OLDER_THAN      = 60


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local byName    = {}
local order     = {}
local excluded  = {}
local listeners = { entries = {}, exclusions = {} }

local entriesDirty = false

-- USER SETTINGS --------------------------------------------------------------

local hideOlder      = false
local executionOrder = false


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- NOTIFICATIONS --------------------------------------------------------------

local function notify(channel)

    local list = listeners[channel]

    for i = 1, #list do
        local fn = list[i]
        if fn then
            pcall(fn)
        end
    end

end

local function scheduleEntriesNotify()

    if entriesDirty then return end

    entriesDirty = true
    C_Timer.After(NOTIFY_INTERVAL, function()
        entriesDirty = false
        notify("entries")
    end)

end

-- EVENT PROCESSING -----------------------------------------------------------

local function formatArgs(...)

    local n = select("#", ...)
    if n == 0 then return nil end

    local out = {}
    for i = 1, n do
        local v = select(i, ...)
        out[i] = tostring(v)
    end

    return out

end

local function moveToTop(name)

    if order[1] == name then return end

    for i = 2, #order do
        if order[i] == name then
            table.remove(order, i)
            break
        end
    end

    table.insert(order, 1, name)

end

local function onEvent(event, ...)

    if excluded[event] then return end

    local rec = byName[event]

    if not rec then
        rec = {
            name      = event,
            count     = 0,
            firstSeen = GetTime(),
        }
        byName[event] = rec
        table.insert(order, 1, event)
    elseif executionOrder then
        moveToTop(event)
    end

    rec.count    = rec.count + 1
    rec.lastSeen = GetTime()
    rec.lastArgs = formatArgs(...)

    scheduleEntriesNotify()

end

-- PERSISTENCE ----------------------------------------------------------------

local function persistExclusions()

    local settings = addon.Core.getSettings(NS)
    settings.excluded = {}

    for name in pairs(excluded) do
        settings.excluded[name] = true
    end

end


--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function EventCapture.init()

    local settings = addon.Core.getSettings(NS)

    for name in pairs(settings.excluded) do
        excluded[name] = true
    end

    hideOlder      = settings.hideOlder and true or false
    executionOrder = settings.executionOrder and true or false

    addon.EventManager.subscribe(onEvent)
    addon.UI.EventCaptureWindow.build()

end


--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

function EventCapture.toggleUI()
    addon.UI.EventCaptureWindow.toggle()
end


--------------------------------------------------------------------------------
-- SETTINGS API
--------------------------------------------------------------------------------

function EventCapture.isHideOlder()
    return hideOlder
end

function EventCapture.setHideOlder(value)

    hideOlder = value and true or false
    addon.Core.getSettings(NS).hideOlder = hideOlder

    notify("entries")

end

function EventCapture.isExecutionOrder()
    return executionOrder
end

function EventCapture.setExecutionOrder(value)

    executionOrder = value and true or false
    addon.Core.getSettings(NS).executionOrder = executionOrder

end


--------------------------------------------------------------------------------
-- ENTRIES API
--------------------------------------------------------------------------------

function EventCapture.getEntries()

    local out = {}
    local cutoff = hideOlder and (GetTime() - OLDER_THAN) or nil

    for i = 1, #order do
        local name = order[i]
        if not excluded[name] then
            local rec = byName[name]
            if not cutoff or (rec.lastSeen and rec.lastSeen >= cutoff) then
                out[#out + 1] = rec
            end
        end
    end

    return out

end


--------------------------------------------------------------------------------
-- EXCLUSIONS API
--------------------------------------------------------------------------------

function EventCapture.getExclusions()

    local out = {}
    for name in pairs(excluded) do
        out[#out + 1] = { name = name }
    end

    table.sort(out, function(a, b) return a.name < b.name end)

    return out

end

function EventCapture.exclude(name)

    if not name or excluded[name] then return end

    excluded[name] = true
    persistExclusions()

    notify("entries")
    notify("exclusions")

end

function EventCapture.include(name)

    if not name or not excluded[name] then return end

    excluded[name] = nil
    persistExclusions()

    notify("entries")
    notify("exclusions")

end

function EventCapture.clearExclusions()

    if not next(excluded) then return end

    excluded = {}
    persistExclusions()

    notify("entries")
    notify("exclusions")

end

function EventCapture.excludeAll()

    local entries = EventCapture.getEntries()
    local changed = false

    for i = 1, #entries do
        local name = entries[i].name
        if not excluded[name] then
            excluded[name] = true
            changed = true
        end
    end

    if not changed then return end

    persistExclusions()

    notify("entries")
    notify("exclusions")

end


--------------------------------------------------------------------------------
-- SUBSCRIPTIONS
--------------------------------------------------------------------------------

function EventCapture.subscribe(channel, fn)

    local list = listeners[channel]
    if not list then return function() end end

    table.insert(list, fn)

    -- return unsubscribe handle
    return function()
        for i = #list, 1, -1 do
            if list[i] == fn then
                table.remove(list, i)
                return
            end
        end
    end

end

local addonName, addon = ...

local EventManager = {}
addon.EventManager = EventManager


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local frame            = CreateFrame("Frame")
local capturing        = false
local subscribers      = {}
local stateSubscribers = {}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- NOTIFICATIONS --------------------------------------------------------------

local function notify(list, ...)

    for i = 1, #list do
        local fn = list[i]
        if fn then
            pcall(fn, ...)
        end
    end

end

local function notifyState()
    notify(stateSubscribers, capturing)
end

-- SUBSCRIPTIONS --------------------------------------------------------------

local function addListener(list, fn)

    table.insert(list, fn)

    -- return unsubscribe function
    return function()
        for i = #list, 1, -1 do
            if list[i] == fn then
                table.remove(list, i)
                return
            end
        end
    end

end


--------------------------------------------------------------------------------
-- CAPTURE STATE API
--------------------------------------------------------------------------------

function EventManager.isCapturing()
    return capturing
end

function EventManager.start()

    if capturing then return end

    capturing = true
    frame:RegisterAllEvents()
    notifyState()

end

function EventManager.stop()

    if not capturing then return end

    capturing = false
    frame:UnregisterAllEvents()
    notifyState()

end

function EventManager.toggle()

    if capturing then
        EventManager.stop()
    else
        EventManager.start()
    end

end


--------------------------------------------------------------------------------
-- SUBSCRIPTIONS API
--------------------------------------------------------------------------------

function EventManager.subscribe(fn)
    return addListener(subscribers, fn)
end

function EventManager.subscribeToState(fn)
    return addListener(stateSubscribers, fn)
end


--------------------------------------------------------------------------------
-- WIRING
--------------------------------------------------------------------------------

frame:SetScript("OnEvent", function(self, event, ...)

    if not capturing then return end

    notify(subscribers, event, ...)

end)

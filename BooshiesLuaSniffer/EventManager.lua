local addonName, addon = ...

local EventManager = {}
addon.EventManager = EventManager


local frame = CreateFrame("Frame")
local capturing = false
local subscribers = {}
local stateSubscribers = {}


local function Notify(list, ...)

    for i = 1, #list do
        local fn = list[i]
        if fn then
            pcall(fn, ...)
        end
    end

end

local function NotifyState()
    Notify(stateSubscribers, capturing)
end


function EventManager.isCapturing()
    return capturing
end

function EventManager.start()

    if capturing then return end

    capturing = true
    frame:RegisterAllEvents()
    NotifyState()

end

function EventManager.stop()

    if not capturing then return end

    capturing = false
    frame:UnregisterAllEvents()
    NotifyState()

end

function EventManager.toggle()

    if capturing then
        EventManager.stop()
    else
        EventManager.start()
    end

end


local function AddListener(list, fn)

    table.insert(list, fn)

    return function()
        for i = #list, 1, -1 do
            if list[i] == fn then
                table.remove(list, i)
                return
            end
        end
    end

end

function EventManager.subscribe(fn)
    return AddListener(subscribers, fn)
end

function EventManager.subscribeToState(fn)
    return AddListener(stateSubscribers, fn)
end


frame:SetScript("OnEvent", function(self, event, ...)

    if not capturing then return end

    Notify(subscribers, event, ...)

end)

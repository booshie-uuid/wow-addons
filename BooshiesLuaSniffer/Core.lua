local addonName, addon = ...

addon.UI = {}

local Core = {}
addon.Core = Core


local DEFAULTS = {
    point = { "CENTER", "UIParent", "CENTER", 0, 0 },
}

local registry = {}


function Core.registerDefaults(namespace, defaults)
    registry[namespace] = defaults
end

function Core.getSettings(namespace)
    return BooshiesLuaSnifferDB[namespace]
end

function Core.getDB()
    return BooshiesLuaSnifferDB
end

function Core.getDefaults()
    return DEFAULTS
end


local function MergeInto(target, defaults)

    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = v
        end
    end

end

local function MergeDefaults()

    BooshiesLuaSnifferDB = BooshiesLuaSnifferDB or {}

    MergeInto(BooshiesLuaSnifferDB, DEFAULTS)

    for namespace, defaults in pairs(registry) do
        BooshiesLuaSnifferDB[namespace] = BooshiesLuaSnifferDB[namespace] or {}
        MergeInto(BooshiesLuaSnifferDB[namespace], defaults)
    end

end


local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)

    if event ~= "ADDON_LOADED" or name ~= addonName then
        return
    end

    MergeDefaults()
    addon.EventCapture.init()
    addon.UI.MainFrame.build()

    self:UnregisterEvent("ADDON_LOADED")

end)


local function Print(msg)
    print("|cff4fc3f7BLS:|r " .. msg)
end

SLASH_BOOSHIESLUASNIFFER1 = "/sniff"
SLASH_BOOSHIESLUASNIFFER2 = "/booshieslsniffer"
SlashCmdList["BOOSHIESLUASNIFFER"] = function(msg)

    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "toggle" then
        addon.UI.MainFrame.toggle()
    elseif msg == "start" then
        addon.EventManager.start()
        Print("capture started")
    elseif msg == "stop" then
        addon.EventManager.stop()
        Print("capture stopped")
    elseif msg == "clear" then
        addon.EventCapture.clearExclusions()
        Print("exclusions cleared")
    else
        Print("/sniff [toggle|start|stop|clear]")
    end

end

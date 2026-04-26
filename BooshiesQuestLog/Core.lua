local addonName, addon = ...

addon.UI = {}

local Core = {}
addon.Core = Core


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local DEFAULTS = {
    enabled                = true,
    filterByZone           = false,
    alwaysShowCampaign     = true,
    alwaysShowAchievements = true,
    debug                  = false,
    includeWorldQuests     = false,
    hideBlizzardTracker    = true,
    point                  = { "TOPRIGHT", "UIParent", "TOPRIGHT", -20, -200 },
    width                  = 280,
    maxHeight              = 300,
    expandedKeys           = {},
    collapsedSections      = {},
    collapsed              = false,
    helpShown              = false,
    lockPosition           = false,
    hideBorder             = false,
    backdropAlpha          = 0.78,
}


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local registry = {}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function mergeInto(target, defaults)

    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = v
        end
    end

end

local function mergeDefaults()

    BooshiesQuestLogDB = BooshiesQuestLogDB or {}

    mergeInto(BooshiesQuestLogDB, DEFAULTS)

    for namespace, defaults in pairs(registry) do
        BooshiesQuestLogDB[namespace] = BooshiesQuestLogDB[namespace] or {}
        mergeInto(BooshiesQuestLogDB[namespace], defaults)
    end

end

local function migrateExpandedKey()

    -- Migrate the legacy single-key form to the expandedKeys set.
    if type(BooshiesQuestLogDB.expandedKey) == "string" then
        BooshiesQuestLogDB.expandedKeys = BooshiesQuestLogDB.expandedKeys or {}
        BooshiesQuestLogDB.expandedKeys[BooshiesQuestLogDB.expandedKey] = true
        BooshiesQuestLogDB.expandedKey = nil
    end

end

local function clampMaxHeight()

    -- Saved height may exceed current screen if the player resized the
    -- WoW window since last save.
    local screenH = UIParent and UIParent:GetHeight() or 768

    if BooshiesQuestLogDB.maxHeight and BooshiesQuestLogDB.maxHeight > screenH - 60 then
        BooshiesQuestLogDB.maxHeight = math.max(DEFAULTS.maxHeight, math.floor(screenH * 0.5))
    end

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Core.registerDefaults(namespace, defaults)
    registry[namespace] = defaults
end

function Core.getSettings(namespace)
    return BooshiesQuestLogDB[namespace]
end

function Core.getDB()
    return BooshiesQuestLogDB
end

function Core.getDefaults()
    return DEFAULTS
end


--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)

    if event ~= "ADDON_LOADED" or name ~= addonName then
        return
    end

    mergeDefaults()
    migrateExpandedKey()
    clampMaxHeight()

    self:UnregisterEvent("ADDON_LOADED")

end)

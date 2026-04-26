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

-- Quest classification numbers used to be the collapsedSections keys for
-- quest sections. Map them onto the display names that TrackedItem.section
-- now uses. Same for the four kind-keyed non-quest sections.
local COLLAPSED_SECTION_REMAP = {
    [0]  = "Important",
    [1]  = "Legendary",
    [2]  = "Campaign",
    [3]  = "Calling",
    [4]  = "Special",
    [5]  = "Recurring",
    [6]  = "Questline",
    [7]  = "Normal",
    [8]  = "Bonus",
    [9]  = "Threat",
    [10] = "World Quests",
    achievements = "Achievements",
    recipes      = "Crafting",
    activities   = "Monthly",
    initiatives  = "Endeavours",
}

local function migrateCollapsedSections()

    local cs = BooshiesQuestLogDB.collapsedSections
    if type(cs) ~= "table" then return end

    local migrated = {}

    for key, value in pairs(cs) do
        local mapped = COLLAPSED_SECTION_REMAP[key]
        if mapped then
            migrated[mapped] = value
        else
            -- Already a display-name key (or unknown); keep as-is.
            migrated[key] = value
        end
    end

    BooshiesQuestLogDB.collapsedSections = migrated

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
    migrateCollapsedSections()
    clampMaxHeight()

    self:UnregisterEvent("ADDON_LOADED")

end)


--------------------------------------------------------------------------------
-- SLASH COMMANDS
--------------------------------------------------------------------------------

local function printStatus(label, value)
    print(("|cff4fc3f7BQL:|r %s %s"):format(label, value and "|cff00ff00on|r" or "|cffff6666off|r"))
end

SLASH_BOOSHIESQUESTLOG1 = "/bql"
SLASH_BOOSHIESQUESTLOG2 = "/booshiesquestlog"
SlashCmdList["BOOSHIESQUESTLOG"] = function(msg)

    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "" or msg == "toggle" then
        addon.Core.getDB().enabled = not addon.Core.getDB().enabled
        printStatus("tracker", addon.Core.getDB().enabled)
        addon.BooshiesTracker.refresh()

    elseif msg == "reset" then
        addon.BooshiesTracker.resetPositionAndSize()
        addon.Core.getDB().helpShown = false
        addon.UI.HelpWindow.show()
        print("|cff4fc3f7BQL:|r position + height reset")

    elseif msg == "refresh" then
        addon.BooshiesTracker.refresh()

    else
        print("|cff4fc3f7BQL:|r /bql [toggle||reset||refresh]")
    end

end

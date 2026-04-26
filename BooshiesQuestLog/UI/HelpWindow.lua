local addonName, addon = ...

addon.UI = addon.UI or {}

local HelpWindow = {}
addon.UI.HelpWindow = HelpWindow


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

-- Gold highlight derived from the central palette so the cheatsheet matches
-- the section-title colour by reference, not coincidence.
local GOLD = addon.UI.Theme.colorEscape(addon.UI.Theme.colors.sectionTitle)
local RESET = "|r"

local BODY_TEXT =
    "• " .. GOLD .. "Left Click:" .. RESET .. " Expand/Collapse the quest/activity.\n"
    .. "• " .. GOLD .. "Right Click:" .. RESET .. " Open quest/activity in relevant window.\n"
    .. "• " .. GOLD .. "Shift + Left Click:" .. RESET .. " Stop tracking quest/activity.\n"
    .. "• " .. GOLD .. "Ctrl + Left Click:" .. RESET .. " \"Super Track\" quest/activity (shows way point).\n"
    .. "• " .. GOLD .. "Ctrl + Right Click:" .. RESET .. " Dump debug information about quest/activity.\n"
    .. "\n"
    .. "You can shrink the entire quest log down by " .. GOLD .. "clicking on the title" .. RESET .. "."


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local frame


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function build()

    if frame then return end

    frame = CreateFrame("Frame", "BooshiesQuestLogHelpFrame", UIParent)
    frame:SetSize(480, 260)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    addon.UI.Theme.applyFlatSkin(frame)

    -- Closes on Escape.
    tinsert(UISpecialFrames, "BooshiesQuestLogHelpFrame")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    title:SetPoint("LEFT", frame, "TOPLEFT", 8, -19)
    title:SetText("Booshie's Quest Log")

    -- Set the FontString's vertex colour from our palette so the inline
    -- |r resets in BODY_TEXT return to our white instead of GameFontNormal's
    -- default gold.
    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    body:SetTextColor(unpack(addon.UI.Theme.colors.itemTitle))
    body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    body:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetWordWrap(true)
    body:SetText(BODY_TEXT)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(70, 22)
    closeBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() HelpWindow.hide() end)

    frame.title = title
    frame.body = body
    frame.closeBtn = closeBtn

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function HelpWindow.show()

    build()

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:Show()

end

function HelpWindow.hide()

    if frame then frame:Hide() end
    addon.Core.getDB().helpShown = true

end

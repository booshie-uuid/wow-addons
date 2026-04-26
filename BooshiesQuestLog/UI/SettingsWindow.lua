local addonName, addon = ...

addon.UI = addon.UI or {}

local SettingsWindow = {}
addon.UI.SettingsWindow = SettingsWindow


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local TOP_PAD       = 46    -- pixels reserved at the top for the title row
local BOTTOM_PAD    = 44    -- pixels reserved at the bottom for the button row
local DEFAULT_WIDTH = 280

local SETTINGS_SPEC = {
    { key = "filterByZone",           label = "Filter Quests by Current Zone" },
    { key = "alwaysShowCampaign",     label = "Always Show Campaign Quests" },
    { key = "alwaysShowAchievements", label = "Always Show Achievements" },
    { key = "hideBlizzardTracker",    label = "Hide Blizzard Activity Tracker" },
    { key = "lockPosition",           label = "Lock Position" },
    { key = "hideBorder",             label = "Hide Outer Border" },
    { key = "backdropAlpha",          label = "Background Opacity",
                                      type = "slider", min = 0, max = 1, step = 0.05 },
    { key = "debug",                  label = "Debug Mode" },
}


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local frame
local config


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function buildSliderRow(row, spec)

    row:SetHeight(40)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(spec.label)

    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    slider:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    slider:SetMinMaxValues(spec.min, spec.max)
    slider:SetValueStep(spec.step)
    slider:SetObeyStepOnDrag(true)

    -- Hide the template's built-in Low/High/Text labels so the row can use a
    -- single right-aligned percentage display instead.
    if slider.Low  then slider.Low:Hide()  end
    if slider.High then slider.High:Hide() end
    if slider.Text then slider.Text:Hide() end

    local function updateValueText(v)
        valueText:SetText(string.format("%d%%", math.floor((v or 0) * 100 + 0.5)))
    end

    slider:SetScript("OnValueChanged", function(self, value)
        frame.pending[spec.key] = value
        updateValueText(value)
    end)

    row.slider = slider
    function row:setValue(v)
        self.slider:SetValue(v or 0)
        updateValueText(v)
    end

end

local function buildCheckboxRow(row, spec)

    row:SetHeight(22)

    local cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", row, "LEFT", 0, 0)
    cb:SetScript("OnClick", function(self)
        frame.pending[spec.key] = self:GetChecked() and true or false
    end)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(spec.label)

    row.checkbox = cb
    function row:setValue(v)
        self.checkbox:SetChecked(v and true or false)
    end

end

local function build()

    if frame then return end

    frame = CreateFrame("Frame", "BooshiesQuestLogSettingsFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    addon.UI.Theme.applyFlatSkin(frame)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    title:SetPoint("LEFT", frame, "TOPLEFT", 8, -19)
    title:SetText("Settings")

    frame.pending = {}
    frame.rows = {}

    local y = TOP_PAD

    for i, spec in ipairs(SETTINGS_SPEC) do
        local row = CreateFrame("Frame", nil, frame)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -y)
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -y)
        row.key = spec.key

        if spec.type == "slider" then
            buildSliderRow(row, spec)
            y = y + 44
        else
            buildCheckboxRow(row, spec)
            y = y + 24
        end

        frame.rows[i] = row
    end

    local backBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    backBtn:SetSize(70, 22)
    backBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function() SettingsWindow.hide() end)

    local helpBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    helpBtn:SetSize(70, 22)
    helpBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    helpBtn:SetText("Help")
    helpBtn:SetScript("OnClick", function() addon.UI.HelpWindow.show() end)

    local applyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    applyBtn:SetSize(70, 22)
    applyBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function() SettingsWindow.apply() end)

    frame:SetSize(addon.Core.getDB().width or DEFAULT_WIDTH, y + BOTTOM_PAD)

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function SettingsWindow.init(opts)
    config = opts
end

function SettingsWindow.isShown()
    return frame and frame:IsShown() or false
end

function SettingsWindow.show()

    build()

    local tracker = config.getTrackerFrame()
    if not tracker then return end

    local right = tracker:GetRight()
    local top   = tracker:GetTop()

    if right and top then
        local uiRight = UIParent:GetRight() or 0
        local uiTop   = UIParent:GetTop() or 0
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", right - uiRight, top - uiTop)
    end

    frame:SetWidth(tracker:GetWidth())

    for _, row in ipairs(frame.rows) do
        row:setValue(addon.Core.getDB()[row.key])
    end

    wipe(frame.pending)
    tracker:Hide()
    frame:Show()

end

function SettingsWindow.hide()

    if frame then frame:Hide() end

    local tracker = config.getTrackerFrame()
    if tracker then tracker:Show() end

    if config.onApply then config.onApply() end

end

function SettingsWindow.apply()

    if not frame then
        SettingsWindow.hide()
        return
    end

    for key, val in pairs(frame.pending) do
        addon.Core.getDB()[key] = val
    end
    wipe(frame.pending)

    local tracker = config.getTrackerFrame()
    if tracker and tracker.filterBtn then
        tracker.filterBtn:SetChecked(addon.Core.getDB().filterByZone)
    end

    addon.BlizzardTracker.applyState()
    addon.UI.Theme.applyAppearance()
    SettingsWindow.hide()

end

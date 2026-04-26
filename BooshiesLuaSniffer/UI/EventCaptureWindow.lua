local addonName, addon = ...

addon.UI = addon.UI or {}

local EventCaptureWindow = {}
addon.UI.EventCaptureWindow = EventCaptureWindow


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local FRAME_WIDTH       = 820
local FRAME_HEIGHT      = 480
local PANEL_GAP         = 6
local FRAME_PAD         = 8
local RIGHT_PANEL_WIDTH = 200
local STACK_GAP         = 6
local ACTION_BTN_HEIGHT = 22
local INFO_BOX_HEIGHT   = 80

local INFO_TEXT = "Right Click an event in capture list to exclude.\n\nRight Click an event in exclude list to capture."


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local window
local startStopBtn


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- FOOTER ---------------------------------------------------------------------

local function updateStartStopLabel()

    if not startStopBtn then return end

    if addon.EventManager.isCapturing() then
        startStopBtn:SetText("Stop Capture")
    else
        startStopBtn:SetText("Start Capture")
    end

end

local function buildFooterControls()

    local footer = window.footer

    startStopBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    startStopBtn:SetSize(120, 22)
    startStopBtn:SetPoint("LEFT", footer, "LEFT", FRAME_PAD, 0)
    startStopBtn:SetScript("OnClick", function() addon.EventManager.toggle() end)

    updateStartStopLabel()
    addon.EventManager.subscribeToState(updateStartStopLabel)

end

-- CONTENT --------------------------------------------------------------------

local function buildContentPanels()

    local content = window.content

    local infoBox = addon.UI.InfoBox.new(content, {
        text   = INFO_TEXT,
        height = INFO_BOX_HEIGHT,
    })
    infoBox:setAnchors(
        { "BOTTOMLEFT",  content, "BOTTOMRIGHT", -RIGHT_PANEL_WIDTH, 0 },
        { "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0 }
    )

    local clearBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearBtn:SetHeight(ACTION_BTN_HEIGHT)
    clearBtn:SetText("Clear Exclusions")
    clearBtn:SetPoint("BOTTOMLEFT",  infoBox.frame, "TOPLEFT",  0, STACK_GAP)
    clearBtn:SetPoint("BOTTOMRIGHT", infoBox.frame, "TOPRIGHT", 0, STACK_GAP)
    clearBtn:SetScript("OnClick", function() addon.EventCapture.clearExclusions() end)

    local excludeAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    excludeAllBtn:SetHeight(ACTION_BTN_HEIGHT)
    excludeAllBtn:SetText("Exclude All")
    excludeAllBtn:SetPoint("BOTTOMLEFT",  clearBtn, "TOPLEFT",  0, STACK_GAP)
    excludeAllBtn:SetPoint("BOTTOMRIGHT", clearBtn, "TOPRIGHT", 0, STACK_GAP)
    excludeAllBtn:SetScript("OnClick", function() addon.EventCapture.excludeAll() end)

    local right = addon.UI.ExclusionList.attach(content)
    right:setAnchors(
        { "TOPRIGHT",   content,       "TOPRIGHT", 0, 0 },
        { "BOTTOMLEFT", excludeAllBtn, "TOPLEFT",  0, STACK_GAP }
    )

    local left = addon.UI.EventList.attach(content)
    left:setAnchors(
        { "TOPLEFT",     content,       "TOPLEFT",    0, 0 },
        { "BOTTOMRIGHT", infoBox.frame, "BOTTOMLEFT", -PANEL_GAP, 0 }
    )

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function EventCaptureWindow.build()

    if window then return end

    window = addon.UI.Window.new({
        name            = "BooshiesLuaSnifferEventCaptureFrame",
        title           = "Booshies Lua Sniffer",
        width           = FRAME_WIDTH,
        height          = FRAME_HEIGHT,
        strata          = "HIGH",
        loadPosition    = function() return addon.Core.getDB().point end,
        savePosition    = function(p) addon.Core.getDB().point = p end,
        defaultPosition = addon.Core.getDefaults().point,
    })

    buildContentPanels()
    buildFooterControls()

end

function EventCaptureWindow.show()
    if window then window:show() end
end

function EventCaptureWindow.hide()
    if window then window:hide() end
end

function EventCaptureWindow.toggle()
    if window then window:toggle() end
end

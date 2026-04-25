local addonName, addon = ...

addon.UI = addon.UI or {}

local MainFrame = {}
addon.UI.MainFrame = MainFrame


local FRAME_WIDTH        = 820
local FRAME_HEIGHT       = 480
local HEADER_HEIGHT      = 26
local FOOTER_HEIGHT      = 36
local PANEL_GAP          = 6
local FRAME_PAD          = 8
local RIGHT_PANEL_WIDTH  = 200
local STACK_GAP          = 6
local ACTION_BTN_HEIGHT  = 22
local INFO_BOX_HEIGHT    = 80

local INFO_TEXT = "Right Click an event in capture list to exclude.\n\nRight Click an event in exclude list to capture."


local frame
local startStopBtn


local function SavePosition()

    if not frame then return end

    local point, _, relPoint, x, y = frame:GetPoint(1)
    if not point then return end

    addon.Core.getDB().point = { point, "UIParent", relPoint, x, y }

end

local function RestorePosition()

    local db = addon.Core.getDB()
    local p = db.point or addon.Core.getDefaults().point

    frame:ClearAllPoints()
    frame:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])

end


local function BuildHeader()

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)

    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", FRAME_PAD, 0)
    title:SetText("Booshies Lua Sniffer")
    title:SetTextColor(unpack(addon.UI.Theme.colors.accent))

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)

    local sep = frame:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(unpack(addon.UI.Theme.colors.border))
    sep:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

end


local function UpdateStartStopLabel()

    if not startStopBtn then return end

    if addon.EventManager.isCapturing() then
        startStopBtn:SetText("Stop Capture")
    else
        startStopBtn:SetText("Start Capture")
    end

end

local function BuildFooter()

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_HEIGHT)

    local sep = footer:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(unpack(addon.UI.Theme.colors.border))
    sep:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
    sep:SetHeight(1)

    startStopBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    startStopBtn:SetSize(120, 22)
    startStopBtn:SetPoint("LEFT", footer, "LEFT", FRAME_PAD, 0)
    startStopBtn:SetScript("OnClick", function() addon.EventManager.toggle() end)

    UpdateStartStopLabel()
    addon.EventManager.subscribeToState(UpdateStartStopLabel)

end


local function BuildPanels()

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_PAD, -HEADER_HEIGHT - FRAME_PAD)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -FRAME_PAD, FOOTER_HEIGHT + FRAME_PAD)

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


function MainFrame.build()

    if frame then return end

    frame = CreateFrame("Frame", "BooshiesLuaSnifferFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    addon.UI.Theme.applyFlatSkin(frame)
    RestorePosition()

    BuildHeader()
    BuildFooter()
    BuildPanels()

end


function MainFrame.show()

    if not frame then return end
    frame:Show()

end

function MainFrame.hide()

    if not frame then return end
    frame:Hide()

end

function MainFrame.toggle()

    if not frame then return end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end

end

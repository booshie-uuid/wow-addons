local addonName, addon = ...

addon.UI = addon.UI or {}

local TrackerWindow = {}
TrackerWindow.__index = TrackerWindow
addon.UI.TrackerWindow = TrackerWindow


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local DEFAULT_WIDTH      = 280
local HEADER_OFFSET      = 46
local BOTTOM_PAD         = 16
local SCROLL_STEP        = 26
local MIN_MAX_HEIGHT     = 150
local MAX_RESIZE_HEIGHT  = 2000
local DEFAULT_MAX_HEIGHT = 500


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function buildMainFrame(self)

    local frame = CreateFrame("Frame", self.opts.name, UIParent)
    frame:SetSize(self.opts.width or DEFAULT_WIDTH, 200)
    frame:SetFrameStrata("MEDIUM")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    addon.UI.Theme.applyFlatSkin(frame)

    self.frame = frame

end

local function buildHeader(self)

    local frame = self.frame
    local opts = self.opts

    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    header:SetHeight(30)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not opts.isLocked() then frame:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        self:savePosition()
    end)
    frame.header = header
    self.header = header

    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalMed1")
    titleText:SetPoint("LEFT", header, "TOPLEFT", 4, -11)
    titleText:SetJustifyH("LEFT")
    titleText:SetText(opts.title or "")
    self.titleText = titleText

    local titleBtn = CreateFrame("Button", nil, header)
    titleBtn:SetAllPoints(titleText)
    titleBtn:SetHitRectInsets(-3, -3, -2, -2)
    titleBtn:SetFrameLevel(header:GetFrameLevel() + 2)
    titleBtn:RegisterForClicks("LeftButtonUp")
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function()
        if not opts.isLocked() then frame:StartMoving() end
    end)
    titleBtn:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        self:savePosition()
    end)
    titleBtn:SetScript("OnClick", function() opts.onTitleClick() end)
    frame.titleBtn = titleBtn

    local zoneText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetTextColor(unpack(addon.UI.Theme.colors.zoneText))
    self.zoneText = zoneText

end

local function buildHeaderButtons(self)

    local frame = self.frame
    local header = self.header
    local opts = self.opts

    local cogBtn = CreateFrame("Button", nil, header)
    cogBtn:SetSize(16, 16)
    cogBtn:SetPoint("RIGHT", header, "TOPRIGHT", 0, -11)
    cogBtn:SetNormalTexture(addon.UI.Theme.textures.cog)

    local cogHover = cogBtn:CreateTexture(nil, "HIGHLIGHT")
    cogHover:SetAllPoints(cogBtn)
    cogHover:SetColorTexture(unpack(addon.UI.Theme.colors.cogHover))

    cogBtn:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("Settings")
        GameTooltip:Show()
    end)
    cogBtn:SetScript("OnLeave", GameTooltip_Hide)
    cogBtn:SetScript("OnClick", function() opts.onSettings() end)
    frame.cogBtn = cogBtn

    local filterBtn = CreateFrame("CheckButton", "BooshiesQuestLogFilterToggle", header, "UICheckButtonTemplate")
    filterBtn:SetSize(18, 18)
    filterBtn:SetPoint("RIGHT", cogBtn, "LEFT", -6, 0)
    filterBtn:SetChecked(opts.isZoneFilterChecked())
    filterBtn:SetHitRectInsets(-3, -3, -3, -3)

    local filterLabel = filterBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("RIGHT", filterBtn, "LEFT", -2, 0)
    filterLabel:SetText("Zone")

    filterBtn:SetScript("OnClick", function(s)
        opts.onZoneFilterChange(s:GetChecked())
    end)
    filterBtn:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:AddLine("Zone Filter")
        GameTooltip:AddLine(s:GetChecked()
            and "Showing only quests in your current zone."
            or "Showing all quests in your log.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    filterBtn:SetScript("OnLeave", GameTooltip_Hide)
    frame.filterBtn = filterBtn

    local collapseAllBtn = CreateFrame("Button", nil, frame)
    local collapseAllText = collapseAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    collapseAllText:SetPoint("RIGHT", collapseAllBtn, "RIGHT", 0, 0)
    collapseAllText:SetText("collapse all")
    collapseAllText:SetTextColor(unpack(addon.UI.Theme.colors.collapseAllText))

    collapseAllBtn:SetSize((collapseAllText:GetStringWidth() or 60) + 4, 14)
    collapseAllBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -22)
    collapseAllBtn:SetFrameLevel((header:GetFrameLevel() or frame:GetFrameLevel()) + 5)
    collapseAllBtn:SetHitRectInsets(-3, -3, -3, -3)

    collapseAllBtn:SetScript("OnEnter", function() collapseAllText:SetTextColor(unpack(addon.UI.Theme.colors.collapseAllHover)) end)
    collapseAllBtn:SetScript("OnLeave", function() collapseAllText:SetTextColor(unpack(addon.UI.Theme.colors.collapseAllText)) end)
    collapseAllBtn:SetScript("OnClick", function() opts.onCollapseAll() end)
    frame.collapseAllBtn = collapseAllBtn

end

local function buildScrollArea(self)

    local frame = self.frame

    local scrollFrame = CreateFrame("ScrollFrame", "BooshiesQuestLogScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -HEADER_OFFSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, BOTTOM_PAD)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize((self.opts.width or DEFAULT_WIDTH) - 40, 1)
    scrollFrame:SetScrollChild(content)

    local bar = scrollFrame.ScrollBar or _G["BooshiesQuestLogScrollScrollBar"]

    if bar then
        bar:HookScript("OnShow", function(s)
            if scrollFrame._bqlForceHidden then s:Hide() end
        end)
        if bar.SetValueStep then bar:SetValueStep(SCROLL_STEP) end
        if bar.SetStepsPerPage then bar:SetStepsPerPage(4) end
    end

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(s, delta)
        local cur = s:GetVerticalScroll() or 0
        local max = s:GetVerticalScrollRange() or 0
        local new = cur - delta * SCROLL_STEP
        if new < 0 then new = 0 elseif new > max then new = max end
        s:SetVerticalScroll(new)
    end)

    self.scrollFrame = scrollFrame
    self.content = content

end

local function buildResizer(self)

    local frame = self.frame
    local opts = self.opts

    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(44, 6)
    resizer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 4)
    resizer:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizer:RegisterForClicks("LeftButtonDown", "LeftButtonUp")

    local grip = resizer:CreateTexture(nil, "OVERLAY")
    grip:SetAllPoints(resizer)
    grip:SetColorTexture(unpack(addon.UI.Theme.colors.resizeGrip))

    local gripHover = resizer:CreateTexture(nil, "HIGHLIGHT")
    gripHover:SetAllPoints(resizer)
    gripHover:SetColorTexture(unpack(addon.UI.Theme.colors.resizeGripHover))

    local function dragUpdate(s)
        local cur = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        local delta = s._dragStartY - cur
        local newMax = math.floor(s._dragStartMax + delta + 0.5)
        if newMax < MIN_MAX_HEIGHT then newMax = MIN_MAX_HEIGHT end
        if newMax > MAX_RESIZE_HEIGHT then newMax = MAX_RESIZE_HEIGHT end
        if newMax ~= opts.getMaxHeight() then
            opts.onResize(newMax)
        end
    end

    resizer:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        s._dragStartY = select(2, GetCursorPosition()) / UIParent:GetEffectiveScale()
        s._dragStartMax = opts.getMaxHeight() or DEFAULT_MAX_HEIGHT
        s:SetScript("OnUpdate", dragUpdate)
    end)

    resizer:SetScript("OnMouseUp", function(s)
        s._dragStartY = nil
        s:SetScript("OnUpdate", nil)
    end)

    frame.resizer = resizer

end


--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function TrackerWindow.new(opts)

    local self = setmetatable({}, TrackerWindow)
    self.opts = opts or {}

    -- Layout constants exposed on the instance so the refresh pipeline
    -- can read them without each consumer hard-coding chrome geometry.
    self.headerOffset = HEADER_OFFSET
    self.bottomPad = BOTTOM_PAD
    self.minMaxHeight = MIN_MAX_HEIGHT

    buildMainFrame(self)
    buildHeader(self)
    buildHeaderButtons(self)
    buildScrollArea(self)
    buildResizer(self)

    self:restorePosition()
    self:savePosition()

    return self

end


--------------------------------------------------------------------------------
-- PUBLIC METHODS
--------------------------------------------------------------------------------

function TrackerWindow:savePosition()

    if not self.frame then return end

    local right = self.frame:GetRight()
    local top = self.frame:GetTop()
    if not right or not top then return end

    local parent = UIParent
    local uiRight = parent:GetRight() or 0
    local uiTop = parent:GetTop() or 0

    local x = right - uiRight
    local y = top - uiTop

    self.opts.savePosition({ "TOPRIGHT", "UIParent", "TOPRIGHT", x, y })

    -- Re-anchor to TOPRIGHT/UIParent/TOPRIGHT regardless of the source anchor
    -- so legacy saves migrate to a consistent origin.
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", x, y)

end

function TrackerWindow:restorePosition()

    self.frame:ClearAllPoints()

    local p = self.opts.loadPosition() or self.opts.defaultPosition
    local rel = _G[p[2]] or UIParent

    self.frame:SetPoint(p[1], rel, p[3], p[4], p[5])

end

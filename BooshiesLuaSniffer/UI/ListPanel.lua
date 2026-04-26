local addonName, addon = ...

addon.UI = addon.UI or {}

local ListPanel = {}
ListPanel.__index = ListPanel
addon.UI.ListPanel = ListPanel


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local ROW_HEIGHT          = 18
local TITLE_HEIGHT        = 22
local HEADER_ROW_HEIGHT   = 18
local TITLE_PAD_BELOW     = 4
local HEADER_PAD_BELOW    = 4
local COL_GAP             = 8
local PADDING_X           = 4
local SOFT_REFRESH_PERIOD = 1.0


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- COLUMN LAYOUT --------------------------------------------------------------

local function hasHeader(cols)

    for i = 1, #cols do
        if cols[i].header then return true end
    end

    return false

end

local function resolveColumnWidths(cols, available)

    local fixed = 0
    local stretchCount = 0

    for i = 1, #cols do
        local w = cols[i].width or 0
        if w > 0 then
            fixed = fixed + w
        else
            stretchCount = stretchCount + 1
        end
    end

    local gaps = COL_GAP * math.max(0, #cols - 1)
    local stretchW = 0

    if stretchCount > 0 then
        stretchW = math.max(20, math.floor((available - fixed - gaps) / stretchCount))
    end

    local out = {}
    for i = 1, #cols do
        local w = cols[i].width or 0
        out[i] = (w > 0) and w or stretchW
    end

    return out

end

local function layoutCells(cells, cols, widths, parent)

    local x = PADDING_X

    for i = 1, #cells do
        local cell = cells[i]
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", parent, "LEFT", x, 0)
        cell:SetWidth(widths[i])
        cell:SetJustifyH(cols[i].justify or "LEFT")
        x = x + widths[i] + COL_GAP
    end

end

-- WIDGET BUILDERS ------------------------------------------------------------

local function buildHeaderRow(panel, parent)

    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_ROW_HEIGHT)

    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(header)
    bg:SetColorTexture(unpack(addon.UI.Theme.colors.headerBg))

    local sep = header:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(unpack(addon.UI.Theme.colors.border))
    sep:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    local cells = {}
    for i = 1, #panel.columns do
        local col = panel.columns[i]
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetText(col.header or "")
        fs:SetTextColor(unpack(addon.UI.Theme.colors.accent))
        cells[i] = fs
    end

    header.cells = cells
    return header

end

local function buildRow(panel)

    local row = CreateFrame("Button", nil, panel.content)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hover = row:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(row)
    hover:SetColorTexture(unpack(addon.UI.Theme.colors.rowHover))
    hover:Hide()
    row.hover = hover

    local cells = {}
    for i = 1, #panel.columns do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetTextColor(unpack(addon.UI.Theme.colors.text))
        cells[i] = fs
    end
    row.cells = cells

    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)

    row:SetScript("OnClick", function(self, button)

        local item = self.item
        if not item then return end

        if button == "RightButton" and panel.onRightClick then
            panel.onRightClick(item)
        elseif button == "LeftButton" and panel.onLeftClick then
            panel.onLeftClick(item)
        end

    end)

    return row

end

-- RENDERING ------------------------------------------------------------------

local function acquireRow(panel, index)

    local row = panel.rows[index]
    if row then return row end

    row = buildRow(panel)
    panel.rows[index] = row

    return row

end

local function layoutRow(panel, row, index)

    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)

end

local function writeRow(panel, row, item)

    for i = 1, #panel.columns do
        local col = panel.columns[i]
        local v = item[col.key]
        local text = col.format and col.format(v, item) or tostring(v or "")
        row.cells[i]:SetText(text)
    end

end

local function softRefresh(panel)

    for i = 1, #panel.items do
        local row = panel.rows[i]
        if row and row:IsShown() and row.item then
            writeRow(panel, row, row.item)
        end
    end

end


--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function ListPanel.new(parent, opts)

    local self = setmetatable({}, ListPanel)

    self.columns      = opts.columns or { { key = "name", width = 0, justify = "LEFT" } }
    self.onRightClick = opts.onRightClick
    self.onLeftClick  = opts.onLeftClick
    self.items        = {}
    self.rows         = {}

    local frame = CreateFrame("Frame", nil, parent)
    addon.UI.Theme.applyFlatSkin(frame, addon.UI.Theme.colors.panelBg)
    self.frame = frame

    if opts.title then
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
        title:SetText(opts.title)
        title:SetTextColor(unpack(addon.UI.Theme.colors.accent))
        self.title = title
    end

    local scrollTop = TITLE_HEIGHT + TITLE_PAD_BELOW

    if hasHeader(self.columns) then
        local header = buildHeaderRow(self, frame)
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -scrollTop)
        header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -scrollTop)
        self.header = header
        scrollTop = scrollTop + HEADER_ROW_HEIGHT + HEADER_PAD_BELOW
    end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 6)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    self.content = content

    local bar = scroll.ScrollBar
    if bar and bar.SetValueStep then bar:SetValueStep(ROW_HEIGHT) end
    if bar and bar.SetStepsPerPage then bar:SetStepsPerPage(4) end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, delta)

        local cur = s:GetVerticalScroll() or 0
        local max = s:GetVerticalScrollRange() or 0
        local new = cur - delta * ROW_HEIGHT

        if new < 0 then new = 0 end
        if new > max then new = max end

        s:SetVerticalScroll(new)

    end)

    scroll:SetScript("OnSizeChanged", function() self:rebuild() end)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)

        elapsed = elapsed + dt
        if elapsed < SOFT_REFRESH_PERIOD then return end

        elapsed = 0
        softRefresh(self)

    end)

    return self

end


--------------------------------------------------------------------------------
-- PUBLIC METHODS
--------------------------------------------------------------------------------

function ListPanel:setAnchors(...)

    self.frame:ClearAllPoints()

    for i = 1, select("#", ...) do
        local a = select(i, ...)
        self.frame:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end

end

function ListPanel:getTableRightAnchor()
    return self.header or self.scroll
end

function ListPanel:setItems(items)

    self.items = items or {}

    self:rebuild()

end

function ListPanel:rebuild()

    local items = self.items
    local count = #items

    local contentWidth = self.scroll:GetWidth() or 1
    self.content:SetSize(contentWidth, math.max(1, count * ROW_HEIGHT))

    local widths = resolveColumnWidths(self.columns, contentWidth - PADDING_X * 2)

    if self.header then
        layoutCells(self.header.cells, self.columns, widths, self.header)
    end

    for i = 1, count do
        local row = acquireRow(self, i)
        local item = items[i]

        row.item = item
        writeRow(self, row, item)
        layoutCells(row.cells, self.columns, widths, row)

        layoutRow(self, row, i)
        row:Show()
    end

    for i = count + 1, #self.rows do
        local row = self.rows[i]
        if row then
            row.item = nil
            row:Hide()
        end
    end

end

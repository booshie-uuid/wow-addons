local addonName, addon = ...

addon.UI = addon.UI or {}

local Window = {}
Window.__index = Window
addon.UI.Window = Window


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local DEFAULT_WIDTH         = 800
local DEFAULT_HEIGHT        = 480
local DEFAULT_STRATA        = "HIGH"
local DEFAULT_HEADER_HEIGHT = 26
local DEFAULT_FOOTER_HEIGHT = 36
local FRAME_PAD             = 8
local CLOSE_BUTTON_SIZE     = 22


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- POSITION -------------------------------------------------------------------

local function savePosition(window)

    local point, _, relPoint, x, y = window.frame:GetPoint(1)
    if not point then return end

    if window.opts.savePosition then
        window.opts.savePosition({ point, "UIParent", relPoint, x, y })
    end

end

local function restorePosition(window)

    local p

    if window.opts.loadPosition then
        p = window.opts.loadPosition()
    end

    p = p or window.opts.defaultPosition or { "CENTER", "UIParent", "CENTER", 0, 0 }

    window.frame:ClearAllPoints()
    window.frame:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])

end

-- CHROME ---------------------------------------------------------------------

local function buildHeader(window)

    local header = CreateFrame("Button", nil, window.frame)
    header:SetPoint("TOPLEFT",  window.frame, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", window.frame, "TOPRIGHT", 0, 0)
    header:SetHeight(window.headerHeight)

    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window.frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        window.frame:StopMovingOrSizing()
        savePosition(window)
    end)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", header, "LEFT", FRAME_PAD, 0)
    title:SetText(window.opts.title or "")
    title:SetTextColor(unpack(addon.UI.Theme.colors.accent))
    window.titleText = title

    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetSize(CLOSE_BUTTON_SIZE, CLOSE_BUTTON_SIZE)
    close:SetPoint("TOPRIGHT", header, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() window:hide() end)

    local sep = window.frame:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(unpack(addon.UI.Theme.colors.border))
    sep:SetPoint("TOPLEFT",  header, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    return header

end

local function buildFooter(window)

    if window.footerHeight <= 0 then return nil end

    local footer = CreateFrame("Frame", nil, window.frame)
    footer:SetPoint("BOTTOMLEFT",  window.frame, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(window.footerHeight)

    local sep = footer:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(unpack(addon.UI.Theme.colors.border))
    sep:SetPoint("BOTTOMLEFT",  footer, "TOPLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)
    sep:SetHeight(1)

    return footer

end

local function buildContent(window)

    local content = CreateFrame("Frame", nil, window.frame)
    content:SetPoint("TOPLEFT", window.frame, "TOPLEFT", FRAME_PAD, -window.headerHeight - FRAME_PAD)

    if window.footer then
        content:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -FRAME_PAD, window.footerHeight + FRAME_PAD)
    else
        content:SetPoint("BOTTOMRIGHT", window.frame, "BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)
    end

    return content

end


--------------------------------------------------------------------------------
-- CONSTRUCTOR
--------------------------------------------------------------------------------

function Window.new(opts)

    local self = setmetatable({}, Window)

    self.opts         = opts or {}
    self.headerHeight = self.opts.headerHeight or DEFAULT_HEADER_HEIGHT
    self.footerHeight = self.opts.footerHeight or DEFAULT_FOOTER_HEIGHT

    local frame = CreateFrame("Frame", self.opts.name, UIParent)
    frame:SetSize(self.opts.width or DEFAULT_WIDTH, self.opts.height or DEFAULT_HEIGHT)
    frame:SetFrameStrata(self.opts.strata or DEFAULT_STRATA)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:Hide()
    self.frame = frame

    addon.UI.Theme.applyFlatSkin(frame)

    self.header  = buildHeader(self)
    self.footer  = buildFooter(self)
    self.content = buildContent(self)

    restorePosition(self)

    return self

end


--------------------------------------------------------------------------------
-- PUBLIC METHODS
--------------------------------------------------------------------------------

function Window:show()
    self.frame:Show()
end

function Window:hide()
    self.frame:Hide()
end

function Window:toggle()

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end

end

function Window:isShown()
    return self.frame:IsShown()
end

function Window:setTitle(text)
    self.titleText:SetText(text or "")
end

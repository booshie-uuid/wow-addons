local addonName, addon = ...

addon.UI = addon.UI or {}

local Theme = {}
addon.UI.Theme = Theme


--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

Theme.colors = {
    backdrop = { 0.05, 0.05, 0.07, 0.92 },
    border   = { 0.20, 0.20, 0.24, 1.00 },
    panelBg  = { 0.08, 0.08, 0.10, 0.85 },
    headerBg = { 0.12, 0.12, 0.16, 0.95 },
    rowAlt   = { 1.00, 1.00, 1.00, 0.04 },
    rowHover = { 0.30, 0.55, 0.95, 0.18 },
    text     = { 0.95, 0.95, 0.95, 1.00 },
    textDim  = { 0.65, 0.65, 0.70, 1.00 },
    accent   = { 0.31, 0.76, 0.97, 1.00 },
    warn     = { 1.00, 0.65, 0.10, 1.00 },
    danger   = { 1.00, 0.30, 0.30, 1.00 },
}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function makeEdge(frame, side)

    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(Theme.colors.border))

    if side == "top" then
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        t:SetHeight(1)
    elseif side == "bottom" then
        t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        t:SetHeight(1)
    elseif side == "left" then
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        t:SetWidth(1)
    elseif side == "right" then
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        t:SetWidth(1)
    end

    return t

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function Theme.applyFlatSkin(frame, bgColor)

    local color = bgColor or Theme.colors.backdrop

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(unpack(color))
    frame.backdrop = bg

    frame.edges = {
        top    = makeEdge(frame, "top"),
        bottom = makeEdge(frame, "bottom"),
        left   = makeEdge(frame, "left"),
        right  = makeEdge(frame, "right"),
    }

end

function Theme.colorize(color, text)

    return string.format("|cff%02x%02x%02x%s|r",
        math.floor(color[1] * 255),
        math.floor(color[2] * 255),
        math.floor(color[3] * 255),
        text)

end

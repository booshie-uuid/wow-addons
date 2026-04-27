local addonName, addon = ...

addon.UI = addon.UI or {}

local Theme = {}
addon.UI.Theme = Theme


--------------------------------------------------------------------------------
-- TEXTURES
--------------------------------------------------------------------------------

Theme.textures = {
    plusButton  = "Interface\\Buttons\\UI-PlusButton-Up",
    minusButton = "Interface\\Buttons\\UI-MinusButton-Up",
    checkmark   = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    radioButton = "Interface\\Buttons\\UI-RadioButton",
    cog         = "Interface\\Buttons\\UI-OptionsButton",
}


--------------------------------------------------------------------------------
-- COLORS
--------------------------------------------------------------------------------

-- RGBA for fills, RGB for text. Use unpack at call sites.
Theme.colors = {
    -- Row Backgrounds
    superTrackBg     = { 1.0,  0.82, 0.0,  0.12 },
    completedBg      = { 0.12, 0.35, 0.15, 0.45 },
    insideBlobBg     = { 0.25, 0.55, 1.0,  0.18 },
    flashHighlight   = { 1.0,  0.85, 0.3,  0.6  },

    -- Progress Bar
    barBg            = { 0.22, 0.22, 0.24, 0.95 },
    barFill          = { 0.95, 0.82, 0.36, 0.9  },
    barFillComplete  = { 0.35, 0.9,  0.35, 0.9  },

    -- Separators / Overlays
    rowSeparator     = { 1, 1, 1, 0.07 },
    rowHover         = { 1, 1, 1, 0.06 },
    sectionStripe    = { 1, 1, 1, 0.14 },
    sectionSeparator = { 1, 1, 1, 0.07 },
    sectionHover     = { 1, 1, 1, 0.07 },
    cogHover         = { 1, 1, 1, 0.2  },

    -- Settings Dialog
    dialogBackdrop   = { 0,    0,    0,    0.78 },
    dialogBorder     = { 0.25, 0.25, 0.27, 1    },

    -- Resize Grip
    resizeGrip       = { 0.45, 0.45, 0.48, 0.55 },
    resizeGripHover  = { 1,    1,    1,    0.25 },

    -- Text
    sectionTitle        = { 1.0,  0.82, 0.0  },
    itemTitle           = { 1,    1,    1    },
    sectionCount        = { 0.85, 0.85, 0.85 },
    zoneText            = { 0.7,  0.7,  0.7  },
    collapseAllText     = { 0.55, 0.55, 0.6  },
    collapseAllHover    = { 1,    1,    1    },
    objectiveDot        = { 0.75, 0.75, 0.75 },
    objectiveFinished   = { 0.55, 0.9,  0.55 },
    objectiveUnfinished = { 0.95, 0.82, 0.36 },
}


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

-- Frames that have been skinned. Tracked so user-tweakable appearance settings
-- (background opacity, outer border visibility) can be re-applied on the fly.
local skinnedFrames = {}


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function makeEdge(frame, side)

    local t = frame:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(Theme.colors.dialogBorder))

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

-- Returns a WoW chat colour escape like "|cffRRGGBB". Pair with "|r" to
-- reset back to the FontString's default colour.
function Theme.colorEscape(rgb)
    return string.format("|cff%02x%02x%02x",
        math.floor(rgb[1] * 255 + 0.5),
        math.floor(rgb[2] * 255 + 0.5),
        math.floor(rgb[3] * 255 + 0.5))
end

function Theme.applyFlatSkin(frame)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(unpack(Theme.colors.dialogBackdrop))
    frame.backdrop = bg

    frame.edges = {
        top    = makeEdge(frame, "top"),
        bottom = makeEdge(frame, "bottom"),
        left   = makeEdge(frame, "left"),
        right  = makeEdge(frame, "right"),
    }

    table.insert(skinnedFrames, frame)

    -- Match the saved appearance immediately, not only after the next
    -- ApplySettings round-trip.
    local r, g, b = unpack(Theme.colors.dialogBackdrop)
    local db = addon.Core.getDB()
    bg:SetColorTexture(r, g, b, db.backdropAlpha or Theme.colors.dialogBackdrop[4])

    for _, t in pairs(frame.edges) do
        t:SetShown(not db.hideBorder)
    end

end

function Theme.applyAppearance()

    local r, g, b = unpack(Theme.colors.dialogBackdrop)
    local db = addon.Core.getDB()
    local alpha = db.backdropAlpha or Theme.colors.dialogBackdrop[4]
    local showBorder = not db.hideBorder

    for _, f in ipairs(skinnedFrames) do
        if f.backdrop then
            f.backdrop:SetColorTexture(r, g, b, alpha)
        end
        if f.edges then
            for _, t in pairs(f.edges) do
                t:SetShown(showBorder)
            end
        end
    end

end

local addonName, addon = ...

addon.UI = addon.UI or {}

local TrackerSection = {}
addon.UI.TrackerSection = TrackerSection


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local SECTION_HEIGHT = 22
local ROW_GAP        = addon.UI.TrackerEntry.ROW_GAP
local ROW_HEIGHT     = addon.UI.TrackerEntry.ROW_HEIGHT


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local pool   = {}
local active = {}

-- Configuration set by TrackerSection.init.
local config

TrackerSection.active = active


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function createHeader()

    local hdr = CreateFrame("Button", nil, config.content)
    hdr:SetHeight(SECTION_HEIGHT)
    hdr.itemKind = "section"
    hdr:RegisterForClicks("LeftButtonUp")

    local stripe = hdr:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints(hdr)
    stripe:SetColorTexture(unpack(addon.UI.Theme.colors.sectionStripe))

    local hdrSep = hdr:CreateTexture(nil, "ARTWORK")
    hdrSep:SetColorTexture(unpack(addon.UI.Theme.colors.sectionSeparator))
    hdrSep:SetHeight(1)
    hdrSep:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
    hdrSep:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
    hdr.separator = hdrSep

    local hover = hdr:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(hdr)
    hover:SetColorTexture(unpack(addon.UI.Theme.colors.sectionHover))

    local arrow = hdr:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("LEFT", hdr, "LEFT", 4, 0)
    arrow:SetTexture(addon.UI.Theme.textures.minusButton)
    hdr.arrow = arrow

    local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    hdr.title = title

    local count = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(unpack(addon.UI.Theme.colors.sectionCount))
    hdr.count = count

    hdr:SetScript("OnClick", function(self)
        if not self.section then return end
        config.onClick(self)
    end)

    return hdr

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function TrackerSection.init(opts)
    config = opts
end

function TrackerSection.acquire()

    local hdr = table.remove(pool) or createHeader()
    hdr:Show()

    return hdr

end

function TrackerSection.release(hdr)

    hdr:Hide()
    hdr.section = nil
    hdr.key = nil

    table.insert(pool, hdr)

end

function TrackerSection.releaseAll()

    for _, hdr in ipairs(active) do TrackerSection.release(hdr) end
    wipe(active)

end

function TrackerSection.render(spec)

    if not spec.items or #spec.items == 0 then return end

    local hdr = TrackerSection.acquire()
    hdr.section = spec.section
    hdr.key     = "section:" .. spec.section
    hdr.title:SetText(spec.title)
    hdr.title:SetTextColor(unpack(addon.UI.Theme.colors.sectionTitle))

    local collapsed = (addon.Core.getDB().collapsedSections or {})[spec.section] and true or false

    hdr.count:SetText(#spec.items)
    hdr.arrow:SetTexture(collapsed and addon.UI.Theme.textures.plusButton or addon.UI.Theme.textures.minusButton)
    hdr:SetHeight(SECTION_HEIGHT)

    table.insert(active, hdr)
    table.insert(spec.layout, hdr)

    if collapsed then return end

    for _, item in ipairs(spec.items) do
        local entry = spec.populateEntry(item)
        if entry then
            entry:SetHeight(ROW_HEIGHT)
            table.insert(addon.UI.TrackerEntry.active, entry)
            table.insert(spec.layout, entry)
        end
    end

end

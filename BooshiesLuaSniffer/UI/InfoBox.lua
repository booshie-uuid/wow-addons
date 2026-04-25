local addonName, addon = ...

addon.UI = addon.UI or {}

local InfoBox = {}
InfoBox.__index = InfoBox
addon.UI.InfoBox = InfoBox


local PADDING = 8


function InfoBox.new(parent, opts)

    local self = setmetatable({}, InfoBox)

    local frame = CreateFrame("Frame", nil, parent)
    addon.UI.Theme.applyFlatSkin(frame, addon.UI.Theme.colors.panelBg)
    self.frame = frame

    if opts.height then
        frame:SetHeight(opts.height)
    end

    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
    fs:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PADDING, PADDING)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(2)
    fs:SetTextColor(unpack(addon.UI.Theme.colors.textDim))
    fs:SetText(opts.text or "")
    self.text = fs

    return self

end


function InfoBox:setText(text)
    self.text:SetText(text or "")
end

function InfoBox:setAnchors(...)

    self.frame:ClearAllPoints()

    for i = 1, select("#", ...) do
        local a = select(i, ...)
        self.frame:SetPoint(a[1], a[2], a[3], a[4], a[5])
    end

end

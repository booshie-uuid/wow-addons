local addonName, addon = ...

addon.UI = addon.UI or {}

local EventList = {}
addon.UI.EventList = EventList


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local AGE_REFRESH_PERIOD = 1.0


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- FORMATTERS -----------------------------------------------------------------

local function formatCount(count)

    if not count then return "" end

    local Theme = addon.UI.Theme

    if count >= 100 then return Theme.colorize(Theme.colors.danger, count) end
    if count >= 50  then return Theme.colorize(Theme.colors.warn, count) end

    return tostring(count)

end

local function formatLastSeen(t)

    if not t then return "" end

    local elapsed = GetTime() - t
    local Theme   = addon.UI.Theme

    if elapsed < 1 then return "now" end

    if elapsed >= 60 then
        return Theme.colorize(Theme.colors.danger, "60s+")
    end

    local label = string.format("%ds ago", math.floor(elapsed))

    if elapsed >= 30 then
        return Theme.colorize(Theme.colors.warn, label)
    end

    return label

end

-- WIDGETS --------------------------------------------------------------------

local function createLabeledCheckbox(parent, text, getInitial, onChange)

    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(18, 18)
    cb:SetHitRectInsets(-3, -3, -3, -3)
    cb:SetChecked(getInitial())

    local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("RIGHT", cb, "LEFT", -2, 0)
    label:SetText(text)

    cb:SetScript("OnClick", function(self) onChange(self:GetChecked()) end)

    cb.label = label
    return cb

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function EventList.attach(parent)

    local panel = addon.UI.ListPanel.new(parent, {
        title   = "Captured Events",
        columns = {
            { key = "name",     header = "Event",     width = 0,   justify = "LEFT"  },
            { key = "count",    header = "Count",     width = 60,  justify = "RIGHT", format = formatCount },
            { key = "lastSeen", header = "Last Seen", width = 70,  justify = "RIGHT", format = formatLastSeen },
        },
        onRightClick = function(item) addon.EventCapture.exclude(item.name) end,
    })

    local function refresh()
        panel:setItems(addon.EventCapture.getEntries())
    end

    local execOrderCb = createLabeledCheckbox(panel.frame, "Execution Order",
        function() return addon.EventCapture.isExecutionOrder() end,
        function(v) addon.EventCapture.setExecutionOrder(v) end)
    execOrderCb:SetPoint("BOTTOMRIGHT", panel:getTableRightAnchor(), "TOPRIGHT", 0, 4)

    local hideOlderCb = createLabeledCheckbox(panel.frame, "Hide Older",
        function() return addon.EventCapture.isHideOlder() end,
        function(v) addon.EventCapture.setHideOlder(v) end)
    hideOlderCb:SetPoint("RIGHT", execOrderCb.label, "LEFT", -16, 0)

    addon.EventCapture.subscribe("entries", refresh)
    refresh()

    local elapsed = 0
    panel.frame:HookScript("OnUpdate", function(_, dt)

        if not addon.EventCapture.isHideOlder() then return end

        elapsed = elapsed + dt
        if elapsed < AGE_REFRESH_PERIOD then return end

        elapsed = 0
        refresh()

    end)

    return panel

end

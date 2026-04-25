local addonName, addon = ...

addon.UI = addon.UI or {}

local ExclusionList = {}
addon.UI.ExclusionList = ExclusionList


function ExclusionList.attach(parent)

    local panel = addon.UI.ListPanel.new(parent, {
        title   = "Excluded",
        columns = {
            { key = "name", width = 0, justify = "LEFT" },
        },
        onRightClick = function(item) addon.EventCapture.include(item.name) end,
    })

    local function refresh()
        panel:setItems(addon.EventCapture.getExclusions())
    end

    addon.EventCapture.subscribe("exclusions", refresh)
    refresh()

    return panel

end

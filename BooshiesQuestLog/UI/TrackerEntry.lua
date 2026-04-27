local addonName, addon = ...

addon.UI = addon.UI or {}

local TrackerEntry = {}
addon.UI.TrackerEntry = TrackerEntry


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local ROW_HEIGHT     = 26
local ROW_GAP        = 6
local BAR_HEIGHT     = 3
local BAR_BOTTOM_PAD = 3
local TOP_CLUSTER_Y  = 3        -- vertical offset for arrow + track + completion icon
local FLASH_DURATION = 0.8

TrackerEntry.ROW_HEIGHT = ROW_HEIGHT
TrackerEntry.ROW_GAP    = ROW_GAP


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local pool   = {}
local active = {}

-- Configuration set by TrackerEntry.init.
local config

TrackerEntry.active = active


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

-- Three full-row textures (super-track tint, completed tint, flash overlay)
-- plus the flash AnimationGroup and the entry:FlashAttention method.
local function buildBackgrounds(entry)

    -- Sublevel ordering: insideBlobBg (-3) is the deepest tint so super-track
    -- gold and completed green layer on top of it without obscuring the blue
    -- proximity indicator.
    local insideBlobBg = entry:CreateTexture(nil, "BACKGROUND", nil, -3)
    insideBlobBg:SetAllPoints(entry)
    insideBlobBg:SetColorTexture(unpack(addon.UI.Theme.colors.insideBlobBg))
    insideBlobBg:Hide()
    entry.insideBlobBg = insideBlobBg

    local superBg = entry:CreateTexture(nil, "BACKGROUND", nil, -2)
    superBg:SetAllPoints(entry)
    superBg:SetColorTexture(unpack(addon.UI.Theme.colors.superTrackBg))
    superBg:Hide()
    entry.superBg = superBg

    local completeBg = entry:CreateTexture(nil, "BACKGROUND")
    completeBg:SetAllPoints(entry)
    completeBg:SetColorTexture(unpack(addon.UI.Theme.colors.completedBg))
    completeBg:Hide()
    entry.completeBg = completeBg

    local flashBg = entry:CreateTexture(nil, "OVERLAY")
    flashBg:SetAllPoints(entry)
    flashBg:SetColorTexture(unpack(addon.UI.Theme.colors.flashHighlight))
    flashBg:Hide()
    entry.flashBg = flashBg

    local flashAnim = flashBg:CreateAnimationGroup()
    local fade = flashAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(FLASH_DURATION)
    fade:SetSmoothing("OUT")
    flashAnim:SetScript("OnFinished", function() flashBg:Hide() end)
    entry.flashAnim = flashAnim

    function entry:FlashAttention()
        self.flashAnim:Stop()
        self.flashBg:SetAlpha(1)
        self.flashBg:Show()
        self.flashAnim:Play()
    end

end

local function buildSeparator(entry)

    local sep = entry:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(unpack(addon.UI.Theme.colors.rowSeparator))
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", entry, "BOTTOMLEFT", 0, -math.floor(ROW_GAP / 2))
    sep:SetPoint("BOTTOMRIGHT", entry, "BOTTOMRIGHT", 0, -math.floor(ROW_GAP / 2))
    entry.separator = sep

end

-- Defines `entry.btn` (the clickable area covering the title row) and
-- `entry.hover` (the highlight texture, shown by wireClick on enter/leave).
local function buildButton(entry)

    local btn = CreateFrame("Button", nil, entry)
    btn:SetPoint("TOPLEFT", entry, "TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", entry, "TOPRIGHT", 0, 0)
    btn:SetHeight(ROW_HEIGHT)
    btn:RegisterForClicks("LeftButtonUp")
    entry.btn = btn

    local hover = btn:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints(btn)
    hover:SetColorTexture(unpack(addon.UI.Theme.colors.rowHover))
    hover:Hide()
    entry.hover = hover

end

local function buildArrow(entry)

    local arrow = entry.btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(14, 14)
    arrow:SetPoint("LEFT", entry.btn, "LEFT", 3, TOP_CLUSTER_Y)
    arrow:SetTexture(addon.UI.Theme.textures.plusButton)
    entry.arrow = arrow

end

-- Radio-style super-track button on the right edge. The OnClick handler reads
-- entry.item at click time so it stays current as the entry gets recycled
-- across different items by the pool.
local function buildSuperTrackBtn(entry)

    local track = CreateFrame("Button", nil, entry.btn)
    track:SetSize(18, 18)
    track:SetPoint("RIGHT", entry.btn, "RIGHT", -2, TOP_CLUSTER_Y)
    track:SetHitRectInsets(-4, -4, -4, -4)

    local ring = track:CreateTexture(nil, "ARTWORK")
    ring:SetAllPoints(track)
    ring:SetTexture(addon.UI.Theme.textures.radioButton)
    ring:SetTexCoord(0, 0.25, 0, 1)
    ring:SetVertexColor(0.75, 0.75, 0.78)

    local fill = track:CreateTexture(nil, "OVERLAY")
    fill:SetAllPoints(track)
    fill:SetTexture(addon.UI.Theme.textures.radioButton)
    fill:SetTexCoord(0.25, 0.5, 0, 1)
    fill:SetVertexColor(1.0, 0.82, 0.0)
    fill:Hide()

    local trackHover = track:CreateTexture(nil, "HIGHLIGHT")
    trackHover:SetAllPoints(track)
    trackHover:SetTexture(addon.UI.Theme.textures.radioButton)
    trackHover:SetTexCoord(0.5, 0.75, 0, 1)
    trackHover:SetBlendMode("ADD")

    track._checked = false
    function track:SetChecked(v)
        self._checked = v and true or false
        fill:SetShown(self._checked)
    end
    function track:GetChecked() return self._checked end

    track:SetScript("OnClick", function(self)
        local item = entry.item
        if not item or item.kind ~= "quest" or not C_SuperTrack then return end
        if self:GetChecked() then
            C_SuperTrack.SetSuperTrackedQuestID(0)
        else
            C_SuperTrack.SetSuperTrackedQuestID(item.id)
        end
    end)
    track:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Super Track")
        GameTooltip:AddLine("Place a waypoint arrow on the map for this quest.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    track:SetScript("OnLeave", GameTooltip_Hide)

    entry.trackCheck = track

end

local function buildCompletionIcon(entry)

    local completionIcon = entry.btn:CreateTexture(nil, "OVERLAY")
    completionIcon:SetSize(14, 14)
    completionIcon:SetPoint("RIGHT", entry.trackCheck, "LEFT", -4, 0)
    completionIcon:SetTexture(addon.UI.Theme.textures.checkmark)
    completionIcon:Hide()
    entry.completionIcon = completionIcon

end

-- Background bar + foreground fill, plus entry:SetProgress(pct, hasAny, complete)
-- which clamps to [0, 1], picks the appropriate fill colour, and falls back to
-- a sensible width when the bar hasn't been measured yet.
local function buildProgressBar(entry)

    local barBg = entry:CreateTexture(nil, "ARTWORK")
    barBg:SetColorTexture(unpack(addon.UI.Theme.colors.barBg))
    barBg:SetHeight(BAR_HEIGHT)
    barBg:SetPoint("BOTTOMLEFT", entry.btn, "BOTTOMLEFT", 4, BAR_BOTTOM_PAD)
    barBg:SetPoint("BOTTOMRIGHT", entry.btn, "BOTTOMRIGHT", -4, BAR_BOTTOM_PAD)
    barBg:Hide()
    entry.barBg = barBg

    local barFill = entry:CreateTexture(nil, "OVERLAY")
    barFill:SetColorTexture(unpack(addon.UI.Theme.colors.barFill))
    barFill:SetHeight(BAR_HEIGHT)
    barFill:SetPoint("LEFT", barBg, "LEFT", 0, 0)
    barFill:SetPoint("TOP", barBg, "TOP", 0, 0)
    barFill:SetPoint("BOTTOM", barBg, "BOTTOM", 0, 0)
    barFill:SetWidth(1)
    barFill:Hide()
    entry.barFill = barFill

    function entry:SetProgress(pct, hasAny, complete)

        if not hasAny then
            self.barBg:Hide()
            self.barFill:Hide()
            return
        end

        self.barBg:Show()
        self.barFill:Show()

        local w = self.barBg:GetWidth()
        if not w or w <= 1 then
            local cw = (config.content and config.content:GetWidth()) or ((addon.Core.getDB().width or 280) - 40)
            w = cw - 8
        end

        local clamped = math.min(math.max(pct or 0, 0), 1)
        self.barFill:SetWidth(math.max(1, w * clamped))

        if complete or clamped >= 1 then
            self.barFill:SetColorTexture(unpack(addon.UI.Theme.colors.barFillComplete))
        else
            self.barFill:SetColorTexture(unpack(addon.UI.Theme.colors.barFill))
        end

    end

end

-- Title font string + entry:SetComplete(flag), which re-anchors the title's
-- right edge to the completion icon when complete (so the icon is visible to
-- its right) or to the track button when not.
local function buildTitle(entry)

    local title = entry.btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", entry.arrow, "RIGHT", 4, 0)
    title:SetPoint("RIGHT", entry.trackCheck, "LEFT", -2, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    entry.title = title

    function entry:SetComplete(flag)
        flag = flag and true or false
        self.completeBg:SetShown(flag)
        self.completionIcon:SetShown(flag)
        self.title:ClearAllPoints()
        self.title:SetPoint("LEFT", self.arrow, "RIGHT", 4, 0)
        if flag then
            self.title:SetPoint("RIGHT", self.completionIcon, "LEFT", -2, 0)
        else
            self.title:SetPoint("RIGHT", self.trackCheck, "LEFT", -2, 0)
        end
    end

end

local function wireClick(entry)

    local btn = entry.btn
    local hover = entry.hover

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnEnter", function() hover:Show() end)
    btn:SetScript("OnLeave", function() hover:Hide() end)

    btn:SetScript("OnClick", function(self, button)

        local item = entry.item
        if not item then return end

        -- Ctrl+Left: super-track this quest.
        if IsControlKeyDown() and button == "LeftButton" then
            if item.kind == "quest" and C_SuperTrack then
                local cur = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0
                if cur == item.id then
                    C_SuperTrack.SetSuperTrackedQuestID(0)
                else
                    C_SuperTrack.SetSuperTrackedQuestID(item.id)
                end
            end
            return
        end

        -- Ctrl+Right: dump debug metadata (debug mode only).
        if IsControlKeyDown() and button == "RightButton" then
            if addon.Core.getDB().debug and item.dump then
                item.dump()
            end
            return
        end

        -- Shift+Left: untrack.
        if IsShiftKeyDown() and button == "LeftButton" then
            if item.untrack then item.untrack() end
            return
        end

        -- Right: open the appropriate Blizzard window for this entry's kind.
        if button == "RightButton" then
            if item.openDetails then item.openDetails() end
            return
        end

        -- Plain left click: toggle expand/collapse.
        config.onClick(entry)

    end)

end

local function createEntry()

    local entry = CreateFrame("Frame", nil, config.content)
    entry:SetHeight(ROW_HEIGHT)

    buildBackgrounds(entry)
    buildSeparator(entry)
    buildButton(entry)
    buildArrow(entry)
    buildSuperTrackBtn(entry)
    buildCompletionIcon(entry)
    buildProgressBar(entry)
    buildTitle(entry)
    wireClick(entry)

    return entry

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function TrackerEntry.init(opts)
    config = opts
end

function TrackerEntry.acquire()

    local entry = table.remove(pool) or createEntry()
    entry:Show()

    return entry

end

function TrackerEntry.release(entry)

    if config.onRelease then config.onRelease(entry) end

    entry:Hide()

    if entry.superBg then entry.superBg:Hide() end
    if entry.insideBlobBg then entry.insideBlobBg:Hide() end
    if entry.flashAnim then entry.flashAnim:Stop() end
    if entry.flashBg then entry.flashBg:Hide() end

    entry.item = nil

    table.insert(pool, entry)

end

function TrackerEntry.releaseAll()

    for _, entry in ipairs(active) do TrackerEntry.release(entry) end
    wipe(active)

end

local addonName, addon = ...

addon.UI = addon.UI or {}

local ObjectivePanel = {}
addon.UI.ObjectivePanel = ObjectivePanel


--------------------------------------------------------------------------------
-- LOCAL CONSTANTS
--------------------------------------------------------------------------------

local ROW_HEIGHT = addon.UI.TrackerEntry.ROW_HEIGHT

local OBJ_LEFT_INDENT  = 3
local OBJ_RIGHT_MARGIN = 26
local COL_MARKER_W     = 14
local COL_GAP          = 4
local OBJ_TOP_PAD      = 5
local OBJ_BOTTOM_PAD   = 5
local OBJ_LINE_GAP     = 3
local LINE_VCENTER     = 5

-- Synthetic objective appended to a complete quest's expansion, telling the
-- player there's nothing left to do but hand it in.
local READY_TO_TURN_IN_PART = { desc = "Ready to turn in", count = nil, finished = true }


--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

-- Hidden FontString reused as a measuring stick for column widths. Allocated
-- lazily on first measureText call.
local measureFS


--------------------------------------------------------------------------------
-- LOCAL FUNCTIONS
--------------------------------------------------------------------------------

local function splitObjective(obj)

    local text = obj.text or ""

    -- "5/10 Slay Murlocs" form: pull the count off the front and return the
    -- remainder as the description.
    local n, m, rest = text:match("^(%d+)%s*/%s*(%d+)%s+(.*)$")
    if n and m and rest and rest ~= "" then
        return rest, n .. "/" .. m
    end

    -- Otherwise synthesise "have/need" from the structured fields if present.
    if obj.numRequired and obj.numRequired > 0 then
        return text, (obj.numFulfilled or 0) .. "/" .. obj.numRequired
    end

    return text, nil

end

local function measureText(text)

    if not measureFS then
        measureFS = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        measureFS:Hide()
    end

    measureFS:SetText(text or "")
    return measureFS:GetStringWidth() or 0

end

local function fetchObjectivesFor(row)

    if row.itemKind == "achievement" then
        return addon.Data.Achievements.getCriteria(row.achievementID)
    elseif row.itemKind == "recipe" then
        return addon.Data.Recipes.getReagents(row.recipeID)
    elseif row.itemKind == "activity" then
        return addon.Data.JournalActivities.getObjectives(row.activityID)
    elseif row.itemKind == "initiative" then
        return addon.Data.NeighbourhoodActivities.getObjectives(row.initiativeID)
    end

    return C_QuestLog.GetQuestObjectives(row.questID) or {}

end

-- The widest count string is tracked so descriptions align in a column.
local function measureObjectiveParts(objectives)

    local parts = {}
    local maxCountW = 0

    for i, obj in ipairs(objectives) do
        local desc, count = splitObjective(obj)

        parts[i] = { desc = desc, count = count, finished = obj.finished }

        if count and count ~= "" then
            local w = measureText(count)
            if w > maxCountW then maxCountW = w end
        end
    end

    return parts, maxCountW

end

local function computeObjectiveColumns(objW, maxCountW)

    local countColW = math.ceil(maxCountW)
    local hasCountCol = countColW > 0
    local descX = COL_MARKER_W + COL_GAP + (hasCountCol and (countColW + COL_GAP) or 0)
    local descW = math.max(objW - descX, 40)

    return {
        countColW   = countColW,
        hasCountCol = hasCountCol,
        descX       = descX,
        descW       = descW,
    }

end

-- Returns the y position for the next row to use.
local function layoutObjectiveRow(row, e, y, part, cols)

    local isFinished = part.finished
    local color = isFinished and addon.UI.Theme.colors.objectiveFinished or addon.UI.Theme.colors.objectiveUnfinished

    e.tex:ClearAllPoints()
    e.dot:ClearAllPoints()

    if isFinished then
        e.tex:SetPoint("CENTER", row.objFrame, "TOPLEFT", COL_MARKER_W / 2, -y - LINE_VCENTER)
        e.tex:SetTexture(addon.UI.Theme.textures.checkmark)
        e.tex:Show()
        e.dot:Hide()
    else
        e.dot:SetPoint("CENTER", row.objFrame, "TOPLEFT", COL_MARKER_W / 2, -y - LINE_VCENTER)
        e.dot:SetJustifyH("CENTER")
        e.dot:SetText("•")
        e.dot:SetTextColor(unpack(addon.UI.Theme.colors.objectiveDot))
        e.dot:Show()
        e.tex:Hide()
    end

    e.count:ClearAllPoints()

    if cols.hasCountCol and part.count then
        e.count:SetPoint("TOPLEFT", row.objFrame, "TOPLEFT", COL_MARKER_W + COL_GAP, -y)
        e.count:SetWidth(cols.countColW)
        e.count:SetText(part.count)
        e.count:SetTextColor(color[1], color[2], color[3])
        e.count:Show()
    else
        e.count:Hide()
    end

    e.desc:ClearAllPoints()
    e.desc:SetPoint("TOPLEFT", row.objFrame, "TOPLEFT", cols.descX, -y)
    e.desc:SetWidth(cols.descW)
    e.desc:SetWordWrap(true)
    e.desc:SetTextColor(color[1], color[2], color[3])
    e.desc:SetText(part.desc)
    e.desc:Show()

    return y + e.desc:GetStringHeight() + OBJ_LINE_GAP

end

-- Each entry holds a texture + dot/count/desc font strings, pooled by index
-- per row.
local function ensureObjEntry(row, i)

    local e = row.objLines[i]

    if not (type(e) == "table" and e.desc) then
        if e and type(e.Hide) == "function" then pcall(e.Hide, e) end

        e = {}
        e.tex = row.objFrame:CreateTexture(nil, "OVERLAY")
        e.tex:SetSize(10, 10)
        e.dot = row.objFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e.count = row.objFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e.count:SetJustifyH("LEFT")
        e.desc = row.objFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        e.desc:SetJustifyH("LEFT")
        e.desc:SetWordWrap(true)
        row.objLines[i] = e
    end

    return e

end

-- Initialises the empty `row.objLines` pool on first expansion as a side effect.
local function ensureObjFrame(row, objW)

    if not row.objFrame then
        row.objFrame = CreateFrame("Frame", nil, row)
        row.objLines = {}
    end

    row.objFrame:ClearAllPoints()
    row.objFrame:SetPoint("TOPLEFT", row, "TOPLEFT", OBJ_LEFT_INDENT, -(ROW_HEIGHT + OBJ_TOP_PAD))
    row.objFrame:SetWidth(objW)
    row.objFrame:Show()

end

-- Called after rendering so a previously-larger row doesn't leave stale
-- entries visible.
local function hideTrailingObjLines(row, fromIdx)

    for i = fromIdx + 1, #row.objLines do
        local e = row.objLines[i]
        if type(e) == "table" then
            if e.tex then e.tex:Hide() end
            if e.dot then e.dot:Hide() end
            if e.count then e.count:Hide() end
            if e.desc then e.desc:Hide() end
        end
    end

end


--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ObjectivePanel.collapse(row)

    row.expanded = false
    row.arrow:SetTexture(addon.UI.Theme.textures.plusButton)
    if row.objFrame then row.objFrame:Hide() end
    row:SetHeight(ROW_HEIGHT)

end

function ObjectivePanel.expand(row)

    row.expanded = true
    row.arrow:SetTexture(addon.UI.Theme.textures.minusButton)

    local parent = row:GetParent()
    local contentW = (parent and parent:GetWidth()) or ((addon.Core.getDB().width or 280) - 40)
    local objW = math.max(contentW - OBJ_LEFT_INDENT - OBJ_RIGHT_MARGIN, 60)

    local objectives = fetchObjectivesFor(row)
    local parts, maxCountW = measureObjectiveParts(objectives)
    local cols = computeObjectiveColumns(objW, maxCountW)

    ensureObjFrame(row, objW)

    local y, idx = 0, 0
    for i, part in ipairs(parts) do
        idx = i
        y = layoutObjectiveRow(row, ensureObjEntry(row, i), y, part, cols)
    end

    -- Quests get an extra "Ready to turn in" line once their objectives are all done.
    if row.itemKind ~= "achievement" and row.questID and C_QuestLog.IsComplete(row.questID) then
        idx = idx + 1
        y = layoutObjectiveRow(row, ensureObjEntry(row, idx), y, READY_TO_TURN_IN_PART, cols)
    end

    hideTrailingObjLines(row, idx)

    local totalY = math.max(y - OBJ_LINE_GAP, 1)
    row.objFrame:SetHeight(totalY)
    row:SetHeight(ROW_HEIGHT + OBJ_TOP_PAD + totalY + OBJ_BOTTOM_PAD)

end

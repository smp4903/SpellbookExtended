-- Toast: the level-up announcement. Rows rise into place one after another,
-- hold, then the whole block drifts upward and fades, like scrolling combat text.
-- Click-through, so it never steals a click mid-fight.

local _, SBE = ...

SBE.Toast = {}

do -- Private Scope
    local Toast = SBE.Toast

    local MAX_ROWS = 8
    local ROW_HEIGHT = 30
    local ICON_SIZE = 26
    local WIDTH = 300
    local RISE = 18
    local ROW_IN = 0.35
    local STAGGER = 0.12
    local HOLD = 6
    local FADE = 1.5
    local DRIFT = 40

    local GOLD = { 1, 0.82, 0 }
    local WHITE = { 1, 1, 1 }
    local NOTE = { 0.5, 0.75, 1 }
    local FADED = { 0.75, 0.75, 0.75 }

    local frame = nil
    local rows = {}
    local startTime = 0
    local rowCount = 0

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Create, CreateRow, Font, Show, OnUpdate, Ease

    function Font(fontString, size)
        fontString:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
        fontString:SetShadowOffset(1, -1)
    end

    function Create()
        frame = CreateFrame("Frame", "SpellbookExtendedToast", UIParent)
        frame:SetSize(WIDTH, 80)
        -- Below Blizzard's own level-up banner.
        frame:SetPoint("TOP", UIParent, "TOP", 0, -260)
        frame:SetFrameStrata("HIGH")
        frame:EnableMouse(false)
        frame:Hide()

        -- A dark band that fades out at both ends, so the text reads on any scene.
        local left = frame:CreateTexture(nil, "BACKGROUND")
        left:SetPoint("TOPLEFT", frame, "TOPLEFT", -60, 8)
        left:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", 0, -8)
        left:SetColorTexture(1, 1, 1, 1)
        left:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.55))

        local right = frame:CreateTexture(nil, "BACKGROUND")
        right:SetPoint("TOPLEFT", frame, "TOP", 0, 8)
        right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 60, -8)
        right:SetColorTexture(1, 1, 1, 1)
        right:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))

        frame.title = frame:CreateFontString(nil, "OVERLAY")
        Font(frame.title, 24)
        frame.title:SetPoint("TOP", frame, "TOP", 0, 0)
        frame.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

        frame.subtitle = frame:CreateFontString(nil, "OVERLAY")
        Font(frame.subtitle, 13)
        frame.subtitle:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)
        frame.subtitle:SetTextColor(WHITE[1], WHITE[2], WHITE[3])

        frame:SetScript("OnUpdate", OnUpdate)
    end

    function CreateRow(index)
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH - 40, ROW_HEIGHT)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.name = row:CreateFontString(nil, "OVERLAY")
        Font(row.name, 15)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetJustifyH("LEFT")

        row.tag = row:CreateFontString(nil, "OVERLAY")
        Font(row.tag, 11)
        row.tag:SetPoint("LEFT", row.name, "RIGHT", 6, -1)
        row.tag:SetTextColor(FADED[1], FADED[2], FADED[3])

        rows[index] = row
        return row
    end

    function Ease(p)
        return 1 - (1 - p) * (1 - p)
    end

    -- Every frame: rows enter one by one, then the block fades and drifts.
    function OnUpdate(self)
        local elapsed = GetTime() - startTime
        local enterEnd = (rowCount - 1) * STAGGER + ROW_IN

        for index = 1, rowCount do
            local row = rows[index]
            local p = math.min(1, math.max(0, (elapsed - (index - 1) * STAGGER) / ROW_IN))
            row:SetAlpha(p)
            row:ClearAllPoints()
            row:SetPoint("TOP", frame, "TOP", 0, row.baseY - RISE * (1 - Ease(p)))
        end

        local fadeStart = enterEnd + HOLD
        if (elapsed < fadeStart) then
            self:SetAlpha(1)
            return
        end

        local p = math.min(1, (elapsed - fadeStart) / FADE)
        self:SetAlpha(1 - p)
        self:ClearAllPoints()
        self:SetPoint("TOP", UIParent, "TOP", 0, -260 + DRIFT * Ease(p))
        if (p >= 1) then
            self:Hide()
        end
    end

    -- items: { entry, other }, other marking quest and book spells.
    function Show(level, items, cost)
        if (not frame) then
            Create()
        end

        frame.title:SetText("Level "..level)
        local trainable = 0
        for _, item in ipairs(items) do
            if (not item.other) then
                trainable = trainable + 1
            end
        end
        local subtitle = trainable.." new "..(trainable == 1 and "spell" or "spells").." at your trainer"
        if (SBE.options.showCosts and cost and cost > 0) then
            subtitle = subtitle.."  "..SBE.FormatMoney(cost)
        end
        frame.subtitle:SetText(subtitle)

        local y = -58
        rowCount = math.min(#items, MAX_ROWS)
        for index = 1, rowCount do
            local item = items[index]
            local entry = item.entry
            local row = rows[index] or CreateRow(index)

            row.icon:SetTexture(SBE.GetSpellIcon(entry.id) or 134400)
            row.name:SetText(SBE.GetSpellName(entry.id) or ("Spell "..entry.id))
            local colour = item.other and NOTE or WHITE
            row.name:SetTextColor(colour[1], colour[2], colour[3])

            local tag = entry.rank and ("Rank "..entry.rank) or ""
            if (item.other) then
                tag = (tag ~= "" and (tag.."  ") or "")..(entry.quest and "Class quest" or "Class book")
            end
            row.tag:SetText(tag)

            row.baseY = y
            row:SetAlpha(0)
            row:Show()
            y = y - ROW_HEIGHT
        end
        for index = rowCount + 1, #rows do
            rows[index]:Hide()
        end

        if (#items > MAX_ROWS) then
            local extra = rows[MAX_ROWS]
            extra.icon:SetTexture(nil)
            extra.name:SetText("+"..(#items - MAX_ROWS + 1).." more in the spellbook")
            extra.name:SetTextColor(FADED[1], FADED[2], FADED[3])
            extra.tag:SetText("")
        end

        frame:SetHeight(-y)
        frame:ClearAllPoints()
        frame:SetPoint("TOP", UIParent, "TOP", 0, -260)
        frame:SetAlpha(1)
        startTime = GetTime()
        frame:Show()
    end

    Toast.Show = Show
    Toast.Hide = function() if (frame) then frame:Hide() end end
end

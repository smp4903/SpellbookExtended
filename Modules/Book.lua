-- Book: the compact spellbook. A narrow scrolling list for browsing spells and
-- dragging them to bars, with the spells still to learn at the end of each
-- section. Blizzard's spellbook is never modified, so its secure code (casting
-- from the book) stays untainted.

local _, SBE = ...

SBE.Book = {}

do -- Private Scope
    local Book = SBE.Book
    local BookData = SBE.BookData
    local SpellList = SBE.SpellList

    local WIDTH = 280
    local MAX_HEIGHT = 620
    local MIN_HEIGHT = 360
    local ROW_HEIGHT = 24
    local CHILD_HEIGHT = 22
    local HEADER_HEIGHT = 24
    local ICON_SIZE = 20
    local CHILD_ICON_SIZE = 18
    local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
    -- The frame's own maximise button, as on Blizzard's spellbook.
    local EXPAND_ATLAS = "RedButton-Expand"
    local ARROW = "Interface\\ChatFrame\\ChatFrameExpandArrow"

    local INK = { 0.18, 0.10, 0.02 }
    local INK_SOFT = { 0.36, 0.24, 0.12 }
    local INK_FADED = { 0.45, 0.40, 0.34 }
    local TRAINABLE = { 0.10, 0.45, 0.05 } -- the panel's "Available" green
    local BAD = { 0.62, 0.08, 0.04 }
    local NOTE = { 0.10, 0.25, 0.55 }
    local TONES = { bad = BAD, note = NOTE, soft = INK_SOFT }

    local frame = nil
    local blizzButton = nil
    local search = ""
    local expanded = {}
    local collapsed = {}
    local rowPool, headerPool = {}, {}
    local usedRows, usedHeaders = 0, 0
    local panelHooked = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Create, CreateToolbar, CreatePage, CreateFooter, Colour, Height, SetHover, MenuToggles
    local AcquireRow, AcquireHeader, ReleaseAll, DrawRow, DrawHeader, DrawFooter, Refresh
    local OnRowClick, OnRowDrag, ShowRowTooltip, UpdateCooldown, UpdateCooldowns, OnHeaderClick
    local TogglePanel, OpenPanelAt, UpdateFooterLit, HookPanel, ShowFilterMenu
    local EnsureBlizzButton, ShowBlizzButton, HideBlizzButton, PlaceBlizzButton, LayerBlizzButton, SavePosition, RestorePosition
    local Toggle, ShowBook, PlaySoundKit

    function Colour(fontString, c)
        fontString:SetTextColor(c[1], c[2], c[3])
    end

    function PlaySoundKit(name)
        if (PlaySound and SOUNDKIT and SOUNDKIT[name]) then
            pcall(PlaySound, SOUNDKIT[name])
        end
    end

    function Height()
        local screen = UIParent:GetHeight() or 0
        return math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, screen - 180))
    end

    function Create()
        if (frame) then
            return frame
        end

        local ok, created = pcall(CreateFrame, "Frame", "SpellbookExtendedBook", UIParent, "PortraitFrameTemplate")
        if (not ok) then
            created = CreateFrame("Frame", "SpellbookExtendedBook", UIParent, "BasicFrameTemplateWithInset")
        end
        frame = created

        frame:SetSize(WIDTH, Height())
        frame:SetToplevel(true)
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self)
            HideBlizzButton()
            self:StartMoving()
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            SavePosition()
            ShowBlizzButton()
        end)
        RestorePosition()
        table.insert(UISpecialFrames, "SpellbookExtendedBook")

        if (frame.SetTitle) then
            frame:SetTitle(SPELLBOOK or "Spellbook")
        end
        if (not (frame.SetPortraitToUnit and pcall(frame.SetPortraitToUnit, frame, "player")) and frame.SetPortraitToAsset) then
            frame:SetPortraitToAsset(BOOK_ICON)
        end

        CreateToolbar()
        CreatePage()
        CreateFooter()

        -- Hooked last: hiding runs OnHide, which needs the widgets above.
        frame:Hide()
        frame:SetScript("OnShow", function()
            PlaySoundKit("IG_SPELLBOOK_OPEN")
            HookPanel()
            Refresh()
            ShowBlizzButton()
            if (SBE.options.autoOpen) then
                SBE.Dock.Anchor()
                SBE.Panel.Show()
            end
        end)
        frame:SetScript("OnHide", function()
            PlaySoundKit("IG_SPELLBOOK_CLOSE")
            if (frame.search:GetText() ~= "") then
                frame.search:SetText("")
            end
            frame.search:ClearFocus()
            search = ""
            HideBlizzButton()
            local panel = SBE.Panel.Frame()
            if (panel and panel.dockedTo == frame) then
                panel:Hide()
            end
        end)

        return frame
    end

    function SavePosition()
        local point, _, relativePoint, x, y = frame:GetPoint()
        if (point) then
            SBE.options.bookPoint = { point, relativePoint, x, y }
        end
    end

    function RestorePosition()
        frame:ClearAllPoints()
        local saved = SBE.options.bookPoint
        if (saved) then
            frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
        else
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
    end

    function CreateToolbar()
        -- Beside the close button, where Blizzard's spellbook has its maximise
        -- button. This greyed stand-in marks the spot; the secure button that
        -- opens Blizzard's spellbook sits over it out of combat.
        local spot = CreateFrame("Button", nil, frame)
        spot:SetSize(24, 24)
        if (frame.CloseButton) then
            spot:SetPoint("RIGHT", frame.CloseButton, "LEFT", 2, 0)
        else
            spot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
        end
        if (spot.SetNormalAtlas) then
            spot:SetNormalAtlas(EXPAND_ATLAS.."-Disabled")
        end
        spot:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Blizzard's spellbook")
            if (InCombatLockdown()) then
                GameTooltip:AddLine("Not available in combat.", 1, 0.1, 0.1)
            else
                -- The real button should be here; put it back.
                ShowBlizzButton()
                GameTooltip:AddLine("Use the micro button if this does not open it.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        spot:SetScript("OnLeave", GameTooltip_Hide)
        frame.blizzSpot = spot

        -- The same arrow Blizzard's spellbook uses for its settings menu.
        local ok, filterButton = pcall(CreateFrame, "DropdownButton", nil, frame, "UIPanelArrowDropdownButtonTemplate")
        if (ok and filterButton and filterButton.SetupMenu) then
            filterButton:SetupMenu(function(_, root)
                for _, toggle in ipairs(MenuToggles()) do
                    root:CreateCheckbox(toggle[1], toggle[2], toggle[3])
                end
            end)
        else
            filterButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            filterButton:SetSize(20, 20)
            filterButton:SetText("...")
            filterButton:SetScript("OnClick", ShowFilterMenu)
        end
        filterButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -33)
        frame.filterButton = filterButton

        local box = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
        box:SetHeight(20)
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -31)
        box:SetPoint("RIGHT", filterButton, "LEFT", -8, 0)
        box:HookScript("OnTextChanged", function(self)
            search = self:GetText() or ""
            Refresh()
        end)
        if (box.Instructions) then
            box.Instructions:SetText(SEARCH or "Search")
        end
        frame.search = box
    end

    function CreatePage()
        local ok, page = pcall(CreateFrame, "Frame", nil, frame, "InsetFrameTemplate")
        if (not ok) then
            page = CreateFrame("Frame", nil, frame)
        end
        page:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -60)
        page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 28)
        frame.page = page

        local bg = page:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        SBE.Panel.ApplyParchment(bg)

        -- ScrollFrameTemplate brings the thin modern scroll bar; older clients
        -- fall back to the classic one.
        local ok, scroll = pcall(CreateFrame, "ScrollFrame", "SpellbookExtendedBookScroll", page, "ScrollFrameTemplate")
        local gutter = 20
        if (not ok or not scroll) then
            scroll = CreateFrame("ScrollFrame", "SpellbookExtendedBookScroll", page, "UIPanelScrollFrameTemplate")
            gutter = 26
        end
        scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
        scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -gutter, 6)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(WIDTH - 50, 10)
        scroll:SetScrollChild(content)
        scroll:SetScript("OnSizeChanged", function(_, width)
            content:SetWidth(width)
        end)
        frame.scroll = scroll
        frame.content = content

        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        empty:SetPoint("TOP", content, "TOP", 0, -30)
        empty:SetShadowOffset(0, 0)
        Colour(empty, INK_SOFT)
        frame.empty = empty
    end

    -- "Spells to learn": opens the panel docked beside the book.
    function CreateFooter()
        local footer = CreateFrame("Button", nil, frame)
        footer:SetHeight(20)
        footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 5)
        footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 5)

        footer.lit = footer:CreateTexture(nil, "BACKGROUND")
        footer.lit:SetAllPoints()
        footer.lit:SetColorTexture(0.95, 0.79, 0.30, 0.15)
        footer.lit:Hide()
        footer:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")

        footer.label = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        footer.label:SetPoint("LEFT", footer, "LEFT", 4, 0)
        footer.label:SetText("Spells to learn")

        footer.arrow = footer:CreateTexture(nil, "OVERLAY")
        footer.arrow:SetSize(10, 10)
        footer.arrow:SetPoint("LEFT", footer.label, "RIGHT", 3, 0)
        footer.arrow:SetTexture(ARROW)

        footer.summary = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        footer.summary:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
        footer.summary:SetJustifyH("RIGHT")

        footer:SetScript("OnClick", TogglePanel)
        footer:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Spells to learn")
            GameTooltip:AddLine("Show the spells and ranks you can still learn, by level.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        footer:SetScript("OnLeave", GameTooltip_Hide)
        frame.footer = footer
    end

    function AcquireHeader()
        usedHeaders = usedHeaders + 1
        local header = headerPool[usedHeaders]
        if (header) then
            header:Show()
            return header
        end

        header = CreateFrame("Button", nil, frame.content)
        header:SetHeight(HEADER_HEIGHT)

        header.toggle = header:CreateTexture(nil, "ARTWORK")
        header.toggle:SetSize(12, 12)
        header.toggle:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 2, 6)

        header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header.title:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 18, 4)
        header.title:SetShadowOffset(0, 0)
        Colour(header.title, INK)

        header.count = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header.count:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -4, 5)
        header.count:SetShadowOffset(0, 0)
        Colour(header.count, INK_SOFT)

        header.rule = header:CreateTexture(nil, "ARTWORK")
        header.rule:SetHeight(1)
        header.rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 1)
        header.rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 1)
        header.rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.55)

        header.hover = header:CreateTexture(nil, "BACKGROUND")
        header.hover:SetAllPoints()
        header.hover:SetColorTexture(1, 0.95, 0.8, 0.25)
        header.hover:Hide()

        header:SetScript("OnClick", OnHeaderClick)
        header:SetScript("OnEnter", function(self)
            SetHover(self, true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.data.name)
            GameTooltip:AddLine(self.data.collapsed and "Click to show this section." or "Click to fold this section.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        header:SetScript("OnLeave", function(self)
            SetHover(self, false)
            GameTooltip_Hide()
        end)

        headerPool[usedHeaders] = header
        return header
    end

    function AcquireRow()
        usedRows = usedRows + 1
        local row = rowPool[usedRows]
        if (row) then
            row:Show()
            return row
        end

        row = CreateFrame("Button", nil, frame.content)
        row:SetHeight(ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:RegisterForDrag("LeftButton")

        row.toggle = row:CreateTexture(nil, "ARTWORK")
        row.toggle:SetSize(12, 12)
        row.toggle:SetPoint("LEFT", row, "LEFT", 2, 0)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local ok, cooldown = pcall(CreateFrame, "Cooldown", nil, row, "CooldownFrameTemplate")
        if (ok and cooldown) then
            cooldown:SetAllPoints(row.icon)
            if (cooldown.SetHideCountdownNumbers) then
                cooldown:SetHideCountdownNumbers(true)
            end
            row.cooldown = cooldown
        end

        row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.meta:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.meta:SetJustifyH("RIGHT")
        row.meta:SetShadowOffset(0, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.meta, "LEFT", -4, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.name:SetShadowOffset(0, 0)

        -- Behind the icon and text, so the hovered row keeps its own colours.
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 0.95, 0.8, 0.35)
        row.hover:Hide()

        row:SetScript("OnClick", OnRowClick)
        row:SetScript("OnDragStart", OnRowDrag)
        row:SetScript("OnEnter", function(self)
            SetHover(self, true)
            ShowRowTooltip(self)
        end)
        row:SetScript("OnLeave", function(self)
            SetHover(self, false)
            GameTooltip_Hide()
        end)

        rowPool[usedRows] = row
        return row
    end

    function SetHover(region, on)
        region.hover:SetShown(on)
    end

    function ReleaseAll()
        for i = 1, usedRows do
            rowPool[i]:Hide()
            rowPool[i].data = nil
        end
        for i = 1, usedHeaders do
            headerPool[i]:Hide()
        end
        usedRows, usedHeaders = 0, 0
    end

    function DrawHeader(header, data)
        header.data = data
        header.title:SetText(data.name)
        header.toggle:SetTexture(data.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        -- Folded sections show how many spells they hold, known and upcoming.
        local count = data.collapsed and (data.count + data.upcoming) or data.count
        header.count:SetText(count > 0 and count or "")
    end

    function OnHeaderClick(header)
        local data = header.data
        if (data) then
            collapsed[data.name] = not data.collapsed or nil
            Refresh()
        end
    end

    function DrawRow(row, data)
        row.data = data
        local child = data.kind == "child"
        local spell = data.spell

        row:SetHeight(child and CHILD_HEIGHT or ROW_HEIGHT)
        row.icon:ClearAllPoints()
        row.icon:SetSize(child and CHILD_ICON_SIZE or ICON_SIZE, child and CHILD_ICON_SIZE or ICON_SIZE)
        row.icon:SetPoint("LEFT", row, "LEFT", child and 34 or 18, 0)
        row.name:SetFontObject(child and "GameFontNormalSmall" or "GameFontNormal")

        if (data.hasChildren) then
            row.toggle:SetTexture(data.expanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
            row.toggle:Show()
        else
            row.toggle:Hide()
        end

        row.name:SetText(data.name)
        row.meta:SetText(data.meta or "")

        if (data.kind == "upcoming") then
            local item = data.item
            local trainable = item.state == SpellList.STATE_TRAINABLE
            row.icon:SetTexture(SBE.GetSpellIcon(item.entry.id) or 134400)
            row.icon:SetDesaturated(true)
            row.icon:SetAlpha(trainable and 0.8 or 0.55)
            Colour(row.name, trainable and TRAINABLE or INK_FADED)
            Colour(row.meta, TONES[data.tone] or INK_SOFT)
            if (row.cooldown) then
                row.cooldown:Clear()
            end
            return
        end

        row.icon:SetTexture(spell.icon or (spell.spellID and SBE.GetSpellIcon(spell.spellID)) or 134400)
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1)
        Colour(row.name, (child or spell.passive) and INK_SOFT or INK)
        Colour(row.meta, INK_SOFT)
        UpdateCooldown(row)
    end

    -- Cooldown values can be hidden from addons in combat; a failed read clears the swipe.
    function UpdateCooldown(row)
        local cooldown = row.cooldown
        local spell = row.data and row.data.spell
        if (not cooldown) then
            return
        end
        if (not (spell and spell.slot and C_SpellBook and C_SpellBook.GetSpellBookItemCooldown)) then
            cooldown:Clear()
            return
        end
        local ok = pcall(function()
            local info = C_SpellBook.GetSpellBookItemCooldown(spell.slot, spell.bank)
            if (info and info.isEnabled) then
                cooldown:SetCooldown(info.startTime, info.duration, info.modRate)
            else
                cooldown:Clear()
            end
        end)
        if (not ok) then
            cooldown:Clear()
        end
    end

    function UpdateCooldowns()
        if (not (frame and frame:IsShown())) then
            return
        end
        for i = 1, usedRows do
            if (rowPool[i].data and rowPool[i].data.kind ~= "upcoming") then
                UpdateCooldown(rowPool[i])
            end
        end
    end

    function DrawFooter(summary)
        local footer = frame.footer
        local text
        if (summary.trainable > 0) then
            text = summary.trainable.." now"
            if (SBE.options.showCosts and summary.cost > 0) then
                text = text.." · "..SBE.FormatMoney(summary.cost)
            end
        elseif (summary.nextLevel) then
            text = "next at level "..summary.nextLevel
        else
            text = "all learned"
        end
        footer.summary:SetText(text)
        UpdateFooterLit()
    end

    function UpdateFooterLit()
        if (not frame) then
            return
        end
        local panel = SBE.Panel.Frame()
        local open = panel and panel:IsShown() and panel.dockedTo == frame
        frame.footer.lit:SetShown(open and true or false)
        if (open) then
            frame.footer.arrow:SetTexCoord(1, 0, 0, 1)
        else
            frame.footer.arrow:SetTexCoord(0, 1, 0, 1)
        end
    end

    function HookPanel()
        if (panelHooked) then
            return
        end
        local panel = SBE.Panel.Create()
        panel:HookScript("OnShow", UpdateFooterLit)
        panel:HookScript("OnHide", UpdateFooterLit)
        panelHooked = true
    end

    function Refresh()
        if (not (frame and frame:IsShown())) then
            return
        end
        ReleaseAll()

        local rows, summary = BookData.Build({
            search = search,
            showUpcoming = SBE.options.bookUpcoming,
            hidePassives = GetCVarBool and GetCVarBool("spellBookHidePassives"),
            unfoldAll = SBE.options.bookUnfoldAll,
            expanded = expanded,
            collapsed = collapsed,
        })

        local content = frame.content
        local y = 0
        for index, data in ipairs(rows) do
            if (data.kind == "header") then
                local header = AcquireHeader()
                y = y + (index > 1 and 6 or 0)
                header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                header:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                DrawHeader(header, data)
                y = y + HEADER_HEIGHT + 2
            else
                local row = AcquireRow()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                DrawRow(row, data)
                y = y + (data.kind == "child" and CHILD_HEIGHT or ROW_HEIGHT)
            end
        end
        content:SetHeight(math.max(y, 10))

        if (#rows == 0) then
            frame.empty:SetText(search ~= "" and "No matching spells." or "No spells yet.")
            frame.empty:Show()
        else
            frame.empty:Hide()
        end

        DrawFooter(summary)
    end

    function OnRowClick(row, button)
        local data = row.data
        if (not data) then
            return
        end

        if (IsModifiedClick("CHATLINK")) then
            local id = data.kind == "upcoming" and data.item.entry.id or data.spell.spellID
            local link = id and C_Spell.GetSpellLink(id)
            if (link) then
                ChatEdit_InsertLink(link)
            end
            return
        end

        if (data.kind == "upcoming") then
            local entry = data.item.entry
            if (button == "RightButton") then
                local implicit = data.item.state == SpellList.STATE_SKIPPED and not SBE.options.skipped[entry.id]
                if (not entry.quest and not entry.book and not implicit) then
                    SpellList.ToggleSkip(entry.id)
                    GameTooltip_Hide()
                end
            else
                OpenPanelAt(entry.id)
            end
            return
        end

        if (button == "RightButton") then
            local spell = data.spell
            if (spell.pet and spell.slot and C_SpellBook.GetSpellBookItemAutoCast) then
                local allowed = C_SpellBook.GetSpellBookItemAutoCast(spell.slot, spell.bank)
                if (allowed) then
                    C_SpellBook.ToggleSpellBookItemAutoCast(spell.slot, spell.bank)
                end
            end
            return
        end

        if (data.hasChildren) then
            expanded[data.key] = not data.expanded or nil
            Refresh()
        end
    end

    function OnRowDrag(row)
        local data = row.data
        if (not data or data.kind == "upcoming") then
            return
        end
        -- The client can refuse the spellbook pickup without an error; when
        -- the cursor stays empty, the spell is picked up by its ID instead.
        local spell = data.spell
        local function holding()
            return GetCursorInfo and GetCursorInfo() ~= nil
        end
        if (spell.slot and C_SpellBook.PickupSpellBookItem) then
            pcall(C_SpellBook.PickupSpellBookItem, spell.slot, spell.bank)
        end
        if (not holding() and spell.spellID) then
            local pickup = (C_Spell and C_Spell.PickupSpell) or PickupSpell
            if (pickup) then
                pcall(pickup, spell.spellID)
            end
        end
        SBE.DebugPrint(string.format("drag %s slot=%s id=%s holding=%s", tostring(spell.name),
            tostring(spell.slot), tostring(spell.spellID), tostring(holding())))
    end

    function ShowRowTooltip(row)
        local data = row.data
        if (not data) then
            return
        end

        if (data.kind == "upcoming") then
            SBE.Panel.ItemTooltip(row, data.item, "Click to show it in Spells to learn.")
            return
        end

        local spell = data.spell
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        local shown = spell.slot and GameTooltip.SetSpellBookItem
            and pcall(GameTooltip.SetSpellBookItem, GameTooltip, spell.slot, spell.bank)
        if (not shown and spell.spellID) then
            GameTooltip:SetSpellByID(spell.spellID)
        end

        if (data.hasChildren) then
            GameTooltip:AddLine(data.expanded and "Click to hide lower ranks." or "Click to show lower ranks.", 0.6, 0.6, 0.6, true)
        end
        if (not spell.passive) then
            GameTooltip:AddLine("Drag to your action bars.", 0.6, 0.6, 0.6, true)
        end
        if (spell.pet and spell.slot and C_SpellBook.GetSpellBookItemAutoCast
            and C_SpellBook.GetSpellBookItemAutoCast(spell.slot, spell.bank)) then
            GameTooltip:AddLine("Right-click to toggle autocast.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end

    function TogglePanel()
        HookPanel()
        local panel = SBE.Panel.Create()
        if (panel:IsShown() and panel.dockedTo == frame) then
            panel:Hide()
        else
            SBE.Dock.Anchor()
            panel:Show()
        end
        UpdateFooterLit()
    end

    function OpenPanelAt(id)
        HookPanel()
        SBE.Dock.Anchor()
        SBE.Panel.JumpTo(id)
        UpdateFooterLit()
    end

    function MenuToggles()
        local options = SBE.options
        local function refreshAfter(fn)
            return function()
                fn()
                Refresh()
            end
        end
        return {
            { "Show upcoming spells", function() return options.bookUpcoming end,
                refreshAfter(function() options.bookUpcoming = not options.bookUpcoming end) },
            { "Hide passive spells", function() return GetCVarBool("spellBookHidePassives") end,
                refreshAfter(function() SetCVar("spellBookHidePassives", GetCVarBool("spellBookHidePassives") and "0" or "1") end) },
            { "Unfold all ranks", function() return options.bookUnfoldAll end,
                refreshAfter(function() options.bookUnfoldAll = not options.bookUnfoldAll end) },
        }
    end

    -- Only where the client lacks dropdown buttons.
    function ShowFilterMenu(owner)
        local toggles = MenuToggles()
        if (MenuUtil and MenuUtil.CreateContextMenu) then
            MenuUtil.CreateContextMenu(owner, function(_, root)
                for _, toggle in ipairs(toggles) do
                    root:CreateCheckbox(toggle[1], toggle[2], toggle[3])
                end
            end)
        else
            toggles[1][3]()
        end
    end

    -- Opens Blizzard's spellbook through a secure click on the micro button,
    -- so the book opens untainted and casting from it keeps working. Secure
    -- buttons cannot be shown or moved in combat, hence the stand-in.
    -- It is placed on the screen, never anchored to the book: a frame a
    -- secure button anchors to becomes protected, and could then not be
    -- opened or closed in combat.
    function EnsureBlizzButton()
        if (blizzButton or InCombatLockdown()) then
            return blizzButton
        end
        local micro = _G.SpellbookMicroButton or _G.PlayerSpellsMicroButton
        if (not micro) then
            return nil
        end

        local button = CreateFrame("Button", "SpellbookExtendedBlizzardBook", UIParent, "SecureActionButtonTemplate")
        button:SetAttribute("type", "click")
        button:SetAttribute("clickbutton", micro)
        button:SetAttribute("useOnKeyDown", false)
        button:RegisterForClicks("LeftButtonUp")
        button:SetSize(24, 24)
        if (button.SetNormalAtlas) then
            button:SetNormalAtlas(EXPAND_ATLAS)
            button:SetPushedAtlas(EXPAND_ATLAS.."-Pressed")
            button:SetHighlightAtlas("RedButton-Highlight", "ADD")
        else
            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture(BOOK_ICON)
        end

        button:HookScript("OnClick", function()
            if (frame:IsShown()) then
                frame:Hide()
            end
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Blizzard's spellbook")
            GameTooltip:AddLine("Open the full spellbook instead.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button:SetScript("OnUpdate", LayerBlizzButton)
        button:Hide()
        blizzButton = button
        return button
    end

    -- On the book's own layer, just above it: windows opened over the book
    -- cover the button too. Clicking a window raises it, so the level is
    -- checked every frame while the button shows.
    function LayerBlizzButton(button)
        if (InCombatLockdown()) then
            return
        end
        local strata, level = frame:GetFrameStrata(), frame:GetFrameLevel() + 20
        if (button:GetFrameStrata() ~= strata) then
            button:SetFrameStrata(strata)
        end
        if (button:GetFrameLevel() ~= level) then
            button:SetFrameLevel(level)
        end
    end

    -- Over the stand-in, in screen coordinates.
    function PlaceBlizzButton(button)
        local x, y = frame.blizzSpot:GetCenter()
        if (not x) then
            return false
        end
        local scale = frame.blizzSpot:GetEffectiveScale() / UIParent:GetEffectiveScale()
        button:ClearAllPoints()
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * scale, y * scale)
        return true
    end

    -- Right after the book shows, its buttons may not have a screen position
    -- yet; placing is retried on the next frames until they do.
    function ShowBlizzButton(tries)
        if (InCombatLockdown() or not (frame and frame:IsShown())) then
            return
        end
        local button = EnsureBlizzButton()
        if (not button) then
            return
        end
        if (PlaceBlizzButton(button)) then
            LayerBlizzButton(button)
            button:Show()
        elseif ((tries or 0) < 10) then
            C_Timer.After(0, function() ShowBlizzButton((tries or 0) + 1) end)
        end
    end

    function HideBlizzButton()
        if (blizzButton and not InCombatLockdown()) then
            blizzButton:Hide()
        end
    end

    function ShowBook()
        Create()
        frame:Show()
    end

    function Toggle()
        Create()
        if (frame:IsShown()) then
            frame:Hide()
        else
            frame:Show()
        end
    end

    SBE.On("SBE_CHANGED", function() Refresh() end)
    SBE.On("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
    SBE.On("PET_BAR_UPDATE", function() SpellList.Changed() end)
    SBE.On("UNIT_PET", function(_, unit)
        if (unit == "player") then
            SpellList.Changed()
        end
    end)
    -- The last moment secure frames can still be hidden before combat.
    SBE.On("PLAYER_REGEN_DISABLED", HideBlizzButton)
    SBE.On("PLAYER_REGEN_ENABLED", ShowBlizzButton)

    Book.Create = Create
    Book.Toggle = Toggle
    Book.Show = ShowBook
    Book.Frame = function() return frame end
    Book.IsShown = function() return frame ~= nil and frame:IsShown() end
end

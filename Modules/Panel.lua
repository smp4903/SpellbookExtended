-- Panel: the spellbook-style window. One header per unlock level, then a dense
-- grid of the spells that unlock there.

local _, SBE = ...

SBE.Panel = {}

do -- Private Scope
    local Panel = SBE.Panel
    local SpellList = SBE.SpellList

    local PANEL_WIDTH = 700
    local PANEL_HEIGHT = 640
    local TILE_WIDTH = 164
    local TILE_HEIGHT = 36
    local ICON_SIZE = 30
    local HEADER_HEIGHT = 30
    local SECTION_GAP = 10
    local INSET = 12

    -- Parchment palette, matched to the spellbook's page text.
    local INK = { 0.18, 0.10, 0.02 }
    local INK_SOFT = { 0.36, 0.24, 0.12 }
    local INK_FADED = { 0.45, 0.40, 0.34 }
    local GOOD = { 0.10, 0.45, 0.05 }
    local BAD = { 0.62, 0.08, 0.04 }
    local NOTE = { 0.10, 0.25, 0.55 }

    -- Retail atlas names that could exist on this client; verified before use.
    local PARCHMENT_ATLASES = { "QuestBG-Parchment", "Spellbook-Page-1", "spellbook-background-evergreen-left" }

    local panel = nil
    local filter = { search = "", tab = 0 }
    local tilePool, headerPool = {}, {}
    local usedTiles, usedHeaders = 0, 0

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Create, CreateChrome, CreateToolbar, CreateFooter, CreateCheckbox, CreateParchment
    local AcquireTile, AcquireHeader, ReleaseAll, Refresh, DrawTile, DrawHeader
    local ShowTooltip, OnTileClick, Colour, SubText, Toggle, ShowPanel, HidePanel

    function Colour(fontString, c)
        fontString:SetTextColor(c[1], c[2], c[3])
    end

    function Create()
        if (panel) then
            return panel
        end

        local ok, frame = pcall(CreateFrame, "Frame", "SpellbookExtendedPanel", UIParent, "PortraitFrameTemplate")
        if (not ok) then
            frame = CreateFrame("Frame", "SpellbookExtendedPanel", UIParent, "BasicFrameTemplateWithInset")
        end
        panel = frame

        panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
        panel:SetPoint("CENTER")
        panel:SetToplevel(true)
        panel:SetMovable(true)
        panel:SetClampedToScreen(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", function(self)
            if (not self.dockedTo) then
                self:StartMoving()
            end
        end)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetScript("OnShow", Refresh)
        panel:Hide()

        -- Escape closes it like any Blizzard panel.
        table.insert(UISpecialFrames, "SpellbookExtendedPanel")

        CreateChrome()
        CreateToolbar()
        CreateParchment()
        CreateFooter()

        return panel
    end

    function CreateChrome()
        local title = "Trainable Spells"
        if (panel.SetTitle) then
            panel:SetTitle(title)
        elseif (panel.TitleText) then
            panel.TitleText:SetText(title)
        end

        if (panel.SetPortraitToAsset) then
            panel:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
        end
    end

    function CreateToolbar()
        local tabs = { "All" }
        for _, name in ipairs(SpellList.Tabs()) do
            table.insert(tabs, name)
        end

        panel.tabButtons = {}
        local previous = nil
        for index, label in ipairs(tabs) do
            local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
            button:SetText(label)
            button:SetSize(math.max(60, button:GetFontString():GetStringWidth() + 24), 22)
            if (previous) then
                button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else
                button:SetPoint("TOPLEFT", panel, "TOPLEFT", 66, -32)
            end
            button:SetScript("OnClick", function()
                filter.tab = index - 1
                SBE.options.tab = filter.tab
                Refresh()
            end)
            button.tabIndex = index - 1
            table.insert(panel.tabButtons, button)
            previous = button
        end

        local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
        search:SetSize(180, 20)
        search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -33)
        search:HookScript("OnTextChanged", function(self)
            filter.search = self:GetText() or ""
            Refresh()
        end)
        if (search.Instructions) then
            search.Instructions:SetText("Search spells")
        end
        panel.search = search
    end

    function CreateParchment()
        local page = CreateFrame("Frame", nil, panel)
        page:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -62)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 40)
        panel.page = page

        local bg = page:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local atlas = nil
        for _, name in ipairs(PARCHMENT_ATLASES) do
            if (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) then
                atlas = name
                break
            end
        end
        if (atlas) then
            bg:SetAtlas(atlas)
        else
            bg:SetColorTexture(1, 1, 1, 1)
            bg:SetGradient("VERTICAL", CreateColor(0.80, 0.70, 0.52, 1), CreateColor(0.93, 0.85, 0.68, 1))
        end

        local scroll = CreateFrame("ScrollFrame", "SpellbookExtendedScrollFrame", page, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", page, "TOPLEFT", INSET, -INSET)
        scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, INSET)

        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(PANEL_WIDTH - 70, 10)
        scroll:SetScrollChild(content)
        scroll:SetScript("OnSizeChanged", function(self, width)
            content:SetWidth(width)
            if (panel:IsShown()) then
                Refresh()
            end
        end)
        panel.scroll = scroll
        panel.content = content

        local empty = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        empty:SetPoint("TOP", content, "TOP", 0, -40)
        Colour(empty, INK_SOFT)
        empty:SetShadowOffset(0, 0)
        panel.empty = empty
    end

    function CreateCheckbox(label, key, tooltip)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        text:SetText(label)
        cb.label = text
        cb:SetScript("OnClick", function(self)
            SBE.options[key] = self:GetChecked() and true or false
            Refresh()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
        cb.key = key
        return cb
    end

    function CreateFooter()
        local known = CreateCheckbox("Show known", "showKnown", "Also list spells and ranks you have already learned.")
        known:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)

        local now = CreateCheckbox("Trainable now", "trainableOnly", "Only list spells a trainer will sell you at your current level.")
        now:SetPoint("LEFT", known.label, "RIGHT", 12, 0)

        local other = CreateCheckbox("Quest & book spells", "showQuestAndBook", "Include spells learned from class quests or class books instead of the trainer.")
        other:SetPoint("LEFT", now.label, "RIGHT", 12, 0)

        panel.checkboxes = { known, now, other }

        local summary = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 16)
        summary:SetJustifyH("RIGHT")
        panel.summary = summary
    end

    function AcquireTile()
        usedTiles = usedTiles + 1
        local tile = tilePool[usedTiles]
        if (tile) then
            tile:Show()
            return tile
        end

        tile = CreateFrame("Button", nil, panel.content)
        tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
        tile:RegisterForClicks("LeftButtonUp")

        tile.icon = tile:CreateTexture(nil, "ARTWORK")
        tile.icon:SetSize(ICON_SIZE, ICON_SIZE)
        tile.icon:SetPoint("LEFT", tile, "LEFT", 2, 0)

        tile.name = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tile.name:SetPoint("TOPLEFT", tile.icon, "TOPRIGHT", 6, -1)
        tile.name:SetPoint("RIGHT", tile, "RIGHT", -2, 0)
        tile.name:SetJustifyH("LEFT")
        tile.name:SetWordWrap(false)
        tile.name:SetShadowOffset(0, 0)

        tile.sub = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tile.sub:SetPoint("BOTTOMLEFT", tile.icon, "BOTTOMRIGHT", 6, 1)
        tile.sub:SetPoint("RIGHT", tile, "RIGHT", -2, 0)
        tile.sub:SetJustifyH("LEFT")
        tile.sub:SetWordWrap(false)
        tile.sub:SetShadowOffset(0, 0)

        tile.highlight = tile:CreateTexture(nil, "HIGHLIGHT")
        tile.highlight:SetAllPoints()
        tile.highlight:SetColorTexture(1, 0.9, 0.6, 0.25)

        tile:SetScript("OnEnter", ShowTooltip)
        tile:SetScript("OnLeave", GameTooltip_Hide)
        tile:SetScript("OnClick", OnTileClick)

        tilePool[usedTiles] = tile
        return tile
    end

    function AcquireHeader()
        usedHeaders = usedHeaders + 1
        local header = headerPool[usedHeaders]
        if (header) then
            header:Show()
            return header
        end

        header = CreateFrame("Frame", nil, panel.content)
        header:SetHeight(HEADER_HEIGHT)

        header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header.title:SetPoint("LEFT", header, "LEFT", 4, 2)
        header.title:SetShadowOffset(0, 0)
        Colour(header.title, INK)

        header.note = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header.note:SetPoint("LEFT", header.title, "RIGHT", 10, 0)
        header.note:SetShadowOffset(0, 0)

        header.cost = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header.cost:SetPoint("RIGHT", header, "RIGHT", -4, 2)
        header.cost:SetShadowOffset(0, 0)
        Colour(header.cost, INK_SOFT)

        -- The spellbook's divider under "General".
        header.rule = header:CreateTexture(nil, "ARTWORK")
        header.rule:SetHeight(1)
        header.rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        header.rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        header.rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.55)

        headerPool[usedHeaders] = header
        return header
    end

    function ReleaseAll()
        for i = 1, usedTiles do
            tilePool[i]:Hide()
        end
        for i = 1, usedHeaders do
            headerPool[i]:Hide()
        end
        usedTiles, usedHeaders = 0, 0
    end

    function DrawHeader(header, section, playerLevel)
        header.title:SetText("Level "..section.level)

        if (section.level <= playerLevel) then
            header.note:SetText("Available")
            Colour(header.note, GOOD)
        else
            local levels = section.level - playerLevel
            header.note:SetText(levels == 1 and "Next level" or ("In "..levels.." levels"))
            Colour(header.note, INK_FADED)
        end

        if (section.trainableCost > 0) then
            header.cost:SetText(SBE.FormatMoney(section.trainableCost))
        else
            header.cost:SetText("")
        end
    end

    function SubText(item)
        local entry = item.entry
        local rank = entry.rank and ("Rank "..entry.rank) or SBE.GetSpellSubtext(entry.id)
        local prefix = (rank and rank ~= "") and (rank.."  ") or ""

        if (item.state == SpellList.STATE_KNOWN) then
            return prefix.."Known", INK_FADED
        end
        if (entry.quest) then
            return prefix.."Class quest", NOTE
        end
        if (entry.book) then
            return prefix.."Class book", NOTE
        end
        if (item.state == SpellList.STATE_FUTURE) then
            return prefix.."Level "..item.level, BAD
        end
        if (item.state == SpellList.STATE_BLOCKED) then
            return prefix.."Needs earlier rank", BAD
        end
        if (item.cost) then
            local colour = (item.cost <= GetMoney()) and INK_SOFT or BAD
            return prefix..SBE.FormatMoney(item.cost), colour
        end
        return prefix.."Trainer", INK_SOFT
    end

    function DrawTile(tile, item)
        tile.item = item
        local entry = item.entry

        tile.icon:SetTexture(SBE.GetSpellIcon(entry.id) or 134400)
        tile.name:SetText(item.name or ("Spell "..entry.id))

        local text, colour = SubText(item)
        tile.sub:SetText(text)
        Colour(tile.sub, colour)

        local dim = item.state == SpellList.STATE_FUTURE or item.state == SpellList.STATE_KNOWN
        tile.icon:SetDesaturated(dim)
        tile.icon:SetAlpha(dim and 0.6 or 1)
        Colour(tile.name, dim and INK_FADED or INK)
    end

    function Refresh()
        if (not panel or not panel:IsShown()) then
            return
        end

        for _, button in ipairs(panel.tabButtons) do
            if (button.tabIndex == filter.tab) then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
        end
        for _, cb in ipairs(panel.checkboxes) do
            cb:SetChecked(SBE.options[cb.key])
        end

        ReleaseAll()

        local sections, summary = SpellList.Build(filter)
        local playerLevel = UnitLevel("player")
        local width = panel.content:GetWidth()
        local columns = math.max(1, math.floor(width / TILE_WIDTH))
        local columnWidth = width / columns
        local y = 0

        for _, section in ipairs(sections) do
            local header = AcquireHeader()
            header:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
            header:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
            DrawHeader(header, section, playerLevel)
            y = y + HEADER_HEIGHT + 4

            for index, item in ipairs(section.items) do
                local column = (index - 1) % columns
                local row = math.floor((index - 1) / columns)
                local tile = AcquireTile()
                tile:SetWidth(columnWidth - 4)
                tile:SetPoint("TOPLEFT", panel.content, "TOPLEFT", column * columnWidth, -(y + row * (TILE_HEIGHT + 2)))
                DrawTile(tile, item)
            end

            local rows = math.ceil(#section.items / columns)
            y = y + rows * (TILE_HEIGHT + 2) + SECTION_GAP
        end

        panel.content:SetHeight(math.max(y, 10))

        if (#sections == 0) then
            local text = (SpellList.Count() == 0) and "No spell data for this class." or "Nothing left to learn here."
            panel.empty:SetText(text)
            panel.empty:Show()
        else
            panel.empty:Hide()
        end

        if (summary.trainable > 0) then
            panel.summary:SetText(string.format("Trainable now: %d  %s", summary.trainable, SBE.FormatMoney(summary.cost)))
        else
            panel.summary:SetText("Nothing to train right now")
        end
    end

    function ShowTooltip(tile)
        local item = tile.item
        if (not item) then
            return
        end
        local entry = item.entry

        GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(entry.id)
        GameTooltip:AddLine(" ")

        local playerLevel = UnitLevel("player")
        local r, g, b = 1, 0.82, 0
        if (item.level > playerLevel) then
            r, g, b = 1, 0.1, 0.1
        end
        GameTooltip:AddLine("Learned at level "..item.level, r, g, b)

        if (entry.quest) then
            GameTooltip:AddLine("Taught by a class quest", 0.5, 0.75, 1)
        elseif (entry.book) then
            local bookName = C_Item.GetItemNameByID(entry.book) or ("item "..entry.book)
            GameTooltip:AddLine("Taught by "..bookName, 0.5, 0.75, 1)
        elseif (item.cost) then
            GameTooltip:AddLine("Trainer cost: "..SBE.FormatMoney(item.cost), 1, 1, 1)
        end

        if (entry.prev and not SBE.IsKnown(entry.prev)) then
            GameTooltip:AddLine("Requires "..(SBE.GetSpellName(entry.prev) or "the previous rank")..
                (SBE.GetSpellSubtext(entry.prev) and (" ("..SBE.GetSpellSubtext(entry.prev)..")") or ""), 1, 0.1, 0.1)
        end
        for _, need in ipairs(entry.needs or {}) do
            if (not SBE.IsKnown(need)) then
                GameTooltip:AddLine("Requires "..(SBE.GetSpellName(need) or ("spell "..need)), 1, 0.1, 0.1)
            end
        end
        if (entry.skill) then
            GameTooltip:AddLine("Requires skill "..entry.skill, 1, 0.82, 0)
        end
        if (entry.requires) then
            GameTooltip:AddLine("Rank of a talent: "..(SBE.GetSpellName(entry.requires) or ""), 0.6, 0.6, 0.6)
        end
        if (entry.discovered) then
            GameTooltip:AddLine("Found at your trainer", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end

    function OnTileClick(tile)
        local item = tile.item
        if (not item) then
            return
        end
        if (IsModifiedClick("CHATLINK")) then
            local link = C_Spell.GetSpellLink(item.entry.id)
            if (link) then
                ChatEdit_InsertLink(link)
            end
        end
    end

    function ShowPanel()
        Create()
        panel:Show()
    end

    function HidePanel()
        if (panel) then
            panel:Hide()
        end
    end

    function Toggle()
        Create()
        if (panel:IsShown()) then
            panel:Hide()
        else
            panel:Show()
        end
    end

    SBE.On("SBE_LOADED", function()
        filter.tab = SBE.options.tab or 0
    end)
    SBE.On("SBE_CHANGED", function() Refresh() end)

    Panel.Create = Create
    Panel.Show = ShowPanel
    Panel.Hide = HidePanel
    Panel.Toggle = Toggle
    Panel.Refresh = Refresh
    Panel.Frame = function() return panel end
end

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
    local PLAN_HEIGHT = 26
    local TAB_SIZE = 35
    local TAB_GAP = 12
    -- The spellbook's own tab artwork: frames 42x38 around a 35x35 icon.
    local TAB_ATLAS = "spellbook-Tab-Frame-C60"
    local TAB_ATLAS_ACTIVE = "spellbook-Tab-Frame-Glow-C60"
    local TAB_ATLAS_GLOW = "spellbook-Tab-Frame-glow-gradient-C60"
    local TAB_FRAME_RAISE = 2 -- the frame's opening sits above its centre
    -- A scroll: the General tab already shows the spellbook's book.
    local ALL_ICON = "Interface\\Icons\\INV_Scroll_03"
    local WEAPONS_ICON = "Interface\\Icons\\INV_Sword_04"

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
    local levelOffsets, tilesById = {}, {}
    local flashId = nil

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Create, CreateChrome, CreateToolbar, CreateFooter, CreateCheckbox, CreateParchment
    local AcquireTile, AcquireHeader, ReleaseAll, Refresh, DrawTile, DrawHeader
    local ShowTooltip, OnTileClick, Colour, SubText, HeaderSummary, Toggle, ShowPanel
    local CreatePlanBar, DrawPlan, ClearSearch, TabIcon, CreateTabFrame
    local ItemTooltip, ApplyParchment, JumpTo, ScrollToTarget, StopFlash

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

        -- Escape closes it like any Blizzard panel.
        table.insert(UISpecialFrames, "SpellbookExtendedPanel")

        CreateChrome()
        CreateToolbar()
        CreateParchment()
        CreatePlanBar()
        CreateFooter()

        -- Hooked last: hiding runs OnHide, which needs the widgets above.
        panel:Hide()
        panel:SetScript("OnShow", Refresh)
        panel:SetScript("OnHide", ClearSearch)

        return panel
    end

    function CreateChrome()
        local title = "Spells to Learn"
        if (panel.SetTitle) then
            panel:SetTitle(title)
        elseif (panel.TitleText) then
            panel.TitleText:SetText(title)
        end

        if (panel.SetPortraitToAsset) then
            panel:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09")
        end
    end

    -- Icon tabs like the spellbook's own, so any number of tabs fits beside the
    -- search box; the active tab's name is written after them.
    function TabIcon(index, name)
        if (index == 0) then
            return ALL_ICON
        end
        if (name == "Weapons") then
            return WEAPONS_ICON
        end
        if (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
            for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
                if (info and info.name == name and info.iconID) then
                    return info.iconID
                end
            end
        end
        return SpellList.TabIcon(index) or 134400
    end

    -- Falls back to an additive glow if this client lacks the spellbook atlases.
    function CreateTabFrame(button, icon)
        local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(TAB_ATLAS)
        local width, height = TAB_SIZE * 42 / 35, TAB_SIZE * 38 / 35

        local function layer(atlas, fallback, sublevel)
            local texture = button:CreateTexture(nil, "ARTWORK", nil, sublevel or 1)
            if (hasAtlas) then
                texture:SetAtlas(atlas)
                texture:SetSize(width, height)
                texture:SetPoint("CENTER", icon, "CENTER", 0, TAB_FRAME_RAISE)
            elseif (fallback) then
                texture:SetAllPoints(icon)
                texture:SetTexture(fallback)
                texture:SetBlendMode("ADD")
            end
            texture:Hide()
            return texture
        end

        -- Trim the icon's own bevel; the frame supplies the edge.
        local trim = hasAtlas and 0.05 or 0.07
        icon:SetTexCoord(trim, 1 - trim, trim, 1 - trim)
        button.frame = layer(TAB_ATLAS)
        button.activeFrame = layer(TAB_ATLAS_ACTIVE, "Interface\\Buttons\\CheckButtonHilight")
        -- Behind the icon: it glows out around the frame instead of tinting the icon.
        button.activeGlow = layer(TAB_ATLAS_GLOW, nil, -1)
    end

    function CreateToolbar()
        local tabs = { "All spells" }
        for _, name in ipairs(SpellList.Tabs()) do
            table.insert(tabs, name)
        end

        panel.tabButtons = {}
        local previous = nil
        for index, label in ipairs(tabs) do
            local button = CreateFrame("Button", nil, panel)
            button:SetSize(TAB_SIZE, TAB_SIZE)
            if (previous) then
                button:SetPoint("LEFT", previous, "RIGHT", TAB_GAP, 0)
            else
                button:SetPoint("TOPLEFT", panel, "TOPLEFT", 66, -32)
            end

            -- A pixel inside the frame's opening, so no icon corner shows past it.
            local icon = button:CreateTexture(nil, "ARTWORK", nil, 0)
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
            icon:SetTexture(TabIcon(index - 1, label))
            button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            CreateTabFrame(button, icon)

            button:SetScript("OnClick", function()
                filter.tab = index - 1
                SBE.options.tab = filter.tab
                Refresh()
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(label)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            button.tabIndex = index - 1
            button.label = label
            table.insert(panel.tabButtons, button)
            previous = button
        end

        local tabLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabLabel:SetPoint("LEFT", previous, "RIGHT", 10, 0)
        panel.tabLabel = tabLabel

        local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
        search:SetSize(170, 20)
        search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -36)
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
        -- The inset's bevelled edge separates the header from the parchment.
        local ok, page = pcall(CreateFrame, "Frame", nil, panel, "InsetFrameTemplate")
        if (not ok) then
            page = CreateFrame("Frame", nil, panel)
        end
        page:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -67)
        page:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 40)
        panel.page = page

        local bg = page:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        ApplyParchment(bg)

        local scroll = CreateFrame("ScrollFrame", "SpellbookExtendedScrollFrame", page, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", page, "TOPLEFT", INSET, -(INSET + PLAN_HEIGHT))
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

    function ApplyParchment(texture)
        for _, name in ipairs(PARCHMENT_ATLASES) do
            if (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) then
                texture:SetAtlas(name)
                return
            end
        end
        texture:SetColorTexture(1, 1, 1, 1)
        texture:SetGradient("VERTICAL", CreateColor(0.80, 0.70, 0.52, 1), CreateColor(0.93, 0.85, 0.68, 1))
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

        local costs = CreateCheckbox("Show costs", "showCosts", "Show the trainer price on each spell and in the level summaries.")
        costs:SetPoint("LEFT", other.label, "RIGHT", 12, 0)

        local auto = CreateCheckbox("Open with spellbook", "autoOpen", "Open this panel whenever you open the spellbook.")
        auto:SetPoint("LEFT", costs.label, "RIGHT", 12, 0)

        panel.checkboxes = { known, now, other, costs, auto }

    end

    -- The gold plan across the top of the page, and "Train all" while a class
    -- trainer is open.
    function CreatePlanBar()
        local page = panel.page

        local train = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        train:SetHeight(22)
        train:SetPoint("TOPRIGHT", page, "TOPRIGHT", -INSET, -INSET + 4)
        train:SetScript("OnClick", function() SBE.Trainer.TrainAll() end)
        train:SetScript("OnEnter", function(self)
            local plan = SBE.Trainer.Plan()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Train all")
            GameTooltip:AddLine("Buys every spell the trainer offers that you have not skipped, cheapest first.", 1, 1, 1, true)
            if (plan.unaffordable > 0) then
                GameTooltip:AddLine(plan.unaffordable.." more you cannot afford yet.", 1, 0.1, 0.1, true)
            end
            GameTooltip:Show()
        end)
        train:SetScript("OnLeave", GameTooltip_Hide)
        train:Hide()
        panel.train = train

        local text = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("TOPLEFT", page, "TOPLEFT", INSET + 4, -INSET)
        text:SetPoint("RIGHT", train, "LEFT", -8, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        text:SetShadowOffset(0, 0)
        Colour(text, INK)
        panel.plan = text

        local rule = page:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", page, "TOPLEFT", INSET, -(INSET + PLAN_HEIGHT - 6))
        rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -INSET, -(INSET + PLAN_HEIGHT - 6))
        rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.35)
    end

    function DrawPlan(summary)
        local showCosts = SBE.options.showCosts
        local money = GetMoney()
        local text

        if (summary.trainable > 0) then
            text = summary.trainable.." to train now"
            if (showCosts and summary.cost > 0) then
                local colour = (summary.cost <= money) and "" or "|cffa01408"
                text = text..": "..colour..SBE.FormatMoney(summary.cost).."|r"
            end
        elseif (summary.nextLevel) then
            text = string.format("Next trainer visit (level %d): %d %s", summary.nextLevel,
                summary.nextCount, summary.nextCount == 1 and "spell" or "spells")
            if (showCosts and summary.nextCost > 0) then
                text = text..", "..SBE.FormatMoney(summary.nextCost)
            end
        else
            text = "Nothing left to train"
        end

        if (showCosts) then
            text = text.."  |cff5c3d1f(you have "..SBE.FormatMoney(money)..")|r"
        end
        panel.plan:SetText(text)

        local plan = SBE.Trainer.Plan()
        if (SBE.Trainer.IsOpen() and #plan.services > 0) then
            local label = "Train all ("..#plan.services..")"
            panel.train:SetText(label)
            panel.train:SetWidth(panel.train:GetFontString():GetStringWidth() + 28)
            panel.train:Show()
        else
            panel.train:Hide()
        end
    end

    function ClearSearch()
        if (panel.search:GetText() ~= "") then
            panel.search:SetText("")
        end
        panel.search:ClearFocus()
        filter.search = ""
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
        tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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

        -- Marks the spell a click in the compact book jumped to.
        tile.flash = tile:CreateTexture(nil, "OVERLAY")
        tile.flash:SetAllPoints()
        tile.flash:SetColorTexture(1, 0.82, 0.2, 0.45)
        tile.flash:SetBlendMode("ADD")
        tile.flash:Hide()
        local pulse = tile.flash:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.2)
        fade:SetDuration(0.4)
        tile.pulse = pulse

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
        if (section.weapons) then
            header.title:SetText("Weapon Skills")
            header.note:SetText("From weapon masters")
            Colour(header.note, INK_FADED)
            header.cost:SetText(HeaderSummary(section, playerLevel))
            return
        end

        header.title:SetText("Level "..section.level)

        if (section.level <= playerLevel) then
            header.note:SetText("Available")
            Colour(header.note, GOOD)
        else
            local levels = section.level - playerLevel
            header.note:SetText(levels == 1 and "Next level" or ("In "..levels.." levels"))
            Colour(header.note, INK_FADED)
        end

        header.cost:SetText(HeaderSummary(section, playerLevel))
    end

    -- Reached levels count what can be bought now; later ones count what is coming.
    function HeaderSummary(section, playerLevel)
        local count, cost, noun
        if (section.weapons) then
            count, cost, noun = section.trainable, section.trainableCost, "to learn"
        elseif (section.level <= playerLevel) then
            count, cost, noun = section.trainable, section.trainableCost, "to train"
        else
            count, cost = section.count, section.cost
            noun = (count == 1) and "spell" or "spells"
        end
        if (count == 0) then
            return ""
        end

        local text = count.." "..noun
        if (SBE.options.showCosts and cost > 0) then
            text = text.."  "..SBE.FormatMoney(cost)
        end
        return text
    end

    function SubText(item)
        local entry = item.entry
        local rank = entry.rank and ("Rank "..entry.rank) or SBE.GetSpellSubtext(entry.id)
        local prefix = (rank and rank ~= "") and (rank.."  ") or ""

        if (item.state == SpellList.STATE_KNOWN) then
            return prefix.."Known", INK_FADED
        end
        if (item.state == SpellList.STATE_SKIPPED) then
            return prefix.."Skipped", INK_FADED
        end
        if (entry.quest or entry.book) then
            local source = entry.quest and "Class quest" or "Class book"
            if (item.gated) then
                return prefix..source..", level "..item.level, BAD
            end
            return prefix..source, NOTE
        end
        if (item.state == SpellList.STATE_FUTURE) then
            return prefix.."Level "..item.level, BAD
        end
        if (item.state == SpellList.STATE_BLOCKED) then
            return prefix.."Needs earlier rank", BAD
        end
        if (item.cost and SBE.options.showCosts) then
            local colour = (item.cost <= GetMoney()) and INK_SOFT or BAD
            return prefix..SBE.FormatMoney(item.cost), colour
        end
        return prefix.."Trainable", INK_SOFT
    end

    function DrawTile(tile, item)
        tile.item = item
        local entry = item.entry

        tile.icon:SetTexture(SBE.GetSpellIcon(entry.id) or 134400)
        tile.name:SetText(item.name or ("Spell "..entry.id))

        local text, colour = SubText(item)
        tile.sub:SetText(text)
        Colour(tile.sub, colour)

        local dim = item.gated or item.state == SpellList.STATE_KNOWN or item.state == SpellList.STATE_SKIPPED
        tile.icon:SetDesaturated(dim)
        tile.icon:SetAlpha(dim and 0.6 or 1)
        Colour(tile.name, dim and INK_FADED or INK)

        tilesById[entry.id] = tile
        local flashing = flashId == entry.id
        tile.flash:SetShown(flashing)
        if (flashing) then
            tile.pulse:Play()
        else
            tile.pulse:Stop()
        end
    end

    function Refresh()
        if (not panel or not panel:IsShown()) then
            return
        end

        for _, button in ipairs(panel.tabButtons) do
            local active = button.tabIndex == filter.tab
            button.frame:SetShown(not active)
            button.activeFrame:SetShown(active)
            button.activeGlow:SetShown(active)
            if (active) then
                panel.tabLabel:SetText(button.label)
            end
        end
        for _, cb in ipairs(panel.checkboxes) do
            cb:SetChecked(SBE.options[cb.key])
        end

        ReleaseAll()
        wipe(levelOffsets)
        wipe(tilesById)

        local sections, summary = SpellList.Build(filter)
        local playerLevel = UnitLevel("player")
        local width = panel.content:GetWidth()
        local columns = math.max(1, math.floor(width / TILE_WIDTH))
        local columnWidth = width / columns
        local y = 0

        for _, section in ipairs(sections) do
            local header = AcquireHeader()
            if (not section.weapons) then
                levelOffsets[section.level] = y
            end
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

        DrawPlan(summary)
    end

    function ShowTooltip(tile)
        if (tile.item) then
            ItemTooltip(tile, tile.item)
        end
    end

    -- Shared with the compact book's rows for spells still to learn.
    function ItemTooltip(owner, item, hint)
        local entry = item.entry

        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(entry.id)
        GameTooltip:AddLine(" ")

        local playerLevel = UnitLevel("player")
        local r, g, b = 1, 0.82, 0
        if (item.level > playerLevel) then
            r, g, b = 1, 0.1, 0.1
        end
        GameTooltip:AddLine("Learned at level "..item.level, r, g, b)

        if (entry.weapon) then
            for _, master in ipairs(SBE.Weapons.MastersFor(entry.id)) do
                GameTooltip:AddDoubleLine(master.name, master.city, 1, 1, 1, 0.8, 0.8, 0.8)
            end
            if (item.cost) then
                GameTooltip:AddLine("Cost: "..SBE.FormatMoney(item.cost), 1, 1, 1)
            end
            if (item.state ~= SpellList.STATE_KNOWN) then
                GameTooltip:AddLine("Click to pin the weapon master on your map.", 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
            return
        end

        if (entry.quest) then
            GameTooltip:AddLine("Taught by a class quest", 0.5, 0.75, 1)
            local hint = SBE.QuestHints and SBE.QuestHints[entry.id]
            if (hint) then
                GameTooltip:AddLine(hint, 0.8, 0.8, 0.8, true)
            end
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

        if (item.state == SpellList.STATE_SKIPPED) then
            if (SBE.options.skipped[entry.id]) then
                GameTooltip:AddLine("Skipped. Right-click to include it again.", 0.6, 0.6, 0.6, true)
            else
                GameTooltip:AddLine("Skipped because an earlier rank is skipped.", 0.6, 0.6, 0.6, true)
            end
        elseif (item.state ~= SpellList.STATE_KNOWN and not entry.quest and not entry.book) then
            GameTooltip:AddLine("Right-click to skip this rank and the ones above it.", 0.6, 0.6, 0.6, true)
        end
        if (hint) then
            GameTooltip:AddLine(hint, 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end

    -- Opens the panel at the level a spell unlocks and flashes its tile.
    function JumpTo(id)
        Create()
        local entry = SpellList.Get(id)
        if (entry and filter.tab ~= 0 and filter.tab ~= entry.tab) then
            filter.tab = 0
            SBE.options.tab = 0
        end
        if (filter.search ~= "") then
            ClearSearch()
        end

        StopFlash()
        flashId = id
        C_Timer.After(2.5, StopFlash)

        if (panel:IsShown()) then
            Refresh()
        else
            panel:Show()
        end
        -- The scroll range updates a frame after the content grows.
        C_Timer.After(0, function() ScrollToTarget(id) end)
    end

    function ScrollToTarget(id)
        local tile = tilesById[id]
        local item = tile and tile.item
        local offset = item and levelOffsets[item.level]
        if (not offset) then
            return
        end
        local range = panel.scroll:GetVerticalScrollRange() or 0
        panel.scroll:SetVerticalScroll(math.max(0, math.min(offset, range)))
    end

    function StopFlash()
        local tile = flashId and tilesById[flashId]
        if (tile and tile.item and tile.item.entry.id == flashId) then
            tile.pulse:Stop()
            tile.flash:Hide()
        end
        flashId = nil
    end

    function OnTileClick(tile, button)
        local item = tile.item
        if (not item) then
            return
        end
        if (button == "RightButton") then
            local entry = item.entry
            local implicit = item.state == SpellList.STATE_SKIPPED and not SBE.options.skipped[entry.id]
            if (item.state ~= SpellList.STATE_KNOWN and not entry.quest and not entry.book and not implicit) then
                SpellList.ToggleSkip(entry.id)
                ShowTooltip(tile)
            end
            return
        end
        if (IsModifiedClick("CHATLINK")) then
            local link = C_Spell.GetSpellLink(item.entry.id)
            if (link) then
                ChatEdit_InsertLink(link)
            end
        elseif (item.entry.weapon and item.state ~= SpellList.STATE_KNOWN) then
            SBE.Weapons.Pin(item.entry.id)
        end
    end

    function ShowPanel()
        Create()
        panel:Show()
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
    Panel.Toggle = Toggle
    Panel.Frame = function() return panel end
    Panel.ItemTooltip = ItemTooltip
    Panel.ApplyParchment = ApplyParchment
    Panel.JumpTo = JumpTo
end

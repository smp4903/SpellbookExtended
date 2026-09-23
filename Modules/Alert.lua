-- Alert: the level-up announcement as Blizzard's own loot toast ("You received"),
-- queued through the game's alert system so it stacks and animates like loot.
-- Falls back to the floating Toast when the client lacks the template.

local _, SBE = ...

SBE.Alert = {}

do -- Private Scope
    local Alert = SBE.Alert

    local TEMPLATE = "LootWonAlertFrameTemplate"
    local MAX_SINGLE = 4
    local SPELL_COLOUR = { 0.44, 0.84, 1 }
    local QUEST_COLOUR = { 1, 0.82, 0 }
    local BORDER_SPELL = "loottoast-itemborder-blue"
    local BORDER_OTHER = "loottoast-itemborder-gold"
    local HOLD = 5 -- seconds on screen before fading; Blizzard's loot toast uses about 4

    local subsystem = nil
    local checked = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Available, Parts, SetBorder, SetHold, SetUp, OnClick, OnEnter, OnLeave, Show

    function Available()
        if (checked) then
            return subsystem ~= nil
        end
        checked = true

        if (not (AlertFrame and AlertFrame.AddQueuedAlertFrameSubSystem)) then
            return false
        end
        if (C_XMLUtil and C_XMLUtil.GetTemplateInfo and not C_XMLUtil.GetTemplateInfo(TEMPLATE)) then
            return false
        end

        local ok, result = pcall(AlertFrame.AddQueuedAlertFrameSubSystem, AlertFrame, TEMPLATE, SetUp, MAX_SINGLE, 6)
        subsystem = ok and result or nil
        SBE.DebugPrint("loot toast alerts: "..(subsystem and "available" or "unavailable"))
        return subsystem ~= nil
    end

    -- The template moved its icon into a lootItem child in newer clients.
    function Parts(frame)
        local item = frame.lootItem or frame
        return {
            icon = item.Icon or frame.Icon,
            border = item.IconBorder or frame.IconBorder,
            count = item.Count or frame.Count,
            label = frame.Label,
            name = frame.ItemName,
            hide = { item.SpecRing, item.SpecIcon, frame.SpecRing, frame.SpecIcon, frame.RollTypeIcon,
                frame.RollValue, frame.PvPBackground, frame.BGAtlas, frame.RatedPvPBackground },
        }
    end

    function SetBorder(border, atlas)
        if (not border) then
            return
        end
        if (C_Texture.GetAtlasInfo(atlas)) then
            border:SetAtlas(atlas)
        end
        border:Show()
    end

    -- The subsystem pools its own frames, so changing their timing touches no
    -- real loot toast.
    function SetHold(frame)
        frame.duration = HOLD
        local group = frame.waitAndAnimOut
        if (not (group and group.GetAnimations)) then
            return
        end
        for _, animation in ipairs({ group:GetAnimations() }) do
            if (animation.GetStartDelay and animation:GetStartDelay() > 0) then
                animation:SetStartDelay(HOLD)
            end
        end
    end

    -- data: { spellID, label, name, count, other, level }
    function SetUp(frame, data)
        local parts = Parts(frame)

        for _, region in pairs(parts.hide) do
            region:Hide()
        end

        if (parts.icon) then
            parts.icon:SetTexture(SBE.GetSpellIcon(data.spellID) or 134400)
        end
        SetBorder(parts.border, data.other and BORDER_OTHER or BORDER_SPELL)
        if (parts.count) then
            parts.count:SetText(data.count or "")
            parts.count:SetShown(data.count ~= nil)
        end
        if (parts.label) then
            parts.label:SetText(data.label)
        end
        if (parts.name) then
            local colour = data.other and QUEST_COLOUR or SPELL_COLOUR
            parts.name:SetText(data.name)
            parts.name:SetTextColor(colour[1], colour[2], colour[3])
        end

        SetHold(frame)
        frame.sbeData = data
        frame.hyperlink = C_Spell.GetSpellLink(data.spellID)
        frame:SetScript("OnClick", OnClick)
        frame:SetScript("OnEnter", OnEnter)
        frame:SetScript("OnLeave", OnLeave)
    end

    -- Right-click dismisses as usual; shift-click links; a plain click opens the panel.
    function OnClick(frame, button, down)
        if (AlertFrame_OnClick and AlertFrame_OnClick(frame, button, down)) then
            return
        end
        if (IsModifiedClick("CHATLINK") and frame.hyperlink) then
            ChatEdit_InsertLink(frame.hyperlink)
            return
        end
        SBE.Dock.Anchor()
        SBE.Panel.Show()
    end

    function OnEnter(frame)
        if (AlertFrame_PauseOutAnimation) then
            AlertFrame_PauseOutAnimation(frame)
        end
        local data = frame.sbeData
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        if (data and data.names) then
            GameTooltip:SetText("Level "..data.level)
            for _, name in ipairs(data.names) do
                GameTooltip:AddLine(name, 1, 1, 1)
            end
            GameTooltip:AddLine("Click to open Trainable Spells.", 0.6, 0.6, 0.6)
        elseif (data) then
            GameTooltip:SetSpellByID(data.spellID)
        end
        GameTooltip:Show()
    end

    function OnLeave(frame)
        if (AlertFrame_ResumeOutAnimation) then
            AlertFrame_ResumeOutAnimation(frame)
        end
        GameTooltip:Hide()
    end

    -- items: { entry, other } as built by Notify. Returns false if the caller
    -- should use another style.
    function Show(level, items, cost)
        if (not Available()) then
            return false
        end

        local function nameOf(entry)
            local name = SBE.GetSpellName(entry.id) or ("Spell "..entry.id)
            return entry.rank and (name.." (Rank "..entry.rank..")") or name
        end

        if (#items <= MAX_SINGLE) then
            for _, item in ipairs(items) do
                local entry = item.entry
                local label = "New at your trainer"
                if (item.other) then
                    label = entry.quest and "Class quest available" or "Class book available"
                end
                subsystem:AddAlert({
                    spellID = entry.id, label = label, other = item.other, level = level,
                    name = SBE.GetSpellName(entry.id) or ("Spell "..entry.id),
                    count = entry.rank and tostring(entry.rank) or nil,
                })
            end
            return true
        end

        local names, short = {}, {}
        for _, item in ipairs(items) do
            table.insert(names, nameOf(item.entry))
            table.insert(short, SBE.GetSpellName(item.entry.id) or ("Spell "..item.entry.id))
        end
        local label = "Level "..level..": "..#items.." new spells"
        if (SBE.options.showCosts and cost and cost > 0) then
            label = label.."  "..SBE.FormatMoney(cost)
        end
        subsystem:AddAlert({
            spellID = items[1].entry.id, label = label, level = level, names = names,
            name = table.concat(short, ", "), count = tostring(#items),
        })
        return true
    end

    Alert.Show = Show
end

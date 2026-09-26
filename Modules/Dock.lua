-- Dock: the panel opens beside whichever spellbook is open (the compact book
-- first, else Blizzard's, which gets a toggle button on its edge) and closes
-- with it. Nothing is parented to or inserted into Blizzard's frame, so its
-- secure code never runs addon code.

local _, SBE = ...

SBE.Dock = {}

do -- Private Scope
    local Dock = SBE.Dock

    -- Newest first. Forever's spellbook lives in a load-on-demand addon, so the
    -- frame may not exist until the player first opens it.
    local CANDIDATES = { "PlayerSpellsFrame", "SpellBookFrame", "SpellbookFrame", "ClassicSpellBookFrame" }
    local LOD_ADDONS = { "Blizzard_PlayerSpells", "Blizzard_SpellBook", "Blizzard_Spellbook" }

    local target = nil
    local button = nil
    local hooked = {}

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Resolve, Attach, CreateButton, Anchor, OnTargetShow, OnTargetHide, SetTarget

    function Resolve()
        local override = SBE.options and SBE.options.dockFrame
        if (override and _G[override]) then
            return _G[override]
        end
        for _, name in ipairs(CANDIDATES) do
            local frame = _G[name]
            if (type(frame) == "table" and frame.HookScript) then
                return frame
            end
        end
        return nil
    end

    function CreateButton()
        button = CreateFrame("Button", "SpellbookExtendedDockButton", UIParent)
        button:SetSize(40, 40)
        button:SetFrameStrata("HIGH")

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

        button:SetScript("OnClick", function()
            local panel = SBE.Panel.Create()
            if (panel:IsShown()) then
                panel:Hide()
            else
                Anchor()
                panel:Show()
            end
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Spells to learn")
            GameTooltip:AddLine("Show the spells and ranks you can still learn, by level.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", GameTooltip_Hide)
        button:Hide()
    end

    -- Beside a spellbook when one is open, otherwise wherever the player left it.
    function Anchor()
        local panel = SBE.Panel.Create()
        local book = SBE.Book.Frame()
        if (book and book:IsShown()) then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", book, "TOPRIGHT", 4, 0)
            panel:SetFrameStrata(book:GetFrameStrata())
            panel.dockedTo = book
        elseif (target and target:IsShown()) then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", target, "TOPRIGHT", 46, 0) -- clear of the button
            panel:SetFrameStrata(target:GetFrameStrata())
            panel.dockedTo = target
        elseif (panel.dockedTo) then
            panel:ClearAllPoints()
            panel:SetPoint("CENTER")
            panel.dockedTo = nil
        end
    end

    function OnTargetShow()
        if (not button) then
            CreateButton()
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", target, "TOPRIGHT", 2, -70)
        button:Show()

        if (SBE.options.autoOpen) then
            Anchor()
            SBE.Panel.Show()
        end
    end

    function OnTargetHide()
        if (button) then
            button:Hide()
        end
        local panel = SBE.Panel.Frame()
        if (panel and panel.dockedTo == target) then
            panel:Hide()
        end
    end

    function SetTarget(frame)
        target = frame
        if (not hooked[frame]) then
            hooked[frame] = true
            frame:HookScript("OnShow", function(self)
                if (self == target) then OnTargetShow() end
            end)
            frame:HookScript("OnHide", function(self)
                if (self == target) then OnTargetHide() end
            end)
        end
        if (frame:IsShown()) then
            OnTargetShow()
        end
        SBE.DebugPrint("docked to "..(frame:GetName() or "?"))
    end

    function Attach()
        local frame = Resolve()
        if (frame and frame ~= target) then
            SetTarget(frame)
        end
        return frame ~= nil
    end

    SBE.On("PLAYER_LOGIN", Attach)
    SBE.On("ADDON_LOADED", function(_, name)
        for _, lod in ipairs(LOD_ADDONS) do
            if (name == lod) then
                Attach()
            end
        end
    end)

    -- The micro button opens the spellbook even before its addon is known here.
    SBE.On("PLAYER_LOGIN", function()
        for _, name in ipairs({ "SpellbookMicroButton", "PlayerSpellsMicroButton" }) do
            local micro = _G[name]
            if (micro and micro.HookScript) then
                micro:HookScript("OnClick", function() C_Timer.After(0, Attach) end)
            end
        end
    end)

    -- A class trainer visit opens the panel beside the trainer window, where
    -- "Train all" is, and closes it again when the trainer goes.
    SBE.On("SBE_TRAINER_SHOW", function()
        if (not SBE.options.openWithTrainer) then
            return
        end
        local panel = SBE.Panel.Create()
        if (panel:IsShown()) then
            return
        end
        -- Blizzard creates the trainer window in response to the same event.
        C_Timer.After(0, function()
            local trainer = _G.ClassTrainerFrame
            if (trainer and trainer:IsShown()) then
                panel:ClearAllPoints()
                panel:SetPoint("TOPLEFT", trainer, "TOPRIGHT", 4, 0)
                panel:SetFrameStrata(trainer:GetFrameStrata())
            end
            panel.dockedTo = trainer or UIParent
            panel.openedByTrainer = true
            panel:Show()
        end)
    end)
    SBE.On("SBE_TRAINER_CLOSED", function()
        local panel = SBE.Panel.Frame()
        if (panel and panel.openedByTrainer) then
            panel.openedByTrainer = nil
            panel:Hide()
            panel.dockedTo = nil
            panel:ClearAllPoints()
            panel:SetPoint("CENTER")
        end
    end)

    Dock.Attach = Attach
    Dock.Anchor = Anchor
    Dock.SetFrameByName = function(name)
        local frame = _G[name]
        if (type(frame) ~= "table" or not frame.HookScript) then
            return false
        end
        SBE.options.dockFrame = name
        SetTarget(frame)
        return true
    end
end

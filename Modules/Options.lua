-- Options: the Settings > AddOns page.

local _, SBE = ...

SBE.Options = {}

do -- Private Scope
    local Options = SBE.Options
    local UI = SBE.UIFactory

    local NOTIFY_STYLES = {
        { "Loot toasts", "alert" },
        { "Floating text", "float" },
        { "Chat links", "chat" },
        { "Off", "off" },
    }

    local frame = nil
    local category = nil
    local checkboxes = {}

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Create, AddCheckbox, Sync, SkippedCount, Open

    function AddCheckbox(stack, key, label, tooltip)
        local cb = UI:MakeCheckbox(frame, label, tooltip)
        cb:SetScript("OnClick", function(self)
            SBE.options[key] = self:GetChecked() and true or false
            SBE.Fire("SBE_CHANGED")
        end)
        cb.key = key
        table.insert(checkboxes, cb)
        stack:Add(cb, { gap = 2 })
    end

    function SkippedCount()
        local count = 0
        for _ in pairs(SBE.options.skipped) do
            count = count + 1
        end
        return count
    end

    function Create()
        frame = CreateFrame("Frame")
        frame:Hide()

        local stack = UI:CreateStack(frame, 16, -16)

        stack:Add(UI:MakeText(frame, "Spellbook Extended", "GameFontNormalLarge"), { gap = 6 })
        local note = UI:MakeText(frame, "The beta client does not load saved settings yet, so these reset when the game restarts.", "GameFontHighlightSmall")
        note:SetWidth(560)
        stack:Add(note, { gap = 18 })

        stack:Add(UI:MakeText(frame, "Trainable Spells panel"), { gap = 6 })
        AddCheckbox(stack, "showKnown", "Show known spells", "Also list spells and ranks you have already learned.")
        AddCheckbox(stack, "trainableOnly", "Only spells trainable now", "Hide spells above your level and spells that need an earlier rank first.")
        AddCheckbox(stack, "showQuestAndBook", "Show quest and book spells", "Include spells taught by class quests or class books.")
        AddCheckbox(stack, "showCosts", "Show costs", "Show trainer prices on spells, level headers and the gold plan.")
        AddCheckbox(stack, "autoOpen", "Open with the spellbook", "Show the panel beside the spellbook whenever you open it.")
        AddCheckbox(stack, "openWithTrainer", "Open when talking to a trainer", "Show the panel, with its Train all button, beside the trainer window.")
        stack:Space(16)

        stack:Add(UI:MakeText(frame, "Level-up announcement"), { gap = 2 })
        local dropdown = UI:MakeDropdown(frame, 150, NOTIFY_STYLES,
            function() return SBE.options.notify end,
            function(value) SBE.options.notify = value end)
        stack:Add(dropdown, { dx = -16, height = 32 })
        frame.dropdown = dropdown

        local preview = UI:MakeButton(frame, 90, "Preview", function() SBE.Preview() end)
        preview:SetPoint("LEFT", dropdown, "RIGHT", -6, 2)
        stack:Space(16)

        stack:Add(UI:MakeText(frame, "Skipped spells"), { gap = 6 })
        local skipped = UI:MakeText(frame, "", "GameFontHighlight")
        stack:Add(skipped, { height = 22 })
        frame.skipped = skipped

        local clear = UI:MakeButton(frame, 110, "Clear skipped", function()
            wipe(SBE.options.skipped)
            SBE.Fire("SBE_CHANGED")
            Sync()
        end)
        clear:SetPoint("LEFT", skipped, "LEFT", 150, 0)

        frame:SetScript("OnShow", Sync)

        category = Settings.RegisterCanvasLayoutCategory(frame, "Spellbook Extended")
        Settings.RegisterAddOnCategory(category)
    end

    function Sync()
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(SBE.options[cb.key])
        end
        frame.dropdown:Sync()
        local count = SkippedCount()
        frame.skipped:SetText(count == 1 and "1 spell skipped" or (count.." spells skipped"))
    end

    function Open()
        if (category) then
            Settings.OpenToCategory(category:GetID())
        end
    end

    SBE.On("PLAYER_LOGIN", function()
        if (Settings and Settings.RegisterCanvasLayoutCategory) then
            Create()
        end
    end)

    Options.Open = Open
end

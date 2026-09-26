-- BookKeys: with the compact spellbook enabled, the keys bound to "Toggle
-- Spellbook" open it instead, through override bindings. The player's own bindings are left as they are,
-- and Blizzard's spellbook stays on the micro button.

local _, SBE = ...

SBE.BookKeys = {}

do -- Private Scope
    local BookKeys = SBE.BookKeys

    local owner = CreateFrame("Frame")
    local pending = false
    local applied = nil -- the keys and setting last applied

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Apply, CreateToggle, State

    -- A binding clicks this button; the button toggles the book.
    function CreateToggle()
        local button = CreateFrame("Button", "SpellbookExtendedBookToggle", UIParent)
        button:RegisterForClicks("AnyUp")
        button:SetScript("OnClick", function() SBE.Book.Toggle() end)
        button:Hide()
    end

    function State()
        return tostring(SBE.options.compactBook).."|"..table.concat({ GetBindingKey("TOGGLESPELLBOOK") }, ",")
    end

    -- Bindings cannot change in combat; retry once it ends.
    function Apply()
        if (InCombatLockdown()) then
            pending = true
            return
        end
        pending = false
        applied = State()
        ClearOverrideBindings(owner)
        if (not SBE.options.compactBook) then
            local book = SBE.Book.Frame()
            if (book and book:IsShown()) then
                book:Hide()
            end
            return
        end
        for _, key in ipairs({ GetBindingKey("TOGGLESPELLBOOK") }) do
            SetOverrideBindingClick(owner, false, key, "SpellbookExtendedBookToggle", "LeftButton")
        end
    end

    SBE.On("PLAYER_LOGIN", function()
        CreateToggle()
        Apply()
    end)
    -- Override changes can raise UPDATE_BINDINGS themselves; only a changed
    -- "Toggle Spellbook" key needs a new override.
    SBE.On("UPDATE_BINDINGS", function()
        if (_G.SpellbookExtendedBookToggle and State() ~= applied) then
            Apply()
        end
    end)
    SBE.On("PLAYER_REGEN_ENABLED", function()
        if (pending) then
            Apply()
        end
    end)

    BookKeys.Apply = Apply
end

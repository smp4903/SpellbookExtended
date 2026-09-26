-- NAMESPACE: the addon table (Dev/DevTools.lua exposes it as a global in development builds)
-- OPTIONS: SpellbookExtended_Options (per character), SpellbookExtended_TrainerCache (account)

local ADDON_NAME, SBE = ...

SBE.Data = {}

do -- Private Scope
    local defaults = {
        ["showKnown"] = false,
        ["trainableOnly"] = false,
        ["showQuestAndBook"] = true,
        ["showCosts"] = true,
        ["notify"] = "alert",
        ["autoOpen"] = false,
        ["openWithTrainer"] = true,
        ["tab"] = 0,
        ["compactBook"] = true,
        ["bookUpcoming"] = true,
        ["bookUnfoldAll"] = false,
    }

    local frame = CreateFrame("Frame")
    local listeners = {}

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local LoadOptions, On, Fire, SafeRegister, OnEvent, Print
    local GetSpellName, GetSpellIcon, GetSpellSubtext, GetSpellLevelLearned, IsKnown, FormatMoney

    function LoadOptions()
        SpellbookExtended_Options = SpellbookExtended_Options or {}
        for key, value in pairs(defaults) do
            if (SpellbookExtended_Options[key] == nil) then
                SpellbookExtended_Options[key] = value
            end
        end

        SpellbookExtended_Options.skipped = SpellbookExtended_Options.skipped or {}
        SpellbookExtended_TrainerCache = SpellbookExtended_TrainerCache or {}
        SBE.options = SpellbookExtended_Options
    end

    -- Modules subscribe here instead of each owning an event frame.
    function On(event, callback)
        if (not listeners[event]) then
            listeners[event] = {}
            if (not event:find("^SBE_")) then
                SafeRegister(event)
            end
        end
        table.insert(listeners[event], callback)
    end

    function Fire(event, ...)
        for _, callback in ipairs(listeners[event] or {}) do
            callback(event, ...)
        end
    end

    -- Registering an event this client lacks throws and aborts the file.
    function SafeRegister(event)
        local ok = pcall(frame.RegisterEvent, frame, event)
        if (not ok) then
            SBE.DebugPrint("event not available: "..event)
        end
        return ok
    end

    function OnEvent(self, event, ...)
        if (event == "ADDON_LOADED" and ... == ADDON_NAME) then
            LoadOptions()
            Fire("SBE_LOADED")
        end
        Fire(event, ...)
    end

    function Print(msg)
        print("|cff34c0ebSpellbookExtended:|r "..msg)
    end


    -- SPELL API
    -- Forever runs the Retail client: the Classic globals (GetSpellInfo...) are gone.
    function GetSpellName(id)
        if (C_Spell.GetSpellName) then
            return C_Spell.GetSpellName(id)
        end
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    end

    function GetSpellIcon(id)
        return C_Spell.GetSpellTexture(id)
    end

    function GetSpellSubtext(id)
        return C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(id) or nil
    end

    -- The live client's own answer beats the shipped table; 0 means "not set".
    function GetSpellLevelLearned(id)
        if (not C_Spell.GetSpellLevelLearned) then
            return nil
        end
        local ok, level = pcall(C_Spell.GetSpellLevelLearned, id)
        if (ok and type(level) == "number" and level > 0) then
            return level
        end
        return nil
    end

    function IsKnown(id)
        if (IsPlayerSpell and IsPlayerSpell(id)) then
            return true
        end
        if (C_SpellBook and C_SpellBook.IsSpellKnown) then
            return C_SpellBook.IsSpellKnown(id) == true
        end
        return IsSpellKnown and IsSpellKnown(id) or false
    end

    function FormatMoney(copper)
        if (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) then
            return C_CurrencyInfo.GetCoinTextureString(copper)
        end
        return GetMoneyString(copper)
    end

    frame:SetScript("OnEvent", OnEvent)
    frame:RegisterEvent("ADDON_LOADED")

    SBE.On = On
    SBE.Fire = Fire
    SBE.Print = Print
    -- Silent in releases; Dev/DevTools.lua replaces it.
    SBE.DebugPrint = function() end
    SBE.GetSpellName = GetSpellName
    SBE.GetSpellIcon = GetSpellIcon
    SBE.GetSpellSubtext = GetSpellSubtext
    SBE.GetSpellLevelLearned = GetSpellLevelLearned
    SBE.IsKnown = IsKnown
    SBE.FormatMoney = FormatMoney
end

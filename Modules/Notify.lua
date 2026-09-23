-- Notify: on level up, prints links to what the new level unlocked.

local _, SBE = ...

do -- Private Scope
    local LINKS_PER_LINE = 6

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local SpellText, PrintLinks, OnLevelUp

    function SpellText(entry)
        local link = C_Spell.GetSpellLink(entry.id)
            or ("["..(SBE.GetSpellName(entry.id) or ("spell "..entry.id)).."]")
        if (entry.rank) then
            link = link.." "..entry.rank
        end
        return link
    end

    -- Split so a busy level (20, 40) does not become one unreadable line.
    function PrintLinks(prefix, items)
        local line = {}
        for index, item in ipairs(items) do
            table.insert(line, SpellText(item.entry))
            if (#line == LINKS_PER_LINE or index == #items) then
                print(prefix..table.concat(line, ", "))
                prefix = "   "
                line = {}
            end
        end
    end

    function OnLevelUp(level)
        local trainable, other = SBE.SpellList.NewAtLevel(level)
        if (#trainable == 0 and #other == 0) then
            return
        end

        local header = "|cff34c0ebSpellbookExtended:|r level "..level.." unlocked "
            ..#trainable..(#trainable == 1 and " spell" or " spells").." at your trainer"
        local cost = 0
        for _, item in ipairs(trainable) do
            cost = cost + (item.cost or 0)
        end
        if (SBE.options.showCosts and cost > 0) then
            header = header.." ("..SBE.FormatMoney(cost)..")"
        end
        print(header..".")

        if (#trainable > 0) then
            PrintLinks("   ", trainable)
        end
        if (#other > 0) then
            PrintLinks("   Quest or book: ", other)
        end
    end

    SBE.On("PLAYER_LEVEL_UP", function(_, level)
        if (not SBE.options.notifyLevelUp or type(level) ~= "number") then
            return
        end
        -- Spells granted with the level and UnitLevel itself settle a moment later.
        C_Timer.After(1, function() OnLevelUp(level) end)
    end)

    SBE.NotifyLevel = OnLevelUp
end

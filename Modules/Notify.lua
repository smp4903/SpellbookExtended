-- Notify: on level up, announces what the new level unlocked, as loot-style
-- alerts, floating text or chat links.

local _, SBE = ...

do -- Private Scope
    local LINKS_PER_LINE = 6

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local SpellText, PrintLinks, PrintChat, Announce, Preview

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

    function PrintChat(level, trainable, other, cost)
        local header = "|cff34c0ebSpellbookExtended:|r level "..level.." unlocked "
            ..#trainable..(#trainable == 1 and " spell" or " spells").." at your trainer"
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

    -- Returns false when the level unlocked nothing.
    function Announce(level, style)
        local trainable, other = SBE.SpellList.NewAtLevel(level)
        if (#trainable == 0 and #other == 0) then
            return false
        end

        local cost = 0
        for _, item in ipairs(trainable) do
            cost = cost + (item.cost or 0)
        end

        if (style == "chat") then
            PrintChat(level, trainable, other, cost)
            return true
        end

        local items = {}
        for _, item in ipairs(trainable) do
            table.insert(items, { entry = item.entry })
        end
        for _, item in ipairs(other) do
            table.insert(items, { entry = item.entry, other = true })
        end
        if (style ~= "alert" or not SBE.Alert.Show(level, items, cost)) then
            SBE.Toast.Show(level, items, cost)
        end
        return true
    end

    -- Shows the next level that unlocks something, from the current one up.
    function Preview()
        for level = UnitLevel("player"), 60 do
            local style = (SBE.options.notify == "off") and "alert" or SBE.options.notify
            if (Announce(level, style)) then
                return
            end
        end
        SBE.Print("nothing left to announce.")
    end

    SBE.On("PLAYER_LEVEL_UP", function(_, level)
        local style = SBE.options.notify
        if (style == "off" or type(level) ~= "number") then
            return
        end
        -- Spells granted with the level and UnitLevel itself settle a moment later.
        C_Timer.After(1, function() Announce(level, style) end)
    end)

    SBE.Preview = Preview
end

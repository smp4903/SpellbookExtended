-- BookData: the rows of the compact spellbook. Known spells come from the
-- client's spellbook, one section per skill line, with lower ranks folded
-- under the highest; spells still to learn close each section. Flyouts
-- (Paladin blessings...) are not grouped: each spell gets its own row.
-- Knows nothing about frames.

local _, SBE = ...

SBE.BookData = {}

do -- Private Scope
    local BookData = SBE.BookData
    local SpellList = SBE.SpellList

    local ITEM = Enum and Enum.SpellBookItemType or {}
    local TYPE_FUTURE = ITEM.FutureSpell or 2
    local TYPE_FLYOUT = ITEM.Flyout or 4
    local BANK = Enum and Enum.SpellBookSpellBank or {}
    local BANK_PLAYER = BANK.Player or 0
    local BANK_PET = BANK.Pet or 1

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Build, KnownSections, ReadItem, AddGroups, AddUpcoming, UpcomingMeta
    local RankOf, Call, Matches

    -- Every C_SpellBook call is optional: an older or newer client may lack one.
    function Call(name, ...)
        local fn = C_SpellBook and C_SpellBook[name]
        if (not fn) then
            return nil
        end
        local ok, a, b = pcall(fn, ...)
        if (ok) then
            return a, b
        end
        return nil
    end

    function RankOf(subName)
        return tonumber((subName or ""):match("(%d+)"))
    end

    function Matches(name, search)
        return search == "" or (name or ""):lower():find(search, 1, true) ~= nil
    end

    function ReadItem(slot, bank, hidePassives)
        local info = Call("GetSpellBookItemInfo", slot, bank)
        if (not info or not info.name) then
            return nil
        end
        local itemType = info.itemType
        -- The spellbook also lists a flyout's spells one by one; those are shown instead.
        if (itemType == TYPE_FUTURE or itemType == TYPE_FLYOUT or info.isOffSpec) then
            return nil
        end
        if (hidePassives and info.isPassive) then
            return nil
        end
        return {
            slot = slot, bank = bank, name = info.name, subName = info.subName,
            spellID = info.spellID, actionID = info.actionID, icon = info.iconID,
            passive = info.isPassive, pet = bank == BANK_PET,
            rank = RankOf(info.subName), lowRank = Call("IsSpellBookItemLowRank", slot, bank) == true,
        }
    end

    -- One group per spell name: the highest rank leads, the others fold under it.
    function AddGroups(section, items)
        local groups, order = {}, {}
        for _, item in ipairs(items) do
            local key = item.name
            local group = groups[key]
            if (not group) then
                group = { key = (item.pet and "pet:" or "")..key, members = {} }
                groups[key] = group
                table.insert(order, group)
            end
            table.insert(group.members, item)
        end

        for _, group in ipairs(order) do
            table.sort(group.members, function(a, b)
                if (a.lowRank ~= b.lowRank) then
                    return not a.lowRank
                end
                return (a.rank or 0) > (b.rank or 0)
            end)
            local lead = group.members[1]
            lead.key = group.key
            lead.children = {}
            for i = 2, #group.members do
                table.insert(lead.children, group.members[i])
            end
            table.insert(section.spells, lead)
        end
    end

    function KnownSections(hidePassives)
        local sections, byName = {}, {}
        for line = 1, (Call("GetNumSpellBookSkillLines") or 0) do
            local info = Call("GetSpellBookSkillLineInfo", line)
            if (info and not info.shouldHide and not info.offSpecID) then
                local items = {}
                for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = ReadItem(slot, BANK_PLAYER, hidePassives)
                    if (item) then
                        table.insert(items, item)
                    end
                end
                local section = { name = info.name, spells = {}, upcoming = {} }
                AddGroups(section, items)
                table.insert(sections, section)
                byName[info.name] = section
            end
        end

        local numPet = Call("HasPetSpells")
        if (numPet and numPet > 0) then
            local items = {}
            for slot = 1, numPet do
                local item = ReadItem(slot, BANK_PET, hidePassives)
                if (item) then
                    table.insert(items, item)
                end
            end
            if (#items > 0) then
                local section = { name = PET or "Pet", spells = {}, upcoming = {}, pet = true }
                AddGroups(section, items)
                table.insert(sections, section)
            end
        end
        return sections, byName
    end

    -- Right-hand text and colour key for a spell still to learn.
    function UpcomingMeta(item)
        local entry = item.entry
        if (item.state == SpellList.STATE_FUTURE or ((entry.quest or entry.book) and item.gated)) then
            return "Lvl "..item.level, "bad"
        end
        if (entry.quest) then
            return "Quest", "note"
        end
        if (entry.book) then
            return "Book", "note"
        end
        if (item.state == SpellList.STATE_BLOCKED) then
            return "Needs rank", "bad"
        end
        if (item.cost and item.cost > 0 and SBE.options.showCosts) then
            return SBE.FormatMoney(item.cost), (item.cost <= GetMoney()) and "soft" or "bad"
        end
        return "Train", "soft"
    end

    -- Spells still to learn go to the section with their spellbook tab's name.
    function AddUpcoming(sections, byName)
        local tabs = SpellList.Tabs()
        local levelSections, summary = SpellList.Build({ upcoming = true })
        for _, levelSection in ipairs(levelSections) do
            for _, item in ipairs(levelSection.items) do
                local tabName = tabs[item.entry.tab] or "Other"
                local section = byName[tabName]
                if (not section) then
                    section = { name = tabName, spells = {}, upcoming = {} }
                    byName[tabName] = section
                    table.insert(sections, section)
                end
                table.insert(section.upcoming, item)
            end
        end
        return summary
    end

    -- opts: { search, showUpcoming, hidePassives, unfoldAll, expanded = { [key] = true },
    --        collapsed = { [section name] = true } }. A search opens folded sections.
    -- Returns flat rows in display order, and the trainer summary for the footer.
    function Build(opts)
        opts = opts or {}
        local search = (opts.search or ""):lower()
        local expanded = opts.expanded or {}
        local collapsed = opts.collapsed or {}
        local sections, byName = KnownSections(opts.hidePassives)
        local summary = AddUpcoming(sections, byName)
        local rows = {}

        for _, section in ipairs(sections) do
            local sectionRows = {}
            for _, spell in ipairs(section.spells) do
                if (Matches(spell.name, search)) then
                    local isOpen = #spell.children > 0 and (opts.unfoldAll or expanded[spell.key]) and true or false
                    table.insert(sectionRows, {
                        kind = "spell", spell = spell, name = spell.name, key = spell.key,
                        hasChildren = #spell.children > 0, expanded = isOpen,
                        meta = spell.passive and "Passive" or (spell.rank and ("R"..spell.rank)) or "",
                    })
                    if (isOpen) then
                        for _, child in ipairs(spell.children) do
                            local label = child.rank and ("Rank "..child.rank) or child.name
                            table.insert(sectionRows, { kind = "child", spell = child, name = label, parent = spell })
                        end
                    end
                end
            end

            local upcomingCount = 0
            if (opts.showUpcoming ~= false) then
                table.sort(section.upcoming, function(a, b)
                    if (a.level ~= b.level) then
                        return a.level < b.level
                    end
                    return (a.name or "") < (b.name or "")
                end)
                for _, item in ipairs(section.upcoming) do
                    local label = item.name or ("Spell "..item.entry.id)
                    if (item.entry.rank) then
                        label = label.." (Rank "..item.entry.rank..")"
                    end
                    if (Matches(label, search)) then
                        local meta, tone = UpcomingMeta(item)
                        table.insert(sectionRows, { kind = "upcoming", item = item, name = label, meta = meta, tone = tone })
                        upcomingCount = upcomingCount + 1
                    end
                end
            end

            if (#sectionRows > 0) then
                local folded = search == "" and collapsed[section.name] == true
                table.insert(rows, { kind = "header", name = section.name, count = #section.spells,
                    upcoming = upcomingCount, pet = section.pet, collapsed = folded })
                if (not folded) then
                    for _, row in ipairs(sectionRows) do
                        table.insert(rows, row)
                    end
                end
            end
        end

        return rows, summary
    end

    BookData.Build = Build
    BookData.BANK_PLAYER = BANK_PLAYER
    BookData.BANK_PET = BANK_PET
end

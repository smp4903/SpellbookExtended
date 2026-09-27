-- SpellList: the player's class spells, their state, and the level sections
-- the panel draws. Knows nothing about frames.

local _, SBE = ...

SBE.SpellList = {}

do -- Private Scope
    local SpellList = SBE.SpellList

    local STATE_KNOWN = "known"
    local STATE_TRAINABLE = "trainable"
    local STATE_FUTURE = "future"
    local STATE_BLOCKED = "blocked" -- level reached, prerequisite missing
    local STATE_OTHER = "other"     -- quest or book, not sold by the trainer
    local STATE_SKIPPED = "skipped" -- the player chose not to buy it

    local classData = nil
    local tabs = {}
    local entries = {}
    local byId = {}
    local nextRank = {}
    local refreshPending = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Init, AddEntry, FamilyKnown, PrevKnown, IsDone, IsEligible, IsSkipped, ToggleSkip, Level, Cost, StateOf
    local Build, NewAtLevel, Matches, Discover, RequestData, OnDataLoaded, Changed, Tabs

    function Init()
        local _, class = UnitClass("player")
        classData = SBE.Data[class]
        entries, byId, nextRank = {}, {}, {}

        if (not classData) then
            return
        end

        for _, spell in ipairs(classData.spells) do
            AddEntry(spell)
        end

        -- Weapon skills get a tab of their own after the class tabs.
        tabs = { unpack(classData.tabs) }
        local weapons = SBE.WeaponSkills
        local weaponTab = #tabs + 1
        for _, id in ipairs(weapons and weapons.order or {}) do
            local skill = weapons.skills[id]
            if (skill.classes[class]) then
                AddEntry({ id = id, level = skill.level or 1, tab = weaponTab, cost = skill.cost or 1000, weapon = true })
                tabs[weaponTab] = "Weapons"
            end
        end

        local discovered = SpellbookExtended_TrainerCache[class]
        for id, record in pairs(discovered and discovered.extra or {}) do
            if (not byId[id]) then
                AddEntry({ id = id, level = record.level or 1, tab = record.tab or 0, discovered = true })
            end
        end

        RequestData()
    end

    function AddEntry(spell)
        local entry = setmetatable({}, { __index = spell })
        table.insert(entries, entry)
        byId[spell.id] = entry
        if (spell.prev) then
            nextRank[spell.prev] = spell.id
        end
    end

    -- True when this rank or any rank above it is learned. Ranks you skipped
    -- stay listed until something higher replaces them.
    function FamilyKnown(id)
        local seen = 0
        while (id and seen < 30) do
            if (SBE.IsKnown(id)) then
                return true
            end
            id = nextRank[id]
            seen = seen + 1
        end
        return false
    end

    -- The previous rank may exist under a second ID (prevAlt).
    function PrevKnown(entry)
        if (not entry.prev or SBE.IsKnown(entry.prev)) then
            return true
        end
        for _, id in ipairs(entry.prevAlt or {}) do
            if (SBE.IsKnown(id)) then
                return true
            end
        end
        return false
    end

    function IsDone(entry)
        return FamilyKnown(entry.id)
    end

    function IsEligible(entry)
        if (entry.race) then
            local _, _, raceID = UnitRace("player")
            if (raceID ~= entry.race) then
                return false
            end
        end

        if (entry.faction and entry.faction ~= UnitFactionGroup("player")) then
            return false
        end

        -- Higher ranks of a talent spell are only sold once the talent is taken.
        if (entry.requires and not FamilyKnown(entry.requires)) then
            return false
        end

        return true
    end

    -- Trainers sell ranks in order, so skipping one also skips every rank above it.
    function IsSkipped(entry)
        local skipped = SBE.options.skipped
        local seen = 0
        while (entry and seen < 30) do
            if (skipped[entry.id]) then
                return true
            end
            entry = entry.prev and byId[entry.prev]
            seen = seen + 1
        end
        return false
    end

    function ToggleSkip(id)
        local skipped = SBE.options.skipped
        skipped[id] = (not skipped[id]) or nil
        SBE.Fire("SBE_CHANGED")
    end

    -- General spells (Parry, Mail...) sit outside the class skill lines, where
    -- the client's own level is 1; their trainer level comes from the data.
    function Level(entry)
        local live = not entry.general and SBE.GetSpellLevelLearned(entry.id)
        if (live) then
            return live
        end

        return SBE.Trainer.Level(entry.id) or entry.level
    end

    function Cost(entry)
        return SBE.Trainer.Cost(entry.id) or entry.cost
    end

    function StateOf(entry, level, playerLevel)
        if (IsDone(entry)) then
            return STATE_KNOWN
        end
        if (entry.quest or entry.book) then
            return STATE_OTHER
        end
        if (IsSkipped(entry)) then
            return STATE_SKIPPED
        end
        if (level > playerLevel) then
            return STATE_FUTURE
        end
        if (not PrevKnown(entry)) then
            return STATE_BLOCKED
        end
        for _, need in ipairs(entry.needs or {}) do
            if (not FamilyKnown(need)) then
                return STATE_BLOCKED
            end
        end
        return STATE_TRAINABLE
    end

    function Matches(entry, name, filter)
        if (filter.tab and filter.tab > 0 and entry.tab ~= filter.tab) then
            return false
        end
        if (filter.search and filter.search ~= "") then
            local haystack = (name or ""):lower()
            if (not haystack:find(filter.search:lower(), 1, true)) then
                return false
            end
        end
        return true
    end

    -- Returns sections sorted by level, each { level, items, count, trainable,
    -- cost, trainableCost }, with weapon skills in a last section of their own,
    -- plus a summary for the gold plan. The summary covers the class trainer
    -- only and ignores the search and tab filters.
    function Build(filter)
        local options = SBE.options
        local playerLevel = UnitLevel("player")
        local sections, byLevel = {}, {}
        local weaponSection = nil
        local summary = { trainable = 0, cost = 0, nextLevel = nil, nextCount = 0, nextCost = 0 }

        for _, entry in ipairs(entries) do
            if (IsEligible(entry)) then
                local level = Level(entry)
                local state = StateOf(entry, level, playerLevel)
                local name = SBE.GetSpellName(entry.id)

                local visible
                if (filter.upcoming) then
                    -- The compact book: everything still to learn, whatever the panel shows.
                    visible = not entry.weapon and state ~= STATE_KNOWN and state ~= STATE_SKIPPED
                else
                    visible = Matches(entry, name, filter)
                        and (state ~= STATE_KNOWN or options.showKnown)
                        and (state ~= STATE_OTHER or options.showQuestAndBook)
                        and (not options.trainableOnly or state == STATE_TRAINABLE)
                end

                local cost = Cost(entry)
                if (state == STATE_TRAINABLE and not entry.weapon) then
                    summary.trainable = summary.trainable + 1
                    summary.cost = summary.cost + (cost or 0)
                elseif (state == STATE_FUTURE and not entry.weapon) then
                    if (not summary.nextLevel or level < summary.nextLevel) then
                        summary.nextLevel, summary.nextCount, summary.nextCost = level, 0, 0
                    end
                    if (level == summary.nextLevel) then
                        summary.nextCount = summary.nextCount + 1
                        summary.nextCost = summary.nextCost + (cost or 0)
                    end
                end

                if (visible) then
                    local section = entry.weapon and weaponSection or byLevel[level]
                    if (not section) then
                        section = { level = level, items = {}, count = 0, trainable = 0, cost = 0, trainableCost = 0 }
                        if (entry.weapon) then
                            section.weapons = true
                            weaponSection = section
                        else
                            byLevel[level] = section
                            table.insert(sections, section)
                        end
                    end

                    table.insert(section.items, {
                        entry = entry, name = name, level = level, state = state, cost = cost,
                        gated = level > playerLevel,
                    })

                    if (state ~= STATE_KNOWN and state ~= STATE_SKIPPED) then
                        section.count = section.count + 1
                        if (state ~= STATE_OTHER) then
                            section.cost = section.cost + (cost or 0)
                        end
                    end
                    if (state == STATE_TRAINABLE) then
                        section.trainable = section.trainable + 1
                        section.trainableCost = section.trainableCost + (cost or 0)
                    end
                end
            end
        end

        table.sort(sections, function(a, b) return a.level < b.level end)
        if (weaponSection) then
            table.insert(sections, weaponSection)
        end
        for _, section in ipairs(sections) do
            table.sort(section.items, function(a, b)
                if (a.entry.tab ~= b.entry.tab) then
                    return a.entry.tab < b.entry.tab
                end
                if ((a.name or "") ~= (b.name or "")) then
                    return (a.name or "") < (b.name or "")
                end
                return (a.entry.rank or 0) < (b.entry.rank or 0)
            end)
        end

        return sections, summary
    end

    -- What reaching this level unlocked: spells the trainer now sells, and
    -- quest or book spells that became possible. Filters are ignored.
    function NewAtLevel(newLevel)
        local trainable, other = {}, {}
        for _, entry in ipairs(entries) do
            if (not entry.weapon and IsEligible(entry) and Level(entry) == newLevel) then
                local state = StateOf(entry, newLevel, newLevel)
                if (state == STATE_TRAINABLE) then
                    table.insert(trainable, { entry = entry, cost = Cost(entry) })
                elseif (state == STATE_OTHER) then
                    table.insert(other, { entry = entry })
                end
            end
        end
        return trainable, other
    end

    -- A trainer listed a spell the shipped data does not have.
    function Discover(id, level, tab)
        if (byId[id]) then
            return
        end
        AddEntry({ id = id, level = level or 1, tab = tab or 0, discovered = true })
        RequestData()
    end

    -- Names and icons of spells the player has never seen arrive asynchronously.
    function RequestData()
        if (not (C_Spell.IsSpellDataCached and C_Spell.RequestLoadSpellData)) then
            return
        end
        for _, entry in ipairs(entries) do
            if (not C_Spell.IsSpellDataCached(entry.id)) then
                C_Spell.RequestLoadSpellData(entry.id)
            end
        end
    end

    -- SPELLS_CHANGED and data loads arrive in bursts; redraw once per burst.
    function Changed()
        if (refreshPending) then
            return
        end
        refreshPending = true
        C_Timer.After(0.25, function()
            refreshPending = false
            SBE.Fire("SBE_CHANGED")
        end)
    end

    function OnDataLoaded(_, spellID)
        if (byId[spellID]) then
            Changed()
        end
    end

    function Tabs()
        return tabs
    end

    SBE.On("PLAYER_LOGIN", function()
        Init()
        Changed()
    end)
    SBE.On("SPELL_DATA_LOAD_RESULT", OnDataLoaded)
    -- UnitLevel lags PLAYER_LEVEL_UP by a moment.
    SBE.On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, Changed) end)
    SBE.On("SPELLS_CHANGED", Changed)
    SBE.On("LEARNED_SPELL_IN_SKILL_LINE", Changed)
    SBE.On("PLAYER_MONEY", Changed)

    SpellList.Build = Build
    SpellList.NewAtLevel = NewAtLevel
    -- For trainer rows whose spell ID the client does not reveal.
    SpellList.FindByName = function(name, subtext)
        local rank = tonumber((subtext or ""):match("(%d+)"))
        for _, entry in ipairs(entries) do
            if (SBE.GetSpellName(entry.id) == name and entry.rank == rank) then
                return entry.id
            end
        end
        return nil
    end
    SpellList.ToggleSkip = ToggleSkip
    SpellList.PrevKnown = PrevKnown
    SpellList.IsSkipped = function(id) return byId[id] ~= nil and IsSkipped(byId[id]) end
    SpellList.IsTrainable = function(id)
        local entry = byId[id]
        return entry ~= nil and IsEligible(entry)
            and StateOf(entry, Level(entry), UnitLevel("player")) == STATE_TRAINABLE
    end
    SpellList.Discover = Discover
    SpellList.Changed = Changed
    SpellList.Tabs = Tabs
    -- The first spell a tab unlocks stands in for its icon.
    SpellList.TabIcon = function(tab)
        local best = nil
        for _, entry in ipairs(entries) do
            if (entry.tab == tab and (not best or entry.level < best.level)) then
                best = entry
            end
        end
        return best and SBE.GetSpellIcon(best.id)
    end
    SpellList.Get = function(id) return byId[id] end
    SpellList.Count = function() return #entries end
    SpellList.STATE_KNOWN = STATE_KNOWN
    SpellList.STATE_TRAINABLE = STATE_TRAINABLE
    SpellList.STATE_FUTURE = STATE_FUTURE
    SpellList.STATE_BLOCKED = STATE_BLOCKED
    SpellList.STATE_OTHER = STATE_OTHER
    SpellList.STATE_SKIPPED = STATE_SKIPPED
end

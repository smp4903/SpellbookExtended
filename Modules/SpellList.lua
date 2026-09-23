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

    local classData = nil
    local entries = {}
    local byId = {}
    local nextRank = {}
    local refreshPending = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Init, AddEntry, FamilyKnown, IsDone, IsEligible, Level, Cost, StateOf
    local Build, Matches, Discover, RequestData, OnDataLoaded, Changed, Tabs

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

    function Level(entry)
        local live = SBE.GetSpellLevelLearned(entry.id)
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
        if (level > playerLevel) then
            return STATE_FUTURE
        end
        if (entry.prev and not SBE.IsKnown(entry.prev)) then
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

    -- Returns sections sorted by level, each { level, items, trainableCost },
    -- plus a summary of what can be bought right now.
    function Build(filter)
        local options = SBE.options
        local playerLevel = UnitLevel("player")
        local sections, byLevel = {}, {}
        local summary = { trainable = 0, cost = 0, total = 0 }

        for _, entry in ipairs(entries) do
            if (IsEligible(entry)) then
                local level = Level(entry)
                local state = StateOf(entry, level, playerLevel)
                local name = SBE.GetSpellName(entry.id)

                local visible = Matches(entry, name, filter)
                    and (state ~= STATE_KNOWN or options.showKnown)
                    and (state ~= STATE_OTHER or options.showQuestAndBook)
                    and (not options.trainableOnly or state == STATE_TRAINABLE)

                if (state ~= STATE_KNOWN) then
                    summary.total = summary.total + 1
                end

                if (visible) then
                    local section = byLevel[level]
                    if (not section) then
                        section = { level = level, items = {}, trainableCost = 0 }
                        byLevel[level] = section
                        table.insert(sections, section)
                    end

                    local cost = Cost(entry)
                    table.insert(section.items, {
                        entry = entry, name = name, level = level, state = state, cost = cost,
                    })

                    if (state == STATE_TRAINABLE) then
                        section.trainableCost = section.trainableCost + (cost or 0)
                        summary.trainable = summary.trainable + 1
                        summary.cost = summary.cost + (cost or 0)
                    end
                end
            end
        end

        table.sort(sections, function(a, b) return a.level < b.level end)
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
        return classData and classData.tabs or {}
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
    SpellList.Discover = Discover
    SpellList.Changed = Changed
    SpellList.Tabs = Tabs
    SpellList.Get = function(id) return byId[id] end
    SpellList.Count = function() return #entries end
    SpellList.STATE_KNOWN = STATE_KNOWN
    SpellList.STATE_TRAINABLE = STATE_TRAINABLE
    SpellList.STATE_FUTURE = STATE_FUTURE
    SpellList.STATE_BLOCKED = STATE_BLOCKED
    SpellList.STATE_OTHER = STATE_OTHER
end

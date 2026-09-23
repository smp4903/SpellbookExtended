-- Trainer: reads an open class trainer's list. Prices and levels there are the
-- server's own, so they replace the shipped Classic values; spells the shipped
-- data lacks are added to the list.

local _, SBE = ...

SBE.Trainer = {}

do -- Private Scope
    local Trainer = SBE.Trainer

    local isOpen = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Store, ServiceSpellID, ServiceTab, Scan, Cost, Level

    function Store()
        local _, class = UnitClass("player")
        local cache = SpellbookExtended_TrainerCache
        cache[class] = cache[class] or { costs = {}, levels = {}, extra = {} }
        return cache[class]
    end

    function ServiceSpellID(index)
        if (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then
            local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
            if (ok and data and type(data.id) == "number") then
                return data.id
            end
        end

        if (GetTrainerServiceItemLink) then
            local ok, link = pcall(GetTrainerServiceItemLink, index)
            local id = ok and link and link:match("spell:(%d+)")
            if (id) then
                return tonumber(id)
            end
        end

        return nil
    end

    -- Weapon masters and riding trainers sell spells too; only services in one of
    -- the class's own skill lines are worth adding to the list.
    function ServiceTab(index)
        if (not GetTrainerServiceSkillLine) then
            return nil
        end
        local ok, skillLine = pcall(GetTrainerServiceSkillLine, index)
        if (not ok or type(skillLine) ~= "string") then
            return nil
        end
        for tab, name in ipairs(SBE.SpellList.Tabs()) do
            if (name == skillLine) then
                return tab
            end
        end
        return nil
    end

    function Scan()
        if (not isOpen or (IsTradeskillTrainer and IsTradeskillTrainer())) then
            return
        end

        local store = Store()
        local found, added = 0, 0

        for index = 1, GetNumTrainerServices() do
            local _, _, category = GetTrainerServiceInfo(index)
            if (category and category ~= "header") then
                local id = ServiceSpellID(index)
                if (id) then
                    local cost = GetTrainerServiceCost(index)
                    local level = GetTrainerServiceLevelReq(index)
                    store.costs[id] = cost
                    if (level and level > 0) then
                        store.levels[id] = level
                    end
                    local tab = not SBE.SpellList.Get(id) and ServiceTab(index)
                    if (tab) then
                        store.extra[id] = { level = level, tab = tab }
                        SBE.SpellList.Discover(id, level, tab)
                        added = added + 1
                    end
                    found = found + 1
                end
            end
        end

        SBE.DebugPrint(string.format("trainer: %d services read, %d new", found, added))
        SBE.SpellList.Changed()
    end

    function Cost(id)
        local store = SpellbookExtended_TrainerCache and Store()
        return store and store.costs[id]
    end

    function Level(id)
        local store = SpellbookExtended_TrainerCache and Store()
        return store and store.levels[id]
    end

    SBE.On("TRAINER_SHOW", function()
        isOpen = true
        Scan()
    end)
    SBE.On("TRAINER_UPDATE", Scan)
    SBE.On("TRAINER_CLOSED", function() isOpen = false end)

    Trainer.Cost = Cost
    Trainer.Level = Level
    Trainer.IsOpen = function() return isOpen end
end

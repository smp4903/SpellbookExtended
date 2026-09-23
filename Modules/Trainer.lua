-- Trainer: reads an open class trainer's list. Prices and levels there are the
-- server's own, so they replace the shipped Classic values; spells the shipped
-- data lacks are added to the list.

local _, SBE = ...

SBE.Trainer = {}

do -- Private Scope
    local Trainer = SBE.Trainer

    local isOpen = false
    local isClassTrainer = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Store, ServiceSpellID, Refused, ServiceTab, Scan, Cost, Level, Plan, TrainAll

    function Store()
        local _, class = UnitClass("player")
        local cache = SpellbookExtended_TrainerCache
        cache[class] = cache[class] or { costs = {}, levels = {}, extra = {} }
        return cache[class]
    end

    -- Prefers an ID the list knows: the tooltip ID is not guaranteed to be the
    -- spell on every client, so a name and rank match beats an unknown number.
    function ServiceSpellID(index)
        local candidates = {}

        if (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then
            local ok, data = pcall(C_TooltipInfo.GetTrainerService, index)
            if (ok and data and type(data.id) == "number") then
                table.insert(candidates, data.id)
            end
        end

        if (GetTrainerServiceItemLink) then
            local ok, link = pcall(GetTrainerServiceItemLink, index)
            local id = ok and type(link) == "string" and link:match("spell:(%d+)")
            if (id) then
                table.insert(candidates, tonumber(id))
            end
        end

        for _, id in ipairs(candidates) do
            if (SBE.SpellList.Get(id)) then
                return id
            end
        end

        local name, subtext = GetTrainerServiceInfo(index)
        return (name and SBE.SpellList.FindByName(name, subtext)) or candidates[1]
    end

    -- Classic clients answer "available"; anything but an explicit refusal is
    -- accepted here and checked against the list's own state in Plan.
    function Refused(category)
        if (type(category) ~= "string") then
            return false
        end
        category = category:lower()
        return category == "unavailable" or category == "used" or category == "header"
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
        if (not isOpen or not isClassTrainer) then
            return
        end

        local store = Store()
        local found, added = 0, 0

        for index = 1, GetNumTrainerServices() do
            local name, subtext, category = GetTrainerServiceInfo(index)
            if (SBE.debug) then
                local id = ServiceSpellID(index)
                SBE.DebugPrint(string.format("  %d: %s (%s) category=%s id=%s listed=%s trainable=%s",
                    index, tostring(name), tostring(subtext), tostring(category), tostring(id),
                    tostring(id and SBE.SpellList.Get(id) ~= nil), tostring(id and SBE.SpellList.IsTrainable(id))))
            end
            if (category ~= "header") then
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

        SBE.DebugPrint(string.format("trainer: %d of %d services recognised, %d new", found, GetNumTrainerServices(), added))
        SBE.SpellList.Changed()
    end

    -- What "Train all" would buy: services the trainer marks available, known to
    -- the list and not skipped, cheapest first while the money lasts.
    function Plan()
        local plan = { services = {}, cost = 0, unaffordable = 0 }
        if (not isOpen or not isClassTrainer) then
            return plan
        end

        local candidates = {}
        for index = 1, GetNumTrainerServices() do
            local _, _, category = GetTrainerServiceInfo(index)
            local id = not Refused(category) and ServiceSpellID(index)
            local sellable = id and (category == "available" or SBE.SpellList.IsTrainable(id))
            if (sellable and SBE.SpellList.Get(id) and not SBE.SpellList.IsSkipped(id)) then
                table.insert(candidates, { index = index, id = id, cost = GetTrainerServiceCost(index) or 0 })
            end
        end
        table.sort(candidates, function(a, b) return a.cost < b.cost end)

        local money = GetMoney()
        for _, service in ipairs(candidates) do
            if (plan.cost + service.cost <= money) then
                table.insert(plan.services, service)
                plan.cost = plan.cost + service.cost
            else
                plan.unaffordable = plan.unaffordable + 1
            end
        end
        return plan
    end

    function TrainAll()
        local plan = Plan()
        if (#plan.services == 0) then
            return
        end

        -- Highest index first: a purchase may reshuffle the entries below it.
        table.sort(plan.services, function(a, b) return a.index > b.index end)
        local bought, spent = 0, 0
        for _, service in ipairs(plan.services) do
            local ok = pcall(BuyTrainerService, service.index)
            if (ok) then
                bought = bought + 1
                spent = spent + service.cost
            end
        end

        if (bought > 0) then
            SBE.Print(string.format("trained %d %s for %s.", bought, bought == 1 and "spell" or "spells", SBE.FormatMoney(spent)))
        else
            SBE.Print("the trainer refused the purchase.")
        end
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
        isClassTrainer = not (IsTradeskillTrainer and IsTradeskillTrainer())
        Scan()
        if (isClassTrainer) then
            SBE.Fire("SBE_TRAINER_SHOW")
        end
    end)
    SBE.On("TRAINER_UPDATE", Scan)
    SBE.On("TRAINER_CLOSED", function()
        local wasClassTrainer = isOpen and isClassTrainer
        isOpen, isClassTrainer = false, false
        if (wasClassTrainer) then
            SBE.Fire("SBE_TRAINER_CLOSED")
        end
        SBE.SpellList.Changed()
    end)

    Trainer.Cost = Cost
    Trainer.Level = Level
    Trainer.IsOpen = function() return isOpen and isClassTrainer end
    Trainer.Plan = Plan
    Trainer.TrainAll = TrainAll
end

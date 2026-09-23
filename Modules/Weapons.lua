-- Weapons: where to learn a weapon skill, and a map pin to get there.

local _, SBE = ...

SBE.Weapons = {}

do -- Private Scope
    local Weapons = SBE.Weapons

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local MastersFor, Pin

    function MastersFor(skillID)
        local faction = UnitFactionGroup("player")
        local found = {}
        for _, master in ipairs(SBE.WeaponSkills and SBE.WeaponSkills.masters or {}) do
            if (master.faction == faction) then
                for _, id in ipairs(master.teaches) do
                    if (id == skillID) then
                        table.insert(found, master)
                        break
                    end
                end
            end
        end
        return found
    end

    -- Pins the first master that teaches the skill; says where if pinning fails.
    function Pin(skillID)
        local master = MastersFor(skillID)[1]
        if (not master) then
            return
        end

        local pinned = false
        local canPin = C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.GetMapInfo(master.map)
            and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(master.map))
        if (canPin) then
            local point = UiMapPoint.CreateFromCoordinates(master.map, master.x / 100, master.y / 100)
            pinned = pcall(C_Map.SetUserWaypoint, point)
            if (pinned and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint) then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end

        local where = string.format("%s, %s (%.1f, %.1f)", master.name, master.city, master.x, master.y)
        SBE.Print((pinned and "map pin set: " or "weapon master: ")..where)
    end

    Weapons.MastersFor = MastersFor
    Weapons.Pin = Pin
end

-- Development-only helpers. Listed between #@debug@ markers in the TOC, so
-- tools/build_release.py leaves this file out of release packages.

local _, SBE = ...

SpellbookExtended = SBE

do -- Private Scope
    local debug = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Inspect, OnTrainerService

    SBE.DebugPrint = function(msg)
        if (debug) then
            print("|cff34c0ebSBE|r "..msg)
        end
    end

    -- Prints the textures of the frame under the mouse, to borrow Blizzard artwork.
    function Inspect()
        local foci = GetMouseFoci and GetMouseFoci()
        local frame = foci and foci[1]
        if (not frame or not frame.GetRegions) then
            SBE.Print("nothing under the mouse.")
            return
        end
        SBE.Print("textures of "..tostring(frame.GetName and frame:GetName() or frame:GetDebugName()))
        for _, region in ipairs({ frame:GetRegions() }) do
            if (region.GetObjectType and region:GetObjectType() == "Texture") then
                local atlas = region.GetAtlas and region:GetAtlas()
                local layer, sublevel = region:GetDrawLayer()
                local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
                local relative = relativeTo and relativeTo.GetDebugName and relativeTo:GetDebugName():match("[^%.]+$") or "?"
                print(string.format("  %s %s  %s/%s  atlas=%s  size=%dx%d  at %s %s %s %.1f,%.1f",
                    region:IsShown() and "+" or "-", tostring(region:GetDebugName():match("[^%.]+$")),
                    tostring(layer), tostring(sublevel), tostring(atlas), region:GetWidth(), region:GetHeight(),
                    tostring(point), relative, tostring(relativePoint), x or 0, y or 0))
            end
        end
    end

    -- One line per trainer service: what the client reports and how the list reads it.
    function OnTrainerService(index, name, subtext, category, id)
        if (not debug) then
            return
        end
        SBE.DebugPrint(string.format("  %d: %s (%s) category=%s id=%s listed=%s trainable=%s",
            index, tostring(name), tostring(subtext), tostring(category), tostring(id),
            tostring(id and SBE.SpellList.Get(id) ~= nil), tostring(id and SBE.SpellList.IsTrainable(id))))
    end

    SBE.OnTrainerService = OnTrainerService

    SBE.AddCommand("debug", "toggle debug output", function()
        debug = not debug
        SBE.Print("debug "..(debug and "on" or "off"))
    end)
    SBE.AddCommand("inspect", "list the textures of the frame under the mouse", Inspect)
end

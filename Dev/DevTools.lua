-- Development-only helpers. Listed between #@debug@ markers in the TOC, so
-- tools/build_release.py leaves this file out of release packages.

local _, SBE = ...

SpellbookExtended = SBE

do -- Private Scope
    local debug = false

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local Inspect, OnTrainerService, Check

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

    -- What the compact spellbook relies on, as this client has it.
    function Check()
        local function line(label, ok, detail)
            print(string.format("  %s %s%s", ok and "|cff40ff40yes|r" or "|cffff4040no|r", label, detail and ("  "..detail) or ""))
        end
        SBE.Print("compact spellbook check")
        local keys = { GetBindingKey("TOGGLESPELLBOOK") }
        line("Toggle Spellbook key", #keys > 0, table.concat(keys, ", "))
        local action = keys[1] and GetBindingAction(keys[1], true)
        line("key opens the compact book", action == "CLICK SpellbookExtendedBookToggle:LeftButton", tostring(action))
        line("micro button", (_G.SpellbookMicroButton or _G.PlayerSpellsMicroButton) ~= nil)
        line("GameTooltip:SetSpellBookItem", GameTooltip.SetSpellBookItem ~= nil)
        line("C_SpellBook.PickupSpellBookItem", C_SpellBook.PickupSpellBookItem ~= nil)
        line("C_SpellBook.IsSpellBookItemLowRank", C_SpellBook.IsSpellBookItemLowRank ~= nil)
        line("C_SpellBook.GetSpellBookItemCooldown", C_SpellBook.GetSpellBookItemCooldown ~= nil)
        line("MenuUtil.CreateContextMenu", MenuUtil and MenuUtil.CreateContextMenu ~= nil)
        line("in combat", InCombatLockdown())
        local rows = SBE.BookData.Build({ showUpcoming = true })
        local counts = { header = 0, spell = 0, upcoming = 0 }
        for _, row in ipairs(rows) do
            counts[row.kind] = (counts[row.kind] or 0) + 1
        end
        line("book rows", #rows > 0, string.format("%d sections, %d spells, %d upcoming", counts.header, counts.spell, counts.upcoming))
    end

    SBE.AddCommand("debug", "toggle debug output", function()
        debug = not debug
        SBE.Print("debug "..(debug and "on" or "off"))
    end)
    SBE.AddCommand("inspect", "list the textures of the frame under the mouse", Inspect)
    SBE.AddCommand("check", "check what the compact spellbook needs from this client", Check)
end

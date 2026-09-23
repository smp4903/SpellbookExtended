local _, SBE = ...

do -- Private Scope
    local Help, Inspect, TopLevelUnderMouse

    function Help()
        SBE.Print("commands:")
        print("  /sbe  - show or hide the panel")
        print("  /sbe options  - open the settings")
        print("  /sbe dock  - hover the spellbook first; docks the panel to it")
        print("  /sbe auto  - open the panel whenever the spellbook opens")
        print("  /sbe notify  - level-up announcement: alert, float, chat or off")
        print("  /sbe test  - preview the level-up announcement")
        print("  /sbe trainer  - open the panel when you talk to your class trainer")
        print("  /sbe debug  - toggle debug output")
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

    function TopLevelUnderMouse()
        local foci = GetMouseFoci and GetMouseFoci()
        local frame = foci and foci[1]
        while (frame and frame.GetParent and frame:GetParent() and frame:GetParent() ~= UIParent) do
            frame = frame:GetParent()
        end
        return frame
    end

    SLASH_SPELLBOOKEXTENDED1 = "/sbe"
    SLASH_SPELLBOOKEXTENDED2 = "/spellbookextended"
    SlashCmdList["SPELLBOOKEXTENDED"] = function(msg)
        local command, arg = strsplit(" ", strtrim(msg or ""), 2)
        command = (command or ""):lower()

        if (command == "") then
            SBE.Dock.Anchor()
            SBE.Panel.Toggle()
        elseif (command == "options" or command == "settings") then
            SBE.Options.Open()
        elseif (command == "dock") then
            local frame = arg and _G[arg] or TopLevelUnderMouse()
            local name = frame and frame.GetName and frame:GetName()
            if (name and SBE.Dock.SetFrameByName(name)) then
                SBE.Print("docked to "..name..".")
            else
                SBE.Print("no named frame under the mouse. Hover the spellbook and try again.")
            end
        elseif (command == "auto") then
            SBE.options.autoOpen = not SBE.options.autoOpen
            SBE.Print("open with the spellbook: "..(SBE.options.autoOpen and "on" or "off"))
        elseif (command == "notify") then
            local nextStyle = { alert = "float", float = "chat", chat = "off", off = "alert" }
            SBE.options.notify = nextStyle[SBE.options.notify] or "alert"
            SBE.Print("level-up announcement: "..SBE.options.notify)
        elseif (command == "test") then
            SBE.Preview()
        elseif (command == "trainer") then
            SBE.options.openWithTrainer = not SBE.options.openWithTrainer
            SBE.Print("open with the class trainer: "..(SBE.options.openWithTrainer and "on" or "off"))
        elseif (command == "inspect") then
            Inspect()
        elseif (command == "debug") then
            SBE.debug = not SBE.debug
            SBE.Print("debug "..(SBE.debug and "on" or "off"))
        else
            Help()
        end
    end
end

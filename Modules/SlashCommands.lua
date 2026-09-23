local _, SBE = ...

do -- Private Scope
    local Help, TopLevelUnderMouse

    function Help()
        SBE.Print("commands:")
        print("  /sbe  - show or hide the panel")
        print("  /sbe dock  - hover the spellbook first; docks the panel to it")
        print("  /sbe auto  - open the panel whenever the spellbook opens")
        print("  /sbe debug  - toggle debug output")
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
        elseif (command == "debug") then
            SBE.debug = not SBE.debug
            SBE.Print("debug "..(SBE.debug and "on" or "off"))
        else
            Help()
        end
    end
end

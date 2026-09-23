local _, SBE = ...

do -- Private Scope
    local commands = {}
    local order = {}

    -- Forward declarations: keep these as file-locals so they never leak into _G.
    local AddCommand, Help, TopLevelUnderMouse, Toggle

    -- Other files add their own subcommands here (Dev/DevTools.lua does).
    function AddCommand(name, help, handler)
        if (not commands[name]) then
            table.insert(order, name)
        end
        commands[name] = { help = help, handler = handler }
    end

    function Help()
        SBE.Print("commands:")
        print("  /sbe  - show or hide the panel")
        for _, name in ipairs(order) do
            if (commands[name].help) then
                print("  /sbe "..name.."  - "..commands[name].help)
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

    function Toggle(key, label)
        SBE.options[key] = not SBE.options[key]
        SBE.Print(label..": "..(SBE.options[key] and "on" or "off"))
        SBE.Fire("SBE_CHANGED")
    end

    AddCommand("options", "open the settings", function() SBE.Options.Open() end)
    AddCommand("settings", nil, function() SBE.Options.Open() end)

    AddCommand("dock", "hover the spellbook first; docks the panel to it", function(arg)
        local frame = arg and _G[arg] or TopLevelUnderMouse()
        local name = frame and frame.GetName and frame:GetName()
        if (name and SBE.Dock.SetFrameByName(name)) then
            SBE.Print("docked to "..name..".")
        else
            SBE.Print("no named frame under the mouse. Hover the spellbook and try again.")
        end
    end)

    AddCommand("auto", "open the panel whenever the spellbook opens", function()
        Toggle("autoOpen", "open with the spellbook")
    end)

    AddCommand("notify", "level-up announcement: alert, float, chat or off", function()
        local nextStyle = { alert = "float", float = "chat", chat = "off", off = "alert" }
        SBE.options.notify = nextStyle[SBE.options.notify] or "alert"
        SBE.Print("level-up announcement: "..SBE.options.notify)
    end)

    AddCommand("test", "preview the level-up announcement", function() SBE.Preview() end)

    AddCommand("trainer", "open the panel when you talk to your class trainer", function()
        Toggle("openWithTrainer", "open with the class trainer")
    end)

    SLASH_SPELLBOOKEXTENDED1 = "/sbe"
    SLASH_SPELLBOOKEXTENDED2 = "/spellbookextended"
    SlashCmdList["SPELLBOOKEXTENDED"] = function(msg)
        local command, arg = strsplit(" ", strtrim(msg or ""), 2)
        command = (command or ""):lower()

        if (command == "") then
            SBE.Dock.Anchor()
            SBE.Panel.Toggle()
        elseif (commands[command]) then
            commands[command].handler(arg)
        else
            Help()
        end
    end

    SBE.AddCommand = AddCommand
end

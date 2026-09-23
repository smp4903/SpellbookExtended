-- Widget helpers shared with FiveSecondRule's options panel.
local _, SBE = ...

SBE.UIFactory = {}

function SBE.UIFactory:MakeCheckbox(parent, label, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(25, 25)

    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 5, 0)
    cb.label:SetText(label)

    cb:SetScript("OnEnter", function(self)
        if (tooltip) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    cb:SetScript("OnLeave", GameTooltip_Hide)
    return cb
end

function SBE.UIFactory:MakeButton(parent, width, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

function SBE.UIFactory:MakeText(parent, text, fontObject)
    local fontString = parent:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    fontString:SetJustifyH("LEFT")
    fontString:SetText(text)
    return fontString
end

-- options: { { text, value }, ... }; onSelect(value)
function SBE.UIFactory:MakeDropdown(parent, width, options, getValue, onSelect)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, option in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option[1]
            info.value = option[2]
            info.checked = (getValue() == option[2])
            info.func = function()
                onSelect(option[2])
                UIDropDownMenu_SetSelectedValue(dropdown, option[2])
                UIDropDownMenu_SetText(dropdown, option[1])
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    dropdown.Sync = function(self)
        for _, option in ipairs(options) do
            if (option[2] == getValue()) then
                UIDropDownMenu_SetSelectedValue(self, option[2])
                UIDropDownMenu_SetText(self, option[1])
            end
        end
    end
    return dropdown
end

-- Vertical flow layout: widgets are placed in the order they are added.
function SBE.UIFactory:CreateStack(parent, x, y, rowGap)
    local stack = { parent = parent, x = x or 0, y = y or 0, rowGap = rowGap or 8 }

    function stack:Add(widget, itemOpts)
        itemOpts = itemOpts or {}
        widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (itemOpts.dx or 0), self.y + (itemOpts.dy or 0))
        self.y = self.y - (itemOpts.height or widget:GetHeight() or 0) - (itemOpts.gap or self.rowGap)
        return widget
    end

    function stack:Space(height)
        self.y = self.y - height
    end

    return stack
end

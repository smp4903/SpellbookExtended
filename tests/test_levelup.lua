-- Level-up announcement: loot alerts, summary above four spells, fallbacks.
local ns = dofile("harness.lua")
local shown = {}
local function fs() local t = {}; return { SetText = function(_, v) t.text = v end, SetTextColor = function() end, SetShown = function() end, GetText = function() return t.text end } end
local function region() return { Hide = function() end, Show = function() end, SetAtlas = function() end, SetTexture = function() end } end
AlertFrame = { AddQueuedAlertFrameSubSystem = function(self, template, setUp)
  return { AddAlert = function(_, data)
    local f = CreateFrame("Button")
    rawset(f, "lootItem", { Icon = region(), IconBorder = region(), Count = fs() })
    rawset(f, "Label", fs()); rawset(f, "ItemName", fs())
    setUp(f, data)
    table.insert(shown, f)
  end }
end }
C_Texture.GetAtlasInfo = function() return {} end

Login("HUNTER", 19, { 1978, 13549, 13550, 3044, 14281, 1130, 13165, 14318, 1515, 136, 2974, 14260, 14261, 20736, 13795, 1495 })
PLAYER.level = 20
Fire("PLAYER_LEVEL_UP", 20); RunTimers()
check(#shown == 1 and shown[1].lootItem.Count:GetText() == "8", "one summary toast for 8 spells, Dual Wield included")

shown = {}
PLAYER.level = 22
Fire("PLAYER_LEVEL_UP", 22); RunTimers()
check(#shown == 2 and shown[1].Label:GetText() == "New at your trainer", "one toast per spell at 22")

AlertFrame_OnClick = function() return false end
shown[1]:GetScript("OnClick")(shown[1], "LeftButton")
check(ns.Panel.Frame():IsShown(), "clicking a toast opens the panel")

ns.options.notify = "float"
Fire("PLAYER_LEVEL_UP", 22); RunTimers()
check(SpellbookExtendedToast and SpellbookExtendedToast:IsShown(), "floating text style")
NOW = NOW + 20; SpellbookExtendedToast:GetScript("OnUpdate")(SpellbookExtendedToast)
check(not SpellbookExtendedToast:IsShown(), "floating text fades out")
done()

-- Spell list states: ranks, talents, race, skipping, weapon skills.
local ns = dofile("harness.lua")
Login("DRUID", 16, { 5176, 5177, 5178, 5185, 5186, 1126, 5232, 8921, 774, 467, 339, 5487, 6795, 6807 })

local items = ListState()
check(ns.SpellList.Count() > 150, "druid data loaded")
check(items[8924] and items[8924].state == "trainable", "Moonfire 2 trainable at 16")
check(items[8925] and items[8925].state == "blocked", "Moonfire 3 blocked without rank 2")
check(items[5570] == nil and items[24974] == nil, "Insect Swarm hidden without the talent")
check(items[5177] == nil, "known Wrath 2 hidden by default")
check(items[1066] and items[1066].state == "other", "Aquatic Form is a quest spell")

PLAYER.known[5570] = true
PLAYER.level = 30
check(ListState()[24974] and ListState()[24974].state == "trainable", "Insect Swarm 2 after the talent")

ns.SpellList.ToggleSkip(8924)
check(ns.SpellList.IsSkipped(8924) and ns.SpellList.IsSkipped(8925), "skipping a rank skips the ranks above")
ns.SpellList.ToggleSkip(8924)
check(not ns.SpellList.IsSkipped(8925), "unskip restores")

local weapons = ListState({ search = "", tab = #ns.SpellList.Tabs() })
check(ns.SpellList.Tabs()[#ns.SpellList.Tabs()] == "Weapons", "Weapons tab present")
check(weapons[227] and weapons[227].entry.weapon, "druid can learn Staves")
check(weapons[201] == nil, "druid cannot learn one-handed swords")
local sections, summary = ns.SpellList.Build({ search = "", tab = 0 })
check(sections[#sections].weapons, "weapon section comes last")
check(#ns.Weapons.MastersFor(227) == 2, "two Alliance masters teach Staves")
SlashCmdList.SPELLBOOKEXTENDED("")
local panel = ns.Panel.Frame()
check(panel:IsShown(), "panel draws with the weapon section")
check(#panel.tabButtons == #ns.SpellList.Tabs() + 1, "one icon tab per spellbook tab plus All")
check(panel.tabLabel:GetText() == "All spells", "active tab named beside the icons")
check(#panel.checkboxes == 5 and panel.checkboxes[5].key == "autoOpen", "Open with spellbook in the footer")
-- Seal of Righteousness 1 exists as 20154 and 21084; paladins start with 21084.
Login("PALADIN", 10, { 21084, 635 })
local paladin = ListState()
check(paladin[20287] and paladin[20287].state == "trainable", "Seal of Righteousness 2 trainable with the starting rank 1")
Login("PALADIN", 10, { 20154, 635 })
check(ListState()[20287].state == "trainable", "and with the other rank 1 ID")
Login("PALADIN", 10, { 635 })
check(ListState()[20287].state == "blocked", "blocked without rank 1")

-- A hunter learns Parry from the class trainer at 8, outside the class skill lines.
Login("HUNTER", 8, { 1978 })
local hunter = ListState()
check(hunter[3127] and hunter[3127].level == 8 and hunter[3127].state == "trainable", "hunter Parry at level 8")
check(hunter[8737] and hunter[8737].level == 40, "hunter Mail at level 40")
done()
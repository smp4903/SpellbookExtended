local ns = dofile("harness.lua")
Login("WARRIOR", 10, { 2457, 78 })
check(SETTINGS_CATEGORY ~= nil, "settings page registered")
SlashCmdList.SPELLBOOKEXTENDED("options")
check(SETTINGS_OPENED == "Spellbook Extended", "/sbe options opens it")
SETTINGS_CATEGORY.frame:Show()
local compact, upcoming
for _, f in ipairs(FRAMES) do
  if rawget(f, "key") == "compactBook" then compact = f end
  if rawget(f, "key") == "bookUpcoming" then upcoming = f end
end
check(compact and compact:GetChecked() == true, "compact spellbook option shown, on by default")
compact:SetChecked(false)
compact._scripts.OnClick(compact)
check(ns.options.compactBook == false and OVERRIDES.P == nil, "unticking it gives the key back to Blizzard")
check(rawget(upcoming, "_enabled") == false, "upcoming option greyed while the book is off")
compact:SetChecked(true)
compact._scripts.OnClick(compact)
check(OVERRIDES.P ~= nil and rawget(upcoming, "_enabled") == true, "ticking it takes the key again")
local items = ListState()
check(items[7386] and items[7386].entry.quest, "Sunder Armor is a quest spell")
check(items[355] and items[355].entry.quest, "Taunt is a quest spell")
done()

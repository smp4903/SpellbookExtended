-- Compact spellbook: sections from the client's spellbook, folded ranks,
-- upcoming spells, the footer, docking and the spellbook key.
local ns = dofile("harness.lua")

-- A level 22 hunter's spellbook as C_SpellBook reports it.
local LINES = {
  { name = "General", items = {
    { id = 6603, name = "Attack" }, { id = 75, name = "Auto Shot" },
    { id = 3127, name = "Parry", passive = true } } },
  { name = "Marksmanship", items = {
    { id = 14282, name = "Arcane Shot", sub = "Rank 3" },
    { id = 14281, name = "Arcane Shot", sub = "Rank 2", low = true },
    { id = 3044, name = "Arcane Shot", sub = "Rank 1", low = true },
    { id = 1978, name = "Serpent Sting", sub = "Rank 1" },
    { id = 14283, name = "Arcane Shot", sub = "Rank 4", future = true } } },
  { name = "Beast Mastery", items = {
    { id = 13165, name = "Aspect of the Hawk", sub = "Rank 1" },
    -- A flyout and its loose spells, as the client lists Paladin blessings.
    { id = 900, name = "Aspects", flyout = true },
    { id = 13163, name = "Aspect of the Monkey" },
    { id = 5118, name = "Aspect of the Cheetah" } } },
}
local PET = { { id = 17253, name = "Bite", sub = "Rank 1" }, { id = 2649, name = "Growl", sub = "Rank 1" } }
local slots = {}
for index, line in ipairs(LINES) do
  line.offset = #slots
  for _, item in ipairs(line.items) do table.insert(slots, item) end
end
local function bankItems(bank) return bank == 1 and PET or slots end
C_SpellBook.GetNumSpellBookSkillLines = function() return #LINES end
C_SpellBook.GetSpellBookSkillLineInfo = function(i)
  local line = LINES[i]
  return { name = line.name, iconID = 1, itemIndexOffset = line.offset, numSpellBookItems = #line.items, shouldHide = false }
end
C_SpellBook.GetSpellBookItemInfo = function(slot, bank)
  local item = bankItems(bank)[slot]
  return item and { actionID = item.id, spellID = item.id, name = item.name, subName = item.sub or "", iconID = 1,
    itemType = item.future and 2 or item.flyout and 4 or (bank == 1 and 3 or 1), isPassive = item.passive or false, isOffSpec = false }
end
C_SpellBook.IsSpellBookItemLowRank = function(slot, bank) return bankItems(bank)[slot].low == true end
C_SpellBook.HasPetSpells = function() return #PET, "PET" end
C_SpellBook.PickupSpellBookItem = function(slot, bank) PICKED = { slot, bank } end
C_SpellBook.GetSpellBookItemAutoCast = function() return false, false end

Login("HUNTER", 22, { 6603, 75, 3127, 14282, 14281, 3044, 1978, 13165, 1494, 13163, 1130 })
local BookData = ns.BookData

local function find(rows, pred)
  for i, row in ipairs(rows) do if pred(row) then return row, i end end
end
local function byName(name) return function(row) return row.name == name end end

local rows = BookData.Build({ showUpcoming = true })
check(rows[1].kind == "header" and rows[1].name == "General", "General section first")
check(find(rows, byName("Parry")) ~= nil, "passives listed by default")
check(find(BookData.Build({ hidePassives = true }), byName("Parry")) == nil, "passives hidden when Blizzard hides them")
check(find(rows, function(r) return r.kind == "spell" and r.spell.spellID == 14283 end) == nil, "future spell items are not known spells")

local arcane, arcaneIndex = find(rows, byName("Arcane Shot"))
check(arcane and arcane.hasChildren and arcane.meta == "R3" and not arcane.expanded, "Arcane Shot leads with rank 3, folded")
check(rows[arcaneIndex + 1].name ~= "Rank 2", "lower ranks hidden while folded")
local open = BookData.Build({ expanded = { [arcane.key] = true } })
local _, openIndex = find(open, byName("Arcane Shot"))
check(open[openIndex + 1].kind == "child" and open[openIndex + 1].name == "Rank 2" and open[openIndex + 2].name == "Rank 1", "unfolded ranks follow, highest first")
local all = BookData.Build({ unfoldAll = true })
check(find(all, byName("Rank 1")) ~= nil, "unfold all")

local _, mmIndex = find(rows, byName("Marksmanship"))
local _, bmIndex = find(rows, byName("Beast Mastery"))
local upcoming = find(rows, function(r) return r.kind == "upcoming" and r.item.entry.id == 13551 end)
check(upcoming and not upcoming.name:find("Rank") and upcoming.tone == "bad", "Serpent Sting 4 upcoming, named without its rank")
check(upcoming.meta:find("R4") and upcoming.meta:find("Lvl 26"), "rank and level on the right")
check(find(rows, function(r) return r.kind == "upcoming" and r.item.entry.id == 14283 end) == nil,
  "Arcane Shot 4 at level 28 is beyond the "..BookData.LOOKAHEAD.."-level lookahead")
local hmark = find(rows, function(r) return r.kind == "upcoming" and r.item.entry.id == 14323 end)
check(hmark and hmark.item.state == "trainable" and not hmark.meta:find("Lvl"), "Hunter's Mark 2 trainable now, priced")
local _, upIndex = find(rows, function(r) return r.kind == "upcoming" and r.item.entry.tab == 2 end)
local _, lastKnownMM = find(rows, byName("Serpent Sting"))
check(upIndex > lastKnownMM and upIndex > mmIndex and upIndex < bmIndex, "upcoming spells close their own section")
check(find(BookData.Build({ showUpcoming = false }), function(r) return r.kind == "upcoming" end) == nil, "upcoming hidden by the toggle")

check(find(rows, byName("Aspects")) == nil, "flyouts are not grouped")
check(find(rows, byName("Aspect of the Monkey")) ~= nil and find(rows, byName("Aspect of the Cheetah")) ~= nil, "flyout spells get their own rows")

local folded = BookData.Build({ collapsed = { ["Marksmanship"] = true }, showUpcoming = true })
local mmHeader, mmAt = find(folded, byName("Marksmanship"))
check(mmHeader.collapsed and folded[mmAt + 1].kind == "header", "a folded section keeps only its header")
check(find(folded, byName("Arcane Shot")) == nil, "folded spells hidden")
local foldSearch = BookData.Build({ collapsed = { ["Marksmanship"] = true }, search = "arc" })
check(find(foldSearch, byName("Arcane Shot")) ~= nil, "searching opens folded sections")

local searched = BookData.Build({ search = "arc", showUpcoming = false })
check(#searched == 2 and searched[1].name == "Marksmanship" and searched[2].name == "Arcane Shot", "search keeps matching rows and their header")
check(find(rows, function(r) return r.kind == "header" and r.pet end) ~= nil and find(rows, byName("Bite")) ~= nil, "pet section")

check(find(rows, function(r) return r.kind == "upcoming" and r.item.entry.id == 3045 end) ~= nil, "Rapid Fire upcoming")
ns.SpellList.ToggleSkip(3045)
check(find(BookData.Build({ showUpcoming = true }), function(r) return r.kind == "upcoming" and r.item.entry.id == 3045 end) == nil, "skipped spells leave the book")
ns.SpellList.ToggleSkip(3045)

-- The frame, footer and docking.
check(OVERRIDES.P == "CLICK SpellbookExtendedBookToggle:LeftButton", "P opens the compact book")
_G.SpellbookExtendedBookToggle._scripts.OnClick()
local book = ns.Book.Frame()
check(book and book:IsShown(), "the binding's button toggles the book")
check((book.footer.summary:GetText() or ""):find("now") ~= nil, "footer shows what can be trained now")
check(book.footer.label:GetText() == "Spells to learn", "footer names the panel")

local function headerNamed(name)
  for _, f in ipairs(FRAMES) do
    if f._kind == "Button" and rawget(f, "data") and f.data.kind == "header" and f.data.name == name and f._shown then return f end
  end
end
local mm = headerNamed("Marksmanship")
mm._scripts.OnClick(mm)
check(headerNamed("Marksmanship").data.collapsed, "clicking a header folds it")
headerNamed("Marksmanship")._scripts.OnClick(headerNamed("Marksmanship"))
check(not headerNamed("Marksmanship").data.collapsed, "clicking again unfolds it")

book.footer._scripts.OnClick()
local panel = ns.Panel.Frame()
check(panel:IsShown() and panel.dockedTo == book, "footer opens the panel docked to the book")
check(panel._points.TOPLEFT == book and panel._points.BOTTOMLEFT == book, "docked panel spans the book's height")
check(book.footer.lit:IsShown(), "footer lit while the panel is open")
book.footer._scripts.OnClick()
check(not panel:IsShown() and not book.footer.lit:IsShown(), "footer closes it again")

ns.Panel.JumpTo(14283)
RunTimers()
check(panel:IsShown(), "an upcoming row opens the panel at its level")
book:Hide()
check(not panel:IsShown(), "closing the book closes the docked panel")
ns.Dock.Anchor()
check(panel.dockedTo == nil and panel._h == ns.Panel.HEIGHT and panel._points.BOTTOMLEFT == nil, "undocked panel goes back to its own height")

-- The spellbook key.
check(ns.options.compactBook == true, "compact spellbook on by default")
ns.Book.Show()
ns.options.compactBook = false
ns.BookKeys.Apply()
check(OVERRIDES.P == nil, "turned off, P goes back to Blizzard")
check(not ns.Book.Frame():IsShown(), "turning it off closes the compact book")
ns.options.compactBook = true
IN_COMBAT = true
ns.BookKeys.Apply()
check(OVERRIDES.P == nil, "no binding changes in combat")
IN_COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
check(OVERRIDES.P ~= nil, "applied once combat ends")
BINDINGS.TOGGLESPELLBOOK = { "B" }
Fire("UPDATE_BINDINGS")
check(OVERRIDES.B ~= nil and OVERRIDES.P == nil, "follows a rebound spellbook key")

SlashCmdList.SPELLBOOKEXTENDED("book")
check(book:IsShown(), "/sbe book opens it")

-- Dragging a spell: the spellbook pickup first, the spell ID if that leaves the cursor empty.
local function spellRow(name)
  for _, f in ipairs(FRAMES) do
    local data = rawget(f, "data")
    if data and data.kind == "spell" and data.name == name and f._shown then return f end
  end
end
local hawk = spellRow("Aspect of the Hawk")
C_SpellBook.PickupSpellBookItem = function(slot) CURSOR = "spell"; PICKED = slot end
hawk._scripts.OnDragStart(hawk)
check(CURSOR == "spell" and PICKED ~= nil, "drag picks up the spellbook item")
CURSOR, PICKED = nil, nil
local byID
C_SpellBook.PickupSpellBookItem = function() end
C_Spell.PickupSpell = function(id) CURSOR = "spell"; byID = id end
hawk._scripts.OnDragStart(hawk)
check(CURSOR == "spell" and byID == 13165, "falls back to the spell ID when the client refuses the pickup")
CURSOR = nil

-- Blizzard's-book button: secure, and never anchored to the book, so the
-- book stays unprotected and opens in combat.
SpellbookMicroButton = CreateFrame("Button", "SpellbookMicroButton")
book:Hide()
book:Show()
local secure = _G.SpellbookExtendedBlizzardBook
check(secure and secure._template == "SecureActionButtonTemplate" and secure:IsShown(), "secure button shown over the book")

-- Before layout the stand-in has no position; the button still appears a frame later.
book:Hide()
local realCenter = book.blizzSpot.GetCenter
rawset(book.blizzSpot, "GetCenter", function() return nil end)
book:Show()
check(not secure:IsShown(), "no position yet, button waits")
rawset(book.blizzSpot, "GetCenter", realCenter)
RunTimers()
check(secure:IsShown(), "button placed once the book has a position")
local function anchoredTo(f, target, depth)
  depth = depth or 0
  if depth > 10 or not f then return false end
  for _, rel in ipairs(rawget(f, "_anchors") or {}) do
    if rel == target or anchoredTo(rel, target, depth + 1) then return true end
  end
  return rawget(f, "_parent") == target or (rawget(f, "_parent") and anchoredTo(rawget(f, "_parent"), target, depth + 1))
end
check(not anchoredTo(secure, book), "secure button is not anchored or parented to the book")
check(secure:GetFrameStrata() == book:GetFrameStrata(), "secure button on the book's strata, so other windows cover it")
book:SetFrameLevel(50)
secure._scripts.OnUpdate(secure)
check(secure:GetFrameLevel() > 50, "secure button follows the book when it is raised")
Fire("PLAYER_REGEN_DISABLED")
check(not secure:IsShown(), "secure button hidden as combat starts")
IN_COMBAT = true
book:Hide()
_G.SpellbookExtendedBookToggle._scripts.OnClick()
check(book:IsShown(), "the book opens in combat")
IN_COMBAT = false
Fire("PLAYER_REGEN_ENABLED")
check(secure:IsShown(), "secure button back after combat")
done()

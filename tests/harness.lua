-- Minimal WoW API stub for loading SpellbookExtended outside the client.
-- Only what the addon touches; unknown frame methods are no-ops.
local root = arg[1] or ".."
local frames = {}
local universal
universal = setmetatable({}, { __call = function() return nil end, __index = function() return universal end })
local function newObject(kind, name)
  local o = { _scripts = {}, _events = {}, _shown = kind ~= "Frame" or true, _kind = kind, _w = 630, _text = "" }
  o._shown = true
  local mt = {}
  mt.__index = function(t, k)
    if type(k) == "string" and k:sub(1,1) == "_" then return nil end
    if type(k) == "string" and k:match("^%l") then return nil end
    return universal
  end
  setmetatable(o, mt)
  o.RegisterEvent = function(self, e)
    if e == "LEARNED_SPELL_IN_TAB" then error("unknown event") end
    self._events[e] = true
  end
  o.SetScript = function(self, s, f) self._scripts[s] = f end
  o.HookScript = function(self, s, f) local old = self._scripts[s]; self._scripts[s] = function(...) if old then old(...) end f(...) end end
  o.GetScript = function(self, s) return self._scripts[s] end
  o.Show = function(self) local was = self._shown; self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
  o.Hide = function(self) local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
  o.IsShown = function(self) return self._shown end
  o.GetWidth = function(self) return self._w end
  o.SetWidth = function(self, w) self._w = w end
  o.GetHeight = function() return 30 end
  o.SetText = function(self, t) self._text = t end
  o.GetText = function(self) return self._text end
  o.GetStringWidth = function() return 50 end
  o.GetFontString = function(self) local fs = rawget(self, "_fs") or newObject("FontString"); rawset(self, "_fs", fs); return fs end
  o.CreateTexture = function() return newObject("Texture") end
  o.CreateFontString = function() return newObject("FontString") end
  o.GetChecked = function(self) return rawget(self, "_checked") end
  o.SetChecked = function(self, v) self._checked = v end
  o.GetName = function() return name end
  o.GetFrameStrata = function() return "MEDIUM" end
  o.GetParent = function() return nil end
  return o
end
function CreateFrame(kind, name, parent, template)
  local f = newObject(kind, name)
  f._shown = true
  table.insert(frames, f)
  if name then _G[name] = f end
  return f
end
UIParent = newObject("Frame", "UIParent")
UISpecialFrames = {}
GameTooltip = newObject("GameTooltip")
GameTooltip_Hide = function() end
SlashCmdList = {}
function strsplit(sep, s, n) local a, b = s:match("^(%S*)%s*(.-)$"); if b == "" then b = nil end return a, b end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CreateColor(...) return {...} end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
NOW = 100
function GetTime() return NOW end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
SETTINGS_OPENED = nil
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name) return { GetID = function() return name end, frame = frame } end,
  RegisterAddOnCategory = function(category) SETTINGS_CATEGORY = category end,
  OpenToCategory = function(id) SETTINGS_OPENED = id end,
}

FAILURES = 0
function check(cond, msg)
  if not cond then
    FAILURES = FAILURES + 1
    print("FAIL: "..msg)
  end
end
function done()
  if FAILURES > 0 then os.exit(1) end
  print("ok")
end

-- Character: Night Elf druid, level 16.
PLAYER = { class = "DRUID", level = 16, race = 4, faction = "Alliance", money = 2500,
  known = { [5176]=true, [5177]=true, [5178]=true, [5185]=true, [5186]=true, [1126]=true, [5232]=true, [8921]=true, [774]=true, [467]=true, [339]=true, [5487]=true, [6795]=true, [6807]=true } }
function UnitClass() return "Druid", PLAYER.class, 11 end
function UnitLevel() return PLAYER.level end
function UnitRace() return "Night Elf", "NightElf", PLAYER.race end
function UnitFactionGroup() return PLAYER.faction end
function GetMoney() return PLAYER.money end
function GetMoneyString(c) return string.format("%dg%ds%dc", c/10000, (c%10000)/100, c%100) end
function IsPlayerSpell(id) return PLAYER.known[id] == true end
function IsModifiedClick() return false end
C_Spell = {
  GetSpellName = function(id) return "Spell"..id end,
  GetSpellTexture = function(id) return 1 end,
  GetSpellSubtext = function(id) return nil end,
  GetSpellLevelLearned = function(id) return 0 end,
  IsSpellDataCached = function() return true end,
  RequestLoadSpellData = function() end,
  GetSpellLink = function(id) return "|Hspell:"..id.."|h" end,
}
C_SpellBook = {}
C_Timer = { After = function(t, f) PENDING = PENDING or {}; table.insert(PENDING, f) end }
C_Texture = { GetAtlasInfo = function() return nil end }
C_CurrencyInfo = {}
C_Item = { GetItemNameByID = function() return "Book" end }
function RunTimers() while PENDING and #PENDING > 0 do local f = table.remove(PENDING, 1); f() end end

local ns = {}
local toc = io.open(root.."/SpellbookExtended.toc"):read("*a")
for line in toc:gmatch("[^\r\n]+") do
  if not line:match("^##") and line:match("%.lua$") then
    local path = root.."/"..line:gsub("\\", "/")
    local chunk = assert(loadfile(path))
    chunk("SpellbookExtended", ns)
  end
end
function Fire(event, ...)
  for _, f in ipairs(frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
-- Class token, level and a list of known spell IDs; loads the addon's state.
function Login(class, level, known, race)
  UnitClass = function() return class, class, 0 end
  PLAYER.level = level
  PLAYER.race = race or PLAYER.race
  PLAYER.known = {}
  for _, id in ipairs(known or {}) do PLAYER.known[id] = true end
  Fire("ADDON_LOADED", "SpellbookExtended")
  Fire("PLAYER_LOGIN")
  RunTimers()
end

-- Items of the built list, keyed by spell ID.
function ListState(filter)
  local out = {}
  for _, section in ipairs(ns.SpellList.Build(filter or { search = "", tab = 0 })) do
    for _, item in ipairs(section.items) do out[item.entry.id] = item end
  end
  return out
end

return ns

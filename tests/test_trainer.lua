-- Train all: Forever-like trainer with odd categories and IDs that are not spell IDs.
local ns = dofile("harness.lua")
C_Spell.GetSpellName = function(id) return ({[3044]="Arcane Shot",[1130]="Hunter's Mark",[13550]="Serpent Sting"})[id] or ("Spell"..id) end
Login("HUNTER", 6, { 1978 })
PLAYER.money = 687

local services = { {"Arcane Shot", "Rank 1", 95}, {"Hunter's Mark", "Rank 1", 95} }
GetNumTrainerServices = function() return #services end
GetTrainerServiceInfo = function(i) return services[i][1], services[i][2], 1 end
C_TooltipInfo = { GetTrainerService = function(i) return { id = 90000 + i } end }
GetTrainerServiceCost = function(i) return services[i][3] end
GetTrainerServiceLevelReq = function() return 6 end
IsTradeskillTrainer = function() return false end
local bought = {}
BuyTrainerService = function(i) table.insert(bought, i) end

Fire("TRAINER_SHOW"); RunTimers()
local panel = ns.Panel.Frame()
check(panel and panel:IsShown(), "panel opens with the trainer")
check(panel.train:IsShown() and panel.train:GetText() == "Train all (2)", "Train all button")
ns.Trainer.TrainAll()
check(table.concat(bought, ",") == "2,1", "buys highest index first")
panel:Hide()
check(panel.search:GetText() == "", "search cleared on hide")
Fire("TRAINER_CLOSED"); RunTimers()
done()

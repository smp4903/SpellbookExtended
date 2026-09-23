-- Weapon skills sold by weapon masters, as in Classic Era. Class lists and
-- master locations from WhatsTraining (MIT). Hand-kept.
local _, SBE = ...

local ONE_HANDED_AXES, TWO_HANDED_AXES = 196, 197
local ONE_HANDED_MACES, TWO_HANDED_MACES = 198, 199
local POLEARMS = 200
local ONE_HANDED_SWORDS, TWO_HANDED_SWORDS = 201, 202
local STAVES, BOWS, GUNS, DAGGERS, THROWN, CROSSBOWS, FIST_WEAPONS = 227, 264, 266, 1180, 2567, 5011, 15590

local function classes(...)
    local set = {}
    for _, class in ipairs({ ... }) do
        set[class] = true
    end
    return set
end

SBE.WeaponSkills = {
    order = {
        ONE_HANDED_AXES, TWO_HANDED_AXES, ONE_HANDED_MACES, TWO_HANDED_MACES,
        ONE_HANDED_SWORDS, TWO_HANDED_SWORDS, DAGGERS, FIST_WEAPONS,
        STAVES, POLEARMS, BOWS, GUNS, CROSSBOWS, THROWN,
    },

    -- cost in copper; 10 silver unless noted
    skills = {
        [ONE_HANDED_AXES] = { classes = classes("WARRIOR", "PALADIN", "HUNTER", "SHAMAN") },
        [TWO_HANDED_AXES] = { classes = classes("WARRIOR", "PALADIN", "HUNTER") },
        [ONE_HANDED_MACES] = { classes = classes("WARRIOR", "PALADIN", "ROGUE", "PRIEST", "SHAMAN", "DRUID") },
        [TWO_HANDED_MACES] = { classes = classes("WARRIOR", "PALADIN", "DRUID") },
        [POLEARMS] = { classes = classes("WARRIOR", "PALADIN", "HUNTER", "DRUID"), level = 20, cost = 10000 },
        [ONE_HANDED_SWORDS] = { classes = classes("WARRIOR", "PALADIN", "HUNTER", "ROGUE", "MAGE", "WARLOCK") },
        [TWO_HANDED_SWORDS] = { classes = classes("WARRIOR", "PALADIN", "HUNTER") },
        [STAVES] = { classes = classes("WARRIOR", "HUNTER", "PRIEST", "SHAMAN", "DRUID", "WARLOCK", "MAGE") },
        [BOWS] = { classes = classes("WARRIOR", "HUNTER", "ROGUE") },
        [GUNS] = { classes = classes("WARRIOR", "HUNTER", "ROGUE") },
        [DAGGERS] = { classes = classes("WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "DRUID", "WARLOCK", "MAGE") },
        [THROWN] = { classes = classes("WARRIOR", "HUNTER", "ROGUE") },
        [CROSSBOWS] = { classes = classes("WARRIOR", "HUNTER", "ROGUE") },
        [FIST_WEAPONS] = { classes = classes("WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID") },
    },

    masters = {
        { name = "Buliwyf Stonehand", city = "Ironforge", faction = "Alliance", map = 1455, x = 61.2, y = 89.5,
          teaches = { ONE_HANDED_AXES, TWO_HANDED_AXES, ONE_HANDED_MACES, TWO_HANDED_MACES, GUNS, FIST_WEAPONS } },
        { name = "Bixi Wobblebonk", city = "Ironforge", faction = "Alliance", map = 1455, x = 62.2, y = 89.6,
          teaches = { DAGGERS, THROWN, CROSSBOWS } },
        { name = "Woo Ping", city = "Stormwind", faction = "Alliance", map = 1453, x = 57.1, y = 57.7,
          teaches = { POLEARMS, ONE_HANDED_SWORDS, TWO_HANDED_SWORDS, STAVES, DAGGERS, CROSSBOWS } },
        { name = "Ilyenia Moonfire", city = "Darnassus", faction = "Alliance", map = 1457, x = 57.7, y = 46.0,
          teaches = { STAVES, BOWS, DAGGERS, THROWN, FIST_WEAPONS } },
        { name = "Hanashi", city = "Orgrimmar", faction = "Horde", map = 1454, x = 81.5, y = 19.6,
          teaches = { ONE_HANDED_AXES, TWO_HANDED_AXES, STAVES, BOWS, THROWN } },
        { name = "Sayoc", city = "Orgrimmar", faction = "Horde", map = 1454, x = 81.7, y = 19.6,
          teaches = { ONE_HANDED_AXES, TWO_HANDED_AXES, STAVES, BOWS, DAGGERS, THROWN, FIST_WEAPONS } },
        { name = "Ansekhwa", city = "Thunder Bluff", faction = "Horde", map = 1456, x = 40.0, y = 63.1,
          teaches = { ONE_HANDED_MACES, TWO_HANDED_MACES, STAVES, GUNS } },
        { name = "Archibald", city = "Undercity", faction = "Horde", map = 1458, x = 57.3, y = 32.8,
          teaches = { POLEARMS, ONE_HANDED_SWORDS, TWO_HANDED_SWORDS, DAGGERS, CROSSBOWS } },
    },
}

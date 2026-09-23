-- Dev tools load from the source tree and are absent from a release build.
local devFile = io.open((arg[1] or "..").."/Dev/DevTools.lua")
DEV = devFile ~= nil
if (devFile) then devFile:close() end
local ns = dofile("harness.lua")
Login("HUNTER", 10, { 1978 })
local out = {}
local oldPrint = print
print = function(...) table.insert(out, table.concat({...}, " ")) end
SlashCmdList.SPELLBOOKEXTENDED("help")
print = oldPrint
local text = table.concat(out, "\n")
check(text:find("options") ~= nil, "help lists options")
check((text:find("inspect") ~= nil) == (DEV == true), "inspect only in development builds")
check((SpellbookExtended ~= nil) == (DEV == true), "global only in development builds")
done()

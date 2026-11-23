local addon = {}
assert(loadfile("GuildWave/Core.lua"))("GuildWave", addon)

local saved = addon.LoadSettings({ guild = { limit = 70, left = "UNKNOWN", menu_WAVE = false } })
assert(saved.mode == "guild" and saved.guild.left == "WAVE" and saved.group.left == "DANCE")
assert(saved.anyone.left == "WAVE" and saved.other.left == "WAVE")
assert(saved.guild.limit == addon.MaxRows and saved.group.limit == addon.DefaultLimit)
assert(saved.guild.menu_WAVE == false and saved.group.menu_WAVE == true)
assert(saved.guild.menu_TARGET == true and saved.group.menu_TARGET == true)
assert(addon.LoadSettings({ guild = { menu_TARGET = false } }).guild.menu_TARGET == false)
assert(saved.debugLogging == false and saved.debugReports == nil)
local oldReport = { logout = { rows = 1 } }
assert(addon.LoadSettings({ debugReports = oldReport }).debugReports == nil)
local savedDebug = addon.LoadSettings({ debugLogging = true, debugReports = oldReport })
assert(savedDebug.debugLogging == true and savedDebug.debugReports == oldReport)
addon.SetDebugLogging(savedDebug, false)
assert(savedDebug.debugLogging == false and savedDebug.debugReports == nil)
assert(saved.pinTarget == false)
local migratedPin = addon.LoadSettings({ pinFocus = true })
assert(migratedPin.pinTarget == true and migratedPin.pinFocus == nil)
assert(addon.LoadSettings({ pinFocus = true, pinTarget = false }).pinTarget == false)
local otherSaved = addon.LoadSettings({ mode = "other", otherGuild = "Other Guild" })
assert(otherSaved.mode == "other" and otherSaved.otherGuild == "Other Guild")
local migrated = addon.LoadSettings({ guild = { left = "CHEER" }, group = { left = "SALUTE" } })
assert(migrated.anyone.left == "CHEER" and migrated.other.left == "CHEER")
migrated.anyone.left = "CHICKEN"
migrated.other.left = "WHISTLE"
migrated.guild.left = "WAVE"
addon.LoadSettings(migrated)
assert(migrated.guild.left == "WAVE" and migrated.group.left == "SALUTE")
assert(migrated.anyone.left == "CHICKEN" and migrated.other.left == "WHISTLE")

local secret = {}
local ada = { name = "Ada", surname = "Stone", guid = "A", guild = true, group = true, inRange = true }
local bea = { name = "Bea", guid = "B", guild = true }
local player = { name = "Player", guid = "P", guild = true, group = true, self = true }
local units = {
    nameplate1 = bea,
    nameplate3 = ada,
    nameplate4 = { name = "Other", guid = "O" },
    nameplate5 = { name = "Secret", guid = secret, guild = true },
    nameplate6 = player,
    party1 = ada,
    party2 = { name = "Near", guid = "N", group = true, inRange = secret, canInteract = true },
    party3 = { name = "Far", guid = "F", group = true, inRange = false },
    raid1 = player,
    raid2 = ada,
}
local guilded, grouped, raiding, lockdown = true, true, false, false
local emotes, whispers = {}, {}

function issecretvalue(value) return value == secret end
function IsInGuild() return guilded end
function IsInGroup() return grouped end
function IsInRaid() return raiding end
function GetNumGroupMembers() return 2 end
function GetNumSubgroupMembers() return 3 end
function UnitExists(unit) return units[unit] ~= nil end
function UnitIsPlayer(unit) return not units[unit].npc end
function UnitIsUnit(unit, other) return units[unit].self and other == "player" end
function UnitIsInMyGuild(unit) return units[unit].guild == true end
function UnitIsFriend(_, unit) return not units[unit].hostile end
function GetGuildInfo(unit) return units[unit].guildName end
function strcmputf8i(a, b) return a:lower() == b:lower() and 0 or 1 end
function UnitInParty(unit) return units[unit].group == true end
function UnitInRaid(unit) return units[unit].group and 2 or nil end
function UnitInRange(unit) return units[unit].inRange, true end
function UnitIsInInteractRange(unit) return units[unit].canInteract == true end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitFullName(unit)
    local info = units[unit]
    if not info.fullNameMissing then return info.name, info.surname end
end
function UnitName(unit) return units[unit].name, units[unit].surname end
function UnitClass() return "Mage", "MAGE" end

local function plate(unit)
    return {
        GetUnit = function() return unit end,
        IsForbidden = function() return false end,
    }
end
local plates = {
    plate("nameplate1"),
    [3] = plate("nameplate3"),
    [4] = plate("nameplate4"),
    [5] = plate("nameplate5"),
    [6] = plate("nameplate6"),
    [7] = plate(secret),
    [8] = { IsForbidden = function() return true end },
}
C_NamePlate = {
    GetNamePlates = function() return plates end,
    GetNamePlateForUnit = function(unit)
        for _, frame in pairs(plates) do
            if not frame:IsForbidden() and frame:GetUnit() == unit then
                return frame
            end
        end
    end,
}
C_ChatInfo = {
    InChatMessagingLockdown = function() return lockdown end,
    PerformEmote = function(action, unit)
        emotes[#emotes + 1] = { action = action, unit = unit }
        return false
    end,
}
ChatFrameUtil = {
    SendTell = function(name) whispers[#whispers + 1] = name end,
}

local guild, guildTotal = addon.GetNearby("guild", 1)
assert(guildTotal == 2 and #guild == 1 and guild[1].name == "Ada Stone")
local adaEntry = guild[1]
assert(addon.GetTargetMacro(adaEntry, "guild") == "/targetexact [nocombat] Ada Stone")
ada.name = "Ada Stone"
assert(addon.GetTargetMacro(adaEntry, "guild") == "/targetexact [nocombat] Ada Stone")
ada.name = "Ada"
local beaEntry = addon.GetNearby("guild", 2)[2]
assert(addon.GetTargetMacro(beaEntry, "guild") == "/targetexact [nocombat] Bea")
assert(addon.GetTargetResult(adaEntry) == "no target")
assert(#emotes == 0 and #whispers == 0)
assert(addon.Perform("WAVE", adaEntry, "guild") == nil)
assert(#emotes == 1 and emotes[1].action == "WAVE" and emotes[1].unit == "nameplate3")
assert(addon.Perform("WHISPER", adaEntry, "guild") == nil and whispers[1] == "Ada Stone")

lockdown = true
assert(addon.Perform("WAVE", adaEntry, "guild") == "Emotes are restricted here.")
lockdown = false
plates[3] = nil
assert(addon.Perform("WAVE", adaEntry, "guild") == "That unit is no longer available.")
assert(addon.GetTargetMacro(adaEntry, "guild") == nil)
plates[3] = plate("nameplate3")
units.nameplate3 = bea
assert(addon.Perform("WAVE", adaEntry, "guild") == "That unit is no longer available.")
assert(addon.GetTargetMacro(adaEntry, "guild") == nil)
assert(#emotes == 1)
units.nameplate3 = ada
guilded = false
assert(#addon.GetNearby("guild", 6) == 0)

local group, groupTotal = addon.GetNearby("group", 6)
assert(groupTotal == 2 and #group == 2 and group[1].unit == "party1" and group[2].unit == "party2")
assert(addon.GetTargetMacro(group[1], "group") == "/target [nocombat] party1")
assert(addon.Perform("DANCE", group[2], "group") == nil)
assert(#emotes == 2 and emotes[2].action == "DANCE" and emotes[2].unit == "party2")
units.party2.canInteract = false
assert(addon.Perform("DANCE", group[2], "group") == "That unit is no longer available.")

raiding = true
local raid = addon.GetNearby("group", 6)
assert(#raid == 1 and raid[1].unit == "raid2")
assert(addon.GetTargetMacro(raid[1], "group") == "/target [nocombat] raid2")
grouped = false
assert(#addon.GetNearby("group", 6) == 0)

units.nameplate4.guildName = "Other Guild"
units.nameplate7 = { name = "Hidden Guild", guid = "H", guildName = secret }
units.nameplate9 = { name = "Enemy", guid = "E", hostile = true, guildName = "Other Guild" }
units.nameplate10 = { name = "Merchant", guid = "M", npc = true }
plates[7] = plate("nameplate7")
plates[9] = plate("nameplate9")
plates[10] = plate("nameplate10")

local friendly = addon.GetNearby("anyone", 6)
assert(#friendly == 4 and friendly[4].name == "Other")
local named = addon.GetNearby("other", 6, "other guild")
assert(#named == 1 and named[1].name == "Other")
assert(#addon.GetNearby("other", 6, "other") == 0)
assert(#addon.GetNearby("other", 6, "") == 0)
assert(#addon.GetNearby("guild", 6) == 0)
assert(addon.Perform("WAVE", named[1], "other", "Other Guild") == nil)
assert(#emotes == 3 and emotes[3].unit == "nameplate4")
units.nameplate4.guildName = "New Guild"
assert(addon.Perform("WAVE", named[1], "other", "Other Guild") == "That unit is no longer available.")
assert(#emotes == 3)

units.target = ada
assert(addon.GetTargetResult(adaEntry) == "selected")
local regular, count, target = addon.GetNearby("anyone", 1, nil, false)
assert(count == 4 and #regular == 1 and regular[1].guid == ada.guid and target == nil)
regular, count, target = addon.GetNearby("anyone", 1, nil, true)
assert(count == 3 and #regular == 1 and regular[1].guid == bea.guid)
assert(target.unit == "target" and target.guid == ada.guid and target.name == "Ada Stone" and target.isPlayer)
assert(addon.GetTargetMacro(target, "anyone") == nil)
assert(addon.Perform("WAVE", target, "other", "Unrelated Guild") == nil)
assert(#emotes == 4 and emotes[4].action == "WAVE" and emotes[4].unit == nil)
units.target = { guid = ada.guid, name = ada.name, surname = ada.surname, fullNameMissing = true }
local _, _, fallbackTarget = addon.GetNearby("anyone", 1, nil, true)
assert(fallbackTarget.name == target.name and not fallbackTarget.readOnly)

units.target = units.nameplate10
assert(addon.GetTargetResult(adaEntry) == "different target")
assert(addon.Perform("WAVE", target, "anyone") == "That unit is no longer available.")
regular, count, target = addon.GetNearby("guild", 1, nil, true)
assert(count == 0 and #regular == 0 and target.name == "Merchant" and not target.isPlayer)
assert(addon.Perform("WHISPER", target, "guild") == "Whisper is only available for players.")
assert(addon.Perform("CHICKEN", target, "guild") == nil)
assert(#emotes == 5 and emotes[5].action == "CHICKEN" and emotes[5].unit == nil)

units.target = units.nameplate5
assert(addon.GetTargetResult(adaEntry) == "identity restricted")
local targetDiagnostics = {}
local _, _, restrictedTarget = addon.GetNearby("anyone", 1, nil, true, targetDiagnostics)
assert(restrictedTarget.name == "Secret" and restrictedTarget.readOnly)
assert(targetDiagnostics["selected target"] == "identity restricted")
assert(addon.Perform("WAVE", restrictedTarget, "anyone") == "Target actions are unavailable while the game hides its identity.")
local _, _, unpinned = addon.GetNearby("anyone", 1, nil, false, targetDiagnostics)
assert(unpinned == nil and targetDiagnostics["selected target"] == "identity restricted")
units.target = { name = secret, guid = "Z", npc = true }
local _, _, unnamedTarget = addon.GetNearby("anyone", 1, nil, true)
assert(unnamedTarget.name == "Name unavailable" and unnamedTarget.readOnly)
units.target = nil
assert(addon.Perform("WAVE", target, "guild") == "That unit is no longer available.")
local _, _, clearedTarget = addon.GetNearby("anyone", 1, nil, true, targetDiagnostics)
assert(clearedTarget == nil and targetDiagnostics["selected target"] == "none")
assert(#emotes == 5 and #whispers == 1)

local diagnostics = {}
local listed, matches = addon.GetNearby("anyone", 1, nil, false, diagnostics)
assert(matches == 4 and #listed == 1 and diagnostics.nameplates == 9)
assert(diagnostics["identity restricted"] == 1 and diagnostics["forbidden nameplates"] == 1)
assert(diagnostics["not a player"] == 1 and diagnostics["view filter"] == 1)

local emptyGuild = {}
addon.GetNearby("guild", 6, nil, false, emptyGuild)
assert(emptyGuild["no guild"] == 1 and emptyGuild.nameplates == nil)

print("GuildWave discovery and action checks passed")

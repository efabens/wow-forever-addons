local _, addon = ...

addon.Modes = {
    { key = "guild", label = "Guild", defaultAction = "WAVE" },
    { key = "group", label = "Party/Raid", defaultAction = "DANCE" },
    { key = "anyone", label = "Anyone", defaultAction = "WAVE", shared = "guild" },
    { key = "other", label = "Other Guild", defaultAction = "WAVE", shared = "guild" },
}
addon.Views = {}
for _, mode in ipairs(addon.Modes) do
    addon.Views[mode.key] = mode
end
addon.Actions = {
    { key = "WAVE", label = "Wave" },
    { key = "DANCE", label = "Dance" },
    { key = "HELLO", label = "Say hello" },
    { key = "CHEER", label = "Cheer" },
    { key = "SALUTE", label = "Salute" },
    { key = "THANK", label = "Say thanks" },
    { key = "FART", label = "Fart" },
    { key = "WHISTLE", label = "Whistle" },
    { key = "CHICKEN", label = "Chicken" },
    { key = "WHISPER", label = "Whisper" },
}
addon.ActionLabels = { NONE = "None" }
for _, action in ipairs(addon.Actions) do
    addon.ActionLabels[action.key] = action.label
end
addon.DefaultLimit = 6
addon.MaxRows = 12
addon.FriendlyNameplatesCVar = "nameplateShowFriendlyPlayers"

function addon.SetDebugLogging(db, enabled)
    db.debugLogging = enabled == true
    if not db.debugLogging then
        db.debugReports = nil
    end
end

function addon.LoadSettings(saved)
    local db = type(saved) == "table" and saved or {}
    addon.SetDebugLogging(db, db.debugLogging)
    for _, mode in ipairs(addon.Modes) do
        local profile = type(db[mode.key]) == "table" and db[mode.key] or {}
        db[mode.key] = profile

        if not addon.ActionLabels[profile.left] then
            profile.left = mode.shared and db[mode.shared].left or mode.defaultAction
        end
        if not mode.shared then
            local limit = tonumber(profile.limit)
            if not limit or limit ~= limit then
                limit = addon.DefaultLimit
            end
            profile.limit = math.max(1, math.min(addon.MaxRows, math.floor(limit)))
            for _, action in ipairs(addon.Actions) do
                local key = "menu_" .. action.key
                if type(profile[key]) ~= "boolean" then
                    profile[key] = true
                end
            end
            if type(profile.menu_TARGET) ~= "boolean" then
                profile.menu_TARGET = true
            end
        end
    end
    if not addon.Views[db.mode] then
        db.mode = "guild"
    end
    if type(db.otherGuild) ~= "string" then
        db.otherGuild = ""
    end
    if type(db.pinTarget) ~= "boolean" then
        db.pinTarget = db.pinFocus == true
    end
    db.pinFocus = nil
    return db
end

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function yes(value)
    return readable(value) and value == true
end

local function hasText(value)
    return readable(value) and type(value) == "string" and value ~= ""
end

local nameSeparators = Constants and Constants.CharacterNameSeparatorConsts
local surnameSeparator = nameSeparators and nameSeparators.CHARACTERNAME_SURNAME_SEPARATOR or " "

local function formatName(name, surname)
    if hasText(surname) and not name:find(surnameSeparator, 1, true) then
        return name .. surnameSeparator .. surname
    end
    return name
end

local function unitIdentity(unit)
    local guid = UnitGUID(unit)
    local name, surname = UnitFullName(unit)
    if not readable(guid) or not readable(name) or not readable(surname) then
        return nil, nil, "identity restricted"
    end
    if not hasText(guid) or not hasText(name) then
        return nil, nil, "identity missing"
    end
    return guid, formatName(name, surname)
end

local function makeEntry(unit, guid, name, isPlayer, fromNameplate)
    local _, class
    if isPlayer then
        _, class = UnitClass(unit)
    end
    return {
        unit = unit,
        guid = guid,
        name = name,
        class = hasText(class) and class or nil,
        isPlayer = isPlayer,
        fromNameplate = fromNameplate,
    }
end

local function getSelectedTarget()
    local exists = UnitExists("target")
    if not readable(exists) then
        return nil, "existence restricted"
    end
    if not exists then
        return nil, "none"
    end

    local isPlayer = yes(UnitIsPlayer("target"))
    local name, surname
    if isPlayer then
        name, surname = UnitFullName("target")
    end
    if not hasText(name) or not readable(surname) then
        local unitName, unitSurname = UnitName("target")
        if hasText(unitName) or not hasText(name) then
            name, surname = unitName, unitSurname
        end
    end

    local guid = UnitGUID("target")
    local reason
    if not readable(guid) or not readable(name) or not readable(surname) then
        reason = "identity restricted"
    elseif not hasText(guid) or not hasText(name) then
        reason = "identity unavailable"
    end

    local displayName = hasText(name) and formatName(name, surname) or "Name unavailable"
    local target = makeEntry("target", hasText(guid) and guid or nil, displayName, isPlayer)
    target.readOnly = reason ~= nil
    return target, reason or "ready"
end

local function groupMember(unit, isRaid)
    if isRaid then
        local raidIndex = UnitInRaid(unit)
        return readable(raidIndex) and type(raidIndex) == "number"
    end
    return yes(UnitInParty(unit))
end

local function nearbyGroupUnit(unit)
    local inRange, checked = UnitInRange(unit)
    if yes(checked) and readable(inRange) then
        return inRange
    end
    return yes(UnitIsInInteractRange(unit))
end

local function matchesView(unit, mode, otherGuild)
    if mode == "guild" then
        return yes(UnitIsInMyGuild(unit))
    end
    if not yes(UnitIsFriend("player", unit)) then
        return false
    end
    if mode == "anyone" then
        return true
    end
    if not hasText(otherGuild) then
        return false
    end
    local guild = GetGuildInfo and GetGuildInfo(unit)
    return hasText(guild) and strcmputf8i(guild, otherGuild) == 0
end

local function identify(unit, mode, isRaid, otherGuild)
    local exists = UnitExists(unit)
    if not readable(exists) then
        return nil, nil, "unit flags restricted"
    end
    if not exists then
        return nil, nil, "unit missing"
    end
    local isPlayer = UnitIsPlayer(unit)
    if not readable(isPlayer) then
        return nil, nil, "unit flags restricted"
    end
    if not isPlayer then
        return nil, nil, "not a player"
    end

    local isSelf = UnitIsUnit(unit, "player")
    if not readable(isSelf) then
        return nil, nil, "unit flags restricted"
    end
    if isSelf then
        return nil, nil, "own character"
    end

    if mode == "group" then
        if not groupMember(unit, isRaid) then
            return nil, nil, "group filter"
        end
    elseif not matchesView(unit, mode, otherGuild) then
        return nil, nil, "view filter"
    end

    return unitIdentity(unit)
end

function addon.GetNearby(mode, limit, otherGuild, pinTarget, diagnostics)
    local function record(key)
        if diagnostics then
            diagnostics[key] = (diagnostics[key] or 0) + 1
        end
    end

    local entries, seen = {}, {}
    local target
    if pinTarget or diagnostics then
        local entry, status = getSelectedTarget()
        if diagnostics then
            diagnostics["selected target"] = status
        end
        if pinTarget and entry then
            target = entry
            if entry.guid then
                seen[entry.guid] = true
            end
        end
    end

    local isRaid = mode == "group" and yes(IsInRaid())
    if mode == "guild" and not IsInGuild() then
        record("no guild")
        return entries, 0, target
    elseif mode == "group" and not IsInGroup() then
        record("no group")
        return entries, 0, target
    elseif mode == "other" and not hasText(otherGuild) then
        record("no guild name")
        return entries, 0, target
    end

    local function add(unit, fromNameplate)
        local guid, name, reason = identify(unit, mode, isRaid, otherGuild)
        if not guid then
            record(reason)
            return
        end
        if seen[guid] then
            record("duplicate")
            return
        end
        if not fromNameplate and not nearbyGroupUnit(unit) then
            record("outside group range or unknown")
            return
        end
        seen[guid] = true
        entries[#entries + 1] = makeEntry(unit, guid, name, true, fromNameplate)
    end

    if mode == "group" then
        local prefix = isRaid and "raid" or "party"
        local count = isRaid and GetNumGroupMembers() or GetNumSubgroupMembers()
        for index = 1, count do
            record("group slots")
            add(prefix .. index, false)
        end
    end

    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        record("nameplates")
        if plate:IsForbidden() then
            record("forbidden nameplates")
        else
            local unit = plate:GetUnit()
            if not readable(unit) then
                record("nameplate tokens restricted")
            elseif hasText(unit) and unit:match("^nameplate%d+$") then
                add(unit, true)
            else
                record("nameplate tokens missing")
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.name == b.name then
            return a.guid < b.guid
        end
        return a.name < b.name
    end)
    local total = #entries
    for index = total, limit + 1, -1 do
        entries[index] = nil
    end
    return entries, total, target
end

function addon.IsCurrent(entry, mode, otherGuild)
    if entry.unit == "target" then
        local target = getSelectedTarget()
        return target and not target.readOnly and target.guid == entry.guid and target.name == entry.name
    end
    local guid, name = identify(entry.unit, mode, mode == "group" and yes(IsInRaid()), otherGuild)
    if guid ~= entry.guid or name ~= entry.name then
        return false
    end
    if entry.fromNameplate then
        return C_NamePlate.GetNamePlateForUnit(entry.unit) ~= nil
    end
    return nearbyGroupUnit(entry.unit)
end

function addon.GetTargetMacro(entry, mode, otherGuild)
    if entry.readOnly or entry.unit == "target" or not addon.IsCurrent(entry, mode, otherGuild) then
        return nil
    end
    if not entry.fromNameplate then
        return "/target [nocombat] " .. entry.unit
    end
    if not entry.name:find("[%c%[%];%%]") then
        return "/targetexact [nocombat] " .. entry.name
    end
end

function addon.GetTargetResult(entry)
    local guid = UnitGUID("target")
    if not readable(guid) then
        return "identity restricted"
    end
    if not hasText(guid) then
        return "no target"
    end
    return guid == entry.guid and "selected" or "different target"
end

function addon.Perform(action, entry, mode, otherGuild)
    if action == "NONE" or not addon.ActionLabels[action] then
        return
    end
    if entry.readOnly then
        return "Target actions are unavailable while the game hides its identity."
    end
    if not addon.IsCurrent(entry, mode, otherGuild) then
        return "That unit is no longer available."
    end
    if action == "WHISPER" then
        if not entry.isPlayer then
            return "Whisper is only available for players."
        end
        ChatFrameUtil.SendTell(entry.name)
        return
    end
    if C_ChatInfo.InChatMessagingLockdown() then
        return "Emotes are restricted here."
    end
    -- The game's default recipient is the selected unit, including NPCs.
    local recipient = entry.unit ~= "target" and entry.unit or nil
    -- Forever can return false after sending an emote. Let the client report failures.
    C_ChatInfo.PerformEmote(action, recipient)
end

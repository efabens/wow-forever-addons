local addonName, addon = ...

local db
local categories = {}
local rows = {}
local panelWidth = 260
local listTop = 36
local rowHeight = 29
local refreshQueued = false
local moving = false
local playerMenu, lastTargetAction
local debugSetting, targetHooks, pendingTargetClick, events

local function profileKey(mode)
    return addon.Views[mode].shared or mode
end

local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -58, -245)
panel:SetSize(panelWidth, 100)
panel:SetMovable(true)
panel:SetFrameStrata("MEDIUM")
local backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}
panel:SetBackdrop(backdrop)
panel:SetBackdropColor(0.075, 0.085, 0.105, 0.94)
panel:SetBackdropBorderColor(0.39, 0.33, 0.22, 1)
panel:Hide()

local function anchorPanelTop()
    local left, top = panel:GetLeft(), panel:GetTop()
    if not left or not top then
        return
    end

    local x = math.max(0, math.min(left - UIParent:GetLeft(), UIParent:GetWidth() - panelWidth))
    local minY = math.min(0, listTop + rowHeight + 40 - UIParent:GetHeight())
    local y = math.max(minY, math.min(0, top - UIParent:GetTop()))
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
    db.position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = x, y = y }
end

local function togglePanel()
    db.hidden = panel:IsShown()
    panel:SetShown(not db.hidden)
end

local function closePlayerMenu()
    if playerMenu and playerMenu:IsShown() and not InCombatLockdown() then
        playerMenu:Hide()
    end
end

local function openOptions()
    closePlayerMenu()
    Settings.OpenToCategory(categories[db.mode]:GetID())
end

local header = CreateFrame("Frame", nil, panel)
header:SetPoint("TOPLEFT", 0, -1)
header:SetPoint("TOPRIGHT", 0, -1)
header:SetHeight(32)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")

local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
title:SetPoint("LEFT", 12, 0)

local function createMinimapButton()
    if not Minimap then
        return
    end

    local button = CreateFrame("Button", "GuildWaveMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 20, 20)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("GuildWave")
        GameTooltip:AddLine("Left-click to toggle the list", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnHide", hideTooltip)
    button:SetScript("OnClick", function(self, mouseButton)
        hideTooltip(self)
        if mouseButton == "RightButton" then
            openOptions()
        else
            togglePanel()
        end
    end)
end

local viewport = CreateFrame("ScrollFrame", nil, panel)
viewport:SetPoint("TOPLEFT", 0, -listTop)
viewport:SetPoint("TOPRIGHT", 0, -listTop)
viewport:SetHeight(1)

local list = CreateFrame("Frame", nil, viewport)
list:SetSize(panelWidth, 1)
viewport:SetScrollChild(list)
viewport:SetScript("OnMouseWheel", function(self, delta)
    local offset = self:GetVerticalScroll() - delta * rowHeight
    self:SetVerticalScroll(math.max(0, math.min(offset, list:GetHeight() - self:GetHeight())))
end)

local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 12, -5)
status:SetPoint("TOPRIGHT", viewport, "BOTTOMRIGHT", -12, -5)
status:SetJustifyH("LEFT")
status:SetTextColor(0.73, 0.75, 0.8)

local enableNameplates = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
enableNameplates:SetPoint("TOPLEFT", viewport, "BOTTOMLEFT", 10, -5)
enableNameplates:SetPoint("TOPRIGHT", viewport, "BOTTOMRIGHT", -10, -5)
enableNameplates:SetHeight(22)
enableNameplates:SetText("Enable friendly player nameplates")
enableNameplates:Hide()

local function refresh()
    if not db or not panel:IsShown() or moving then
        return
    end

    local mode = db.mode
    local profile = db[profileKey(mode)]
    title:SetText("GuildWave  ·  " .. addon.Views[mode].label)

    local entries, total, target = addon.GetNearby(mode, profile.limit, db.otherGuild, db.pinTarget)
    local nearbyShown = #entries
    if target then
        table.insert(entries, 1, target)
    end
    local contentHeight = math.max(1, #entries * rowHeight)
    list:SetHeight(contentHeight)
    for index, row in ipairs(rows) do
        local entry = entries[index]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row.name:SetText(entry == target and ("Target: " .. entry.name) or entry.name)
            local color = entry.class and RAID_CLASS_COLORS[entry.class]
            if color then
                row.name:SetTextColor(color.r, color.g, color.b)
                row.icon:SetAtlas("classicon-" .. entry.class:lower())
            else
                row.name:SetTextColor(0.96, 0.88, 0.72)
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            local action = db[mode].left
            if action == "WHISPER" and not entry.isPlayer then
                action = "NONE"
            end
            row.action:SetText(entry.readOnly and "Unavailable" or addon.ActionLabels[action])
        end
    end
    local showEnable = false
    if total == 0 and not target then
        if mode == "group" then
            status:SetText(IsInGroup() and "No party or raid members in range." or "Join a party or raid.")
        elseif mode == "other" and db.otherGuild == "" then
            status:SetText("Set the guild name in Options.")
        elseif mode == "guild" and not IsInGuild() then
            status:SetText("Join a guild to see nearby guildmates.")
        elseif not C_CVar.GetCVarBool(addon.FriendlyNameplatesCVar) then
            showEnable = true
            status:SetText("")
        elseif mode == "anyone" then
            status:SetText("No friendly players on visible nameplates.")
        elseif mode == "other" then
            status:SetText("No players from that guild on visible nameplates.")
        else
            status:SetText("No guildmates on visible nameplates.")
        end
    elseif total > nearbyShown then
        status:SetFormattedText("Showing %d of %d nearby", nearbyShown, total)
    else
        status:SetText("")
    end
    enableNameplates:SetShown(showEnable)
    local footerHeight = showEnable and 30 or (status:GetText() ~= "" and status:GetStringHeight() + 12 or 0)
    local fixedHeight = listTop + 5 + footerHeight
    local availableHeight = (panel:GetTop() or UIParent:GetTop()) - UIParent:GetBottom() - fixedHeight
    local viewportHeight = math.max(1, math.min(contentHeight, availableHeight))
    local maxScroll = contentHeight - viewportHeight
    viewport:SetHeight(viewportHeight)
    viewport:SetVerticalScroll(math.min(viewport:GetVerticalScroll(), maxScroll))
    viewport:EnableMouseWheel(maxScroll > 0)
    panel:SetHeight(fixedHeight + viewportHeight)
end

local function queueRefresh()
    if not db or not panel:IsShown() or refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        refresh()
    end)
end

enableNameplates:SetScript("OnClick", function()
    if InCombatLockdown() then
        UIErrorsFrame:AddMessage("GuildWave: Leave combat to enable friendly player nameplates.", 1, 0.66, 0.25)
        return
    end
    C_CVar.SetCVar(addon.FriendlyNameplatesCVar, "1")
    queueRefresh()
end)

local function selectView(mode)
    closePlayerMenu()
    if db.mode ~= mode then
        viewport:SetVerticalScroll(0)
    end
    db.mode = mode
    refresh()
end

local function showViewMenu(_, button)
    if button ~= "RightButton" or moving then
        return
    end
    closePlayerMenu()
    MenuUtil.CreateContextMenu(panel, function(_, menu)
        local function isSelected(mode)
            return db.mode == mode
        end
        for _, mode in ipairs(addon.Modes) do
            menu:CreateRadio(mode.label, isSelected, selectView, mode.key)
        end
    end)
end

panel:EnableMouse(true)
panel:SetScript("OnMouseUp", showViewMenu)
header:SetScript("OnMouseUp", showViewMenu)
viewport:EnableMouse(true)
viewport:SetScript("OnMouseUp", showViewMenu)

header:SetScript("OnDragStart", function()
    moving = true
    panel:SetClampedToScreen(true)
    panel:StartMoving()
end)

local function stopMoving()
    if not moving then
        return
    end
    panel:StopMovingOrSizing()
    panel:SetClampedToScreen(false)
    moving = false
    anchorPanelTop()
    refresh()
end

header:SetScript("OnDragStop", stopMoving)
panel:SetScript("OnHide", function()
    closePlayerMenu()
    stopMoving()
end)

local function doAction(action, entry, mode)
    if not panel:IsShown() or db.mode ~= mode or (entry.unit == "target" and not db.pinTarget) then
        return
    end
    local message = addon.Perform(action, entry, mode, db.otherGuild)
    if message then
        UIErrorsFrame:AddMessage("GuildWave: " .. message, 1, 0.66, 0.25)
        queueRefresh()
    end
end

local menuRowHeight = 20
local menuTitleHeight = 25

local function traceTargetCalls()
    local macroHook = C_Macro and type(C_Macro.RunMacroText) == "function"
        and pcall(hooksecurefunc, C_Macro, "RunMacroText", function(text)
            local report = pendingTargetClick and pendingTargetClick.report
            if report and (not issecretvalue or not issecretvalue(text)) and text == report.macro then
                report.macroDispatch = "observed"
            end
        end)
    local targetHook = type(TargetUnit) == "function" and pcall(hooksecurefunc, "TargetUnit", function(unit, exact)
        local report = pendingTargetClick and pendingTargetClick.report
        if report and not report.afterClick then
            if issecretvalue and issecretvalue(unit) then
                report.targetCall = "argument restricted"
            else
                report.targetCall = type(unit) == "string" and unit or "no name argument"
            end
            if not issecretvalue or not issecretvalue(exact) then
                report.exactMatch = exact == true
            end
        end
    end)
    return { macro = macroHook, target = targetHook }
end

local function updateDebugLogging()
    addon.SetDebugLogging(db, db.debugLogging)
    local debugEvents = { "PLAYER_LOGOUT", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "UI_ERROR_MESSAGE" }
    if db.debugLogging then
        targetHooks = targetHooks or traceTargetCalls()
        for _, event in ipairs(debugEvents) do
            events:RegisterEvent(event)
        end
    else
        lastTargetAction = nil
        if pendingTargetClick then
            pendingTargetClick.report = nil
        end
        for _, event in ipairs(debugEvents) do
            events:UnregisterEvent(event)
        end
    end
end

local function finishTargetClick(click)
    local afterClick = addon.GetTargetResult(click.entry)
    if click.report then
        click.report.afterClick = afterClick
    elseif afterClick == "selected" then
        pendingTargetClick = nil
        return
    end
    C_Timer.After(0.25, function()
        if pendingTargetClick ~= click then
            return
        end
        pendingTargetClick = nil
        local afterDelay = addon.GetTargetResult(click.entry)
        local report = click.report
        local selected = afterClick == "selected" or (report and report.targetChangedTo == "selected")
        local result = selected and "selected" or afterDelay
        if report then
            report.afterDelay, report.result = afterDelay, result
        end
        if result == "no target" or result == "different target" then
            UIErrorsFrame:AddMessage("GuildWave: The game did not select " .. click.entry.name .. ".", 1, 0.66, 0.25)
        end
    end)
end

local function createMenuButton(menu, index, template)
    local button = CreateFrame("Button", nil, menu, template)
    local y = -menuTitleHeight - (index - 1) * menuRowHeight
    button:SetPoint("TOPLEFT", 4, y)
    button:SetPoint("TOPRIGHT", -4, y)
    button:SetHeight(menuRowHeight)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.79, 0.66, 0.39, 0.19)
    button.label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    button.label:SetPoint("LEFT", 7, 0)
    return button
end

local function createPlayerMenu()
    -- Keep the protected menu separate from the resizable list and Blizzard's frame pools.
    local menu = CreateFrame("Frame", "GuildWavePlayerMenu", UIParent, "BackdropTemplate,SecureHandlerStateTemplate")
    menu:Hide()
    menu:EnableMouse(true)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:SetBackdrop(backdrop)
    menu:SetBackdropColor(0.075, 0.085, 0.105, 0.98)
    menu:SetBackdropBorderColor(0.39, 0.33, 0.22, 1)
    menu:SetAttribute("_onstate-combat", [[
        if newstate == "combat" then
            self:Hide()
        end
    ]])
    RegisterStateDriver(menu, "combat", "[combat] combat; peaceful")
    table.insert(UISpecialFrames, menu:GetName())

    menu.title = menu:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", 11, -8)
    menu.title:SetPoint("TOPRIGHT", -11, -8)
    menu.title:SetJustifyH("LEFT")
    menu.title:SetWordWrap(false)
    menu.actions = {}
    menu:SetScript("OnHide", function(self)
        self.entry, self.mode, self.canTarget = nil, nil, nil
    end)

    local button = createMenuButton(menu, 1, "SecureActionButtonTemplate")
    menu.targetButton = button
    button.label:SetText("Target")
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "macro")
    button:HookScript("PreClick", function(self, mouse, down)
        local entry = menu.entry
        if mouse ~= "LeftButton" or down or not entry then
            return
        end
        pendingTargetClick = nil
        local combat = InCombatLockdown() == true
        local report
        if db.debugLogging then
            report = { source = entry.fromNameplate and "nameplate" or "group", combat = combat }
            lastTargetAction = report
        end
        if combat then
            if report then
                report.result = "combat lockdown"
            end
            return
        end
        local macro
        if panel:IsShown() and db.mode == menu.mode and db[profileKey(menu.mode)].menu_TARGET then
            macro = addon.GetTargetMacro(entry, menu.mode, db.otherGuild)
        end
        self:SetAttribute("macrotext1", macro)
        menu.canTarget = macro ~= nil
        if report then
            report.result = macro and "click received" or "unit unavailable"
            if macro then
                report.macro = macro
                report.beforeClick = addon.GetTargetResult(entry)
                report.macroDispatch = targetHooks.macro and "not observed" or "hook unavailable"
                report.targetCall = targetHooks.target and "not observed" or "hook unavailable"
            end
        end
        if macro then
            pendingTargetClick = { entry = entry, report = report }
        end
    end)
    button:HookScript("PostClick", function(_, mouse, down)
        if mouse ~= "LeftButton" or down or InCombatLockdown() or not menu.entry then
            return
        end
        local canTarget = menu.canTarget
        closePlayerMenu()
        if canTarget == false then
            UIErrorsFrame:AddMessage("GuildWave: That unit is no longer available.", 1, 0.66, 0.25)
            queueRefresh()
        elseif canTarget and pendingTargetClick then
            finishTargetClick(pendingTargetClick)
        end
    end)
    return menu
end

local function showPlayerTargetMenu(entry, mode, actions)
    playerMenu = playerMenu or createPlayerMenu()
    local menu = playerMenu
    local height = menuTitleHeight + (#actions + 1) * menuRowHeight + 4
    menu.title:SetText(entry.name)
    local width = math.max(164, math.min(260, menu.title:GetUnboundedStringWidth() + 22))
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale - UIParent:GetLeft(), y / scale - UIParent:GetBottom()

    menu.entry, menu.mode = entry, mode
    if db.debugLogging and not lastTargetAction then
        lastTargetAction = { source = entry.fromNameplate and "nameplate" or "group", result = "menu opened" }
    end
    menu.targetButton:SetAttribute("macrotext1", addon.GetTargetMacro(entry, mode, db.otherGuild))
    for index, action in ipairs(actions) do
        local button = menu.actions[index] or createMenuButton(menu, index + 1)
        menu.actions[index] = button
        button.label:SetText(action.label)
        button:SetScript("OnClick", function()
            closePlayerMenu()
            action.run()
        end)
        button:Show()
    end
    for index = #actions + 1, #menu.actions do
        menu.actions[index]:Hide()
    end
    menu:SetSize(width, height)
    menu:ClearAllPoints()
    menu:SetPoint(y >= height and "TOPLEFT" or "BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    menu:Show()
end

local function showMenu(row, entry, mode)
    closePlayerMenu()
    local profile = db[profileKey(mode)]
    local showTarget = profile.menu_TARGET and entry.unit ~= "target"
    local actions = {}
    for _, action in ipairs(addon.Actions) do
        local key = action.key
        if profile["menu_" .. key] and (key ~= "WHISPER" or entry.isPlayer) then
            local function run()
                if profile["menu_" .. key] then
                    doAction(key, entry, mode)
                end
            end
            actions[#actions + 1] = { label = action.label, run = run }
        end
    end
    if showTarget and not InCombatLockdown() then
        showPlayerTargetMenu(entry, mode, actions)
        return
    end
    MenuUtil.CreateContextMenu(row, function(_, menu)
        menu:CreateTitle(entry.name)
        if showTarget then
            menu:CreateButton("Target"):SetEnabled(false)
        end
        for _, action in ipairs(actions) do
            menu:CreateButton(action.label, action.run)
        end
        if not showTarget and #actions == 0 then
            menu:CreateButton("Configure actions…", function()
                Settings.OpenToCategory(categories[mode]:GetID())
            end)
        end
    end)
end

for index = 1, addon.MaxRows + 1 do
    local row = CreateFrame("Button", nil, list)
    row:SetPoint("TOPLEFT", 10, -(index - 1) * rowHeight)
    row:SetPoint("TOPRIGHT", -10, -(index - 1) * rowHeight)
    row:SetHeight(rowHeight - 3)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:Hide()

    local background = row:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.13, 0.16, 0.21, 0.98)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.79, 0.66, 0.39, 0.19)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 4, 0)
    row.action = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.action:SetPoint("RIGHT", -8, 0)
    row.action:SetTextColor(0.68, 0.7, 0.75)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.name:SetPoint("RIGHT", row.action, "LEFT", -7, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:SetScript("OnMouseDown", function(self)
        self.pressed = self.entry and { guid = self.entry.guid, mode = db.mode }
    end)
    row:SetScript("OnClick", function(self, button)
        local pressed, entry = self.pressed, self.entry
        self.pressed = nil
        local mode = db.mode
        if not pressed or not entry or pressed.guid ~= entry.guid or pressed.mode ~= mode then
            return
        end
        if button == "RightButton" then
            if not entry.readOnly then
                showMenu(self, entry, mode)
            end
        else
            doAction(db[mode].left, entry, mode)
        end
    end)
    rows[index] = row
end

local function leftClickOptions()
    local choices = Settings.CreateControlTextContainer()
    for _, action in ipairs(addon.Actions) do
        choices:Add(action.key, action.label)
    end
    choices:Add("NONE", addon.ActionLabels.NONE)
    return choices:GetData()
end

local function registerGuildNameOption(layout)
    local popup = "GUILDWAVE_EDIT_GUILD_NAME"

    local function saveGuildName(editBox)
        db.otherGuild = editBox:GetText():match("^%s*(.-)%s*$")
        queueRefresh()
    end

    StaticPopupDialogs[popup] = {
        text = "Enter the full guild name.",
        button1 = "Save",
        button2 = CANCEL,
        hasEditBox = true,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnShow = function(dialog)
            local editBox = dialog:GetEditBox()
            editBox:SetText(db.otherGuild)
            editBox:HighlightText()
            editBox:SetFocus()
        end,
        OnAccept = function(dialog)
            saveGuildName(dialog:GetEditBox())
        end,
        EditBoxOnEnterPressed = function(editBox)
            saveGuildName(editBox)
            editBox:GetParent():Hide()
        end,
    }

    local initializer = CreateSettingsButtonInitializer("Guild name", "Edit", function()
        StaticPopup_Show(popup)
    end, "Enter the full guild name for the Other Guild view.", true)
    layout:AddInitializer(initializer)
end

local function registerSettings()
    local guild = Settings.RegisterVerticalLayoutCategory("GuildWave")
    categories.guild = guild
    for _, mode in ipairs(addon.Modes) do
        if mode.key ~= "guild" then
            local category, layout = Settings.RegisterVerticalLayoutSubcategory(guild, mode.label)
            categories[mode.key] = category
            if mode.key == "other" then
                registerGuildNameOption(layout)
            end
        end
    end
    Settings.RegisterAddOnCategory(guild)

    local targetSetting = Settings.RegisterAddOnSetting(
        guild, "GuildWave_pinTarget", "pinTarget", db, "boolean", "Pin selected target to top", false)
    targetSetting:SetValueChangedCallback(queueRefresh)
    debugSetting = Settings.RegisterAddOnSetting(
        guild, "GuildWave_debugLogging", "debugLogging", db, "boolean", "Save debug reports", false)
    debugSetting:SetValueChangedCallback(updateDebugLogging)
    Settings.CreateCheckbox(guild, debugSetting, "Save targeting and scan diagnostics on reload or logout.")

    local listSettings = {}
    for _, mode in ipairs(addon.Modes) do
        local category = categories[mode.key]
        local profile = db[mode.key]
        local function register(key, label, default)
            local variable = "GuildWave_" .. mode.key .. "_" .. key
            local setting = Settings.RegisterAddOnSetting(category, variable, key, profile, type(default), label, default)
            setting:SetValueChangedCallback(queueRefresh)
            return setting
        end

        Settings.CreateCheckbox(category, targetSetting, "Show your current target above the list in every view.")
        Settings.CreateDropdown(category, register("left", "Left-click action", mode.defaultAction), leftClickOptions)

        if not mode.shared then
            local settings = {
                limit = register("limit", "Maximum names", addon.DefaultLimit),
                menu = { register("menu_TARGET", "Right-click menu: Target", true) },
            }
            for _, action in ipairs(addon.Actions) do
                settings.menu[#settings.menu + 1] = register("menu_" .. action.key, "Right-click menu: " .. action.label, true)
            end
            listSettings[mode.key] = settings
        end

        local settings = listSettings[profileKey(mode.key)]
        local slider = Settings.CreateSliderOptions(1, addon.MaxRows, 1)
        slider:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, settings.limit, slider)

        for _, setting in ipairs(settings.menu) do
            Settings.CreateCheckbox(category, setting)
        end
    end
end

local function captureDiagnostics(slot)
    local mode = db.mode
    local _, build = GetBuildInfo()
    local report = {
        capturedAt = time(),
        build = build,
        view = mode,
        panelShown = panel:IsShown(),
        friendlyNameplates = C_CVar.GetCVarBool(addon.FriendlyNameplatesCVar) == true,
        pinTarget = db.pinTarget,
        limit = db[profileKey(mode)].limit,
        targetAction = lastTargetAction,
        scan = { nameplates = 0 },
    }
    local ok, entries, total, target = pcall(addon.GetNearby, mode, report.limit, db.otherGuild, report.pinTarget, report.scan)
    if ok then
        report.matches = total
        report.rows = #entries
        report.targetRow = target ~= nil
    else
        report.error = tostring(entries)
    end

    if db.debugLogging then
        if type(db.debugReports) ~= "table" then
            db.debugReports = {}
        end
        db.debugReports[slot] = report
    end
    return report
end

local function printDiagnostics(report)
    print(("GuildWave debug | view: %s | friendly player nameplates: %s | pin target: %s"):format(
        addon.Views[report.view].label, report.friendlyNameplates and "on" or "off", report.pinTarget and "on" or "off"))
    if report.targetAction then
        local target = report.targetAction
        print(("GuildWave Target | %s | %s"):format(target.source, target.result))
        if target.macro then
            print(("GuildWave Target | %s | macro %s | TargetUnit %s"):format(
                target.macro, target.macroDispatch, target.targetCall))
        end
    end
    if report.error then
        print("GuildWave scan error: " .. report.error)
        return
    end

    local counts = {}
    for label, count in pairs(report.scan) do
        counts[#counts + 1] = label .. "=" .. count
    end
    table.sort(counts)
    print(("GuildWave scan | %s | nearby matches=%d | rows=%d | target row=%s"):format(
        table.concat(counts, ", "), report.matches, report.rows, report.targetRow and "yes" or "no"))
end

SLASH_GUILDWAVE1 = "/guildwave"
SlashCmdList.GUILDWAVE = function(message)
    local command, argument = message:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "options" and argument == "" then
        openOptions()
    elseif command == "debug" and argument == "" then
        printDiagnostics(captureDiagnostics("manual"))
    elseif command == "debug" and (argument == "on" or argument == "off") then
        debugSetting:SetValue(argument == "on")
        print(db.debugLogging and "GuildWave debug logging is on." or "GuildWave debug logging is off.")
    elseif addon.Views[command] and (command == "other" or argument == "") then
        if command == "other" and argument ~= "" then
            db.otherGuild = argument
        end
        selectView(command)
        db.hidden = false
        panel:Show()
    elseif command == "" then
        togglePanel()
    else
        print("GuildWave: /guildwave [guild | group | anyone | other [guild name] | options | debug [on | off]]")
    end
end

panel:SetScript("OnShow", function()
    anchorPanelTop()
    refresh()
end)

events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("UNIT_NAME_UPDATE")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:RegisterEvent("UNIT_IN_RANGE_UPDATE")
events:RegisterEvent("UNIT_DISTANCE_CHECK_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("GLOBAL_MOUSE_DOWN")
events:RegisterEvent("CVAR_UPDATE")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:SetScript("OnEvent", function(self, event, arg, detail)
    if event == "ADDON_LOADED" then
        if arg == addonName then
            self:UnregisterEvent(event)
            db = addon.LoadSettings(GuildWaveDB)
            GuildWaveDB = db
            local position = db.position
            if type(position) == "table" then
                panel:ClearAllPoints()
                panel:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
            end
            registerSettings()
            updateDebugLogging()
            createMinimapButton()
        end
    elseif event == "PLAYER_LOGOUT" then
        if db.debugLogging then
            captureDiagnostics("logout")
        end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local report = pendingTargetClick and pendingTargetClick.report
        if report and (not issecretvalue or not issecretvalue(arg)) and arg == addonName then
            local readableDetail = (not issecretvalue or not issecretvalue(detail)) and type(detail) == "string"
            report.blockedAction = readableDetail and (event .. " " .. detail) or event
        end
    elseif event == "UI_ERROR_MESSAGE" then
        local report = pendingTargetClick and pendingTargetClick.report
        if report and not report.afterClick and (not issecretvalue or not issecretvalue(detail)) then
            report.clientError = detail
        end
    elseif event == "GLOBAL_MOUSE_DOWN" then
        if playerMenu and playerMenu:IsShown() and not playerMenu:IsMouseOver() then
            closePlayerMenu()
        end
    elseif event == "PLAYER_ENTERING_WORLD" and db then
        closePlayerMenu()
        panel:SetShown(not db.hidden)
        queueRefresh()
    elseif (event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED") and db and not moving then
        closePlayerMenu()
        anchorPanelTop()
        queueRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        closePlayerMenu()
        queueRefresh()
    elseif event == "PLAYER_TARGET_CHANGED" then
        local report = pendingTargetClick and pendingTargetClick.report
        if report and report.targetChangedTo ~= "selected" then
            report.targetChangedTo = addon.GetTargetResult(pendingTargetClick.entry)
        end
        if db and db.pinTarget then
            queueRefresh()
        end
    elseif event == "UNIT_IN_RANGE_UPDATE" or event == "UNIT_DISTANCE_CHECK_UPDATE" then
        if db and db.mode == "group" then
            queueRefresh()
        end
    else
        queueRefresh()
    end
end)

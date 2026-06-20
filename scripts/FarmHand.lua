--
-- FarmHand
--
-- Entry point and bootstrap for the FarmHand employment mod.
--
-- Responsibilities of this file:
--   * expose the mod name / directory so other modules can locate resources,
--   * load the rest of the mod's scripts,
--   * create the central manager once a savegame is loaded,
--   * wire the in-game month rollover through to the manager's tick.
--
-- The actual employment logic lives in scripts/FarmHandManager.lua and the
-- modules it owns. This file should stay thin: load order and lifecycle only.
--

FarmHand = {}

FarmHand.MOD_NAME = g_currentModName
FarmHand.MOD_DIRECTORY = g_currentModDirectory
FarmHand.VERSION = "0.1.0.0"

-- Pull in the rest of the mod. Order matters: settings and the worker model are
-- needed before the manager that uses them.
local sourceFiles = {
    "scripts/FarmHandSettings.lua",
    "scripts/FarmHandWorker.lua",
    "scripts/FarmHandManager.lua",
    "scripts/FarmHandGate.lua",
    "scripts/FarmHandWorkDetector.lua",
    "scripts/gui/FarmHandsDialog.lua",
}

for _, file in ipairs(sourceFiles) do
    source(FarmHand.MOD_DIRECTORY .. file)
end

-- The live manager instance for the loaded savegame, or nil between games.
FarmHand.manager = nil

-- Whether the open-panel input hook has been installed (install-once guard).
FarmHand.inputHookInstalled = false

--- Create the manager when a mission starts loading.
-- Appended to Mission00.load so it runs for every savegame, single- or
-- multiplayer, as part of normal mission setup.
function FarmHand:onMissionLoad(mission)
    FarmHand.manager = FarmHandManager.new(FarmHand.MOD_DIRECTORY, FarmHand.MOD_NAME)
    FarmHand.manager:load()

    -- Install task-permission gates here rather than at script load: the AI job
    -- and field-worker classes are reliably defined by the time a mission loads.
    -- FarmHandGate.install() is guarded so it only wraps the base functions once.
    FarmHandGate.install()

    -- Load the Farm Hands panel GUI (guarded so it only loads once).
    FarmHandsDialog.register()

    -- Bind the open-panel key. Done here (not at script load) because the
    -- player input component class is reliably defined by mission load.
    FarmHand.installInputHook()
end

--- Install the open-panel key hook once. Appends to the player's action-event
--- registration so FARMHAND_OPEN is bound for the local player.
function FarmHand.installInputHook()
    if FarmHand.inputHookInstalled then
        return
    end

    if PlayerInputComponent == nil or PlayerInputComponent.registerActionEvents == nil then
        return
    end

    PlayerInputComponent.registerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerActionEvents, FarmHand.onRegisterPlayerActionEvents)
    FarmHand.inputHookInstalled = true
end

--- Register the open-panel key for the local player.
-- Appended to the player's action-event registration, so the FARMHAND_OPEN
-- action is bound in the on-foot context. (In-vehicle binding can follow.)
function FarmHand.onRegisterPlayerActionEvents(playerInputComponent)
    if playerInputComponent.player == nil or not playerInputComponent.player.isOwner then
        return
    end

    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.FARMHAND_OPEN, FarmHand, FarmHand.onOpenFarmHands, false, true, false, true)
    g_inputBinding:endActionEventsModification()

    if eventId ~= nil then
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_FARMHAND_OPEN"))
        g_inputBinding:setActionEventTextVisibility(eventId, true)
    end
end

--- Open-panel action callback.
function FarmHand.onOpenFarmHands(self, actionName, inputValue)
    FarmHandsDialog.show()
end

--- Tear the manager down when the mission ends so a fresh game starts clean.
function FarmHand:onMissionDelete()
    if FarmHand.manager ~= nil then
        FarmHand.manager:delete()
        FarmHand.manager = nil
    end
end

--- Forward the in-game month rollover to the manager.
-- Everything the mod does on a schedule (course progress, experience tally,
-- wages, retention, candidate refresh) is driven from here.
function FarmHand:onPeriodChanged()
    if FarmHand.manager ~= nil then
        FarmHand.manager:onMonthChanged()
    end
end

local function init()
    -- Lifecycle hooks into the base mission.
    Mission00.load = Utils.appendedFunction(Mission00.load, function(mission, ...)
        FarmHand:onMissionLoad(mission)
    end)

    Mission00.delete = Utils.prependedFunction(Mission00.delete, function(mission, ...)
        FarmHand:onMissionDelete()
    end)

    -- The month rollover is the mod's heartbeat.
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, FarmHand.onPeriodChanged, FarmHand)

    print(string.format("FarmHand %s loaded.", FarmHand.VERSION))
end

init()

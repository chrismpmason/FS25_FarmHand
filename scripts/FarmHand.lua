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
    "scripts/FarmHandWear.lua",
    "scripts/gui/FarmHandsDialog.lua",
}

for _, file in ipairs(sourceFiles) do
    source(FarmHand.MOD_DIRECTORY .. file)
end

-- The live manager instance for the loaded savegame, or nil between games.
FarmHand.manager = nil

-- Whether the open-panel input hook has been installed (install-once guard).
FarmHand.inputHookInstalled = false

-- Whether the AIJob.start hook (forces the active hand's driver) is installed.
FarmHand.aiJobHookInstalled = false

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

    -- Force the active hand's driver/name at AI job start (guaranteed AIJob here).
    FarmHand.installAIJobHook()
end

--- Append to base AIJob.start so the active hand's registered helper is used
--- (its character + name). AIJobFieldWork:start calls super (this) BEFORE
--- createAgent, so reassigning helperIndex here lands before the cab driver is
--- built. nil active index = leave the base random pick untouched. Install-once.
function FarmHand.onAIJobStart(self, farmId, ...)
    local manager = FarmHand.manager
    local idx = manager ~= nil and manager.getActiveHelperIndex and manager:getActiveHelperIndex() or nil
    if idx ~= nil then
        self.helperIndex = idx
    end
end

function FarmHand.installAIJobHook()
    if FarmHand.aiJobHookInstalled then
        return
    end
    if AIJob == nil or AIJob.start == nil then
        return
    end

    AIJob.start = Utils.appendedFunction(AIJob.start, FarmHand.onAIJobStart)
    FarmHand.aiJobHookInstalled = true
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

    -- TEMP: hire-first-candidate debug trigger, removed when the K panel wires
    -- hiring. A NEW binding only registers after a full game restart.
    local _, hireEventId = g_inputBinding:registerActionEvent(InputAction.FARMHAND_HIRE, FarmHand, FarmHand.onHireFirstCandidate, false, true, false, true)
    g_inputBinding:endActionEventsModification()

    if eventId ~= nil then
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("input_FARMHAND_OPEN"))
        g_inputBinding:setActionEventTextVisibility(eventId, true)
    end
    if hireEventId ~= nil then
        g_inputBinding:setActionEventText(hireEventId, g_i18n:getText("input_FARMHAND_HIRE"))
        g_inputBinding:setActionEventTextVisibility(hireEventId, true)
    end
end

--- Open-panel action callback.
function FarmHand.onOpenFarmHands(self, actionName, inputValue)
    FarmHandsDialog.show()
end

--- TEMP debug trigger: hire the first candidate in the pool. Removed once the
--- K panel wires hiring through the GUI.
function FarmHand.onHireFirstCandidate(self, actionName, inputValue)
    local manager = FarmHand.manager
    if manager == nil then
        return
    end
    -- TEMP: refill an empty pool so repeated presses keep hiring without waiting
    -- for a month tick. The real GUI slice refills only on the monthly schedule.
    if manager.candidates[1] == nil then
        print("FarmHand [DEBUG]: pool empty -> regenerating candidates") -- TEMP DEBUG
        manager:generateCandidates()
    end
    local candidate = manager.candidates[1]
    if candidate ~= nil then
        manager:hireCandidate(candidate.id)
    end
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

--- Persist the roster when the game saves. Appended to the savegame writer;
--- `missionInfo.savegameDirectory` is the current savegame folder.
function FarmHand.onSaveToXMLFile(missionInfo, ...)
    if FarmHand.manager == nil or missionInfo == nil or missionInfo.savegameDirectory == nil then
        return
    end

    local path = missionInfo.savegameDirectory .. "/FS25_FarmHand.xml"
    FarmHand.manager:saveToXMLFile(path)
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

    -- Persist the roster into the savegame whenever the game saves.
    if FSCareerMissionInfo ~= nil then
        FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, FarmHand.onSaveToXMLFile)
    end

    -- Force the active hand's driver at AI job start. Try at mod load (AIJob is
    -- a job class, not a baked vehicle spec); onMissionLoad re-attempts as a
    -- guaranteed fallback, and the install-once guard prevents double-wrapping.
    FarmHand.installAIJobHook()

    print(string.format("FarmHand %s loaded.", FarmHand.VERSION))
end

init()

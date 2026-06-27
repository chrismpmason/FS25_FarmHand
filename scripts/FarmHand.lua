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
    "scripts/FarmHandSpeed.lua",
    "scripts/FarmHandOperation.lua",
    -- FarmHandsDialog (the legacy K dialog) is RETIRED: the shell replaced it in
    -- build 2. Its files are kept one version as a fallback but are no longer
    -- sourced/registered. Re-add this line + register()/a key to revive it.
    "scripts/gui/FarmHandShellScreen.lua",
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

    -- Load the Farm Hands panel GUI: the full-screen shell, opened on K.
    -- (The legacy FarmHandsDialog is retired and no longer registered.)
    FarmHandShellScreen.register()

    -- Bind the open-panel key. Done here (not at script load) because the
    -- player input component class is reliably defined by mission load.
    FarmHand.installInputHook()

    -- Force the active hand's driver/name at AI job start (guaranteed AIJob here).
    FarmHand.installAIJobHook()

    -- Suppress the vanilla per-job helper fee while a FarmHand does the work, so
    -- the monthly salary is the only labour cost. Hooks this mission's addMoney.
    FarmHand.installAddMoneyHook()

    -- Detect ADS at mission start (reliable by runtime, unlike mod load order: ADS
    -- finalizes vehicle types before FarmHand even loads). The AI-job hooks use
    -- this to decide between the ADS per-instance override and the vanilla path.
    FarmHandWear.adsPresent = g_modIsLoaded ~= nil and g_modIsLoaded["FS25_AdvancedDamageSystem"] == true

    FarmHand.warnOnConflictingHelperMods()
end

--- Warn (once at mission start) if another hired-worker manager is loaded.
--- FarmHand drives helpers directly (AI job hooks, the active hand, wage), so a
--- second helper manager can stop a job starting or hand it to the wrong system.
--- Substring-matched on "HiredHelper" so it catches the mod regardless of its
--- exact registered name.
function FarmHand.warnOnConflictingHelperMods()
    if g_modIsLoaded == nil then
        return
    end
    for modName, loaded in pairs(g_modIsLoaded) do
        if loaded == true and type(modName) == "string" and modName:find("HiredHelper", 1, true) then
            Logging.warning("FarmHand: '%s' is also loaded. Both manage hired workers; run only one helper manager or a hand may not start its job.", modName)
            return
        end
    end
end

--- Append to base AIJob.start. Two jobs in one:
--- (1) Driver identity: force the active hand's registered helper (character +
---     name). AIJobFieldWork:start calls super (this) BEFORE createAgent, so
---     reassigning helperIndex here lands before the cab driver is built.
--- (2) Cost suppression: mark this job FarmHand-run and bump the running-job
---     counter, so its per-job helper fee is suppressed in addMoney.
--- Only counts when a hand is active (Option-A: the active hand does the work).
function FarmHand.onAIJobStart(self, farmId, ...)
    local manager = FarmHand.manager
    if manager == nil then
        return
    end

    local hand = manager:getActiveHand()
    if hand == nil then
        return -- no active hand: a vanilla helper job, leave it untouched
    end

    local idx = manager.getActiveHelperIndex and manager:getActiveHelperIndex() or nil
    if idx ~= nil then
        self.helperIndex = idx
    end

    -- Per-job flag keeps the counter balanced across the stop/delete end hooks
    -- (only the first to fire decrements). Guard against a double start().
    if not self.farmHandCounted then
        self.farmHandCounted = true
        manager.farmHandJobCount = (manager.farmHandJobCount or 0) + 1

        local rootVehicle = FarmHand.getJobRootVehicle(self)

        -- SLICE B1 (LOG-ONLY): classify the operation to de-risk detection before
        -- any boost is built on it. No cert check, no boost applied here.
        local opClass, opDetail = FarmHandOperation.classify(rootVehicle)
        print(string.format("FarmHand [DEBUG]: operation=%s (%s) hand=%s", -- TEMP DEBUG
            tostring(opClass), tostring(opDetail), tostring(hand.name)))

        -- ADS path: scale this hand's vehicles' wear with a per-instance override
        -- (removed at job end). Instance-field shadowing is independent of the
        -- load/finalize order that defeats a class-level wrap.
        if FarmHandWear.adsPresent then
            self._farmHandAdsVehicles =
                FarmHandWear.applyADSOverride(rootVehicle, hand, manager.settings)
        end

        -- Proficiency -> speed: lower-tier hands work the field slower (scales the
        -- root's getSpeedLimit on working passes only; removed at job end).
        self._farmHandSpeedVehicles = FarmHandSpeed.applyOverride(rootVehicle, hand, manager)
    end
end

--- Appended to AIJob.stop and AIJob.delete: decrement the running-job counter
--- once per job, gated by the per-job flag so stop-then-delete only counts down
--- once. Clamped at 0 so a missed/extra end can never drive it negative.
function FarmHand.onAIJobEnd(self, ...)
    if not self.farmHandCounted then
        return
    end
    self.farmHandCounted = false

    local manager = FarmHand.manager
    if manager ~= nil then
        manager.farmHandJobCount = math.max(0, (manager.farmHandJobCount or 0) - 1)
    end

    -- Restore the ADS per-instance overrides installed for this job's vehicles.
    if self._farmHandAdsVehicles ~= nil then
        FarmHandWear.removeADSOverride(self._farmHandAdsVehicles)
        self._farmHandAdsVehicles = nil
    end

    -- Restore the getSpeedLimit overrides installed for this job's vehicles.
    if self._farmHandSpeedVehicles ~= nil then
        FarmHandSpeed.removeOverride(self._farmHandSpeedVehicles)
        self._farmHandSpeedVehicles = nil
    end
end

--- Best-effort extraction of an AI job's root vehicle (the combination to scale
--- for ADS). Tries the job's accessors defensively; returns nil if none yields a
--- vehicle, in which case the ADS override is simply skipped for that job.
function FarmHand.getJobRootVehicle(job)
    if job == nil then
        return nil
    end
    if job.getVehicle ~= nil then
        local v = job:getVehicle()
        if v ~= nil then
            return v
        end
    end
    if job.vehicleParameter ~= nil and job.vehicleParameter.getVehicle ~= nil then
        return job.vehicleParameter:getVehicle()
    end
    return nil
end

function FarmHand.installAIJobHook()
    if FarmHand.aiJobHookInstalled then
        return
    end
    if AIJob == nil or AIJob.start == nil then
        return
    end

    AIJob.start = Utils.appendedFunction(AIJob.start, FarmHand.onAIJobStart)

    -- End signals: hook both stop and delete (guarded). The per-job flag means
    -- whichever fires first does the single decrement.
    if AIJob.stop ~= nil then
        AIJob.stop = Utils.appendedFunction(AIJob.stop, FarmHand.onAIJobEnd)
    end
    if AIJob.delete ~= nil then
        AIJob.delete = Utils.appendedFunction(AIJob.delete, FarmHand.onAIJobEnd)
    end

    FarmHand.aiJobHookInstalled = true
end

--- Overwrites THIS mission's addMoney to suppress the vanilla per-job helper fee
--- (MoneyType.AI) while a FarmHand job is running on the player's farm, so the
--- monthly salary is the only labour cost. Every other charge passes through.
function FarmHand.addMoneyOverride(self, superFunc, amount, farmId, moneyType, addChange, ...)
    local manager = FarmHand.manager
    local isAI = MoneyType ~= nil and MoneyType.AI ~= nil and moneyType == MoneyType.AI

    if isAI and manager ~= nil and not manager.moneyPassthrough
        and manager.settings ~= nil and manager.settings:getSalaryReplacesHelperCost() then

        local playerFarmId = g_currentMission ~= nil and g_currentMission:getFarmId() or nil
        local isPlayerFarm = playerFarmId ~= nil and farmId == playerFarmId
        local jobRunning = (manager.farmHandJobCount or 0) > 0

        if isPlayerFarm and jobRunning then
            return -- skip the charge entirely: the salary already covers this labour
        end
    end

    return superFunc(self, amount, farmId, moneyType, addChange, ...)
end

--- Install the addMoney suppression hook on the current mission instance. Done
--- per mission load (a new g_currentMission each game has the base method);
--- guarded by a per-instance marker so a re-entry never double-wraps.
function FarmHand.installAddMoneyHook()
    if g_currentMission == nil or g_currentMission.addMoney == nil then
        return
    end
    if g_currentMission.farmHandAddMoneyHooked then
        return
    end

    g_currentMission.addMoney = Utils.overwrittenFunction(g_currentMission.addMoney, FarmHand.addMoneyOverride)
    g_currentMission.farmHandAddMoneyHooked = true
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

--- Open-panel action callback (K). Opens the full-screen shell.
function FarmHand.onOpenFarmHands(self, actionName, inputValue)
    FarmHandShellScreen.show()
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

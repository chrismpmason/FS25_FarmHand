--
-- FarmHandCourseplay
--
-- Parallel attach point that gives Courseplay FIELD-WORK jobs the same active-hand
-- attribution the basegame AI path gets: the per-operation speed/wear boost and
-- per-tick experience (hectares + worked-this-month), credited to the active hand.
--
-- Why a separate attach point rather than reusing FarmHand's basegame hooks:
-- Courseplay does not route field work through either surface FarmHand already
-- hooks. A CP field job
--   * starts via CpAIJob:start, which re-implements AIJob:start and never calls
--     it, so FarmHand.onAIJobStart (appended to AIJob.start) never fires; and
--   * drives from CpAIWorker:onUpdate / its own drive strategy, not
--     AIFieldWorker:updateAIFieldWorker, so the basegame per-tick accrual hook
--     never fires either.
-- (Coexistence is still clean today: CpAIJob:stop DOES call AIJob.stop, so
-- FarmHand.onAIJobEnd fires but early-returns because the job was never counted.)
--
-- So we attach to Courseplay's OWN field-work lifecycle and reuse FarmHand's
-- existing boost/accrual logic unchanged. All three hooks sit on ONE class,
-- CpAITaskFieldWork -- the field-work-specific task -- so there is no need to
-- filter out CP's transport modes (silo loader, combine unloader, bale finder),
-- and no risk of double-counting basegame jobs:
--   * CpAITaskFieldWork:start  -> install the boost (carrier = the task)
--   * CpAITaskFieldWork:update -> accrue this tick (ticked every frame while the
--                                 field-work task is active)
--   * CpAITaskFieldWork:stop   -> tear the boost down
--
-- These are CpObject methods (late-bound through the class table at call time),
-- so appending them at mission load is seen by every task instance created
-- afterwards -- unlike a baked vehicle-specialization function, which must be
-- wrapped at script-load scope.
--
-- Attribution follows the Option-A model (the active hand), the same as the
-- basegame path; per-vehicle worker assignment arrives with multi-hand.
--
-- v1 speed split on Courseplay (confirmed in-game, Novice cultivate). CP resets
-- its per-loop speed ceiling to vehicle:getSpeedLimit(true) each update, then
-- min's in every constraint (its own field-speed setting, turns, proximity). Our
-- FarmHandSpeed override wraps that getSpeedLimit, so:
--   * the proficiency PENALTY lands -- a low-tier hand's scaled-down ceiling
--     drops below CP's field speed and binds (Novice 0.6x seen driving ~9 km/h
--     on a ~15 km/h cultivator); and
--   * experience (hectares) and the wear scaling land fully, identical to the
--     basegame path (shared accrue / installJobBoost).
-- The cert speed BOOST, by contrast, usually does NOT show on CP: raising the
-- ceiling above CP's own field-speed setting leaves that setting as the binding
-- min. This is accepted for v1 -- the boost defers to CP's speed setting rather
-- than forcing past it; the wear cert bonus still applies.
--

FarmHandCourseplay = {}

FarmHandCourseplay.installed = false

-- Bring-up debug logging: start/tick/end lines carrying the numbers behind the
-- behaviour (hand, operation, speed factor, gate state, live speed, hectares).
-- On for the CP verification run; flip off once the path is confirmed in-game.
FarmHandCourseplay.DEBUG = true
FarmHandCourseplay.DEBUG_TICK_MS = 1000

--- The field-work task's combination root vehicle, or nil. On CpAITaskFieldWork
--- the vehicle is self.vehicle; FarmHandOperation.classify / the overrides / the
--- accrual all accept it exactly as they accept a basegame root vehicle.
local function taskVehicle(task)
    return task ~= nil and task.vehicle or nil
end

--- Appended to CpAITaskFieldWork:start. Install the active hand's operation boost
--- on the task's vehicle, stashing teardown state on the TASK (its :stop is the
--- matching end signal). No-op when no hand is active -- e.g. a CP job the player
--- started outside FarmHand, or another farm's -- so those run exactly as vanilla.
local function onFieldWorkStart(self, ...)
    local manager = FarmHand.manager
    if manager == nil then
        return
    end

    local hand = manager:getActiveHand()
    if hand == nil then
        return
    end

    local vehicle = taskVehicle(self)
    if vehicle == nil then
        return
    end

    FarmHand.installJobBoost(self, vehicle, hand)

    -- Debug: report the boost this job installed. classify()/boostFor() are cheap
    -- and re-run once here purely for the log; installJobBoost above did the real
    -- install. Seeds the per-tick throttle + the per-job hectare baseline too.
    if FarmHandCourseplay.DEBUG then
        local opClass, opDetail = FarmHandOperation.classify(vehicle)
        local speedBoost, wearBoost = FarmHandOperation.boostFor(hand, opClass)
        local tierFactor = manager:getTierSpeedFactor(hand)
        local speedFactor = math.min(tierFactor * speedBoost, FarmHandSpeed.MAX_FACTOR)
        self._farmHandCpHand = hand -- captured so STOP reports the same hand even if the active hand clears on unload
        self._farmHandCpStartHa = hand.hectaresWorked or 0
        self._farmHandCpTickAccum = 0
        print(string.format(
            "FarmHand[CP] START: hand='%s' tier=%s op=%s (%s) tierFactor=%.2f speedBoost=%.2f -> speedFactor=%.2f wearBoost=%.2f",
            tostring(hand.name), tostring(manager:getTier(hand)), tostring(opClass), tostring(opDetail),
            tierFactor, speedBoost, speedFactor, wearBoost))
    end
end

--- Appended to CpAITaskFieldWork:update. Runs every frame while the field-work
--- task is active. Accrue this tick to the active hand, guarded by CP's own public
--- getIsCpFieldWorkActive() predicate (true only for a CpAIJobFieldWork job) so a
--- lingering/edge tick outside real field work credits nothing.
local function onFieldWorkUpdate(self, dt, ...)
    local vehicle = taskVehicle(self)
    if vehicle == nil then
        return
    end
    if vehicle.getIsCpFieldWorkActive == nil or not vehicle:getIsCpFieldWorkActive() then
        return
    end

    FarmHandWorkDetector.accrue(vehicle, dt)

    -- Debug: throttled (~1s) so the run gets the numbers behind the visual.
    -- fieldWorkActive is the key diagnostic: it's the basegame getIsFieldWorkActive
    -- our speed override gates on -- if it's true, the scaledSpeedLimit below is
    -- already scaled by the hand's factor, so a Novice shows a lower ceiling.
    if FarmHandCourseplay.DEBUG then
        self._farmHandCpTickAccum = (self._farmHandCpTickAccum or 0) + dt
        if self._farmHandCpTickAccum >= FarmHandCourseplay.DEBUG_TICK_MS then
            self._farmHandCpTickAccum = 0
            local manager = FarmHand.manager
            local hand = manager ~= nil and manager:getActiveHand() or nil
            local speedKmh = (vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed()) or 0
            local scaledLimit = (vehicle.getSpeedLimit ~= nil and vehicle:getSpeedLimit(true)) or -1
            local fieldWorkActive = vehicle.getIsFieldWorkActive ~= nil and vehicle:getIsFieldWorkActive() or false
            print(string.format(
                "FarmHand[CP] tick: cpFieldWork=true fieldWorkActive=%s speed=%.1fkm/h scaledSpeedLimit=%.1fkm/h ha=%.3f",
                tostring(fieldWorkActive), speedKmh, scaledLimit,
                hand ~= nil and (hand.hectaresWorked or 0) or 0))
        end
    end
end

--- Appended to CpAITaskFieldWork:stop. Mirror onFieldWorkStart: tear down the
--- overrides stashed on the task. Safe when nothing was installed.
local function onFieldWorkStop(self, ...)
    FarmHand.teardownJobBoost(self)

    -- Debug: confirm teardown ran and report the hectares this job credited to the
    -- hand captured at START (not the current active hand, which is nil during a
    -- mission unload and would otherwise show a bogus negative delta).
    if FarmHandCourseplay.DEBUG then
        local hand = self._farmHandCpHand
        if hand ~= nil then
            local nowHa = hand.hectaresWorked or 0
            local jobHa = nowHa - (self._farmHandCpStartHa or nowHa)
            print(string.format(
                "FarmHand[CP] STOP: teardown done; '%s' credited %.3f ha this job (hand total %.3f)",
                tostring(hand.name), jobHa, nowHa))
        else
            print("FarmHand[CP] STOP: teardown done (no hand captured at start).")
        end
        self._farmHandCpHand = nil
        self._farmHandCpStartHa = nil
        self._farmHandCpTickAccum = nil
    end
end

--- Install the Courseplay attach points. Idempotent, and a guarded no-op (with a
--- log) when Courseplay isn't loaded or its expected class/methods aren't present,
--- so a missing or restructured CP can never break FarmHand -- it simply doesn't
--- attribute CP jobs. Called from FarmHand:onMissionLoad.
function FarmHandCourseplay.install()
    if FarmHandCourseplay.installed then
        return
    end

    local cpLoaded = g_modIsLoaded ~= nil and g_modIsLoaded["FS25_Courseplay"] == true
    if not cpLoaded then
        return -- Courseplay not present: nothing to attach to, no message needed.
    end

    -- FS25 isolates each mod's Lua globals: another mod's classes are NOT visible
    -- by bare name, only through the global table named after that mod's folder.
    -- (Courseplay reaches AutoDrive the same way: `FS25_AutoDrive.AutoDrive`.) So a
    -- bare `CpAITaskFieldWork` resolves to nil from here; go through FS25_Courseplay.
    -- The table it holds is the live class Courseplay instantiates from, so
    -- appending its methods is seen by every field-work task (CpObject late-binds).
    local cpEnv = FS25_Courseplay
    if cpEnv == nil then
        print("FarmHand: Courseplay loaded but its mod-env table FS25_Courseplay is not reachable - CP field-work attribution NOT installed.")
        return
    end
    local task = cpEnv.CpAITaskFieldWork
    if task == nil then
        print("FarmHand: FS25_Courseplay reachable but FS25_Courseplay.CpAITaskFieldWork is nil - CP field-work attribution NOT installed.")
        return
    end
    if task.start == nil or task.update == nil or task.stop == nil then
        print("FarmHand: CpAITaskFieldWork found but start/update/stop missing - CP field-work attribution NOT installed.")
        return
    end

    task.start  = Utils.appendedFunction(task.start,  onFieldWorkStart)
    task.update = Utils.appendedFunction(task.update, onFieldWorkUpdate)
    task.stop   = Utils.appendedFunction(task.stop,   onFieldWorkStop)

    FarmHandCourseplay.installed = true
    print("FarmHand: Courseplay field-work attribution installed on FS25_Courseplay.CpAITaskFieldWork (start/update/stop).")
end

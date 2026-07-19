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

FarmHandCourseplay = {}

FarmHandCourseplay.installed = false

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
end

--- Appended to CpAITaskFieldWork:stop. Mirror onFieldWorkStart: tear down the
--- overrides stashed on the task. Safe when nothing was installed.
local function onFieldWorkStop(self, ...)
    FarmHand.teardownJobBoost(self)
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

    if CpAITaskFieldWork == nil
        or CpAITaskFieldWork.start == nil
        or CpAITaskFieldWork.update == nil
        or CpAITaskFieldWork.stop == nil then
        print("FarmHand: Courseplay present but CpAITaskFieldWork start/update/stop not found - CP field-work attribution NOT installed.")
        return
    end

    CpAITaskFieldWork.start  = Utils.appendedFunction(CpAITaskFieldWork.start,  onFieldWorkStart)
    CpAITaskFieldWork.update = Utils.appendedFunction(CpAITaskFieldWork.update, onFieldWorkUpdate)
    CpAITaskFieldWork.stop   = Utils.appendedFunction(CpAITaskFieldWork.stop,   onFieldWorkStop)

    FarmHandCourseplay.installed = true
    print("FarmHand: Courseplay field-work attribution installed on CpAITaskFieldWork (start/update/stop).")
end

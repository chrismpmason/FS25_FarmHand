--
-- FarmHandAutoDrive
--
-- Gives AutoDrive transport tasks (carting, haulage) the active hand's IDENTITY and
-- PRESENCE -- nothing else. When a hand is active and drives an AD task, that hand is
-- shown as the driver (cab character + HUD name) and shows as working in the Overview.
--
-- Scope is deliberately narrow: identity + working-state ONLY. Carting does not build a
-- hand, so this file touches NO progression -- no experience/hectares, no
-- workedThisMonth, no operation boost, no wear, no farmHandJobCount, no fees. It only
-- reassigns the driver and marks the shared working-state set. (Contrast
-- FarmHandCourseplay, which also accrues experience and installs the speed/wear boost --
-- CP field work builds a hand; AD transport does not.)
--
-- Why hook onStartAutoDrive rather than fight AD's own driver pick:
-- AD does not use the base-game createAgent/AIJob path. It stores a helper index on its
-- state module and, at start, paints the cab character from that helper via the
-- base-game setRandomVehicleCharacter. On start (AutoDrive:startAutoDrive) it assigns a
-- RANDOM helper unless one is already set -- and that guard is
--     self.ad.currentHelper == nil OR getCurrentHelperIndex() <= 0
-- so setting only the index does NOT skip the random pick (currentHelper is still nil).
-- Rather than reach into AD's private currentHelper field or depend on that exact branch,
-- we let AD pick its random helper, then OVERRIDE the visible identity in onStartAutoDrive
-- (the very event where AD paints the driver): set the helper index, set the HUD name, and
-- repaint the cab character with the hand's registered helper. Decoupled from AD internals
-- -- it relies only on the state-module setters and the base-game character method.
--
-- Reached through the FS25_AutoDrive env table (FS25 isolates each mod's globals; another
-- mod's classes are only visible through the global named after its folder -- the same
-- lesson as FS25_Courseplay). onStartAutoDrive / onStopAutoDrive are registered vehicle
-- spec events on that AutoDrive class table.
--
-- No active hand -> we do nothing: AD's own random helper stands, exactly as without this
-- mod. A guarded no-op (with a log) when AutoDrive isn't loaded or its class/methods moved.
--

FarmHandAutoDrive = {}

FarmHandAutoDrive.installed = false

-- Bring-up debug logging: start/stop lines carrying the hand and the index we set. Off
-- now identity is confirmed in-game; flip true to re-diagnose. The one-time "installed"
-- info log in install() stays on regardless.
FarmHandAutoDrive.DEBUG = false

--- Resolve the active hand and its registered helper index together. Returns
--- (hand, idx), or (nil, nil) if there is no active hand OR no registered helper index --
--- in which case the caller defers entirely to AutoDrive's own (random) helper.
local function resolveActiveDriver(manager)
    if manager == nil then
        return nil, nil
    end
    local hand = manager:getActiveHand()
    if hand == nil then
        return nil, nil
    end
    local idx = manager.getActiveHelperIndex and manager:getActiveHelperIndex() or nil
    if idx == nil then
        return nil, nil
    end
    return hand, idx
end

--- Appended to AutoDrive:onStartAutoDrive (self = the AD vehicle). If a hand is active
--- and has a registered helper, make that hand the driver: set AD's stored helper index,
--- set the HUD driver name, and repaint the cab character from the hand's helper (guarded
--- on the base-game method existing -- not every vehicle type has it). Then mark the
--- vehicle working in the shared set the Overview reads. No hand / no index -> no-op, so
--- AD's own random helper is left exactly as-is.
local function onAutoDriveStart(self, ...)
    local manager = FarmHand.manager
    local hand, idx = resolveActiveDriver(manager)
    if hand == nil then
        if FarmHandAutoDrive.DEBUG then
            print("FarmHand[AD] START: no active hand/registered index -- deferring to AutoDrive's own helper.")
        end
        return
    end

    local stateModule = self.ad ~= nil and self.ad.stateModule or nil
    if stateModule == nil then
        return -- AD state not present on this vehicle; nothing to reassign.
    end

    -- Identity: index (AD's own bookkeeping) + HUD name + cab character.
    if stateModule.setCurrentHelperIndex ~= nil then
        stateModule:setCurrentHelperIndex(idx)
    end
    if stateModule.setName ~= nil then
        stateModule:setName(hand.name)
    end

    local characterSet = false
    local helper = g_helperManager ~= nil and g_helperManager:getHelperByIndex(idx) or nil
    if helper ~= nil and self.setRandomVehicleCharacter ~= nil then
        self:setRandomVehicleCharacter(helper)
        characterSet = true
    end

    -- Presence: mark this vehicle working (keyed by the vehicle -- AD has no separate job
    -- object). Same shared set the vanilla + Courseplay paths use, so the Overview shows
    -- an AD-driving hand as working. Deliberately nothing else -- no boost/experience.
    manager:markCarrierWorking(self, self, hand)

    if FarmHandAutoDrive.DEBUG then
        print(string.format(
            "FarmHand[AD] START: hand='%s' helperIndex=%s name-set=%s character-set=%s -> marked working",
            tostring(hand.name), tostring(idx), tostring(stateModule.setName ~= nil), tostring(characterSet)))
    end
end

--- Appended to AutoDrive:onStopAutoDrive(isPassingToCP, isStartingAIVE). Clear this
--- vehicle from the working set. Safe when it was never marked (no hand was active at
--- start) -- markCarrierIdle is a no-op then.
local function onAutoDriveStop(self, ...)
    local manager = FarmHand.manager
    if manager == nil then
        return
    end

    if FarmHandAutoDrive.DEBUG then
        local entry = manager.workingCarriers ~= nil and manager.workingCarriers[self] or nil
        local who = entry ~= nil and entry.hand ~= nil and entry.hand.name or nil
        if who ~= nil then
            print(string.format("FarmHand[AD] STOP: '%s' marked idle.", tostring(who)))
        end
    end

    manager:markCarrierIdle(self)
end

--- Install the AutoDrive identity/presence hooks. Idempotent, and a guarded no-op (with a
--- log) when AutoDrive isn't loaded or its expected class/methods aren't present, so a
--- missing or restructured AD can never break FarmHand -- it simply doesn't reassign AD
--- drivers. Called from FarmHand:onMissionLoad.
function FarmHandAutoDrive.install()
    if FarmHandAutoDrive.installed then
        return
    end

    local adLoaded = g_modIsLoaded ~= nil and g_modIsLoaded["FS25_AutoDrive"] == true
    if not adLoaded then
        return -- AutoDrive not present: nothing to attach to, no message needed.
    end

    -- FS25 isolates each mod's Lua globals: reach AD's class through the global named after
    -- its folder (FS25_AutoDrive), not a bare AutoDrive (which resolves to nil from here).
    local adEnv = FS25_AutoDrive
    if adEnv == nil then
        print("FarmHand: AutoDrive loaded but its mod-env table FS25_AutoDrive is not reachable - AD identity NOT installed.")
        return
    end
    local ad = adEnv.AutoDrive
    if ad == nil then
        print("FarmHand: FS25_AutoDrive reachable but FS25_AutoDrive.AutoDrive is nil - AD identity NOT installed.")
        return
    end
    if ad.onStartAutoDrive == nil or ad.onStopAutoDrive == nil then
        print("FarmHand: FS25_AutoDrive.AutoDrive found but onStartAutoDrive/onStopAutoDrive missing - AD identity NOT installed.")
        return
    end

    ad.onStartAutoDrive = Utils.appendedFunction(ad.onStartAutoDrive, onAutoDriveStart)
    ad.onStopAutoDrive  = Utils.appendedFunction(ad.onStopAutoDrive,  onAutoDriveStop)

    FarmHandAutoDrive.installed = true
    print("FarmHand: AutoDrive identity+presence installed on FS25_AutoDrive.AutoDrive (onStartAutoDrive/onStopAutoDrive).")
end

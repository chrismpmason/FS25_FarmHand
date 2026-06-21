--
-- FarmHandWear
--
-- Scales equipment wear by the active hand's experience while a basegame AI
-- helper does field work: a green hand is hard on machinery (~1.75x), a veteran
-- easy on it (~0.9x). Curve comes from FarmHandWorker:getWearMultiplier.
--
-- Applied from the work-detection context (FarmHandWorkDetector's
-- updateAIFieldWorker hook), which already fires every tick during AI field
-- work with the active hand known. Each tick we rescale the wear DELTA the game
-- added since last tick: newWear = lastWear + (currentWear - lastWear) * mult.
-- Because the node API lets us SET wear to a lower value, this scales base wear
-- both up (green, >1) and down (veteran, <1). Overall damage gets the same.
--
-- Only AI-helper field work is scaled; the player driving is untouched (the
-- caller gates on getIsFieldWorkActive).
--

FarmHandWear = {}

-- Per-tick wear deltas are tiny. A larger jump means our cached baseline went
-- stale (e.g. the helper stopped and the player drove between ticks), so we
-- rebaseline rather than rescale it, to avoid a one-tick wear spike.
local MAX_TICK_DELTA = 0.01

--- Rescale one wearable node's wear delta this tick.
--- @return the effective (post-rescale) delta applied, for debug.
local function rescaleNodeWear(cv, nodeData, mult)
    if cv.getNodeWearAmount == nil or cv.setNodeWearAmount == nil then
        return 0
    end

    local current = cv:getNodeWearAmount(nodeData)
    local last = nodeData.farmHandLastWear
    nodeData.farmHandLastWear = current -- default: rebaseline to current

    if last == nil then
        return 0
    end

    local delta = current - last
    if delta <= 0 or delta > MAX_TICK_DELTA then
        return 0
    end

    local adjusted = math.max(0, math.min(1, last + delta * mult))
    cv:setNodeWearAmount(nodeData, adjusted, true)
    nodeData.farmHandLastWear = adjusted
    return adjusted - last
end

--- Rescale the vehicle's overall damage delta this tick.
--- @return the effective (post-rescale) delta applied, for debug.
local function rescaleDamage(cv, mult)
    local spec = cv.spec_wearable
    if spec == nil or cv.setDamageAmount == nil then
        return 0
    end

    local current = spec.damage or 0
    local last = cv.farmHandLastDamage
    cv.farmHandLastDamage = current

    if last == nil then
        return 0
    end

    local delta = current - last
    if delta <= 0 or delta > MAX_TICK_DELTA then
        return 0
    end

    local adjusted = math.max(0, math.min(1, last + delta * mult))
    cv:setDamageAmount(adjusted, true)
    cv.farmHandLastDamage = adjusted
    return adjusted - last
end

--- Apply the active hand's wear multiplier to the whole combination this tick.
function FarmHandWear.applyToCombination(rootVehicle, hand, settings)
    local mult = hand:getWearMultiplier(settings:getWearFloor(), settings:getWearGreen(), settings:getWearK())

    local children = rootVehicle.childVehicles or { rootVehicle }
    for _, cv in pairs(children) do
        local spec = cv.spec_wearable
        if spec ~= nil then
            if spec.wearableNodes ~= nil then
                for _, nodeData in ipairs(spec.wearableNodes) do
                    rescaleNodeWear(cv, nodeData, mult)
                end
            end
            rescaleDamage(cv, mult)
        end
    end
end

-- =========================================================================
-- Advanced Damage System (ADS) integration. When ADS is installed it OWNS the
-- damage model, so we must not write vanilla wear (one-owner per datum). Instead
-- we scale the INPUT to ADS's own per-system accrual:
--   updateSystemConditionAndStress(self, dt, systemName, wearRate, debugFactors)
-- derives condition loss AND stress from wearRate, so multiplying wearRate by the
-- same experience curve moves condition, stress and breakdown risk together. We
-- write NONE of ADS's fields and copy NO ADS code.
--
-- A class-level wrap can't work: vehicle types finalize (capturing ADS's function
-- via registerFunction) BEFORE FarmHand's source even loads. So instead we shadow
-- the type function with a PER-INSTANCE override on the hand's vehicles at job
-- start, and remove it at job end (driven from FarmHand's job-start/end hooks).
-- Instance-field timing is independent of load/finalize order.
-- =========================================================================

-- ADS present? Resolved at MISSION START via g_modIsLoaded (reliable by runtime),
-- set from FarmHand:onMissionLoad. Defaults false until then.
FarmHandWear.adsPresent = false

--- Install a per-instance override of updateSystemConditionAndStress on every
--- vehicle in the combination that has the ADS spec, scaling wearRate by the
--- active hand's experience factor (captured now, for this job). Returns the list
--- of wrapped vehicles for removeADSOverride to restore at job end. Scales only
--- the input passed to ADS's own function; touches none of ADS's fields.
function FarmHandWear.applyADSOverride(rootVehicle, hand, settings)
    if rootVehicle == nil then
        return nil
    end

    local factor = hand:getWearMultiplier(settings:getWearFloor(), settings:getWearGreen(), settings:getWearK())

    local wrapped = {}
    local seen = {}
    local function tryWrap(cv)
        if cv == nil or seen[cv] then
            return
        end
        seen[cv] = true

        -- Skip vehicles without the ADS spec (the function resolves to nil), and
        -- any already wrapped (guard on the saved original).
        if cv.updateSystemConditionAndStress == nil or cv._farmHandOrigUSCAS ~= nil then
            return
        end

        local orig = cv.updateSystemConditionAndStress -- the ADS type fn (via metatable)
        cv._farmHandOrigUSCAS = orig
        cv.updateSystemConditionAndStress = function(v, dt, systemName, wearRate, debugFactors, ...)
            local scaled = wearRate
            if scaled ~= nil then
                scaled = scaled * factor
            end
            return orig(v, dt, systemName, scaled, debugFactors, ...)
        end
        wrapped[#wrapped + 1] = cv
    end

    for _, cv in pairs(rootVehicle.childVehicles or { rootVehicle }) do
        tryWrap(cv)
    end
    tryWrap(rootVehicle) -- in case the root is not in childVehicles

    return wrapped
end

--- Remove the per-instance overrides installed by applyADSOverride. Clearing the
--- instance field lets the vehicle's type function show through the metatable
--- again, so ADS runs unscaled once the hand's job ends.
function FarmHandWear.removeADSOverride(wrapped)
    if wrapped == nil then
        return
    end
    for _, cv in ipairs(wrapped) do
        if cv._farmHandOrigUSCAS ~= nil then
            cv.updateSystemConditionAndStress = nil
            cv._farmHandOrigUSCAS = nil
        end
    end
end

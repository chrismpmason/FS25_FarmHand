--
-- FarmHandGate
--
-- Task-permission gate. Blocks an AI field-work job from starting when the
-- active hand is not qualified for the task it would perform.
--
-- One rule for now: applying herbicide requires the PESTICIDES certificate.
-- Per the design decision we gate the *activity*, not the machine — a sprayer
-- whose tank holds herbicide. Fertilising, liquid fertilising and liming (same
-- specialization, different fill/spray types) are deliberately left open.
--
-- Herbicide-ness is derived from the sprayer's current FILL TYPE (tank
-- contents), not its active spray type: getActiveSprayType() is only set once
-- the job is working the field, so it is nil at validate time. The fill type is
-- known as soon as the tank is filled, and maps to a spray-type descriptor via
-- g_sprayTypeManager:getSprayTypeByFillTypeIndex (descriptor.isHerbicide).
--
-- Hook: AIJobFieldWork:validate(farmId) returns (isValid, errorMessage); the
-- UI shows errorMessage when a job is refused.
--

FarmHandGate = {}

-- Guard so install() only wraps the base function once, even though it is
-- driven from mission load (which can fire more than once per session).
FarmHandGate.installed = false

--- Inspect one sprayer implement's tank and decide whether it holds herbicide.
-- @return fillType, sprayTypeIndex, isHerbicide  (nils/false if undeterminable)
local function sprayerHerbicideInfo(sprayer)
    -- Prefer the sprayer's designated tank fill unit; fall back to scanning all.
    local indices = {}
    if sprayer.getSprayerFillUnitIndex ~= nil then
        local idx = sprayer:getSprayerFillUnitIndex()
        if idx ~= nil then
            indices[#indices + 1] = idx
        end
    end
    if #indices == 0 and sprayer.getFillUnitCount ~= nil then
        for i = 1, sprayer:getFillUnitCount() do
            indices[#indices + 1] = i
        end
    end

    for _, idx in ipairs(indices) do
        local fillType = nil
        if sprayer.getFillUnitLastValidFillType ~= nil then
            fillType = sprayer:getFillUnitLastValidFillType(idx)
        end
        -- Empty tank: fall back to what the unit can carry (e.g. a herbicide-only
        -- sprayer reports herbicide even before it is filled).
        if (fillType == nil or (FillType ~= nil and fillType == FillType.UNKNOWN))
            and sprayer.getFillUnitFirstSupportedFillType ~= nil then
            fillType = sprayer:getFillUnitFirstSupportedFillType(idx)
        end

        if fillType ~= nil and not (FillType ~= nil and fillType == FillType.UNKNOWN) then
            local desc = nil
            if g_sprayTypeManager ~= nil and g_sprayTypeManager.getSprayTypeByFillTypeIndex ~= nil then
                desc = g_sprayTypeManager:getSprayTypeByFillTypeIndex(fillType)
            end
            if desc ~= nil then
                local isHerbicide = desc.isHerbicide == true
                    or (SprayType ~= nil and desc.index == SprayType.HERBICIDE)
                return fillType, desc.index, isHerbicide
            end
        end
    end

    return nil, nil, false
end

--- Walk the combination (vehicle + attached implements, recursively) and report
--- the sprayer/herbicide situation.
-- @return hasSprayer, isHerbicide, fillType, sprayTypeIndex
local function inspectCombination(vehicle)
    local hasSprayer, isHerbicide, fillType, sprayIndex = false, false, nil, nil

    local function visit(v)
        if v == nil then
            return
        end

        if v.spec_sprayer ~= nil then
            hasSprayer = true
            local ft, idx, herb = sprayerHerbicideInfo(v)
            if fillType == nil then fillType = ft end
            if sprayIndex == nil then sprayIndex = idx end
            if herb then isHerbicide = true end
        end

        if v.getAttachedImplements ~= nil then
            for _, implement in ipairs(v:getAttachedImplements()) do
                if implement.object ~= nil then
                    visit(implement.object)
                end
            end
        end
    end

    visit(vehicle)
    return hasSprayer, isHerbicide, fillType, sprayIndex
end

-- Exposed for reuse: FarmHandOperation classifies a job's operation from the same
-- combination walk (the sprayer family, split by fill type). Returns
-- hasSprayer, isHerbicide, fillType, sprayIndex.
FarmHandGate.inspectCombination = inspectCombination

--- True if the combination is set to apply herbicide.
local function combinationAppliesHerbicide(vehicle)
    local _, isHerbicide = inspectCombination(vehicle)
    return isHerbicide
end

--- The gate check, applied only after the base validation has passed.
-- @return isValid, errorMessage
local function checkPesticidesGate(vehicle)
    if not combinationAppliesHerbicide(vehicle) then
        return true, nil
    end

    local manager = FarmHand.manager
    local hand = manager ~= nil and manager:getActiveHand() or nil

    if hand == nil then
        return false, "No farm hand is selected to handle pesticides."
    end

    if not hand:hasCertificate(FarmHandCertificate.PESTICIDES) then
        return false, string.format("%s isn't certified to handle pesticides.", hand.name)
    end

    return true, nil
end

--- Install the overwrite into AIJobFieldWork:validate. Idempotent.
function FarmHandGate.install()
    if FarmHandGate.installed then
        return
    end
    FarmHandGate.installed = true

    if AIJobFieldWork == nil or AIJobFieldWork.validate == nil then
        print("FarmHand: AIJobFieldWork:validate not found - pesticides gate NOT installed.")
        return
    end

    AIJobFieldWork.validate = Utils.overwrittenFunction(AIJobFieldWork.validate, function(self, superFunc, ...)
        -- Respect the base game's own validation result first.
        local isValid, errorMessage = superFunc(self, ...)
        if not isValid then
            return isValid, errorMessage
        end

        local vehicle = self.vehicleParameter ~= nil and self.vehicleParameter:getVehicle() or nil
        return checkPesticidesGate(vehicle)
    end)

    print("FarmHand: pesticides gate installed on AIJobFieldWork:validate.")
end

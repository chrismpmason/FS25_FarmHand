--
-- FarmHandSpeed
--
-- Proficiency -> AI work speed. While the active hand works a field, a Novice
-- drives the working passes slower than a Master, by scaling the value the AI
-- motor clamps to: vehicle:getSpeedLimit.
--
-- Reuses the ADS-integration per-instance override pattern EXACTLY, including the
-- restore-to-CAPTURED-ORIGINAL on removal (never nil — a nil-restore leaves the
-- method genuinely missing). Installed at job start and removed at job end from
-- FarmHand's AI-job hooks, the same place the ADS wear override lives.
--
-- Two deliberate choices:
--   * Wrap only the ROOT vehicle. Its getSpeedLimit already aggregates attached
--     tools' working limits (min), so wrapping implements too would re-scale an
--     already-scaled child value (factor^2). The root is what the motor reads.
--   * Scale only while the implement is engaged (getIsFieldWorkActive). During
--     headland turns getSpeedLimit returns the transport limit; scaling that would
--     slow the turns. We slow the WORK, not the turns.
--

FarmHandSpeed = {}

--- Install a per-instance getSpeedLimit override on the root vehicle, scaling the
--- returned working limit by the hand's tier speed factor (captured now, for this
--- job). Returns the wrapped-vehicle list for removeOverride, or nil if nothing
--- was wrapped (no method / already wrapped / no vehicle).
function FarmHandSpeed.applyOverride(rootVehicle, hand, manager)
    if rootVehicle == nil or manager == nil then
        return nil
    end
    if rootVehicle.getSpeedLimit == nil or rootVehicle._farmHandOrigGSL ~= nil then
        return nil
    end

    local factor = manager:getTierSpeedFactor(hand)

    local orig = rootVehicle.getSpeedLimit
    rootVehicle._farmHandOrigGSL = orig
    rootVehicle.getSpeedLimit = function(v, onlyIfWorking, ...)
        local limit, doCheck = orig(v, onlyIfWorking, ...)

        -- Only scale the working passes: during headland turns / transit the
        -- implement is raised (getIsFieldWorkActive false) and we leave the limit
        -- alone so turns run at full speed.
        if type(limit) == "number" and v.getIsFieldWorkActive ~= nil and v:getIsFieldWorkActive() then
            limit = limit * factor
        end

        return limit, doCheck
    end

    return { rootVehicle }
end

--- Remove the per-instance overrides installed by applyOverride. Restore the
--- CAPTURED ORIGINAL (not nil) so the vehicle's getSpeedLimit resolves cleanly
--- again — the lesson from the ADS cleanup crash.
function FarmHandSpeed.removeOverride(wrapped)
    if wrapped == nil then
        return
    end
    for _, v in ipairs(wrapped) do
        if v._farmHandOrigGSL ~= nil then
            v.getSpeedLimit = v._farmHandOrigGSL
            v._farmHandOrigGSL = nil
        end
    end
end

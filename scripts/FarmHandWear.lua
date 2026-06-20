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

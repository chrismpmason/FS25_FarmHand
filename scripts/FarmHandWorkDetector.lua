--
-- FarmHandWorkDetector
--
-- Attributes basegame AI-helper field work to the active hand. This is the
-- foundation primitive the wear curve, specialisation gains and the deferred
-- "course month only counts if he worked" condition all read from.
--
-- Detection: hook AIFieldWorker.updateAIFieldWorker; while the helper is
-- actively field-working we (a) mark the active hand worked this month and
-- (b) accumulate hectares.
--
-- Hectares are estimated as swept area = work width x distance moved this tick.
-- This is a per-tick DELTA (so it never double-counts a cumulative total) and
-- uses getLastSpeed(), which is reliable. It is an approximation, not the exact
-- pixel-processed area — good enough as the progression primitive; can be
-- refined to true processed area later if that accessor surfaces.
--
-- Attribution follows the Option-A model: all helper work is credited to the
-- current active hand (the same one the pesticides gate checks). Per-vehicle
-- worker assignment comes later.
--

FarmHandWorkDetector = {}

FarmHandWorkDetector.installed = false

-- Nominal work width (m) used when the real width can't be derived.
local DEFAULT_WORK_WIDTH = 6

--- Derive the real working width by spanning the outermost work-area marker
--- nodes (across every implement in the combination) on the root's lateral
--- axis. Returns width(m), or nil if it can't be determined. Fully guarded:
--- any missing field/node falls through to nil so the caller uses the default.
local function deriveWorkAreaWidth(rootVehicle, children)
    local refNode = rootVehicle.rootNode
    if refNode == nil or refNode == 0 then
        return nil
    end

    local minX, maxX
    local function consider(node)
        if node ~= nil and node ~= 0 and entityExists(node) then
            local wx, wy, wz = getWorldTranslation(node)
            local lx = worldToLocal(refNode, wx, wy, wz) -- lateral offset
            if minX == nil or lx < minX then minX = lx end
            if maxX == nil or lx > maxX then maxX = lx end
        end
    end

    for _, cv in pairs(children) do
        local spec = cv.spec_workArea
        if spec ~= nil and spec.workAreas ~= nil then
            for _, wa in ipairs(spec.workAreas) do
                consider(wa.start)
                consider(wa.width)
                consider(wa.height)
            end
        end
    end

    if minX ~= nil and maxX ~= nil then
        local width = maxX - minX
        if width > 0.1 then
            return width
        end
    end
    return nil
end

--- Work width for the combination, with a nominal fallback. Cached per vehicle
--- and recomputed only when the implement count changes. Returns width, source.
local function getWorkWidth(vehicle)
    local children = vehicle.childVehicles
    if children == nil then
        children = { vehicle }
    end

    local n = #children
    if vehicle.farmHandWidthCacheN ~= n then
        local spec = vehicle.spec_aiFieldWorker
        local direct = spec ~= nil and (spec.workWidth or spec.lastValidWorkWidth or spec.aiWorkWidth) or nil
        if type(direct) == "number" and direct > 0 then
            vehicle.farmHandWidthCache, vehicle.farmHandWidthCacheSrc = direct, "aiFieldWorker"
        else
            local derived = deriveWorkAreaWidth(vehicle, children)
            if derived ~= nil then
                vehicle.farmHandWidthCache, vehicle.farmHandWidthCacheSrc = derived, "workArea"
            else
                vehicle.farmHandWidthCache, vehicle.farmHandWidthCacheSrc = DEFAULT_WORK_WIDTH, "default"
            end
        end
        vehicle.farmHandWidthCacheN = n
    end

    return vehicle.farmHandWidthCache, vehicle.farmHandWidthCacheSrc
end

--- Appended to AIFieldWorker.updateAIFieldWorker. Runs per frame for every
--- AI-capable vehicle; we only act when it is actively field-working.
local function onUpdateAIFieldWorker(self, dt)
    if self.getIsFieldWorkActive == nil or not self:getIsFieldWorkActive() then
        return
    end

    local manager = FarmHand.manager
    local hand = manager ~= nil and manager:getActiveHand() or nil
    if hand == nil then
        return
    end

    -- Swept area this tick = width x distance. getLastSpeed() is km/h.
    local speedKmh = (self.getLastSpeed ~= nil and self:getLastSpeed()) or 0
    local distM = (speedKmh / 3.6) * (dt / 1000)
    local width = getWorkWidth(self)
    local deltaHa = (width * distM) / 10000

    -- Attribution: accumulate the delta and flag the month worked.
    hand.hectaresWorked = hand.hectaresWorked + deltaHa
    hand.workedThisMonth = true

    -- Experience-to-wear. When ADS owns the damage model, the per-job instance
    -- override (installed at job start) does the scaling, so write no vanilla
    -- wear here. Otherwise rescale vanilla wear directly.
    if not FarmHandWear.adsPresent then
        FarmHandWear.applyToCombination(self, hand, manager.settings)
    end
end

--- Install the hook. Idempotent.
--- MUST run at file/mod-load scope, NOT at mission load: vehicle-specialization
--- functions are baked into each vehicle type at type registration (before the
--- mission loads), so a later overwrite of AIFieldWorker.updateAIFieldWorker is
--- never seen by the registered types. AIBaler hooks this the same way.
function FarmHandWorkDetector.install()
    if FarmHandWorkDetector.installed then
        return
    end

    if AIFieldWorker == nil or AIFieldWorker.updateAIFieldWorker == nil then
        print("FarmHand: AIFieldWorker.updateAIFieldWorker not found - work detection NOT installed.")
        return
    end

    AIFieldWorker.updateAIFieldWorker = Utils.appendedFunction(AIFieldWorker.updateAIFieldWorker, onUpdateAIFieldWorker)
    FarmHandWorkDetector.installed = true
    print("FarmHand: work detection installed on AIFieldWorker.updateAIFieldWorker.")
end

-- Install now, at mod-load scope (see the timing note on install() above).
FarmHandWorkDetector.install()

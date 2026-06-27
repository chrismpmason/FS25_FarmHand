--
-- FarmHandOperation
--
-- Classifies the field operation an AI job's machine combination is performing,
-- so College course boosts (Slice B) can be applied per-operation.
--
-- SLICE B1 is LOG-ONLY: this module just classifies and the caller logs the
-- result. No cert checks, no boost, no gating yet — purely to verify detection
-- accuracy in-game before anything is built on it.
--
-- Detection mirrors FarmHandGate's proven spec-inspection: walk the combination
-- and key off each implement's specialization. The sprayer family is split by
-- fill type via the gate's own herbicide logic (reused, not duplicated).
--

FarmHandOperation = {}

-- Operation specs, checked in priority order AFTER the sprayer split. Sprayer is
-- handled first (it needs the fill-type split). Names are confirmed against FS25
-- mod code where possible; any miss surfaces in the OTHER branch's spec dump.
local SEED_SPECS    = { "spec_sowingMachine", "spec_plantingMachine", "spec_planter" }
local HARVEST_SPECS = { "spec_combine", "spec_cutter" }
local FORAGE_SPECS  = { "spec_mower", "spec_tedder", "spec_windrower", "spec_baler",
                        "spec_forageWagon", "spec_baleWrapper" }

--- Flatten the combination to a list of vehicles. Prefers childVehicles (the flat
--- combination list, set once attached); falls back to the gate's recursive
--- attached-implement walk if it isn't populated.
local function combinationVehicles(root)
    if root == nil then
        return {}
    end
    if root.childVehicles ~= nil and #root.childVehicles > 0 then
        return root.childVehicles
    end

    local out = {}
    local function visit(v)
        if v == nil then
            return
        end
        out[#out + 1] = v
        if v.getAttachedImplements ~= nil then
            for _, impl in ipairs(v:getAttachedImplements()) do
                if impl.object ~= nil then
                    visit(impl.object)
                end
            end
        end
    end
    visit(root)
    return out
end

--- First spec from `specNames` present on any vehicle in the combination, or nil.
local function firstSpecMatch(vehicles, specNames)
    for _, v in ipairs(vehicles) do
        for _, s in ipairs(specNames) do
            if v[s] ~= nil then
                return s
            end
        end
    end
    return nil
end

--- Every distinct `spec_` key across the combination (sorted) — the diagnostic
--- the OTHER branch logs so unclassified operations reveal their real specs.
local function allSpecKeys(vehicles)
    local seen = {}
    for _, v in ipairs(vehicles) do
        for k in pairs(v) do
            if type(k) == "string" and k:sub(1, 5) == "spec_" then
                seen[k] = true
            end
        end
    end
    local list = {}
    for k in pairs(seen) do
        list[#list + 1] = k
    end
    table.sort(list)
    return list
end

--- Classify the operation the combination performs.
--- @return class  one of SPRAY / FERTILISER-SLURRY / SEED / HARVEST / FORAGE / OTHER
--- @return detail short string for logging (matched spec(s), fill type, or spec dump)
function FarmHandOperation.classify(rootVehicle)
    local vehicles = combinationVehicles(rootVehicle)

    -- Sprayer family first, split by fill type using the gate's reused inspection.
    local hasSprayer, isHerbicide, fillType
    if FarmHandGate ~= nil and FarmHandGate.inspectCombination ~= nil then
        hasSprayer, isHerbicide, fillType = FarmHandGate.inspectCombination(rootVehicle)
    end
    if hasSprayer then
        if isHerbicide then
            return "SPRAY", string.format("spec_sprayer fillType=%s herbicide", tostring(fillType))
        end
        return "FERTILISER-SLURRY", string.format("spec_sprayer fillType=%s", tostring(fillType))
    end

    local seed = firstSpecMatch(vehicles, SEED_SPECS)
    if seed ~= nil then
        return "SEED", seed
    end

    local harvest = firstSpecMatch(vehicles, HARVEST_SPECS)
    if harvest ~= nil then
        return "HARVEST", harvest
    end

    local forage = firstSpecMatch(vehicles, FORAGE_SPECS)
    if forage ~= nil then
        return "FORAGE", forage
    end

    return "OTHER", "specs=[" .. table.concat(allSpecKeys(vehicles), ", ") .. "]"
end

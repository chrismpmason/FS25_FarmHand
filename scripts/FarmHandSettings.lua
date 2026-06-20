--
-- FarmHandSettings
--
-- Player-configurable multipliers. All default to 1.0 and are intended to be
-- surfaced in the in-game settings UI. The course-duration multiplier is the
-- only one required for the first feature slice; the rest are reserved so the
-- UI and save format can be built once.
--

FarmHandSettings = {}

local FarmHandSettings_mt = Class(FarmHandSettings)

function FarmHandSettings.new()
    local self = setmetatable({}, FarmHandSettings_mt)

    -- Scales how many in-game months a course takes. 1.0 = design default.
    self.courseDurationMultiplier = 1.0

    -- Reserved for later slices (kept here so the save format is stable).
    self.wageMultiplier = 1.0
    self.wearCurveStrength = 1.0
    self.experienceGainRate = 1.0
    self.leaveRiskStrength = 1.0

    return self
end

--- Restore settings from the savegame / mod settings file.
function FarmHandSettings:load()
    -- TODO(slice 1): read persisted values; fall back to the defaults above.
end

--- Persist current settings.
function FarmHandSettings:save()
    -- TODO(slice 1): write values to the mod settings file.
end

function FarmHandSettings:getCourseDurationMultiplier()
    return self.courseDurationMultiplier
end

function FarmHandSettings:getWageMultiplier()
    return self.wageMultiplier
end

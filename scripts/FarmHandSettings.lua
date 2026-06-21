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

    self.wageMultiplier = 1.0

    -- When ON (default), the monthly salary REPLACES the vanilla per-job helper
    -- fee: that fee is suppressed while a FarmHand does the work, so labour is
    -- paid for once (the salary), not twice. Toggle OFF to pay both.
    self.salaryReplacesHelperCost = true

    -- Experience-to-wear curve: multiplier = floor + (green - floor) * exp(-ha / K).
    self.wearFloor = 0.9   -- veteran (many hectares): easiest on machinery
    self.wearGreen = 1.75  -- green (zero hectares): hardest on machinery
    self.wearK = 100       -- hectares constant; lower = faster early improvement

    -- Leave-risk / synthetic market value. A hand's market wage is base plus a
    -- per-cert bonus (deliberately ABOVE the 500 actually paid) plus an
    -- experience bonus, so trained/experienced hands become underpaid.
    self.marketCertBonus = 800       -- market value per certificate
    self.marketExpBonus = 1500       -- market value at full experience
    self.marketExpK = 150            -- hectares constant for the experience factor
    self.retentionSensitivity = 0.5  -- how strongly the pay gap drives quitting
    self.maxMonthlyQuitChance = 0.25 -- cap on a single month's quit probability

    -- Reserved for later slices (kept here so the save format is stable).
    self.experienceGainRate = 1.0

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

function FarmHandSettings:getSalaryReplacesHelperCost()
    return self.salaryReplacesHelperCost
end

function FarmHandSettings:getWearFloor()
    return self.wearFloor
end

function FarmHandSettings:getWearGreen()
    return self.wearGreen
end

function FarmHandSettings:getWearK()
    return self.wearK
end

function FarmHandSettings:getMarketCertBonus()
    return self.marketCertBonus
end

function FarmHandSettings:getMarketExpBonus()
    return self.marketExpBonus
end

function FarmHandSettings:getMarketExpK()
    return self.marketExpK
end

function FarmHandSettings:getRetentionSensitivity()
    return self.retentionSensitivity
end

function FarmHandSettings:getMaxMonthlyQuitChance()
    return self.maxMonthlyQuitChance
end

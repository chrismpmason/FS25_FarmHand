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

-- Global mod settings file (not per-savegame), under the player's FS profile.
local SETTINGS_FILE = "modSettings/FS25_FarmHand.xml"

function FarmHandSettings.new()
    local self = setmetatable({}, FarmHandSettings_mt)

    -- Scales how many in-game months a course takes. 1.0 = design default.
    self.courseDurationMultiplier = 1.0

    self.wageMultiplier = 1.0

    -- National Minimum Wage floor inputs. nmwHourly is the April 2026 21+ rate;
    -- weeklyHours is the agricultural standard week. The monthly floor is derived
    -- (see getNmwFloorMonthly). Both annually updatable.
    self.nmwHourly = 12.71
    self.weeklyHours = 39

    -- When ON (default), the monthly salary REPLACES the vanilla per-job helper
    -- fee: that fee is suppressed while a FarmHand does the work, so labour is
    -- paid for once (the salary), not twice. Toggle OFF to pay both.
    self.salaryReplacesHelperCost = true

    -- Experience-to-wear curve: multiplier = floor + (green - floor) * exp(-ha / K).
    self.wearFloor = 0.9   -- veteran (many hectares): easiest on machinery
    self.wearGreen = 1.75  -- green (zero hectares): hardest on machinery
    self.wearK = 100       -- hectares constant; lower = faster early improvement

    -- Master switch for the experience-to-wear scaling above. When FALSE, FarmHand
    -- installs NO wear override at all — ADS / vanilla wear behave exactly as they
    -- would without this mod (it writes none of ADS's own fields, so this can't
    -- corrupt a save; it just stops scaling). Speed and everything else are
    -- unaffected. For players on hard wear setups. Read from the modSettings file.
    self.experienceWearEnabled = true

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

--- Restore settings from the global mod settings file. Creates it with defaults
--- on first run so the player has a file to edit. Only the wear off-switch is
--- read for now; other values stay at their code defaults until surfaced.
function FarmHandSettings:load()
    local path = getUserProfileAppPath() .. SETTINGS_FILE

    if not fileExists(path) then
        self:save() -- write defaults the player can edit
        return
    end

    local xmlFile = loadXMLFile("FarmHandSettings", path)
    if xmlFile == nil or xmlFile == 0 then
        return
    end
    self.experienceWearEnabled =
        Utils.getNoNil(getXMLBool(xmlFile, "farmHand.experienceWearEnabled"), self.experienceWearEnabled)
    delete(xmlFile)
end

--- Persist current settings to the global mod settings file.
function FarmHandSettings:save()
    createFolder(getUserProfileAppPath() .. "modSettings/")
    local path = getUserProfileAppPath() .. SETTINGS_FILE

    local xmlFile = createXMLFile("FarmHandSettings", path, "farmHand")
    if xmlFile == nil or xmlFile == 0 then
        return
    end
    setXMLBool(xmlFile, "farmHand.experienceWearEnabled", self.experienceWearEnabled)
    saveXMLFile(xmlFile)
    delete(xmlFile)
end

function FarmHandSettings:getExperienceWearEnabled()
    return self.experienceWearEnabled
end

function FarmHandSettings:getCourseDurationMultiplier()
    return self.courseDurationMultiplier
end

function FarmHandSettings:getWageMultiplier()
    return self.wageMultiplier
end

function FarmHandSettings:getNmwHourly()
    return self.nmwHourly
end

function FarmHandSettings:getWeeklyHours()
    return self.weeklyHours
end

--- The legal monthly wage floor: NMW hourly x weekly hours x 52 weeks / 12 months.
function FarmHandSettings:getNmwFloorMonthly()
    return self.nmwHourly * self.weeklyHours * 52 / 12
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

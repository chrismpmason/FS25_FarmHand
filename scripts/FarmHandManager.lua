--
-- FarmHandManager
--
-- Central owner of the mod's state and the month-tick orchestrator.
--
-- Holds the candidate pool, the roster of employed workers, and the "active
-- hand" (the worker the lightweight Option-A model treats as the one being put
-- on a job). Runs the ordered month rollover described in DESIGN.md.
--
-- The month-tick steps are currently clearly-marked stubs; the first feature
-- slice will fill them in (pesticides certificate gating, the experience-to-
-- wear curve, on-the-job month-tick training, monthly wages, basic leave-risk).
--

FarmHandManager = {}

-- Grade-based pay. Grade (1-4) is COMPUTED from a hand's certs + experience each
-- time wage is calculated (never persisted), so hands promote automatically as
-- they earn certs and hours. Monthly rates and names are tunable constants; the
-- NMW floor (settings) is applied on top so no grade can pay below the legal min.
FarmHandManager.GRADE_RATES = { 2150, 2250, 2450, 2650 } -- monthly £, index = grade
FarmHandManager.GRADE_NAMES = { "Trainee", "Farm worker", "Skilled operator", "Senior hand" }

-- Experience thresholds (in hectaresWorked, the existing experience measure) that
-- promote within a tier: 1->2 (uncertificated) and 3->4 (certificated). Tuned for
-- a few months of work, not glacial.
FarmHandManager.GRADE_EXP_MID = 50   -- "experienced"
FarmHandManager.GRADE_EXP_HIGH = 200 -- "highly experienced"

-- Certificates that gate the skilled grades (3-4). A small list so adding certs
-- later is trivial. FarmHandCertificate is defined in the worker module (loaded
-- before this one).
local SKILLED_CERTS = { FarmHandCertificate.PESTICIDES }

local FarmHandManager_mt = Class(FarmHandManager)

-- Name pools for generating green candidates. Small hardcoded lists; a first
-- name is picked to match the candidate's gender, paired with a random surname.
local MALE_FIRST = {
    "Jack", "Tom", "Harry", "George", "Charlie", "Oliver", "Jacob", "Alfie", "Ryan", "Sam",
}
local FEMALE_FIRST = {
    "Emily", "Sophie", "Grace", "Lucy", "Chloe", "Ella", "Mia", "Freya", "Holly", "Daisy",
}
local SURNAMES = {
    "Carter", "Hale", "Watson", "Brennan", "Fletcher", "Marsh", "Doyle", "Pryce", "Whitlock", "Ainsley",
}

--- Construct a manager. Does not touch game state yet; see load().
-- @param modDirectory absolute path to the mod, for loading resources
-- @param modName the registered mod name
function FarmHandManager.new(modDirectory, modName)
    local self = setmetatable({}, FarmHandManager_mt)

    self.modDirectory = modDirectory
    self.modName = modName

    self.settings = FarmHandSettings.new()

    -- Hire pool: candidates available this month. Runtime-only, never saved;
    -- regenerated on load and on every month tick. Each entry: {id, name, isMale}.
    self.candidates = {}
    -- Monotonic counters for unique runtime ids (candidate ids / hired worker ids).
    self.candidateCounter = 0
    self.hireCounter = 0
    -- Employed workers, keyed by worker id (id -> FarmHandWorker).
    self.workers = {}
    -- Stable display order for the roster (workers itself is keyed by id).
    self.workerOrder = {}
    -- The worker currently treated as "the one being assigned" (Option A).
    -- The certificate gate will check this worker. nil = no hand selected.
    self.activeHandId = nil

    -- Helper-cost suppression. farmHandJobCount > 0 means at least one FarmHand AI
    -- job is running, so its vanilla per-job fee (MoneyType.AI) is suppressed and
    -- the monthly salary is the only labour cost. moneyPassthrough guards our OWN
    -- money operations so they always go through the addMoney hook untouched.
    self.farmHandJobCount = 0
    self.moneyPassthrough = false

    return self
end

--- Bring the manager online for a loaded savegame. Restore persisted state if a
--- save file exists; otherwise seed the default roster (new game).
function FarmHandManager:load()
    self.settings:load()

    local loaded = self:loadFromXMLFile(self:getSavePath())
    if loaded == nil then
        self:seedDefaultRoster()
    end

    -- Register a per-hand helper (driver appearance + name) for the whole roster.
    self:registerHelpersForRoster()

    -- Seed the hire pool (runtime-only; regenerated monthly via refreshCandidates).
    self:generateCandidates()
end

--- Seed the default roster for a brand-new game (no save yet). TEMPORARY test
--- scaffolding until real hiring lands:
---   * Alan Carter - certified veteran (control).
---   * Tom Hale    - green, enrolled on the 3-month pesticides course (subject).
function FarmHandManager:seedDefaultRoster()
    local certified = FarmHandWorker.new("test_certified", "Alan Carter")
    certified:grantCertificate(FarmHandCertificate.PESTICIDES)
    certified.hectaresWorked = 500 -- veteran: wear multiplier ~0.9x
    certified.isMale = true
    self:addWorker(certified)

    local rookie = FarmHandWorker.new("test_rookie", "Tom Hale")
    rookie.hectaresWorked = 0 -- green: wear multiplier ~1.75x
    rookie.isMale = true
    self:addWorker(rookie)
    self:enrollCourse(rookie, FarmHandCertificate.PESTICIDES, 3)
end

--- Release anything held for the current game.
function FarmHandManager:delete()
    self.candidates = {}
    self.workers = {}
    self.workerOrder = {}
    self.activeHandId = nil
end

-- =========================================================================
-- Savegame persistence.
-- =========================================================================

--- Path to our XML inside the current savegame folder, or nil if unavailable.
function FarmHandManager:getSavePath()
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if missionInfo == nil or missionInfo.savegameDirectory == nil then
        return nil
    end
    return missionInfo.savegameDirectory .. "/FS25_FarmHand.xml"
end

--- Write the roster + active hand to the savegame. Returns the count saved.
function FarmHandManager:saveToXMLFile(path)
    if path == nil then
        return 0
    end

    local xmlFile = XMLFile.create("farmHandXML", path, "farmHand")
    if xmlFile == nil then
        return 0
    end

    local key = "farmHand"
    xmlFile:setString(key .. "#activeHandId", self.activeHandId or "")

    local workers = self:getWorkersList()
    xmlFile:setTable(key .. ".workers.worker", workers, function(workerKey, worker)
        xmlFile:setString(workerKey .. "#id", worker.id)
        xmlFile:setString(workerKey .. "#name", worker.name)
        xmlFile:setFloat(workerKey .. "#hectaresWorked", worker.hectaresWorked or 0)
        xmlFile:setInt(workerKey .. "#baseWage", worker.baseWage or 2000)

        -- Driver appearance slot + gender (helperIndex is runtime-only, not saved).
        if worker.styleSlot ~= nil then
            xmlFile:setInt(workerKey .. "#styleSlot", worker.styleSlot)
        end
        xmlFile:setBool(workerKey .. "#isMale", worker.isMale)

        -- Active-hand flag, stored per-worker (root attributes read back
        -- unreliably; per-element attributes like this are dependable).
        if worker.id == self.activeHandId then
            xmlFile:setBool(workerKey .. "#active", true)
        end

        -- Certificates as a space-separated list of ids.
        local certs = {}
        for certId in pairs(worker.certificates) do
            certs[#certs + 1] = certId
        end
        xmlFile:setString(workerKey .. "#certificates", table.concat(certs, " "))

        if worker:isEnrolled() then
            xmlFile:setString(workerKey .. ".course#targetCert", worker.targetCert)
            xmlFile:setInt(workerKey .. ".course#progress", worker.courseProgress or 0)
            xmlFile:setInt(workerKey .. ".course#length", worker.courseLength or 0)
        end
    end)

    xmlFile:save()
    xmlFile:delete()
    return #workers
end

--- Load the roster + active hand from the savegame. Returns the count loaded,
--- or nil if there is no save file (caller should then seed a new game).
function FarmHandManager:loadFromXMLFile(path)
    if path == nil then
        return nil
    end

    local xmlFile = XMLFile.loadIfExists("farmHandXML", path)
    if xmlFile == nil then
        return nil
    end

    local key = "farmHand"

    xmlFile:iterate(key .. ".workers.worker", function(_, workerKey)
        local id = xmlFile:getString(workerKey .. "#id", nil)
        if id ~= nil then
            local worker = FarmHandWorker.new(id, xmlFile:getString(workerKey .. "#name", "Hand"))
            worker.hectaresWorked = xmlFile:getFloat(workerKey .. "#hectaresWorked", 0)
            worker.baseWage = xmlFile:getInt(workerKey .. "#baseWage", 2000)
            worker.styleSlot = xmlFile:getInt(workerKey .. "#styleSlot", nil)
            worker.isMale = xmlFile:getBool(workerKey .. "#isMale", true)

            local certStr = xmlFile:getString(workerKey .. "#certificates", "")
            for certId in string.gmatch(certStr, "%S+") do
                worker:grantCertificate(certId)
            end

            if xmlFile:hasProperty(workerKey .. ".course") then
                local targetCert = xmlFile:getString(workerKey .. ".course#targetCert", nil)
                if targetCert ~= nil then
                    worker:enrollCourse(targetCert, xmlFile:getInt(workerKey .. ".course#length", 1))
                    worker.courseProgress = xmlFile:getInt(workerKey .. ".course#progress", 0)
                end
            end

            self:addWorker(worker)

            -- Restore the active hand from the per-worker flag (overrides the
            -- default-to-first-added that addWorker applies).
            if xmlFile:getBool(workerKey .. "#active", false) then
                self.activeHandId = worker.id
            end
        end
    end)

    xmlFile:delete()

    return #self:getWorkersList()
end

-- =========================================================================
-- Worker roster + active hand.
-- =========================================================================

--- Add a worker to the employed roster, keyed by his id.
function FarmHandManager:addWorker(worker)
    if self.workers[worker.id] == nil then
        self.workerOrder[#self.workerOrder + 1] = worker.id
    end
    self.workers[worker.id] = worker

    -- Default the active hand to the first one added, until the player picks.
    if self.activeHandId == nil then
        self.activeHandId = worker.id
    end
end

--- Look up an employed worker by id, or nil if not employed.
function FarmHandManager:getWorker(id)
    return self.workers[id]
end

--- Employed workers in stable display order.
function FarmHandManager:getWorkersList()
    local list = {}
    for _, id in ipairs(self.workerOrder) do
        local worker = self.workers[id]
        if worker ~= nil then
            list[#list + 1] = worker
        end
    end
    return list
end

--- Set the active hand by id. Only succeeds for an employed worker.
-- @return true if set, false if no such worker
function FarmHandManager:setActiveHand(id)
    if self.workers[id] == nil then
        return false
    end

    self.activeHandId = id
    return true
end

--- The active hand worker object, or nil if none is set / he is gone.
function FarmHandManager:getActiveHand()
    if self.activeHandId == nil then
        return nil
    end

    return self.workers[self.activeHandId]
end

--- Clear the active hand selection.
function FarmHandManager:clearActiveHand()
    self.activeHandId = nil
end

--- Remove a worker from the roster (e.g. on quitting). Clears any in-progress
--- course (progress is lost) and reassigns the active hand if it was them.
function FarmHandManager:removeWorker(id)
    local worker = self.workers[id]
    if worker == nil then
        return
    end

    worker:clearCourse()
    self.workers[id] = nil

    for i, wid in ipairs(self.workerOrder) do
        if wid == id then
            table.remove(self.workerOrder, i)
            break
        end
    end

    -- If the active hand just left, fall back to the next one (or nil).
    if self.activeHandId == id then
        self.activeHandId = self.workerOrder[1]
    end
end

-- =========================================================================
-- Driver identity (consistent helper character + name per hand).
-- =========================================================================

--- Make a worker id safe for use as a HelperManager index name.
function FarmHandManager:sanitizeId(id)
    return tostring(id):gsub("[^%w_]", "_")
end

--- Gender of a playerStyle: true=male, false=female, nil=unknown.
--- Gender is not a boolean on the runtime style; it is encoded in the player
--- model filename the style references: dataS/character/playerM/playerM.xml
--- (male) vs .../playerF/playerF.xml (female). We don't know which field holds
--- that path at runtime, so scan the style's top-level string values for the
--- "playerm"/"playerf" token. Returns true=male, false=female, nil=unknown.
local function playerStyleIsMale(style)
    if style == nil then
        return nil
    end
    for _, v in pairs(style) do
        if type(v) == "string" then
            local lower = v:lower()
            if lower:find("playerf", 1, true) then
                return false
            elseif lower:find("playerm", 1, true) then
                return true
            end
        end
    end
    return nil
end

--- The vanilla helper at a style slot, or nil.
function FarmHandManager:getVanillaStyle(slot)
    if slot == nil then
        return nil
    end
    local helper = g_helperManager:getHelperByIndex(slot)
    return helper ~= nil and helper.playerStyle or nil
end

--- Split the vanilla helpers into male/female style-slot pools and cache them on
--- the manager. Must run BEFORE we add any of our own helpers, so the count and
--- slots only ever reflect base-game helpers (ours land at indices above these).
--- The cached pools + cycle counters are reused for mid-game hires.
function FarmHandManager:buildGenderPools()
    self.maleSlots, self.femaleSlots = {}, {}
    self.vanillaCount = 0
    self.useGender = false
    self.maleCycle, self.femaleCycle, self.allCycle = 0, 0, 0

    if g_helperManager == nil then
        return
    end
    local vanillaCount = g_helperManager.numHelpers or 0
    if vanillaCount <= 0 then
        return -- helpers not ready yet; nothing to borrow from
    end
    self.vanillaCount = vanillaCount

    for slot = 1, vanillaCount do
        local male = playerStyleIsMale(self:getVanillaStyle(slot))
        if male == true then
            self.maleSlots[#self.maleSlots + 1] = slot
        elseif male == false then
            self.femaleSlots[#self.femaleSlots + 1] = slot
        end
    end
    self.useGender = #self.maleSlots > 0 and #self.femaleSlots > 0
end

--- Give one hand a stable, gender-matched driver: pick a styleSlot from the
--- matching-gender pool (if not already set / if the current slot's gender no
--- longer matches), borrow that vanilla helper's appearance, and register a
--- per-hand HelperManager helper titled with the hand's name. helperIndex is
--- runtime-only; styleSlot/isMale persist so the face stays stable across loads.
--- Requires buildGenderPools() to have run first.
function FarmHandManager:registerHelperForHand(hand)
    if g_helperManager == nil or (self.vanillaCount or 0) <= 0 then
        return
    end

    if self.useGender then
        local pool = hand.isMale and self.maleSlots or self.femaleSlots
        local current = playerStyleIsMale(self:getVanillaStyle(hand.styleSlot))
        if hand.styleSlot == nil or current ~= hand.isMale then
            if hand.isMale then
                hand.styleSlot = pool[(self.maleCycle % #pool) + 1]
                self.maleCycle = self.maleCycle + 1
            else
                hand.styleSlot = pool[(self.femaleCycle % #pool) + 1]
                self.femaleCycle = self.femaleCycle + 1
            end
        end
    elseif hand.styleSlot == nil then
        -- Gender unavailable: fall back to a plain all-helpers cycle.
        hand.styleSlot = (self.allCycle % self.vanillaCount) + 1
        self.allCycle = self.allCycle + 1
    end

    local slot = math.max(1, math.min(self.vanillaCount, hand.styleSlot))
    local style = self:getVanillaStyle(slot)
    local helper = g_helperManager:addHelper("FARMHAND_" .. self:sanitizeId(hand.id), hand.name, { 1, 1, 1 }, style)
    if helper ~= nil then
        hand.helperIndex = helper.index
    end
end

--- Register a per-hand helper for the whole roster. Re-derives the gender pools
--- (capturing the vanilla count before adding ours) and registers each hand.
function FarmHandManager:registerHelpersForRoster()
    self:buildGenderPools()
    if (self.vanillaCount or 0) <= 0 then
        return
    end
    for _, worker in ipairs(self:getWorkersList()) do
        self:registerHelperForHand(worker)
    end
end

-- =========================================================================
-- Hire pool (candidates) + hiring. Candidates are runtime-only and never
-- saved; hired hands enter the roster and ride the existing persistence.
-- =========================================================================

--- A gender-matched random display name, e.g. "First Last".
function FarmHandManager:makeCandidateName(isMale)
    local firsts = isMale and MALE_FIRST or FEMALE_FIRST
    local first = firsts[math.random(#firsts)]
    local last = SURNAMES[math.random(#SURNAMES)]
    return first .. " " .. last
end

--- Replace the hire pool with n freshly generated green candidates, each with a
--- random gender, a gender-matched name, and a unique runtime id.
function FarmHandManager:generateCandidates(n)
    n = n or 3
    self.candidates = {}
    for _ = 1, n do
        self.candidateCounter = self.candidateCounter + 1
        local isMale = math.random() < 0.5
        local candidate = {
            id = "cand_" .. self.candidateCounter,
            name = self:makeCandidateName(isMale),
            isMale = isMale,
        }
        self.candidates[#self.candidates + 1] = candidate
    end
end

--- Hire a candidate by id: create a green worker from it, add it to the roster,
--- assign its driver identity now, and remove it from the pool. Returns the new
--- worker, or nil if no such candidate. v1: no recruitment fee (wages are the
--- cost); the candidate pool is not persisted.
function FarmHandManager:hireCandidate(candidateId)
    local index, candidate
    for i, c in ipairs(self.candidates) do
        if c.id == candidateId then
            index, candidate = i, c
            break
        end
    end
    if candidate == nil then
        return nil
    end

    -- Unique worker id, guarded against colliding with a reloaded "hire_N".
    local workerId
    repeat
        self.hireCounter = self.hireCounter + 1
        workerId = "hire_" .. self.hireCounter
    until self.workers[workerId] == nil

    -- Green by construction: FarmHandWorker.new() defaults 0 hectares, no certs,
    -- no course and the standard base wage. Only identity comes from the candidate.
    local worker = FarmHandWorker.new(workerId, candidate.name)
    worker.isMale = candidate.isMale

    self:addWorker(worker)
    self:registerHelperForHand(worker)

    table.remove(self.candidates, index)

    return worker
end

--- The active hand's registered helper index, or nil (nil -> vanilla random).
function FarmHandManager:getActiveHelperIndex()
    local hand = self:getActiveHand()
    return hand ~= nil and hand.helperIndex or nil
end

-- =========================================================================
-- Courses / on-the-job training.
-- =========================================================================

--- Enroll a worker on a course for a certificate. Required months is the base
--- length scaled by the player's course-duration multiplier (min 1).
function FarmHandManager:enrollCourse(worker, targetCert, baseMonths)
    local multiplier = self.settings:getCourseDurationMultiplier()
    local length = math.max(1, math.floor(baseMonths * multiplier + 0.5))
    worker:enrollCourse(targetCert, length)
end

-- =========================================================================
-- Wages.
-- =========================================================================

--- True if the worker holds any skilled (grade-gating) certificate.
function FarmHandManager:hasSkilledCert(worker)
    for _, certId in ipairs(SKILLED_CERTS) do
        if worker:hasCertificate(certId) then
            return true
        end
    end
    return false
end

--- The worker's computed employment grade (1-4), from certs + experience. Not
--- persisted; recomputed on demand so promotion tracks experience/cert growth.
--- A skilled cert gates the skilled grades (3-4); experience promotes within a
--- tier (1->2 uncertificated, 3->4 certificated).
function FarmHandManager:getGrade(worker)
    local exp = worker.hectaresWorked or 0
    if not self:hasSkilledCert(worker) then
        return exp >= FarmHandManager.GRADE_EXP_MID and 2 or 1
    end
    return exp >= FarmHandManager.GRADE_EXP_HIGH and 4 or 3
end

--- The worker's grade display name.
function FarmHandManager:getGradeName(worker)
    return FarmHandManager.GRADE_NAMES[self:getGrade(worker)] or "?"
end

--- A single hand's monthly wage: the grade rate, floored at the legal NMW
--- minimum. Grade is computed at call time, so hands promote automatically.
function FarmHandManager:getWorkerMonthlyWage(worker)
    local rate = FarmHandManager.GRADE_RATES[self:getGrade(worker)] or 0
    return math.max(rate, self.settings:getNmwFloorMonthly())
end

-- =========================================================================
-- Month rollover. Steps run in the order defined in DESIGN.md section 4.
-- =========================================================================

function FarmHandManager:onMonthChanged()
    self:advanceCourses()      -- 1. course progress (only for workers who worked)
    self:tallyExperience()     -- 2. fold the month's hectares into experience
    self:payWages()            -- 3. debit monthly wages
    self:runRetentionCheck()   -- 4. roll leave-risk; departures lose course progress
    self:refreshCandidates()   -- 5. regenerate the hire pool

    self:resetMonthlyCounters()
end

--- 1. Advance each enrolled worker's course by one month and grant the
--- certificate on completion. A month only counts if the hand actually worked
--- it: we read workedThisMonth for the month just ended (resetMonthlyCounters,
--- the last step of onMonthChanged, clears it afterwards for the new month).
function FarmHandManager:advanceCourses()
    for _, worker in pairs(self.workers) do
        if worker:isEnrolled() and worker.workedThisMonth then
            worker.courseProgress = worker.courseProgress + 1

            if worker.courseProgress >= worker.courseLength then
                worker:grantCertificate(worker.targetCert)
                worker:clearCourse()
            end
        end
    end
end

--- 2. Fold the hectares worked this month into each worker's experience value
--- (fast early gains, slow plateau).
function FarmHandManager:tallyExperience()
    -- TODO(slice 1): accumulate hectares -> experience; experience drives the
    -- wear curve (~1.75x green down toward ~0.9x experienced).
end

--- 3. Pay every employed worker's monthly wage from the farm account. The
--- total across ALL roster hands is scaled by the wage multiplier and deducted
--- once (negative money change = expense).
function FarmHandManager:payWages()
    local total = 0
    for _, worker in pairs(self.workers) do
        total = total + self:getWorkerMonthlyWage(worker)
    end

    total = math.floor(total * self.settings:getWageMultiplier() + 0.5)
    if total <= 0 then
        return
    end

    local farmId = g_currentMission ~= nil and g_currentMission:getFarmId() or nil
    local farm = farmId ~= nil and g_farmManager:getFarmById(farmId) or nil
    if farm == nil then
        return
    end

    -- Pay the whole roster as a single deduction. addMoney does the balance move,
    -- the finance-stat record and the on-screen change in one call; MoneyType.AI
    -- puts it on the hired-labour ("Wages") Finances line — the same line the
    -- suppressed per-job helper fee used to hit, so labour reads as one cost.
    --
    -- CRITICAL: wrap in the passthrough flag. Our helper-fee suppression eats
    -- MoneyType.AI charges while a hand is mid-job; without this guard a salary
    -- paid during a running job at the month rollover would be suppressed too.
    local moneyType = MoneyType.AI or MoneyType.WAGES or MoneyType.OTHER

    self.moneyPassthrough = true
    g_currentMission:addMoney(-total, farm:getId(), moneyType, true, true)
    self.moneyPassthrough = false
end

--- 4. For each worker, roll the leave-risk against their GRADE rate benchmark
--- (what their grade is worth). They quit when paid below it. This slice pays
--- exactly the grade rate (no player-set offer yet), so the gap is always 0 and
--- no one quits — this is plumbing for the wage-negotiations slice, which adds an
--- offered wage that can fall below the benchmark. A hand who quits mid-course
--- loses their in-progress course progress.
function FarmHandManager:runRetentionCheck()
    local settings = self.settings
    local sensitivity = settings:getRetentionSensitivity()
    local maxChance = settings:getMaxMonthlyQuitChance()

    -- Collect quitters first; don't mutate the roster while iterating it.
    local quitters = {}
    for id, worker in pairs(self.workers) do
        local benchmark = self:getWorkerMonthlyWage(worker) -- the fair grade rate
        local paidWage = benchmark                          -- == grade rate until negotiations land
        local gap = math.max(0, benchmark - paidWage)

        local quitChance = 0
        if benchmark > 0 then
            quitChance = math.min(maxChance, math.max(0, sensitivity * gap / benchmark))
        end

        if math.random() < quitChance then
            quitters[#quitters + 1] = id
        end
    end

    for _, id in ipairs(quitters) do
        self:removeWorker(id)
    end
end

--- 5. Replace the hire pool with a freshly generated set of candidates
--- (monthly = full regenerate; the pool is runtime-only and never persisted).
function FarmHandManager:refreshCandidates()
    self:generateCandidates()
end

--- Clear per-month accumulators (the worked-this-month flag) ready for the new
--- month. Runs last in onMonthChanged, after the steps that read the flag.
function FarmHandManager:resetMonthlyCounters()
    for _, worker in pairs(self.workers) do
        worker.workedThisMonth = false
    end
end

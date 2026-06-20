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

-- Per-certificate monthly wage premium added on top of a hand's base wage
-- (first-pass placeholder for balancing).
FarmHandManager.CERT_WAGE_PREMIUM = 500

local FarmHandManager_mt = Class(FarmHandManager)

--- Construct a manager. Does not touch game state yet; see load().
-- @param modDirectory absolute path to the mod, for loading resources
-- @param modName the registered mod name
function FarmHandManager.new(modDirectory, modName)
    local self = setmetatable({}, FarmHandManager_mt)

    self.modDirectory = modDirectory
    self.modName = modName

    self.settings = FarmHandSettings.new()

    -- Hire pool: candidates available this month.
    self.candidates = {}
    -- Employed workers, keyed by worker id (id -> FarmHandWorker).
    self.workers = {}
    -- Stable display order for the roster (workers itself is keyed by id).
    self.workerOrder = {}
    -- The worker currently treated as "the one being assigned" (Option A).
    -- The certificate gate will check this worker. nil = no hand selected.
    self.activeHandId = nil

    return self
end

--- Bring the manager online for a loaded savegame. Restore persisted state if a
--- save file exists; otherwise seed the default roster (new game).
function FarmHandManager:load()
    self.settings:load()

    local loaded = self:loadFromXMLFile(self:getSavePath())
    if loaded ~= nil then
        return
    end

    self:seedDefaultRoster()
end

--- Seed the default roster for a brand-new game (no save yet). TEMPORARY test
--- scaffolding until real hiring lands:
---   * Alan Carter - certified veteran (control).
---   * Tom Hale    - green, enrolled on the 3-month pesticides course (subject).
function FarmHandManager:seedDefaultRoster()
    local certified = FarmHandWorker.new("test_certified", "Alan Carter")
    certified:grantCertificate(FarmHandCertificate.PESTICIDES)
    certified.hectaresWorked = 500 -- veteran: wear multiplier ~0.9x
    self:addWorker(certified)

    local rookie = FarmHandWorker.new("test_rookie", "Tom Hale")
    rookie.hectaresWorked = 0 -- green: wear multiplier ~1.75x
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

--- A single hand's monthly wage: base plus a premium per certificate held.
--- (Experience scaling comes with the experience/wear slice.)
function FarmHandManager:getWorkerMonthlyWage(worker)
    return worker.baseWage + worker:getCertificateCount() * FarmHandManager.CERT_WAGE_PREMIUM
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

    -- Crib of Employment's monthly salary deduction: record the change for the
    -- finance stats, then move the farm balance.
    local moneyType = MoneyType.WAGES or MoneyType.OTHER
    g_currentMission:addMoneyChange(-total, farm:getId(), moneyType, true)
    farm:changeBalance(-total, moneyType)
end

--- 4. For each worker, roll the leave-risk. The more a hand's market wage
--- exceeds what the farm pays them, the likelier they quit. A hand who quits
--- mid-course loses their in-progress course progress.
function FarmHandManager:runRetentionCheck()
    local settings = self.settings
    local sensitivity = settings:getRetentionSensitivity()
    local maxChance = settings:getMaxMonthlyQuitChance()
    local certBonus = settings:getMarketCertBonus()
    local expBonus = settings:getMarketExpBonus()
    local expK = settings:getMarketExpK()

    -- Collect quitters first; don't mutate the roster while iterating it.
    local quitters = {}
    for id, worker in pairs(self.workers) do
        local paidWage = self:getWorkerMonthlyWage(worker)
        local marketWage = worker:getMarketWage(certBonus, expBonus, expK)
        local gap = worker:getPayGap(paidWage, certBonus, expBonus, expK)

        local quitChance = 0
        if marketWage > 0 then
            quitChance = math.min(maxChance, math.max(0, sensitivity * gap / marketWage))
        end

        if math.random() < quitChance then
            quitters[#quitters + 1] = id
        end
    end

    for _, id in ipairs(quitters) do
        self:removeWorker(id)
    end
end

--- 5. Replace the hire pool with a freshly generated set of candidates.
function FarmHandManager:refreshCandidates()
    -- TODO(slice 1): generate names, low starting experience, wage, signing cost.
end

--- Clear per-month accumulators (the worked-this-month flag) ready for the new
--- month. Runs last in onMonthChanged, after the steps that read the flag.
function FarmHandManager:resetMonthlyCounters()
    for _, worker in pairs(self.workers) do
        worker.workedThisMonth = false
    end
end

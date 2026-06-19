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
    -- The worker currently treated as "the one being assigned" (Option A).
    -- The certificate gate will check this worker. nil = no hand selected.
    self.activeHandId = nil

    return self
end

--- Bring the manager online for a loaded savegame.
-- Will eventually restore persisted state and seed the first candidate pool.
function FarmHandManager:load()
    self.settings:load()

    -- TODO(slice 1): restore saved workers/candidates, or seed an initial pool.

    -- TEMPORARY test scaffolding (no hiring UI yet): two hands so the gate can
    -- be exercised once it exists. One is certified for pesticides, one is not;
    -- the uncertified hand is made active so the default state demonstrates a
    -- block. Remove once real hiring lands.
    local certified = FarmHandWorker.new("test_certified", "Alan Carter")
    certified:grantCertificate(FarmHandCertificate.PESTICIDES)
    self:addWorker(certified)

    local rookie = FarmHandWorker.new("test_rookie", "Tom Hale")
    self:addWorker(rookie)

    self:setActiveHand(rookie.id)
end

--- Release anything held for the current game.
function FarmHandManager:delete()
    self.candidates = {}
    self.workers = {}
    self.activeHandId = nil
end

-- =========================================================================
-- Worker roster + active hand.
-- =========================================================================

--- Add a worker to the employed roster, keyed by his id.
function FarmHandManager:addWorker(worker)
    self.workers[worker.id] = worker
end

--- Look up an employed worker by id, or nil if not employed.
function FarmHandManager:getWorker(id)
    return self.workers[id]
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

--- 1. Advance each in-training worker by one month, but only if he worked
--- during the month just ended. Idle months do not count.
function FarmHandManager:advanceCourses()
    -- TODO(slice 1): pesticides certificate progresses one month per worked month,
    -- scaled by settings:getCourseDurationMultiplier().
end

--- 2. Fold the hectares worked this month into each worker's experience value
--- (fast early gains, slow plateau).
function FarmHandManager:tallyExperience()
    -- TODO(slice 1): accumulate hectares -> experience; experience drives the
    -- wear curve (~1.75x green down toward ~0.9x experienced).
end

--- 3. Pay every employed worker's monthly wage from the farm account.
function FarmHandManager:payWages()
    -- TODO(slice 1): debit farm for sum of monthly wages.
end

--- 4. For each worker, roll the leave-risk. Underpaid valuable workers may
--- leave; a worker leaving mid-course loses his course progress.
function FarmHandManager:runRetentionCheck()
    -- TODO(slice 1): basic leave-risk roll.
end

--- 5. Replace the hire pool with a freshly generated set of candidates.
function FarmHandManager:refreshCandidates()
    -- TODO(slice 1): generate names, low starting experience, wage, signing cost.
end

--- Clear per-month accumulators (e.g. hectares-worked-this-month, worked flag)
--- ready for the new month.
function FarmHandManager:resetMonthlyCounters()
    -- TODO(slice 1): reset per-worker monthly tallies.
end

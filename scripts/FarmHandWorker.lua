--
-- FarmHandWorker
--
-- A single employed farm hand.
--
-- Minimal for now: identity plus the set of qualifications he holds. The
-- progression values (experience, course-in-progress, wage, monthly work
-- tally) will be added in the slices that need them. Keeping this small means
-- the gate slice only depends on "does this hand hold certificate X".
--

-- Qualification identifiers. One per course/certificate the mod can grant.
-- Stored as stable strings so they survive saving without depending on order.
FarmHandCertificate = {
    PESTICIDES = "pesticides",
    -- Boost certs (College Slice B): additive string tokens in the same space-
    -- separated #certificates attribute. Old saves (no token) load unaffected.
    COMBINE = "combine",
    SEEDER = "seeder",
    FERTILISER = "fertiliser",
    FORAGE = "forage",
}

FarmHandWorker = {}

local FarmHandWorker_mt = Class(FarmHandWorker)

--- Create a worker.
-- @param id stable unique identifier (used as the roster key)
-- @param name display name
function FarmHandWorker.new(id, name)
    local self = setmetatable({}, FarmHandWorker_mt)

    self.id = id
    self.name = name

    -- Held qualifications, as a set: certificateId -> true.
    self.certificates = {}

    -- Base monthly wage before any per-certificate premium (first-pass default).
    self.baseWage = 2000

    -- Active course (all nil when not enrolled). See enrollCourse().
    self.targetCert = nil      -- certificate this course grants on completion
    self.courseProgress = nil  -- months completed so far
    self.courseLength = nil    -- months required to complete

    -- Work accumulation. Foundation the wear curve, specialisation gains and
    -- the deferred "course month only counts if he worked" condition read from.
    self.hectaresWorked = 0      -- lifetime hectares attributed to this hand
    self.workedThisMonth = false -- set when any work is attributed; reset monthly

    -- Proficiency tier (1/2/3) the player was last notified about. PERSISTED. The
    -- manager baselines it to the hand's current tier when added (so no spurious
    -- tier-up fires) and bumps it when a crossing is announced. nil until then.
    self.lastNotifiedTier = nil

    -- Driver identity. styleSlot = which vanilla helper's appearance to borrow
    -- (PERSISTED, so the face is stable across reloads). helperIndex = the index
    -- of our per-hand registered helper (RUNTIME only, re-derived each load).
    -- isMale picks the gender pool to borrow from (PERSISTED); defaults male
    -- until proper gender selection arrives at hire.
    self.styleSlot = nil
    self.helperIndex = nil
    self.isMale = true

    return self
end

--- True if the worker holds the given certificate.
function FarmHandWorker:hasCertificate(certificateId)
    return self.certificates[certificateId] == true
end

--- Grant a certificate (e.g. on course completion).
function FarmHandWorker:grantCertificate(certificateId)
    self.certificates[certificateId] = true
end

--- Remove a certificate.
function FarmHandWorker:revokeCertificate(certificateId)
    self.certificates[certificateId] = nil
end

--- Equipment-wear multiplier driven by accumulated experience (hectares).
--- Front-loaded exponential decay from `green` (at 0 ha) toward `floor`:
---   multiplier = floor + (green - floor) * exp(-hectaresWorked / k)
--- Params come from settings; defaults make the method usable standalone.
function FarmHandWorker:getWearMultiplier(floor, green, k)
    floor = floor or 0.9
    green = green or 1.75
    k = k or 100
    return floor + (green - floor) * math.exp(-self.hectaresWorked / k)
end

--- Number of certificates the worker currently holds.
function FarmHandWorker:getCertificateCount()
    local count = 0
    for _ in pairs(self.certificates) do
        count = count + 1
    end
    return count
end

-- ---- Synthetic market value (leave-risk) -----------------------------------

--- Experience factor in [0,1): 0 when green, approaching 1 with hectares.
function FarmHandWorker:experienceFactor(k)
    k = k or 150
    return 1 - math.exp(-self.hectaresWorked / k)
end

--- What the open market would pay this hand: base plus a per-cert bonus and an
--- experience bonus. Params come from settings; defaults keep it standalone.
function FarmHandWorker:getMarketWage(certBonus, expBonus, expK)
    certBonus = certBonus or 800
    expBonus = expBonus or 1500
    return self.baseWage
        + certBonus * self:getCertificateCount()
        + expBonus * self:experienceFactor(expK)
end

--- How far the hand's market wage exceeds what the farm actually pays them
--- (>= 0). Green/uncertified hands sit near 0; trained ones open a gap.
function FarmHandWorker:getPayGap(paidWage, certBonus, expBonus, expK)
    return math.max(0, self:getMarketWage(certBonus, expBonus, expK) - (paidWage or 0))
end

-- ---- Course / on-the-job training ------------------------------------------

--- Enroll the worker on a course for a certificate, resetting progress.
function FarmHandWorker:enrollCourse(targetCert, courseLength)
    self.targetCert = targetCert
    self.courseProgress = 0
    self.courseLength = courseLength
end

--- True if currently enrolled on a course.
function FarmHandWorker:isEnrolled()
    return self.targetCert ~= nil
end

--- Clear any active course enrollment (on completion or if it is lost).
function FarmHandWorker:clearCourse()
    self.targetCert = nil
    self.courseProgress = nil
    self.courseLength = nil
end

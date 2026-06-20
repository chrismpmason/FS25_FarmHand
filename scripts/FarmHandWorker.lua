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

--- Number of certificates the worker currently holds.
function FarmHandWorker:getCertificateCount()
    local count = 0
    for _ in pairs(self.certificates) do
        count = count + 1
    end
    return count
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

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

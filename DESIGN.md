# FarmHand — Design

An employment-realism mod for Farming Simulator 25. You don't just hire a worker and pay
a worker — you take on a person, train them, and grow them. The headline idea: **one farm
hand who starts as a complete novice and, over a long save, grows into someone who can
practically run the farm.** As the farm expands you take on more people, but the original
hand grows *with* the farm — your loyal right hand.

---

## 1. Core fantasy

The spine of the mod is a single progression arc, modelled on the driver/skill progression
in Euro Truck Simulator 2:

- A hand arrives knowing almost nothing — slow, limited, cheap.
- Every job they do makes them better at it.
- You invest farm money to put them through formal courses that unlock new kinds of work.
- Years later that same hand is ticketed for everything and highly skilled across the board.

The single-hand-to-master arc is the heart of the mod and the thing we balance around. A
roster of multiple workers is the *scale* layer that comes in as the farm outgrows one
person — it never replaces the spine.

---

## 2. The two-axis model (from ETS2)

ETS2 runs two different kinds of skill, and the mod copies both because they do different
jobs:

**Gated capability — "tickets".** ADR-style hard unlocks. You either can do the task or you
can't. In ETS2 you unlock ADR to be *allowed* to haul dangerous goods. Here, formal
certificates gate legal or safety-critical tasks (pesticide spraying, telehandler, livestock
handling). Earned only by completing a farm-funded course.

**Graded proficiency — "specialisations".** The skills that just make you better and faster
the more you do them (ETS2's Long Distance, Eco, High Value). Here, per-task specialisation
levels that climb with experience and affect work speed and quality.

These two axes are kept **separate** and must never be merged. A pesticide ticket is a
binary legal gate; how *good* a hand is at spraying is a different thing. You need the ticket
to spray at all, and experience makes you faster at it.

---

## 3. Specialisations (the proficiency axis)

Each hand holds **every** specialisation at some level. Roughly 5–8 task domains:

- Animal care
- Milking
- Ground work
- Harvesting
- Carting
- Yield improvement
- Grasswork

(Final list to be settled during build.)

**Levels.** Each specialisation is graded **A / B / C** (stored internally as 1–3 so it can
extend later). Level sets how well the hand performs that task:

- Level C — ~30% slower
- Level B — ~10% slower
- Level A — full speed

(All percentages are first-pass and settings-tunable.)

So you *can* send an animal-care hand to do field work or carting — it just won't be optimal.
Optionally, a job can be blocked outright if the only available hand is level C for it.

**Rarity / distribution.** Generic skills (carting, grasswork, ground work) are commonly held
at A/B by most hands. The rarer skills (animal care, milking, yield improvement) are harder
to find and **don't usually combine** with harvesting or yield in the same hand. This rarity
rule is the balancing lever: it's what stops a single hand from trivially becoming A-grade at
everything, and it's what eventually forces you to build a team.

---

## 4. Certificates & courses (the gated axis)

Formal tickets gate the legal/safety-critical tasks. A hand earns a ticket by being enrolled
on a course:

- **Courses cost the farm money** — tuition, paid when you enrol the hand. This is the ETS2
  "spend a hard-won perk point" beat: training is a real investment decision, not free.
- **Courses cost time** — progress accrues on the in-game month rollover.
- On-the-job: a month only counts toward the course if the hand actually worked that month
  *(planned — depends on work-detection)*.
- On completion, the ticket is granted and the matching gate opens.

Example ladder (maps to real UK qualifications): pesticide ticket → telehandler ticket →
Level 2 general farm worker → Level 3 technician → Level 4/5 manager (can supervise others).

---

## 5. Experience & "learn from the master"

Proficiency rises two ways:

- **By doing the job.** Working a specialisation raises its level over time (tied to work
  done — hectares).
- **Learn from the master.** Flag a hand to "learn", and jobs *you* (the player) do yourself
  raise that hand's specialisation levels (e.g. +0.1 per in-game hour). You still pay the
  hand while they learn.

Experience also drives **equipment wear**: a green hand is hard on machinery (~1.75× wear),
curving down to ~0.9× for a veteran. The curve is front-loaded so the first improvements
feel meaningful.

---

## 6. Employment & the UK employment-law layer (the terms)

The contract is the object the rest of the mod hangs off. Each hand has one: type, fee, start
date, notice period, holiday.

**Contract types / periods**, chosen at hire:

- **Permanent** — loyal and stable, but full statutory rights, notice, and redundancy exposure.
- **Fixed-term / seasonal** — ends on its own (e.g. a 3-month harvest contract); mirrors real
  seasonal agricultural labour.
- **Monthly** — rolling, constant monthly cost.
- **Single job** — basegame hourly behaviour, paid per job. (Not strictly limited to one job.)

Longer commitment buys a cheaper rate but locks in a constant monthly cost.

**Payment.** The monthly fee is paid at the end of the month as a lump sum. The mod
**suppresses the basegame helper pay (sets it to 0)** and charges its own fee instead — no
double-charging. Wages scale with certificates/skill, so a trained hand costs more.

**Legal wage floor.** A hand can't be paid below the age-banded UK minimum (real rates, from
April 2026: £12.71/hr for 21+, £10.85 for 18–20, £8.00 for under-18s and apprentices). A hand
on a course is an apprentice on the lower rate, moving to their age rate once qualified. If the
farm houses the worker, an accommodation offset (£11.10/day) can count toward the minimum.

**True cost of employment.** The headline wage understates the real cost. On top sit
employer National Insurance, pension auto-enrolment, holiday accrual (5.6 weeks), and SSP.
A hand costs noticeably more than their gross pay.

**Rights accrue with service.** Statutory notice grows with tenure; unfair-dismissal
protection applies after a qualifying period (two years now, dropping to six months from
January 2027); redundancy pay after two years. Firing a long-serving, trained hand costs
notice, process, and potentially redundancy — the stick that makes retention matter.

**Compliance.** Paying below the minimum or breaking the rules makes you non-compliant
(Fair Work Agency enforcement, fines) — natural synergy with the Red Tape mod. The 2026→2027
legal transition can be a flavour hook.

---

## 7. Job assignment

Start a job from the worker menu: pick a worker, then choose how they run it.

- **AI Worker job (basegame)** — the first and primary integration target. The basegame AI
  worker menu behaves as normal, but the mod is aware of the worker's properties.
- **Courseplay job** — same idea, but Courseplay is a large separate mod with its own API.
  Treated as a later stretch, not a launch requirement.

When a job starts, the mod applies the worker's properties: **gate** it if the worker lacks
the required ticket, and apply the **speed penalty** for their specialisation level. Using the
wrong specialist works but is slower.

---

## 8. Animal productivity from the roster (systemic — later module)

Husbandry output scales with the best available animal-care specialisation across the whole
roster, not a single assigned job:

- No animal-care hand — productivity −30%
- At least one at level C — −20%
- At least one at level B — −10%
- At least one at level A — full productivity (if feed is optimal)

Milk production is tied to the Milking specialisation the same way. This is a bigger,
passive, farm-wide system than "a worker does a job", so it's built as its own module.

---

## 9. Single hand vs roster — reconciliation

The single-hand-to-master arc is the core. The roster is the scale layer. They coexist because:

- Rare specialisations don't combine well in one hand.
- A hand doing a field job can't simultaneously be milking — one person can't be everywhere.
- So one novice carries the early and mid game, but a growing farm eventually forces a team.

Balance follows from treating the single hand as the spine: it sets how fast proficiency
should climb and whether to cap how many top tickets one hand can hold.

---

## 10. Status

**Built & committed**

- Pesticides certificate gate — blocks an uncertified active hand from herbicide spraying.
- Farm Hands roster panel (key K) with active-hand selection.
- On-the-job course training — monthly progression that grants the cert on completion.
- Monthly wages scaled by certificates (base + per-certificate premium).
- Real mod icon (256×256 DXT5).

**Planned (this document)**

- Specialisation data model (A/B/C per task) + speed effect on AI jobs.
- Course tuition cost (the farm pays to enrol) — the missing ETS2 investment beat.
- Contract types/periods + suppression of basegame helper pay.
- Experience→wear curve + work-detection (also unlocks the deferred "month only counts if he
  worked" course condition).
- Learn-from-the-master training route.
- Leave-risk / retention (a trained, underpaid hand may quit, losing in-progress course work).
- True-cost employer on-costs + legal wage floor + compliance.
- Animal-productivity-from-roster module.
- Courseplay integration (stretch).

---

## 11. Suggested build order

1. **Specialisation model + AI-job speed effect** — generalises the gate and the experience
   idea in one slice.
2. **Course tuition cost** — small, and lands the ETS2 investment beat.
3. **Contract types/periods + suppress basegame pay** — completes the wages/contract layer.
4. **Experience→wear + work-detection.**
5. **Learn from the master.**
6. **Leave-risk / retention.**
7. **True-cost on-costs + wage floor + compliance.**
8. **Animal-productivity-from-roster.**
9. **Courseplay integration** (stretch).

---

## 12. Implementation notes & risks

- **Courseplay integration is a large dependency** with its own API. The basegame AI worker
  is the tractable target and is what the certificate gate already hooks. Build everything on
  AI-worker first; treat Courseplay as a later stretch.
- **The "throttle vehicle power to slow a worker" approach needs a prototype spike.** Changing
  motor/power can affect AI pathing, fuel use, and basegame compensation. Prefer a cleaner
  helper-speed hook if one exists; prove the lever before committing to it.
- The monthly tick path (`PERIOD_CHANGED → onMonthChanged`) is already wired and drives course
  training and wages; new monthly logic should hang off the same handler to avoid double-firing.
- **All numbers** (speed penalties, wage values, course lengths and costs, productivity steps,
  wear curve) are first-pass and exposed as tunable settings.

---

## 13. Conventions

- Keep the two axes distinct: **certificates/tickets = legal gates; specialisations =
  proficiency.** Never merge them.
- The single hand who grows with the farm is the spine. Every system should serve that arc
  first and the roster second.

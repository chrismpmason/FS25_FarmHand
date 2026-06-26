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

### Machinery-ticket research (planned)

UK reality is tickets, not degrees — and most fieldwork needs none. Three bands:

- **No ticket legally required** for tractor/combine fieldwork on private land — the bulk of the
  work. A hand can do it green; experience (tiers) makes them better, but nothing gates it.
- **Competence tickets expected** for telehandler / ATV / chainsaw (LANTRA / NPORS). Not a legal
  licence — insurance- and employer-driven — but the real-world norm. Model as skilled tickets.
- **Legally mandatory** PA1 + PA2 (boom) / PA6 (knapsack) for spraying — already the pesticide
  gate, the only hard legal block.

Intent: a skilled ticket lifts a hand into a higher pay grade (ties into the grade model in §6);
most fieldwork needs none, so the ungated baseline stays the common case.

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

### Experience → wear: ADS integration — IMPLEMENTED (6dd52c2)

Experience-to-wear routes through ADS when present, via a per-vehicle override. We write none
of ADS's fields — one-owner respected.

- Detection: FarmHandWear.adsPresent = g_modIsLoaded["FS25_AdvancedDamageSystem"], checked at
  mission start (onMissionLoad). (g_modIsLoaded is a TABLE, indexed not called.)
- Override: at job start, each combination vehicle that has updateSystemConditionAndStress
  gets an INSTANCE-level shadow of that function (guarded), scaling the wearRate argument by
  the active hand's experience factor (~x1.75 green … x0.9 veteran) before deferring to the
  saved original. ADS's own calc then drives condition, stress and breakdowns off the scaled
  input. Removed at job end.
- Why per-instance, NOT a class-level wrap: vehicle types finalize ("Loaded vehicle types")
  BEFORE FarmHand's mod loads, so ADS has already captured
  AdvancedDamageSystem.updateSystemConditionAndStress into the types before our code exists —
  a class-level wrap can never win that race. Instance-field shadowing is timing-independent.
  Do not re-attempt the class-wrap.
- extraConditionWear is ADS-owned (breakdown effects write/reset it) — left untouched.
- Without ADS: vanilla applyToCombination path, unchanged.

### Experience tiers — IMPLEMENTED (8393388)

Three proficiency tiers — Novice / Experienced / Master — computed from the single experience
value (hectaresWorked), never persisted. Thresholds TIER_EXP_EXPERIENCED = 50 ha,
TIER_EXP_MASTER = 400 ha — a long-but-achievable grind at the ~1 XP/hectare-swept accrual rate.
getTier / getTierName / getTierProgress drive the K-panel display and the work-speed lever.

- Tier (proficiency) and grade (pay) are DELIBERATELY distinct axes reading the same XP value:
  tier thresholds 50/400 vs grade thresholds 50/200. They must never collapse into one number —
  proficiency makes a hand faster, grade sets what they cost.

### Proficiency → work speed — IMPLEMENTED (8d5ad47)

A Novice works a field slower than a Master. Per-instance wrap on the ROOT vehicle's
getSpeedLimit, scaling the returned limit by TIER_SPEED_FACTOR {0.6 / 0.8 / 1.0}
(Novice/Experienced/Master). Applied at job start, removed at job end — restoring the CAPTURED
ORIGINAL, not nil (the ADS cleanup lesson). Reuses the ADS per-instance override pattern.

Two load-bearing decisions — do not undo:

- **Root-only.** The root's getSpeedLimit already aggregates attached tools' working limits (min);
  wrapping implements too would re-scale an already-scaled child value (factor^2).
- **Working-only gate.** Scaling is gated on getIsFieldWorkActive(), so only the working passes
  slow — headland turns / transit return the transport limit and stay full speed. This protects
  the fragile headland turning we already saw vanilla AI struggle with.
- As with ADS, this MUST be a per-instance override, not a class-level wrap (same load-order race).
  Do not re-attempt the class-wrap.

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

### Wage realism: UK farm-pay grounding

The current model (flat £2,000/month base + £500/cert) is a believable average but isn't
anchored to the real UK floor, and the per-cert structure isn't how UK ag pay works.

- **Legal floor:** April 2026 National Minimum Wage is £12.71/hr (21+). At the agricultural
  standard 39-hour week, a full-time adult hand can't lawfully earn below ~£25,800/yr
  (~£2,150/month). The current £2,000 base sits just under that. Peg the floor to the real
  NMW, not a round number.
- **Typical actual pay:** UK farm workers average ~£22k–£27k/yr (Indeed ~£27.3k; Glassdoor
  ~£22.4k farm / ~£23.5k agriculture), ranging ~£19k entry to ~£31–33k experienced. The base
  figure is roughly right; it's the floor and structure that need work.
- **Structure — grade by role, not flat-per-cert:** real ag pay is set by job grade, role and
  experience. A certificate should unlock a higher-paying role/grade rather than apply a fixed
  monthly top-up.
- **England vs graded nations:** England abolished its Agricultural Wages Board (2013), so
  English workers are on plain NMW (our baseline — Chris is England-based). Wales/Scotland/NI
  keep graded Agricultural Minimum Wage boards above NMW. Modelling the graded system is
  optional depth.
- **Ag-specific extras (optional realism layer):** night-work premium (7pm–6am), weekly
  allowance per working dog kept, accommodation offset if housed, on-call allowance,
  apprentice rates pegged to a grade, agricultural sick pay at the minimum wage.

### Grade-based wages + NMW floor — IMPLEMENTED (c3ca7a6)

Replaces the old flat base + £500/cert with grade-based pay, building on the wage-realism
grounding above. Grade (1-4: Trainee / Farm worker / Skilled operator / Senior hand) is COMPUTED
from certs + experience each pay tick, never persisted: a skilled certificate gates the skilled
grades 3-4; experience promotes within a tier. Monthly wage = grade rate {2150/2250/2450/2650},
floored at the legal NMW minimum (nmwHourly × weeklyHours × 52 / 12 ≈ £2,148). Surfaces on the
hired-labour (Wages) finance line via MoneyType.AI, guarded by the true-cost passthrough so the
salary itself is never suppressed. Leave-risk benchmark repointed at the grade rate — plumbing
for negotiations; no underpay-quit fires until an offered wage can fall below it.

### Wage = true cost of employment — IMPLEMENTED (7e6886d)

The monthly salary is now the only labour cost for a hand's work. An addMoney override
suppresses the vanilla helper charge (MoneyType.AI) while a FarmHand job runs on the player's
farm, so the player no longer double-pays (salary + per-job fee). Gated by the
salaryReplacesHelperCost setting (default ON), a per-job counter (incremented on job start,
cleared on stop/delete), and a passthrough guard on the mod's own money ops. Realises the
"true cost of employment" pillar: you pay a salary, not a per-job fee.

### Wage negotiations (planned)

Pay isn't fixed by the game — the player sets it, and it should matter. A negotiation beat at
hire (and for retention): the offered wage interacts with leave-risk (underpay raises quit
chance) and candidate willingness. Grounds the loop in a real decision rather than a fixed
cost.

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

## 10. Panel UI: full-screen tabbed shell (PLANNED — build 2, before College)

The current K panel is a small 5-row dialog with a Hands/Hire mode toggle. It's at capacity —
tier+grade+wage already crowd one cell, and College has no home in it. Replace it with a
full-screen frame with left-hand nav tabs swapping content panes. This is a REBUILD of the
presentation layer, not a tweak — new frame architecture, tab switching, and porting each
existing view across. All manager logic (roster, hiring, wages, tiers, dismiss, persistence)
stays unchanged — this is pure presentation, so layout risk only, no data risk.

Tabs:

- **Roster** — employed crew: select active, dismiss, per-hand tier/grade/wage/experience
  (today's Hands view).
- **Hire** — the candidate pool (tiered random hiring), with room to show each candidate's
  tier/grade/wage properly instead of cramped rows.
- **College** — enrol hands on courses, tuition, who's training and time remaining. The build-2
  College feature lives here; full design in §11 (the shell is what gives College its UI real estate).
- **Overview / Stats** — company dashboard: total monthly payroll, headcount, active vs idle vs
  currently-working, certified count, courses in progress. The ETS2 "company manager" feel —
  turns the panel from "manage one hand" into "run a workforce".

Build approach (de-risked, given the GUI fragility this project has hit — footer reflow, dialog
stacking, button registration):

- Build the EMPTY shell first: full-screen frame + left tabs switching between blank panes.
  Verify it renders and switches cleanly BEFORE porting any content.
- Then port each existing view (Roster, Hire) into its tab one at a time, verifying each.
- Incremental, not big-bang. No manager/logic changes.

Sequencing: this is the OPENING move of build 2 — build the shell first, then build College INTO
it as a tab (rather than cramming College into the old toggle and rebuilding around it later).
Do not start until tiered random hiring is committed and the current test build's feedback is in.

---

## 11. College / training — IN DESIGN (learn-on-the-job model)

Turns the existing course scaffolding (enrol, monthly advance, completion cert-grant, persistence
— **all already built**) into a player-facing progression feature: a course catalogue, tuition,
operation-specific boosts, and the College tab UI. The shell (§10) is what gives it the screen
real estate.

**Study model — LEARN-ON-THE-JOB (decided).** A hand enrolled on a course keeps working; the
course advances each month the hand actually worked (`workedThisMonth` — the existing
`advanceCourses` rule). The cost of training is **tuition (money) + time (N months)** — never lost
labour. (Released-to-study — the hand benched while training — is a possible v2 depth upgrade,
deliberately not v1: it would mean undoing the working logic and reintroducing a lockout.)

**Course catalogue (5).** All tuition/duration values are tunable constants.

- **Spray** *(GATE — already built)* — grants the PESTICIDES cert; required to apply herbicide.
  Tuition £800, 3 months.
- **Combine** *(BOOST)* — grants COMBINE cert; faster + gentler when harvesting. £600, 3 months.
- **Seeder** *(BOOST)* — SEEDER cert; faster + gentler when seed drilling. £600, 3 months.
- **Slurry & Fertiliser** *(BOOST)* — FERTILISER cert; faster + gentler when fertilising/slurry.
  £600, 3 months.
- **Forage** *(BOOST)* — FORAGE cert; faster + gentler when mowing/tedding/baling. £600, 3 months.

**Gate vs boost (the hybrid).**

- **GATE** — can't do the operation at all without the cert (spray/herbicide — legal; already
  implemented via `FarmHandGate`).
- **BOOST** — can do it untrained, but the cert makes the hand faster + gentler on kit for *that*
  operation (and contributes to pay grade). Never locks the player out of farming.

**Operation detection** *(feasible — per the College audit).* Reuse `FarmHandGate`'s
spec-inspection: walk the implement combination and identify the operation by specialisation —
`spec_combine`/cutter = harvest, `spec_sowingMachine`/planter = seed,
`spec_mower`/`spec_tedder`/`spec_windrower`/`spec_baler` = forage, `spec_sprayer` + fill type =
spray vs fertiliser/slurry. The spray↔fertiliser split is fill-type-driven (already handled in the
gate).

**Boost application.** At `FarmHand.onAIJobStart` — where the speed + ADS-wear overrides already
install — detect the operation, check whether the active hand holds the matching course cert, and
if so apply a boost factor (~+15% speed, ~−15% wear, tunable) *on top of* the tier factor. Removed
at job end like the existing overrides. Boost surface = **speed + wear only** (quality/waste levers
aren't hooked in the engine — out of scope).

**Tuition.** A one-off fee deducted on enrolment via the proven `addMoney` path (same as
`payWages`, with the passthrough flag). Block enrolment if farm funds are insufficient (confirm the
farm-balance accessor in-game at build time — a one-liner).

**Completion.** `advanceCourses` already grants the cert on completion; **add** a small XP bonus
(~+25 ha to `hectaresWorked`, tunable) in the completion branch.

**New cert types needed.** COMBINE, SEEDER, FERTILISER, FORAGE — currently only PESTICIDES exists.
Extend the `FarmHandCertificate` definitions.

**College tab UI** (the shell's College pane). List employees with course status — "Studying:
{course} ({n}/{len} mo)" if enrolled, or an **Enrol** action if not. Enrol flow: pick a hand →
pick a course (showing tuition) → confirm (with cost) → deduct tuition → enrol. Show the course
catalogue + costs.

**Dropped — Road/Towing course.** Road transport is AutoDrive/Courseplay, not hookable via
FarmHand's field-work hooks (`AIJobFieldWork:validate` / `AIFieldWorker.updateAIFieldWorker`).

**Build slices (proposed).**

- **Slice A** *(vertical loop, low risk)* — College tab UI + tuition deduction + completion XP,
  using the EXISTING fully-built pesticide course. Proves enrol → study → complete → cert
  end-to-end with real UI + money.
- **Slice B** *(the boost courses)* — add the 4 new cert types + operation detection + speed/wear
  boosts.

---

## 12. Status

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

## 13. Suggested build order

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

## 14. Implementation notes & risks

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

## 15. Conventions

- Keep the two axes distinct: **certificates/tickets = legal gates; specialisations =
  proficiency.** Never merge them.
- The single hand who grows with the farm is the spine. Every system should serve that arc
  first and the roster second.
- **One owner per datum.** Every piece of state has exactly one authoritative owner; two
  systems must never both write the same datum. The ADS/wear conflict is the live example —
  when ADS owns wear, FarmHand must not also write it. Governs all integration and
  persistence work.

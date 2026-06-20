# FarmHand — Design Notes

A farm-worker employment mod for Farming Simulator 25. You hire farm hands who
start near-useless and get better over time through two independent means:
hands-on experience and formal training. Wages are realistic and recurring, so
keeping a good worker is a genuine cost/benefit decision.

These notes are the source of truth for behaviour. Build against them. Numbers
are starting points and are expected to be tuned in play-testing; where a value
is player-facing it should be exposed as a settings multiplier (see Settings).

---

## 1. Candidates and hiring

- There is always a small **pool of candidates** available to hire.
- The pool **refreshes each in-game month**: old candidates are replaced with a
  freshly generated set (an employed worker is never in the pool).
- Each candidate has:
  - a **name**,
  - a **low starting experience level** (see Experience below),
  - a **monthly wage**,
  - a one-off **signing cost** paid at the moment of hire.
- Hiring moves a candidate out of the pool and onto the farm's roster of
  employed workers.

## 2. Progression — two tracks that do NOT overlap

The mod deliberately separates *how well* a worker does a job from *what jobs*
he is permitted to do. These never feed into each other.

### Track A — Experience (how WELL)

- Measures competence at the tasks the worker is already allowed to do.
- Builds **automatically from work done**, measured in **hectares worked**.
- Curve: **fast early gains, then a plateau** (diminishing returns). A worker
  improves quickly out of the gate and slowly thereafter.
- Primary effect is **equipment wear**:
  - A green (zero-experience) worker causes roughly **1.75x** normal wear.
  - This curves down toward roughly **0.9x** as he becomes experienced.
- Secondary, smaller effects from the same experience value:
  - slight **fuel-use** modifier,
  - slight **work-speed** modifier.
- Experience is a continuous value driven by cumulative hectares; the wear /
  fuel / speed modifiers are all derived from it.

### Track B — Courses / Qualifications (WHAT)

- Determine **which task types** a worker may be assigned.
- A worker **cannot be assigned a task he is not qualified for** — e.g. he
  cannot take the sprayer until he holds a **pesticides certificate**.
- Courses **cost money** and **take time**.
- Training is **on-the-job**:
  - the worker **stays on the farm working** for the whole course,
  - his course **advances by one month per in-game month**,
  - but a month **only counts if he actually did work that month** (idle months
    do not progress the course).
- Course length is in in-game months and is scaled by a settings multiplier.

## 3. Wages and retention

- **Wages are paid monthly** for every employed worker, on the month rollover.
- **Retention**: trained / experienced workers become more valuable. A worker
  **may leave if underpaid** relative to his value (a per-month leave-risk check).
- If a worker **leaves mid-course, his course progress is lost**.

## 4. The month tick

Everything is driven off the **in-game month rollover**. On each rollover, in a
defined order:

1. **Course progress** — advance each in-training worker by one month, but only
   if he worked at all during the month just ended.
2. **Experience tally** — fold the month's hectares into each worker's
   experience value.
3. **Wages** — debit the farm for each employed worker's monthly wage.
4. **Retention check** — for each worker, roll the leave-risk; departures take
   effect now (losing any in-progress course).
5. **Candidate-pool refresh** — regenerate the hire pool.

(Order matters: a worker is paid and progresses for the month he just completed
before we test whether he leaves.)

## 5. Settings (player-configurable)

All multipliers default to 1.0 and are exposed in the in-game settings UI.

- **Course-duration multiplier** (required) — scales how many in-game months a
  course takes.
- Further multipliers expected later: wage multiplier, wear-curve strength,
  experience-gain rate, leave-risk strength.

---

## Minimum first version (build target)

The first working slice should implement, end to end:

1. A **pesticides certificate** course that **gates spraying** (sprayer cannot
   be assigned without it).
2. The **experience-to-wear curve** (~1.75x green → ~0.9x experienced), driven
   by hectares worked.
3. **On-the-job, month-tick training** (one month per worked in-game month).
4. **Monthly wages**.
5. A **basic leave-risk** check on the month tick.

Everything else (full course catalogue, fuel/speed modifiers, richer retention,
additional settings) comes after this slice works.

---

## Implementation notes (verified against the FS25 script API)

These were confirmed from the real API (working mods + the FS25 script source),
not assumed. The base game scripts ship encrypted, so verification was done
against shipping mods and public script mirrors.

### Worker assignment model (Option A, lightweight)

The game's "Hire assistant" spawns an anonymous helper; the AI job only learns
which helper it is inside `start()` (`self.helperIndex = helper.index`), **not**
at validation time. So the gate cannot ask the job "whose certificate?". Instead
the mod keeps a single **active hand** (`FarmHandManager:getActiveHand()`), and
the gate checks that hand. Proper per-vehicle hand selection is a later slice.

### Pesticides gate

- **Hook:** overwrite `AIJobFieldWork:validate(farmId)`, which returns
  `(isValid, errorMessage)`. Call the original; if still valid, apply the check
  and, to block, return `false, "<reason>"` — the UI shows that string.
- **Scope decision: gate the activity, not the machine.** The `Sprayer`
  specialization (work-area type `SPRAYER`) is shared by herbicide sprayers,
  liquid-fertilizer sprayers, granular fertilizer spreaders and lime spreaders.
  The pesticides certificate gates **only herbicide application** — detected
  from the sprayer tank's current **fill type** (see below), mapped to a
  spray-type descriptor whose `.isHerbicide` is true. Fertilizing, liquid
  fertilizing and liming stay open
  and can get their own certificates later. Mechanical weeders and salt
  spreaders are separate work-area types and are unaffected.

### Confirmed API surface

- Month tick: `g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, ...)`.
- Named-helper roster: `g_helperManager` (`addHelper`, `getHelperByName`,
  `availableHelpers`), `g_currentMission.maxNumHirables`.
- Per-vehicle AI worker context: `AIFieldWorker` spec, `updateAIFieldWorker`,
  `self.spec_aiFieldWorker`, `self:getIsFieldWorkActive()` (for later wear/speed).
- Spray types: `g_sprayTypeManager.sprayTypes[SprayType.HERBICIDE | FERTILIZER |
  LIQUIDFERTILIZER | LIME]`.
- Vehicle from a job: `self.vehicleParameter:getVehicle()` (inside validate).
- Reaching the sprayer: `vehicle:getAttachedImplements()` (entries have
  `.object`; recurse for the whole combination), plus the vehicle itself for
  self-propelled sprayers.
- Spray type from tank contents (works at validate time, unlike
  `getActiveSprayType()` which is nil until the job is actually working): read
  the sprayer's fill unit via
  `getFillUnitLastValidFillType(getSprayerFillUnitIndex())` (fall back to
  `getFillUnitFirstSupportedFillType` when the tank is empty), then
  `g_sprayTypeManager:getSprayTypeByFillTypeIndex(fillType)` → descriptor with
  `.index` and `.isHerbicide`.
- Hooking idiom: `Utils.overwrittenFunction / appendedFunction / prependedFunction`.

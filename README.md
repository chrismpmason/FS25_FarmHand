# FarmHand

Employment realism for Farming Simulator 25. Your hired hands aren't interchangeable helpers — they have names, experience, qualifications, and a real wage. You build a roster, send them to college, train them up, pay them, and let them go when you need to.

## Requirements
- Farming Simulator 25, PC.
- **Single-player only** for this build — don't load it in multiplayer; worker/wage/experience state isn't MP-synced yet.
- Optional: **Advanced Damage System**. If installed, a hand's experience affects machinery wear and breakdowns. Without it, FarmHand runs fine on vanilla wear.

## Install
1. Drop `FS25_FarmHand.zip` into your mods folder.
2. Enable it when starting or loading a save.

## The panel
Press **K** to open the FarmHand panel. It has four tabs:

- **Employees** — your roster. Select a hand to make them **active** (the one who does the work), or **Dismiss** them (with confirmation) to take them off the roster and payroll. Dismissing permanently loses that hand's experience, certs and course progress.
- **Hire** — a rotating pool of named candidates that refreshes each month. Most start green, but the occasional candidate arrives already experienced or qualified, so hiring is a build-vs-buy choice.
- **College** — enrol a hand on a training course (see below).
- **Overview** — a workforce dashboard: your hands, their tiers, grades and wages at a glance.

## How it works
- **Put a hand to work** — select a hand in Employees to make them active, then start a worker job as normal (hold **H**). The active hand does the work, with their own named driver in the cab.
- **Experience** builds with hectares worked, moving a hand through tiers: **Novice → Experienced → Master**. Higher tiers work **faster** — a Novice is noticeably slower than a Master.
- **Pay grade** is a separate axis from tier: hands sit in pay grades (Trainee → Senior hand), floored at the real UK minimum wage, rising with experience and qualifications.
- **Milestones notify you** — a hand pops an on-screen message when they reach a new tier or qualify from a course, so you don't have to watch the panel.
- **Wage = true cost** — while a hand works, the vanilla per-job helper fee is suppressed; instead each hand draws a monthly salary, shown on the hired-labour (Wages) line in Finances. Hands are paid whether they work or not — so don't over-hire, and dismiss the ones you don't need.

## College & qualifications
Enrol a hand from the **College** tab. Each course charges a one-off tuition up front and takes about three in-game months of *worked* time — a hand only makes progress in months they actually do work, and an idle hand's course stalls until they're back on the job. On completion the hand earns the qualification (plus a small experience bonus). One course at a time per hand; finish one to start another.

| Course | Qualifies for | Tuition |
| --- | --- | --- |
| Spraying | Applying herbicide (**required** — see below) | £800 |
| Combine | Harvesting | £700 |
| Slurry & Fertiliser | Fertilising & slurry | £600 |
| Seeder | Sowing & planting | £500 |
| Forage | Mowing, tedding, raking, baling | £450 |

- **Spraying is a gate.** Applying herbicide needs the Spraying qualification — a hand without it can't be sent to spray weed killer. Fertilising, liquid fertilising and liming are open to any hand.
- **The other four are boosts.** Any hand can harvest, sow, fertilise or do forage work untrained, but a hand who holds the matching qualification does that job **faster and with less machinery wear**. Training pays off on the operations you run most.

## Courseplay
FarmHand now works with **Courseplay** field jobs, not just the base-game helper. Start a CP field-work course with a hand active and that hand does the work: they **earn experience** (hectares worked), apply their **tier speed effect** and **wear behaviour**, and appear as the **named driver** in the cab — the same as a vanilla worker job.

- **Speed on Courseplay — read this.** The tier **penalty** and the wear/experience effects apply fully on CP: a Novice really does drive a CP course slower, and every hand levels up and scales wear as usual. The certificate **speed bonus**, however, **defers to your Courseplay field-speed setting** — CP caps the vehicle at the speed you set, so a certified hand can't push past it. So a certified hand still helps (less wear, still earning experience) and is never *slower* for the cert, but CP's own speed setting, not the cert, sets the top speed. Raise CP's field speed if you want a certified hand to run faster.
- **With a hand active, FarmHand governs the job** — including the gates. Sending a hand to spray **herbicide** on a CP job requires the **Spraying** qualification, exactly as on a vanilla job; an uncertified hand is refused before the job starts, with a message. Fertilising, liquid fertilising and liming stay open.
- **With no hand active, FarmHand defers entirely** — the CP job runs untouched: no attribution, no speed/wear change, no gate. FarmHand only ever steps in when one of your hands is the one doing the work.
- **AutoDrive is not integrated** in this build. AutoDrive handles transport driving rather than field work, so hands don't yet earn or gate on AD routes. Planned for a later build.

## Settings — the wear toggle
FarmHand writes a settings file the first time you run it:

```
…\Documents\My Games\FarmingSimulator2025\modSettings\FS25_FarmHand.xml
```

The one setting exposed there is the **experience-to-wear** switch:

```xml
<farmHand>
    <experienceWearEnabled>true</experienceWearEnabled>
</farmHand>
```

- **`true`** (default) — a hand's experience scales machinery wear: green hands are hard on equipment (~1.75×), veterans easy on it (~0.9×). With Advanced Damage System installed this drives breakdowns too.
- **`false`** — FarmHand installs **no** wear override at all; ADS / vanilla wear behave exactly as they would without the mod. Everything else (speed, wages, training, hiring) is unaffected. For players on hard-wear setups who don't want green hands punished on machinery.

Edit the value, save the file, and restart the game (or reload a save) for it to take effect. Turning it off writes none of ADS's own fields, so it can't corrupt a save — it just stops the scaling.

## Known issues (not FarmHand)
- **"No field detected for preview"** / a worker stalling at the headland is a base-game FS25 bug (common on Riverbend Springs, reproducible with all mods off). Park fully inside the field, detach/reattach the implement, or restart the game. Courseplay sidesteps it.
- **Other hired-helper mods** — FarmHand manages your hired workers directly, so running it alongside another helper-management mod (for example HiredHelperTool) can stop a worker from starting. Run only one helper manager at a time; if a hand won't begin a job, disable the others and reload.

## Feedback I'm after
- Did it install and load cleanly on your map + mod setup?
- Any crashes or errors? Send your `log.txt`.
- Is the hire → train → work → experience → wage → dismiss loop clear and worth using?
- What's confusing or missing?

Found a bug or have feedback? Open an issue: https://github.com/chrismpmason/FS25_FarmHand/issues

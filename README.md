# FarmHand

Employment realism for Farming Simulator 25. Your hired hands aren't interchangeable helpers — they have names, experience, qualifications, and a real wage. You build a roster, train them up, pay them, and let them go when you need to.

## Requirements
- Farming Simulator 25, PC.
- **Single-player only** for this test build — don't load it in multiplayer; worker/wage/experience state isn't MP-synced yet.
- Optional: **Advanced Damage System**. If installed, a hand's experience affects machinery wear and breakdowns. Without it, FarmHand runs fine on vanilla wear.

## Install
1. Drop `FS25_FarmHand.zip` into your mods folder.
2. Enable it when starting or loading a save.

## How it works
- Press **K** to open the FarmHand panel.
- **Hire** — in the Hire view, pick from a rotating pool of named candidates (refreshes monthly). Each starts as a Trainee.
- **Dismiss** — in the Hands view, select a hand and use Dismiss (with confirmation) to take them off the roster and off payroll. This permanently loses that hand's experience, certs and course progress.
- **Put a hand to work** — select a hand to make them active, then start a worker job as normal (hold H). The active hand does the work, with their own named driver in the cab.
- **Experience** builds with hectares worked, moving a hand through tiers: **Novice → Experienced → Master**. Higher tiers work **faster** — a Novice is noticeably slower than a Master.
- **Pay grade** is a separate axis from tier: hands sit in pay grades (Trainee → Senior hand), floored at the real UK minimum wage, rising with experience and qualifications.
- **Certs** — applying herbicide needs the pesticide qualification; a hand without it can't be sent to spray weed killer. Fertilising, liquid fertilising and liming are open to any hand.
- **Wage = true cost** — while a hand works, the vanilla per-job helper fee is suppressed; instead each hand draws a monthly salary, shown on the hired-labour (Wages) line in Finances. Hands are paid whether they work or not — so don't over-hire, and dismiss the ones you don't need.

## Known issues (not FarmHand)
- **"No field detected for preview"** / a worker stalling at the headland is a base-game FS25 bug (common on Riverbend Springs, reproducible with all mods off). Park fully inside the field, detach/reattach the implement, or restart the game. Courseplay sidesteps it.
- **Other hired-helper mods** — FarmHand manages your hired workers directly, so running it alongside another helper-management mod (for example HiredHelperTool) can stop a worker from starting. Run only one helper manager at a time; if a hand won't begin a job, disable the others and reload.

## Feedback I'm after
- Did it install and load cleanly on your map + mod setup?
- Any crashes or errors? Send your `log.txt`.
- Is the hire → work → experience → wage → dismiss loop clear and worth using?
- What's confusing or missing?

Report to: [your channel here]

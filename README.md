# FarmHand

A farm-worker employment mod for Farming Simulator 25.

Hire farm hands and grow them into a capable workforce. New hands start
near-useless — they wear equipment hard and can only handle basic tasks. Two
separate paths make them better:

- **Experience** builds automatically from the work they do and steadily reduces
  the wear, fuel and time they cost you.
- **Courses** are formal, on-the-job qualifications that unlock *what* a hand is
  allowed to do — a hand cannot touch the sprayer until he has earned his
  pesticides certificate.

Wages are paid every month, and a well-trained hand who is underpaid may walk.

See [DESIGN.md](DESIGN.md) for the full behaviour specification.

## Project layout

```
modDesc.xml              FS25 mod manifest
icon_FarmHand.dds        mod icon (placeholder — see below)
scripts/
  FarmHand.lua           entry point: load order + lifecycle + month tick
  FarmHandManager.lua    state owner + month-rollover orchestration
  FarmHandSettings.lua   player-configurable multipliers
DESIGN.md                behaviour specification (source of truth)
```

## Icon

`icon_FarmHand.dds` is currently a **placeholder** and must be replaced with a
real icon before release: a **256x256 DDS** (DXT5). Author it as a PNG and
convert with the GIANTS texture tool, or any DDS exporter.

## Status

Skeleton only. The first feature slice will implement, end to end: the
pesticides certificate that gates spraying, the experience-to-wear curve,
on-the-job month-tick training, monthly wages, and a basic leave-risk.

## Author

Chris Mason

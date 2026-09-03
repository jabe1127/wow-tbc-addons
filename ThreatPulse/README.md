# ThreatPulse

Threat meter for TBC Anniversary (Interface 20505). Companion to PulseMeter and
LogLovers — runs fully standalone, lights up integration when they're present.

## What it does

- **Live threat bars** — server-exact values from `UnitDetailedThreatSituation`,
  polled 4×/sec across the group. Bars scale to the current leader.
- **Tank view** — flips (automatically, if you like) when you're tanking:
  shows who's climbing toward you, warns when someone crosses your line.
- **Time-to-pull** — footer estimate of seconds until you pass the tank, from
  your relative threat rates. Smoothed; treat it as a trend gauge.
- **Per-ability threat breakdown** — *estimated* from the combat log using
  TBC 2.4.3 threat formulas. Registers as a "Threat (est.)" mode inside
  PulseMeter when available. Estimation caveats in `ThreatValues.lua`, which is
  fully data-driven — tune any constant without touching code.
- **Warnings** — role presets (110 melee / 130 ranged) with a configurable warn
  line, plus custom raw-% thresholds. Sound, screen flash, and text splash each
  toggle independently. Edge-triggered with hysteresis, so no alert spam.

## Usage

- `/tp` — toggle the window
- `/tp options` — options panel (also: hamburger icon, or right-click menu)
- `/tp lock` — lock/unlock position
- `/tp tank` / `/tp threat` — switch views (chevrons do this too)
- `/tp test` — fire a test warning

Colors, thresholds, bar sizing: everything is in the options panel, with a live
preview strip at the top that re-renders as you change things.

## Testing offline

```
cd ThreatPulse && lua5.1 test/run.lua
```

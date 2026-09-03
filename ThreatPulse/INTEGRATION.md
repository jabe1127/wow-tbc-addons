# ThreatPulse ↔ PulseMeter / LogLovers integration contract

ThreatPulse feature-detects everything below at login (with one retry 2s
later). Missing hooks degrade gracefully to standalone behavior. Check what
attached at runtime: `/dump ThreatPulse.Integration.status`

| Hook | If present | Fallback |
|---|---|---|
| `PulseMeter.RegisterLogConsumer(fn)` | Shares one CLEU marshalling call + identical event ordering | Own CLEU frame (correct, tiny redundant marshal) |
| `PulseMeter.RegisterFightListener({onStart,onEnd})` | Segments align 1:1 with PulseMeter's group-combat-state fights, fight names stamped | Player combat state (merges multi-pull) |
| `PulseMeter.Layout.RegisterWindow(frame, opts)` | Full dock-system member (edges, size match, swap) | Free-floating drag + saved position |
| `PulseMeter.RegisterExternalMode(spec)` | "Threat (est.)" mode inside PulseMeter | Breakdown reachable via API only |

## PulseMeter-side shim (~20 lines, add next build)

```lua
-- in PulseMeter Core, after the LogLovers wrap:
local consumers = {}
function PulseMeter.RegisterLogConsumer(fn) consumers[#consumers+1] = fn end
-- inside the existing shared CLEU dispatch, after PulseMeter's own parse:
for i = 1, #consumers do consumers[i](...) end  -- same marshalled vararg

local fightListeners = {}
function PulseMeter.RegisterFightListener(l) fightListeners[#fightListeners+1] = l end
-- call l.onStart(fight)/l.onEnd(fight) where segments open/close;
-- fight = { name = "Gruul the Dragonkiller", ... }

local externalModes = {}
function PulseMeter.RegisterExternalMode(spec) externalModes[spec.id] = spec end
-- mode chip iteration includes externalModes; rendering calls:
--   spec.GetRows()      -> { {guid, name, class, threat}, ... } sorted desc
--   spec.GetDetail(guid)-> rows, total, name  (per-ability drill-down)
```

`Layout.RegisterWindow` already exists in PulseMeter's Layout.lua — ThreatPulse
calls it with `{ id = "ThreatPulse", title = "Threat", matchSize = true }`.
If the actual signature differs, adjust `Integration.lua` → `AttachDock()`.

## What ThreatPulse exposes back

- `PulseMeter.ThreatPulse` / `LogLovers.ThreatPulse` — full API handle
- `ThreatPulse.LogThreat:SourceRows(seg)` — per-source estimated threat totals
- `ThreatPulse.LogThreat:AbilityRows(seg, guid)` — per-ability rows, total, name
- `ThreatPulse.Engine` — live snapshot (`rows`, `rowCount`, `mobName`,
  `playerIsTanking`), plus `:Rate(guid)` threat/sec

# PulseMeter — TBC Anniversary Damage Meter

A full combat meter (Details/Recount style) for the TBC Anniversary client (2.5.x), with a live window edit mode and a public API for other addons to plug into.

## Install
1. Copy the `PulseMeter` folder into `World of Warcraft\_anniversary_\Interface\AddOns\`
2. Restart the client (not just /reload — new addon).
3. If the addon shows as "out of date", enable *Load out of date AddOns*, or check your exact client interface number in-game with `/dump select(4, GetBuildInfo())` and set it in `PulseMeter.toc`.

## Commands
| Command | Action |
|---|---|
| `/pm` | Open options |
| `/pm edit` | Toggle live edit mode |
| `/pm new` | Create another window |
| `/pm toggle` | Show/hide all windows |
| `/pm reset` | Wipe all data |
| `/pm deaths` | Open the log browser |
| `/pm test` | Toggle test mode (fake data) |
| `/pm mini deaths` | Spawn a mini window (also: interrupts, dispels) |
| `/pm new` | End the current fight and start a fresh segment |
| `/pm window` | Create a new meter window |
| `/pm ll on\|off` | Turn the Log Lovers bridge on or off |
| `/pm saved` | Open the saved boss fight archive |
| `/pm debug` | Print parser / feed / roster / archive diagnostics |

## Navigating a window

The title bar is a single centred header:

```
[<]        Damage Done        [>] [=]
             Gruul the Dragonkiller
```

- **`<` and `>` step through modes** without opening anything. They're drawn
  as real buttons - filled panel, border, highlight on hover - not text glyphs.
- **The mode name is centred and clickable** - it opens the mode picker.
- **The fight name sits underneath**, dim, and opens the fight picker. On a
  short title bar (or a mini window) it folds onto the same line.
- **`=` at the far right opens the control panel** - every mode as a chip,
  every fight as a chip, and the actions. Right-clicking the window opens it too.

Every icon is drawn from plain rectangles rather than font characters,
because the client's default font has no box or arrow glyphs and renders them
as an empty square.

## Docking windows

Drag a window against another in edit mode and they dock. A dock stores the
**edge** ("right" means the child sits to the right of its parent), not a
free-floating offset, so the pair stays flush when either one is resized.

**A docked child takes the parent's width and height by default**, so snapping
two windows together gives you a matched pair rather than a ragged one.

Snapping opens the **docking panel** (also on `D` in edit mode, "Docking..."
in the control panel, or the button in the options):

| Control | What it does |
|---|---|
| Placement | Re-dock to the left, right, above, or below the parent. |
| Same width / Same height | Per-pair overrides of the global default. |
| Gap | Pixels between the two windows. |
| Match now | Re-apply sizing after hand-resizing something. |
| Swap order | Exchange parent and child, keeping the pair in place. |
| Undock | Break the link and leave the window where it sits. |

The panel also lists every dock currently in play. Defaults for **new** docks
live under **Edit / Snapping** in the options; each pair can override them.

## Fights and segments

A fight closes when **nobody in your group is still in combat** - not when the
combat log goes quiet. In a raid the log never goes quiet, which is what used
to weld several boss pulls into one endless segment.

An **actual boss** dying also closes the pull promptly, so loot and rezzing
aren't tacked on. Trash never does: killing the first mob of a pack leaves the
segment open, because the next mob is already on you. A multi-mob pull is
named after the first mob with a count, e.g. `Mire Hydra +3`.

There's a hard length cap as a backstop, and `/pm new` ends the fight by hand.
All of it is tunable under **Fights & Segments**.

### What "Current" shows

"Current" means the fight in progress, and **holds the last real fight on
screen** when there isn't one. A newly opened segment does not take over the
display until it actually has data in it, so the window never blinks to empty
and back between pulls. Out-of-combat healing no longer opens a segment at all
- healers topping people up between pulls used to create and discard a
throwaway fight every few seconds, which is what made the numbers flicker.

## Saved boss fights (`/pm saved`)

Boss pulls are written to **SavedVariables** and kept until you delete them -
no matter how many fights ago, across logouts, across leaving the raid,
across dying and releasing mid-fight. Trash is never archived.

The **Saved Fights** tab groups fights into raid nights (zone + date) and
marks each one as a kill (`+`) or a wipe (`x`). Select one to see the full
summary - top damage with per-second numbers, healing, deaths, interrupts -
then:

- **Show in Window** loads it into a meter window like any other segment, so
  every mode and the spell drill-down work on it.
- **Pin** protects a fight from ever being auto-pruned.
- **Delete** removes it.

### What it costs

Live segments are fat: six keyed spell tables per actor plus a target map.
Archiving those verbatim would put megabytes of repeated key names on disk, so
fights are **compacted into positional arrays** on the way in and only
rehydrated when you actually open one - a single fight is expanded at a time.

A full 25-man boss fight with spell breakdowns lands around **25-30 KB**. At
the default cap of 60 fights that's roughly **1.5-2 MB** of SavedVariables,
which is unremarkable for an addon. Options under **Fights & Segments**:

| Setting | Effect |
|---|---|
| Fights kept before pruning | Oldest **unpinned** fight goes first. Pinned fights are never auto-removed. |
| Keep spell breakdowns | Off shrinks each fight by roughly 90% (totals only, no drill-down). |
| Spells kept per player | Top N per category; the tail is dropped. |
| Kills only | Skip wipes. |
| Only while in a raid | Ignore boss kills done outside a raid group. |

`/pm debug` prints the fight count and current size.

> WoW only writes SavedVariables to disk on logout or `/reload`. Everything
> archived during a session is safe through leaving the raid or changing zones,
> but a hard client crash loses whatever hasn't been flushed yet.

### Dying mid-fight

Corpse-running out of a raid puts every group member out of range, so the game
reports nobody in combat even though the pull is still going. A boss fight is
therefore held open much longer while you're dead (30s by default, tunable), so
a battle rez - or the raid finishing without you - still lands in **one**
segment instead of being split in half.

## Log Browser (`/pm deaths`, or Death Log in the control panel)
Three tabs - **Deaths / Interrupts / Dispels** - grouped by boss fight (full
TBC boss table built in) with a **Trash** bucket for everything else, plus an
**Other deaths** bucket so nothing is ever unreachable.

## Mini windows

Every mode in the control panel's **SHOW** grid has a small pop-out button on
its right edge. Click it and that mode opens as its own mini window - tiny
bars, same skinning, ~158px - **inheriting the fight you were looking at** and
appearing beside the window you popped it out of, stepped down so several in a
row don't land on top of each other.

Right-click a mini to close it. `/pm mini deaths|interrupts|dispels` still
works, and minis dock like any other window.

## Window linking
In edit mode, drop any window **flush against another** and they dock: dragging
the parent moves the whole stack; dragging the child away unlinks it.

## Test mode
The **Test Mode** button in options (or `/pm test`) fills every window with fake
raid data. Edit mode turns it on automatically when there's no real data.

## Pet, totem and guardian attribution

Damage from anything you summon is credited to you. That covers more than
unit-token pets, because most summons in TBC never occupy a pet frame at all:

| Class | Summons handled |
|---|---|
| Shaman | Searing / Magma / Fire Nova totems, Fire and Earth Elemental |
| Druid | Force of Nature treants |
| Warlock | Imp / Voidwalker / Succubus / Felhunter / Felguard, Infernal, Doomguard |
| Hunter | pets |
| Mage | Water Elemental |
| Priest | Shadowfiend |
| Any | engineering constructs and other guardians |

Ownership is learned from `SPELL_SUMMON` / `SPELL_CREATE`, which is the only
signal totems give, and it is followed **transitively** - Fire Elemental Totem
summons the Greater Fire Elemental, so the chain is shaman → totem → elemental
and one lookup would stop short.

Summon events are read before the group filter and before a fight exists,
because totems go down during the pull countdown.

**Nothing is ever silently dropped.** If a summon appears whose owner was never
seen - you joined mid-fight, or it is something not anticipated here - it keeps
its own row in the meter rather than being hidden, and `/pm debug` lists it
under *unattributed summons*. That list is the fastest way to spot a gap:
if your numbers disagree with Warcraft Logs, run it and see what shows up.

Also tracked: environmental damage (falling, fire, lava, slime, drowning,
fatigue) now counts toward Damage Taken, and damage taken *by* a pet rolls into
its owner when pet merging is on.

Deliberately not parsed: `SWING_DAMAGE_LANDED` (a duplicate of `SWING_DAMAGE`)
and `SPELL_ABSORBED` (partial absorbs already come from the damage event's own
absorbed field, full ones from `SPELL_MISSED`). Either would double-count.

## Parser performance

The combat log handler is the only code in this addon that runs hundreds of
times a second, so it is written to allocate nothing per event. Measured over
300,000 synthetic 25-man events:

| | before | after |
|---|---|---|
| time per event | 6.40 us | 3.36 us |
| garbage per event | 174 bytes | ~1 byte |
| garbage at 400 events/sec | ~4 MB/min | ~0 |

The garbage figure is the one that matters. Lua's collector runs on WoW's main
thread, so allocation churn shows up as frame hitches in a raid, not as a
number in a profiler. What changed:

- The two target segments (this fight, and overall) were being packed into a
  fresh `{ cur, overall }` table on every single event. That one line was most
  of the 174 bytes; it now reuses a permanent two-slot buffer.
- The death log allocated a table per incoming hit and trimmed with
  `table.remove(log, 1)` - an O(n) shift every time. It is now a real ring
  buffer over pre-allocated entries, and the display string
  ("Shadow Bolt (Gruul)") is built once on death rather than on every hit.
- Repeated `select(n, ...)` calls each walked the vararg again; each event
  family now destructures in one pass.
- `IsGroupGUID` called `next(roster)` on every lookup (twice per event) to
  detect an empty roster - now a flag maintained by the roster scan.
- Per-target damage totals were being accumulated but never read by anything.
  Off by default now (`trackTargets`).

Beyond this the returns drop off sharply - the last round of lookup hoisting
bought 5%. At 400 events/sec, 3.36 us/event is under 0.2% of one core, so CPU
time was never the real cost; the allocations were.

## Working with Log Lovers

If Log Lovers is installed, PulseMeter detects it at login and links up:

| | |
|---|---|
| **One combat log parse** | Log Lovers already reads and normalizes every event. PulseMeter taps that single stream instead of registering its own, so the log is parsed once per event rather than twice. |
| **Shared fight identity** | PulseMeter stamps its fight boundaries and zone onto the matching Log Lovers segment, so "this pull" means the same thing in both addons. |
| **Better death recaps** | Log Lovers' recap keeps full normalized events, knows the killing blow, and survives a reload. PulseMeter's Deaths tab lists those records grouped by fight; click a death once for the timeline, again to open the full Log Lovers recap. |
| **Cross-links** | The control panel gains **Combat Log** and **LL Stats** buttons. |
| **API handle** | Log Lovers receives `LogLovers.PulseMeter` - the full PulseMeter API - so it can read live rankings, DPS, and segment data. |

Toggle it with `/pm ll on|off`, or under **Fights & Segments** in the options.

### Reading PulseMeter data from Log Lovers

```lua
local PM = LogLovers.PulseMeter          -- set automatically when both load
local list, total = PM:GetRanking("current", "dps")
for i, entry in ipairs(list) do
    print(i, entry.actor.name, entry.value)
end

PM:RegisterCallback("SEGMENT_END", function(_, seg)
    print("fight over:", seg.name, "top:", PM:GetRanking(1, "damage")[1].actor.name)
end)
```

## Edit mode (`/pm edit`)## Edit mode (`/pm edit`)
- Drag windows from anywhere; corner grips resize live.
- **Magnetic snapping** to screen edges, screen center, and the edges of your other PulseMeter windows, with cyan alignment guide lines.
- **Shift** while dragging disables snap. **G** toggles a grid overlay. **Arrow keys** nudge the selected window 1px (Shift+arrows = 10px). **Esc/Enter** exits.

## Modes
Damage, DPS, Healing, Overhealing, Absorbs, Healing+Absorbs, Damage Taken, Friendly Fire, Deaths (with death recap in the tooltip), Interrupts, Dispels/Steals, CC Breaks.

> Note on absorbs: the TBC client has no `SPELL_ABSORBED` combat log event, so absorbs are reconstructed from shield casts + absorbed hits. It's a good estimate, not server-exact — every TBC-era meter has this limitation.

## Plugging in your own addon
Two options — see `API.lua` for the full surface:

**A. Read data out of PulseMeter** (PulseMeter parses the log itself):
```lua
local ranking, total = PulseMeter.API:GetRanking("current", "damage")
PulseMeter.API:RegisterCallback("SEGMENT_END", function(msg, segment)
    -- fight just ended
end)
```

**B. Your addon owns the combat log and feeds PulseMeter** (enable *External combat log feed* in `/pm` → General, or call `PulseMeter.API:SetExternalFeed(true)` on load):
```lua
-- inside your COMBAT_LOG_EVENT_UNFILTERED handler:
PulseMeter.API:FeedCLEU(CombatLogGetCurrentEventInfo())
```

You can also register entirely new meter modes from your addon with `PulseMeter.API:RegisterMode(key, def)`.

## Files
- `Core.lua` — saved variables, profiles, segments, combat detection, roster/pet tracking
- `Parser.lua` — combat log parsing (all trackers)
- `Modes.lua` — display modes + tooltips
- `Window.lua` — meter windows, bars, context menus
- `EditMode.lua` — live drag/resize/snap editing
- `Skins.lua` — textures, fonts, skin presets (auto-detects LibSharedMedia)
- `Options.lua` — options panel
- `API.lua` — public integration API
- `textures/` — bundled statusbar textures (flat, gradient, glossy, minimal, smooth)

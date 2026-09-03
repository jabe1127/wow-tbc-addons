<p align="center"><img src="icon/jct-icon-256.png" width="128" alt="JCT"></p>

# Jabe's Combat Text (JCT)

A complete replacement for Blizzard's floating combat text, written from scratch for **World of Warcraft: The Burning Crusade Classic — Anniversary realms** (client 2.5.6, interface `20506`).

No Ace libraries. No Blizzard XML templates. No external dependencies. About 5,900 lines of Lua across ten files.

---

## At a glance

| | |
|---|---|
| **22** independently routable message classes | **10** display frames, each separately placed, sized, styled and animated |
| **5** layout presets | **10** animation paths |
| **87** curated enemy-ability alerts | **8** reactive and conditional abilities detected |
| **54** tracked stances, aspects, forms, auras and seals | **10** damage/healing thresholds |
| **25** content filters | **13** per-stream merge windows |
| **36** colour settings | Nameplate or fixed-screen anchoring, per frame |
| Named profiles, account-wide | Export/import as a shareable text string |
| One `OnUpdate` for the whole addon | Zero cost out of combat |

---

## 1. It genuinely replaces Blizzard's combat text

Blizzard's floating combat text is two unrelated systems, and most people don't realise the difference matters:

- **Engine-drawn world text** — the numbers over your target's head, drawn in C++. **No addon can restyle these.** Not the font, not the colour, not the position. The only lever anyone has is a console variable that switches them off.
- **Lua-drawn text** — the stream near your own character, drawn by the load-on-demand `Blizzard_CombatText` addon.

JCT switches off both and draws everything itself, which is the only way to get real control.

- Suppresses `enableFloatingCombatText` plus **11** engine-side `floatingCombatText*` variables.
- Detects the `_v2` variable names introduced when the Classic client was rebased onto the modern UI codebase, and falls back to the legacy names when they aren't present.
- Re-asserts suppression on `CVAR_UPDATE`, so nothing — including Blizzard's own options panel — can quietly turn the old numbers back on mid-session.
- Re-suppresses if `Blizzard_CombatText` gets loaded on demand partway through a session.
- **Remembers your original values and restores them** when you switch the takeover off. Those originals are persisted, so restoring works after a relogin, not just in the session that captured them.

---

## 2. Message classes and routing

Every message is tagged with one of **22 classes**, and each class can be sent to any frame. Route everything into one box for a single stream, spread it across ten, or anything between.

**Outgoing** — spell/ability damage · melee swings · Auto Shot · crits · DoT ticks · healing · healing crits · misses and dodges

**Pet** — damage · crits · healing · misses

**Incoming** — damage taken · crits taken · healing received · attacks you avoided

**Other** — power gains · notifications · reactive abilities ready · stance/aspect/form changes · enemy cooldowns · enemy broke your control

Frames that are switched off are marked `(off)` in the routing dropdowns, because pointing a stream at a disabled frame silently discards it. `/jct verify` machine-checks every preset against every class for exactly that mistake.

---

## 3. Display frames

**10 frames**: Outgoing · Crits · Melee swings · Auto Shot · Pet · Incoming · Healing · Power · Notifications · Enemy alerts.

Each one independently controls:

- Position and size, by slider or by dragging
- Scale and frame strata
- Animation path and curve direction
- Text alignment
- Font family, size and outline (or inherit from General)
- Message lifetime (or inherit)
- Maximum simultaneous lines
- Icon side — left, right, or none
- Random horizontal jitter

**Unlock mode** shows every frame with a labelled, coloured overlay and lets you drag them. Positions are stored relative to screen centre, so they survive resolution and UI-scale changes. A **32-pixel alignment grid** with marked centre axes is one click away.

---

## 4. Layout presets

Presets only move frames and change routing. They never touch your fonts, colours or filters, so switching layouts doesn't cost you your tuning.

| Preset | Shape |
|---|---|
| **Columns** | Separate boxes per stream, each owning a fixed piece of screen. You learn where to look instead of parsing one mixed stream. |
| **Classic arcs** | Blizzard's familiar shape — outgoing arcs up one side of your character, incoming up the other — with your font, colours, speed and position. |
| **Weave** | Melee swings and Auto Shot get dedicated frames either side of your character. Built for reading attack rhythm. |
| **Minimal** | Two tight columns. Damage right, damage taken left, everything else folded in. |

---

## 5. Animation engine

Five motion paths, per frame:

- **Scroll up** and **scroll down** — straight linear travel
- **Fountain** — a sideways parabola that leaves the anchor line, bulges to the full frame width at mid-life, and comes back in as it fades
- **Horizontal** — travels sideways in stacked rows, left or right or alternating
- **Static** — stacks in place with no motion

Plus:

- Adjustable message lifetime and fade-start point
- **Crit "pop"** — an overshoot-and-settle scale animation, with a configurable size multiplier
- Per-frame random jitter, so simultaneous hits don't stack into an unreadable column
- **Time-domain overlap avoidance**: when a new number appears, older ones are pushed forward *in time* rather than repositioned. Each motion path stays a pure function of progress, and a damage burst visibly accelerates older numbers off screen instead of piling them up.

---

## 6. Typography

- Seven client fonts included: Friz Quadrata, Arial Narrow, Skurri, Morpheus, 2002, 2002 Bold, Nimrod
- **LibSharedMedia-3.0 fonts picked up automatically** if any other addon has it loaded
- Drop your own `.ttf` into the addon's `Fonts` folder and register it with one line
- Outline: none, outline, thick outline, or outline + monochrome
- Optional drop shadow
- Per-frame font, size and outline overrides
- Global opacity

Two client-specific traps are handled: patch 2.5.6 made `SetFont` reject `nil`, `false` and `"NONE"` as flag arguments where older clients tolerated them, and `SetFont` returns `false` for a missing font file rather than raising — so a bad path would otherwise leave text permanently invisible with no error.

---

## 7. Number formatting

- Thousands separators (`12,345`)
- Optional abbreviation (`12.3k`), off by default — TBC numbers are small enough that abbreviating loses more than it saves
- Inline spell icons, left or right, at font size or a fixed size
- Optional spell names
- Merge counts (`1250 x5`)
- Optional crit prefix and suffix
- Overhealing shown in brackets after the effective heal
- Partial absorbs, blocks and resists shown with the amount

---

## 8. Merging

Repeated hits of the same spell collapse into one growing number — what makes a Volley or a pet's swing stream readable.

- **The first hit of a window always displays immediately.** Only the hits behind it are folded into a follow-up number with a count. A single hit is never delayed. Merging that holds everything back by a fixed interval destroys the timing information in the stream, which is the main thing worth reading if you're pacing your own attacks.
- **13 independent merge windows**, one per stream, each 0–5 seconds. Zero disables merging for that stream.
- **Spell ranks collapse automatically.** In TBC every rank has its own spell ID, so merging on the raw ID would split Steady Shot Rank 3 from Rank 4. Ranks are aliased by name at runtime — no hand-maintained table.
- **Incoming damage is keyed by attacker**, so two mobs hitting you don't sum into one number that hides the fact there are two.
- Crits bypass merging by default — a crit is information you want the instant it lands.
- Thresholds are applied **after** merging, so "hide hits under 500" never eats a tick train that adds up to 5,000.

---

## 9. Filtering

**10 thresholds**, each independent: your hits, your crits, pet hits, pet crits, damage taken, crits taken, your heals, your heal crits, heals you receive, power gains. Separate crit thresholds matter — a value that hides trash white hits would otherwise also hide small crits.

**23 content toggles**, including melee swings, Auto Shot, DoT ticks, HoT ticks, overhealing, your misses, attacks you avoided, buffs and procs, buffs falling off, pet melee, pet abilities, pet crit styling, pet misses, damage taken, healing received, power gains, environmental damage, killing blows, interrupts, dispels, low-health warning, combat state, and a global in-combat-only switch.

**Per-spell blocking.** Every spell seen in combat is recorded and listed with a checkbox, so you can silence anything without looking up IDs. `/jct block <id>` adds one by hand.

Pet melee is off by default — a Beast Mastery pet's white swings are the single loudest source of combat text in the game.

---

## 10. Colours

- **25 message colours**, one per class plus melee, Auto Shot, killing blows, interrupts, dispels and the low-health warning
- **9 spell-school colours**: Physical, Holy, Fire, Nature, Frost, Frostfire, Shadow, Shadowflame, Arcane
- School colouring can be switched off entirely, falling back to per-class colours
- Full colour picker on every entry, with both the modern and legacy `ColorPickerFrame` APIs supported

---

## 11. Melee weaving support

Melee swings and Auto Shot are **first-class message classes**, not just colour variations, so each can be routed to its own frame.

The **Weave** preset puts them in small dedicated boxes either side of your character. The alternation then reads *positionally*, at the edge of vision, without having to look at or parse the numbers — peripheral vision is poor at reading digits and good at noticing rhythm and location.

Supporting defaults:

- **Melee and Auto Shot never merge.** Merging adds latency, and latency is exactly what destroys a timing signal.
- **Crits can stay in their source stream** rather than jumping to a shared crit frame, so a melee crit is still a melee-coloured number in the melee box, just bigger.
- Default colours sit deliberately far apart: melee orange, Auto Shot aqua, physical spell damage white, pet periwinkle.

---

## 12. Enemy ability alerts

Tells you when an enemy uses something that changes what you should do next.

**87 curated spells across 4 toggleable categories:**

- **CC breaks and immunities** (10) — PvP trinket, Will of the Forsaken, Escape Artist, Stoneform, Blessing of Freedom, Blessing of Protection, Divine Shield, Ice Block, Cloak of Shadows, Spell Reflection
- **Crowd control and interrupts** (21) — traps, stuns, fears, silences, roots, Counterspell, Earth Shock, Grounding and Tremor Totem
- **Major cooldowns** (45) — every class's significant offensive and defensive cooldowns
- **Racials** (11) — including all three Blood Fury variants and both Arcane Torrent variants

Every spell is individually toggleable.

**Matching is by spell name, not ID.** In TBC every rank has its own ID, so ID matching would require every rank of every spell listed and would silently miss any that were wrong. One correct ID per spell is resolved to its localised name at login, which covers all ranks on any locale — and a bad ID fails *loudly*: `/jct spells` lists anything that didn't resolve.

**Scoping** is target-and-focus by default, widening to any enemy player or everything hostile. Combat log range is roughly 100 yards, so an arena is covered completely and a large battleground is not. Focus casts are labelled. Hostility is checked on every scope, so a focused teammate's trinket never reads as the enemy's.

---

## 13. Reactive and conditional abilities

**Reactives** — Counterattack, Mongoose Bite, Overpower, Revenge, Riposte — are derived from the combat log rather than from Blizzard's `SPELL_ACTIVE` message, which rides on the very system JCT switches off.

- A parry lights Counterattack and Riposte
- A dodge lights Mongoose Bite
- Your target dodging lights Overpower
- Any avoidance lights Revenge, **including a partial block** — which in TBC is the normal case, and which arrives as damage with a blocked amount rather than as a miss event, so watching only misses would catch almost none of them

**Conditional abilities** — Execute, Hammer of Wrath, Victory Rush — produce no combat log event at all, and are detected by edge-watching whether the client reports them as usable.

That deliberately avoids health arithmetic. In Classic, `UnitHealth` returns real values for NPCs but a whole-number **percentage** for enemy players, so a hand-computed 20% would be off by up to 1% of maximum health in PvP. Asking the client leaves the threshold to the server. It also makes Victory Rush work, where the obvious approach — watching for a killing blow — fires on grey mobs that don't grant it.

Only abilities the character actually knows are watched, rechecked after a respec. A Beast Mastery hunter gets Mongoose Bite and not Counterattack, since Counterattack is a Survival talent. Alerts are suppressed while the ability is genuinely on cooldown.

### States: stances, aspects, forms, auras, seals

Fifty-four states across all nine classes are tracked by name, so every rank collapses onto one entry: hunter aspects, warrior stances, druid forms, paladin auras and seals, mage and warlock armours, shaman shields, Stealth, Prowl, Shadowform, Inner Fire, Ghost Wolf, Slice and Dice, Soul Link, Ice Barrier, Mana Shield.

These are handled separately from the generic "buff gained" filter for two reasons.

**They are shown out of combat.** A state is something you chose, and you choose most of them between pulls. The generic buff filter is combat-only on purpose — out of combat it would be nothing but raid-buff spam — which is exactly why an aspect swap never appeared there.

**Losing one gets its own colour.** A gained state is cool and calm, a lost state is warm and loud. A dazed Cheetah, an expired seal, a form you were knocked out of — each is a mistake, and each should read as one without you having to actually read it.

**Swaps count as one message.** Swapping Hawk for Viper is one decision but two combat log events, so the fade of the old state is held briefly and dropped if a state from the same group lands behind it. Only genuine losses show the fade colour. The hold survives either event order, since the combat log does not guarantee that the removal arrives before the application. Turn it off to see both halves.


---

## 14. Profiles

- Named snapshots of **every** setting: layout, fonts, colours, routing, filters, merge windows, enemy alerts
- Stored in their own saved variable, separate from live settings, so they survive a Reset
- **Account-wide** — a profile saved on one character loads on any other
- Reset takes an automatic snapshot first, because Reset has no undo
- Two-click delete, for the same reason
- Full slash access: `/jct profile save|load|delete <name>`

---

## 15. Export and import

Turns your settings into a block of text you can paste anywhere, and read back on any character or machine.

- **Only differences from defaults are exported**, taking a typical string from tens of kilobytes to a few hundred characters — which matters when the transport is a text box you select by hand
- Deliberate absences are encoded explicitly: a frame with no font size is *inheriting*, which is not the same as the default size
- **Base64 output**, so the string is letters, digits and three punctuation marks. The raw payload contains colour escapes that chat frames, Discord and forums each mangle differently
- **Importing cannot execute code.** The easy implementation is to serialise as Lua and run it, which makes importing a stranger's string equivalent to running their code. This uses a hand-written parser over a deliberately tiny grammar: it can only produce data, and malformed input returns an error rather than throwing
- Imported values are **range-checked, not just type-checked**. A frame scale of zero or an unknown strata would throw inside the display code — which runs at login *before* slash commands register — so a bad import could otherwise leave no way to undo it from in game
- Applying is rolled back if it fails anyway, and a snapshot is always taken first

---

## 16. Options interface

A standalone, movable, **resizable** window with **8 tabs**: General, Layout, Routing, Filters, Enemies, Colours, Merging, Profiles. Size and position are remembered between sessions.

Standalone rather than embedded, because the Settings and InterfaceOptions APIs differ across Classic builds — the addon can't be made unconfigurable by an API change. It still registers in **Options → AddOns**, where selecting it opens the real window.

Every widget is built from raw frames and textures. No Ace libraries, and no Blizzard XML templates — the Classic client is now on the modern UI codebase, where several long-standing templates are no longer guaranteed to exist. Custom checkbox, slider, dropdown with scrolling, colour swatch, single- and multi-line text entry, scroll container, window, and resize grip.

**Test mode** emits synthetic combat text of every kind so you can position and style everything out of combat. It refuses to start in combat.

---

## 17. Diagnostics

`/jct debug` reports, in one go:

- Client build and interface version, with a warning if the TOC doesn't match
- Which combat-text APIs exist on this client
- Whether the combat log is actually registered
- Which options system the client uses
- The live state of every suppressed CVar
- How many curated enemy spells resolved, and how many failed
- Which reactive and conditional abilities were detected for this character
- Frames built and enabled, and the resolved font path
- **Running counters for combat events seen versus messages drawn** — if events are arriving but nothing is drawing, it says so and points at the likely cause

`/jct spells` lists any spell ID that failed to resolve. `/jct verify` checks every preset routes every class at an enabled frame.

---

## 18. Performance

This runs on every combat log event in a 25-man raid, so:

- **One `OnUpdate` for the entire addon**, hidden the moment nothing is animating. Out of combat it costs nothing.
- **`SetFont` is cached** per FontString on `(path, size, flags)`. It's the most expensive call in this path and most strings in a fight share one font.
- **FontStrings are pooled forever.** A FontString can't be garbage collected in WoW, so pooling is mandatory rather than an optimisation.
- The combat log handler **bails on affiliation before doing any string work**, and allocates nothing on the reject path.
- Enemy alerts reject with a single hash probe before any flag arithmetic.
- Per-frame line caps with oldest-first eviction, so a burst can't spawn unbounded strings.

---

## Slash commands

| Command | Effect |
|---|---|
| `/jct` | Open the options window |
| `/jct unlock` / `lock` | Show and drag the frames |
| `/jct grid` | 32px alignment grid |
| `/jct test` | Synthetic combat text for positioning |
| `/jct preset <name>` | `columns`, `classic`, `weave`, `minimal` |
| `/jct profile` | List profiles |
| `/jct profile save\|load\|delete <name>` | Manage profiles |
| `/jct export` | Jump to the export/import boxes |
| `/jct block <id>` / `unblock <id>` | Silence a spell by ID |
| `/jct debug` | Full diagnostic report |
| `/jct spells` | List unresolved spell IDs |
| `/jct verify` | Check preset routing integrity |
| `/jct reset` | Back to defaults (snapshots first) |
| `/jct on` / `off` | Toggle the addon |

---

## Requirements

- **TBC Anniversary** (client 2.5.6, interface `20506`)
- No dependencies. LibSharedMedia-3.0 is used if present but never required.

Install into `_anniversary_\Interface\AddOns\JCT`. Note that as of 2026 `_classic_` is Mists of Pandaria Classic, not TBC — a common source of "the addon doesn't appear" reports.

---

## Known limitations

Stated plainly, because they're structural rather than bugs:

- **The numbers over your target's head cannot be restyled by any addon.** They're drawn by the game engine, not Lua. JCT switches them off and draws its own; nothing else is possible.
- **Combat log range is roughly 100 yards.** Enemy alerts are complete in an arena and incomplete in a large battleground.
- **Clipped Auto Shots produce no combat log event**, so the weave display shows them as an absence rather than an event — and absences are harder to notice than things appearing.
- **Widening the options window doesn't reflow the widgets.** They're positioned against a fixed column width, so extra width becomes margin. Height is where resizing pays off.
- `COMBAT_TEXT_UPDATE` supplies four minor message types (reactive procs, honour, reputation, extra attacks) and is driven by the same system the Blizzard takeover switches off. If it doesn't fire on a given build, those four are simply absent; nothing else is affected.

---

## Project layout

```
Core.lua       namespace, compatibility shims, saved variables, Blizzard takeover
Format.lua     number formatting, inline icons, colour resolution
Codec.lua      export/import serialisation, base64, diff against defaults
SpellData.lua  curated enemy spell list, reactive and conditional definitions
Profiles.lua   named profiles, config validation, legacy migration
Presets.lua    layout presets and a routing self-check
Engine.lua     frames, FontString pool, animation paths, the global OnUpdate
Events.lua     combat log parsing, classification, merging, filtering, routing
Widgets.lua    dependency-free widget kit
Options.lua    configuration window, test mode, slash commands
```

---

## License

MIT — see [LICENSE](LICENSE).

No third-party code, libraries or font files are bundled. LibSharedMedia-3.0
is used only if another addon has already loaded it, and is never required.

# Jabe's Combat Text (JCT)

A complete replacement for Blizzard's floating combat text, built for **TBC Anniversary** (client 2.5.6, interface `20506`).

Written from scratch: no Ace libraries, no Blizzard XML templates, no external dependencies. About 2,500 lines you can actually read and change.

---

## Install

Drop the `JCT` folder into:

```
Windows   C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\JCT
macOS     /Applications/World of Warcraft/_anniversary_/Interface/AddOns/JCT
```

**`_anniversary_` is the important part.** As of 2026 `_classic_` is Mists of Pandaria Classic, not TBC. A lot of addon guides still say otherwise. If you're unsure, use Battle.net → the game → cog icon → "Show in Explorer" and check the folder name.

Then `/jct` in game, or **Esc → Options → AddOns → Jabe's Combat Text**.

### Upgrading from FCT

**Leave the old `FCT` folder installed and enabled for one login.** That's the whole procedure — no file editing.

WoW names each addon's saved-variables file after its folder, so JCT can't read `FCT.lua` directly. But while FCT is still installed and enabled, the game loads its settings into memory as normal, and JCT simply reads them from the running addon.

On that first login JCT will:

1. Copy every setting across.
2. Save a copy as a profile called **Imported from FCT**, so it survives even a Reset.
3. Hand the combat-text CVars back to Blizzard and then re-take them, so "Take over Blizzard's combat text" can still be switched off later. Without this step the originals would be lost and Blizzard's numbers could never be restored.
4. Silence the old addon for the rest of the session so you don't see doubled numbers.

Then untick FCT in the AddOns list, or delete the folder. Done.

Nothing is written into FCT's own configuration at any point, so if you ever go back to it, it behaves exactly as it did.

If you'd rather start clean, just don't install FCT alongside — JCT begins on the Columns preset.

## Profiles

The **Profiles** tab saves complete snapshots of every setting: layout, fonts, colours, routing, filters, merge windows, enemy alerts. Name one and save it; load it back any time.

Profiles are stored in their own saved variable, separate from your live settings, so they survive a Reset. They're also account-wide, so a profile saved on one character loads on any other — useful for keeping a PvP layout and a raid layout, or setting up an alt in one click.

Reset takes an automatic snapshot first, saved as **Before reset**, because Reset has no undo. Deleting a profile is two-click for the same reason.

```
/jct profile              list saved profiles
/jct profile save <name>
/jct profile load <name>
/jct profile delete <name>
/jct export               jump to the export/import boxes
```

### Export and import

At the bottom of the Profiles tab. Export turns your settings into a block of text; click the box to select it all and Ctrl+C. Import takes that text back, on any character or any machine.

Only the **differences from the defaults** are exported, which keeps a typical string to a few hundred characters instead of tens of kilobytes. Deliberate absences are encoded too — a frame with no font size is *inheriting* from General, which is not the same as the default size, so the distinction has to survive the round trip.

The output is base64, so it is letters, digits and three punctuation marks. Colour codes and other characters in the raw payload get mangled differently by chat frames, Discord and forums; base64 survives all of them.

Importing never runs code. The obvious way to read a settings string back is to serialise it as Lua and execute it, which would make importing something a stranger sent you equivalent to running their code. This uses a hand-written parser over a deliberately tiny grammar instead — it can only produce data, and malformed input returns an error rather than throwing.

Imported values are also range-checked, not just type-checked. A frame scale of zero or an unknown frame strata would throw inside the display code, and because that code runs at login *before* slash commands are registered, a bad import could otherwise leave you with no way to undo it from inside the game. Anything out of range is dropped and the default restored, applying is rolled back if it fails anyway, and a snapshot is always taken first as **Before import**.

---

## What it actually does

Blizzard's combat text is two separate systems:

- **Engine-drawn world text** — the numbers over your target's head. These are drawn in C++. No addon can restyle them: not the font, not the colour, not the position. The only lever anyone has is a CVar that turns them off.
- **Lua-drawn text** — the stuff that scrolls near your character, drawn by the load-on-demand `Blizzard_CombatText` addon.

JCT switches both off and draws everything itself, so the font, size, colour, position, motion path, filtering and grouping are all yours. It re-asserts the CVars if something (including the options menu) turns them back on mid-session.

If you ever want Blizzard's back, untick **Take over Blizzard's combat text** on the General tab and the original CVar values are restored.

---

## Layouts

Four presets, switchable from the General tab. A preset only moves frames and changes routing — it never touches your font, colours or filters.

| Preset | Shape |
|---|---|
| **Columns** | Separate boxes for outgoing, crits, pet, incoming, healing, power and notifications. Each stream owns a fixed piece of screen, so you learn where to look instead of reading one mixed stream. This is the xCT+ shape. |
| **Classic arcs** | The familiar Blizzard look — everything you do arcs up the right of your character, everything done to you up the left — but with your font, your colours and real control over speed and position. |
| **Weave** | Melee swings and Auto Shot get their own small frames either side of your character, and neither ever merges. See below. |
| **Minimal** | Two tight columns. Damage right, damage taken left, everything else folded in. |

Presets are just data. Anything a preset does you can do by hand on the **Layout** and **Routing** tabs, and you can build something none of them cover.

---

## The Weave preset

Eighteen kinds of message are routed independently, and three of them are yours specifically:

- **Melee swings** (`SWING_DAMAGE` from you)
- **Auto Shot** (`RANGE_DAMAGE`, spell 75)
- **Spell / ability damage** (everything else)

They're separate *classes*, not just separate colours, so each can go to its own frame. The Weave preset puts melee in a small box to the right of your character and Auto Shot in a matching box to the left, both at 24pt with no icons. The alternation reads positionally at the edge of vision, without you having to look at or parse the numbers.

Three defaults support this:

- **Melee and Auto Shot never merge** (interval 0). Merging adds latency, and latency is exactly what destroys a timing signal. Everything else merges normally.
- **The first hit of any merge window displays immediately.** Only the hits behind it get folded into a follow-up number with a count. A single hit is never delayed by merging at all.
- **Crits stay in their own stream** in the Weave preset (`critsOwnStream` off), so a melee crit is still a melee-coloured number in the melee box, just bigger — instead of jumping to a shared gold crit frame and losing its identity.

Default colours are chosen to sit far apart: melee orange, Auto Shot aqua, physical spell damage white, pet periwinkle.

**Pet melee is off by default.** A BM pet's white swings are the loudest single source of combat text in the game. Turn it on under Filters if you want it.

---

## Enemy alerts and reactive abilities

**Enemy alerts** tell you when someone uses something that changes what you should do next: a PvP trinket, Escape Artist, Recklessness, a stun, a major cooldown. 87 spells across four categories — CC breaks and immunities, crowd control and interrupts, major cooldowns, racials — each toggleable individually on the **Enemies** tab.

Matching is by spell **name**, resolved once at login from one ID per spell. In TBC every rank has its own ID, so ID matching would need every rank of every spell listed and would silently miss the ones I got wrong. Name matching means one correct ID covers all ranks on any locale, and a bad ID fails loudly — `/jct spells` lists anything that didn't resolve.

Scoped to your **target and focus** by default. Combat log range is around 100 yards, so an arena is covered completely and a large battleground is not; widening the scope in a BG is a firehose. Focus casts are labelled so you can tell the two apart. Hostility is checked on every scope, so a focused teammate's trinket never reads as the enemy's.

**Reactive abilities** — Counterattack, Mongoose Bite, Overpower, Revenge, Riposte — are derived from the combat log rather than from Blizzard's `SPELL_ACTIVE` message, which rides on the system JCT switches off. A parry makes Counterattack and Riposte live, a dodge makes Mongoose Bite live, your target dodging makes Overpower live, and any avoidance including a *partial* block makes Revenge live.

**Conditional abilities** — Execute, Hammer of Wrath and Victory Rush — produce no combat log event at all, so they're detected by edge-watching whether the client reports them as usable. That deliberately avoids doing the health arithmetic: in Classic `UnitHealth` returns real values for NPCs but a whole-number *percentage* for enemy players, so a hand-computed 20% would be off by up to 1% of max health in PvP. Asking the client leaves the threshold to the server. It also means Victory Rush works correctly, where the obvious approach — watching for a killing blow — would fire on grey mobs that don't grant it.

Only abilities this character actually knows are watched, checked at login and again after a respec. Counterattack is a Survival talent, so a Beast Mastery hunter correctly gets Mongoose Bite and not Counterattack. The Enemies tab shows you what it detected. Alerts are also suppressed while the ability is genuinely on cooldown, so you aren't told Counterattack is ready four seconds before it is.

## Commands

```
/jct              open the options window
/jct unlock       show and drag the frames
/jct lock         put them back
/jct grid         32px alignment grid, red centre axes
/jct test         fake combat text so you can position and style out of combat
/jct preset <name>   columns | classic | weave | minimal
/jct block <id>   stop a spell producing combat text
/jct unblock <id>
/jct debug        print client version, API and CVar state, and event counters
/jct spells       list any curated enemy spell ID that failed to resolve
/jct profile      list, save, load or delete a settings profile
/jct verify       check every preset routes every stream at an enabled frame
/jct reset        back to defaults
/jct on | off
```

---

## Options, briefly

**General** — font, size, outline, shadow, how long a number lives, when it starts fading, crit size and pop, strata, opacity, number formatting (thousands separators on, abbreviation off — TBC numbers are small enough that abbreviating loses more than it saves), spell icons.

**Layout** — per frame: position, size, scale, animation (up / down / fountain arc / horizontal / static), curve direction, jitter, alignment, font size override, duration override, max simultaneous lines, icon side. Anything left at 0 inherits from General.

**Routing** — which frame each of the eighteen message classes goes to. Frames that are switched off are marked `(off)` so you can't accidentally route a stream into the void.

**Filters** — ten thresholds (separate ones for crits, for pet damage, and for heals you receive, because one number can't sensibly cover all of them), twenty toggles, and a list of every spell you've actually seen in combat that you can tick to block. Thresholds are applied **after** merging, so "hide hits under 500" never eats a tick train that adds up to 5,000.

**Colours** — per message class, plus per spell school.

**Merging** — the window per stream, and whether crits merge at all (off by default: a crit is information you want the instant it lands).

The window itself is draggable by its title bar and resizable from the grip in the bottom right corner. Both size and position are remembered between sessions.

---

## Fonts

Seven client fonts are listed by default. To add your own, drop a `.ttf` into `JCT\Fonts\` and add one line to `ns.customFonts` at the top of `Core.lua`:

```lua
ns.customFonts = {
    ["Expressway"] = [[Interface\AddOns\JCT\Fonts\Expressway.ttf]],
}
```

The client can't list a directory, so the table has to be the index. If any other addon has LibSharedMedia-3.0 loaded, its fonts are picked up automatically.

One 2.5.6 gotcha the addon handles for you: `SetFont` on this patch rejects `nil`, `false` and `"NONE"` as the flags argument, where older clients tolerated them. It's the single most common reason a font-heavy addon breaks on Anniversary.

---

## Worth checking in game

The client was rebased onto Blizzard's modern UI codebase, and a few things can only be confirmed from inside it. Run:

```
/jct debug
```

It prints the client build and interface number, which combat-text APIs exist, which options system this build uses, the state of every CVar JCT suppresses, how many frames are built and enabled, and running counters for combat events seen versus messages drawn. If events are arriving but nothing is drawing, it says so and tells you where to look.

If the interface number it reports isn't `20506`, change `## Interface:` in `JCT.toc` to match — the addon still runs either way, it'll just be flagged out of date in the addon list.

JCT feature-detects everything above, so an unexpected answer shouldn't break anything. The one path that genuinely depends on the client is `COMBAT_TEXT_UPDATE`, which supplies only four minor message types (reactive-ability procs, honor, reputation, extra attacks). If it doesn't fire on this build those four are simply absent; nothing else is affected.

---

## Structure

```
Core.lua      namespace, compat shims, saved variables, Blizzard takeover
Format.lua    number formatting, inline icons, colour resolution
Presets.lua   layout presets and a self-check
Engine.lua    frames, FontString pool, animation paths, one global OnUpdate
Events.lua    combat log parsing, classification, merging, filtering, routing
Widgets.lua   dependency-free widget kit
Options.lua   config window, test mode, slash commands
```

Performance notes, since this runs on every combat log event in a 25-man:

- One `OnUpdate` for the whole addon, hidden the moment nothing is animating. Out of combat it costs nothing.
- `SetFont` is cached per FontString on `(path, size, flags)`. It's the most expensive call in this path and most strings in a fight share one font.
- The combat log handler bails on affiliation before doing any string work.
- FontStrings are pooled forever — a FontString can't be garbage collected in WoW, so pooling is mandatory rather than an optimisation.
- Overlap avoidance happens in the *time* domain: when a new number appears, older ones are pushed forward in time rather than repositioned. Each motion path stays a pure function of progress, and a burst of damage visibly accelerates older numbers off screen instead of stacking them up.

# Log Lovers

**Advanced combat log and chat replacement for World of Warcraft: TBC Anniversary.**

Version 1.14.0 · Interface 20506 / 20505 · MIT licence · no dependencies

---

## What it does

Log Lovers replaces the two windows you read most — the combat log and the chat
frame — with faster, fully interactive versions wrapped in a warm dark skin.
Every line is a live object you can hover, click, filter by, or break out into
its own window. Every chat tab is a filter set you control down to the channel.

## Combat log

* Events go into a rolling buffer (up to 20,000). Windows render *from* the
  buffer, so changing a filter instantly re-slices your whole history —
  filtering never loses anything.
* **Hover a spell** for its tooltip and spell ID. **Click it** for the spell
  inspector (hit/crit/miss/avg/max, by you and against you), to isolate or hide
  it, to break it into its own window, or to highlight it everywhere.
* **Click a name** to focus events from/to that unit, spawn a window for them,
  or open their death recap. Hovering shows their fight totals.
* Crits, glancing/crushing, resists, blocks, absorbs, overkill, overheal,
  off-hand, dots/hots — all rendered, school-coloured, with icons.
* **Who you see is set per situation.** Every combat view has one line per
  place — out in the world, dungeons, raids, battlegrounds, arenas — and each is
  simply *Just me*, *Me and my group*, or *Everyone*. Defaults: just me
  everywhere, everyone in arenas. "Just me" always includes your pet; there is
  no way to separate them.
* **Which events** is a separate choice: everything you're involved in (default),
  only what you do, or only what's done to you.
* **AoE farming mode** — one line per kill and nothing else, each with a
  clickable `[recap]`. Made for mages and paladins grinding big pulls: instead of
  hundreds of damage lines you get a tidy list of what died, and can open any
  kill to see exactly how it went. `/ll aoe` toggles it.
* **Hidden buffs and debuffs** — a global blacklist for zone buffs and other
  people's food, drink and flasks. Add one by picking from the auras currently
  on you, by typing a name, by right-clicking the buff in the log, or with
  `/ll hidebuff <name>`. It applies to every window at once.
* Plus 11 event categories, a "hide begins casting" switch, spell allow/block
  lists, and — only when other players are actually shown — switches for their
  professions, cooking and fishing.

## Chat

* Complete Blizzard chat replacement — reversible any time, your Blizzard
  settings are never modified. Blizzard's own pop-out whisper windows are kept
  out of the way, including the tabs they leave behind when closed.
* Tabs live in the title bar, **drag to reorder** or pull off to float; they
  wrap onto extra rows and show unread counts.
* The **combat log docks here as a tab**, and any combat window can dock in or
  break out again.
* Typing uses Blizzard's own edit box, so every slash command, macro,
  tab-completion, sticky channel and `/r` works exactly as stock.
* Left-click a name to whisper, ctrl-click for the full player menu, right-click
  for Blizzard's own. Whispers raise a pop-out bar and every whisper line has an
  inline `[+]`; pop-outs have their own reply box.
* **Shift-click a name** — in chat or in the log — and Log Lovers runs the
  `/who` and prints the answer exactly the way the game does:

  ```
  [Lampart]: Level 66 Undead Warrior <M O B> - Zangarmarsh
  1 player total
  ```

  No window opens — Blizzard's Who frame is deafened for the second the lookup
  is in flight, so it never pops up — and there is nothing else to click.
* **Player info.** Ctrl-click a name for everything `/who` cannot tell you:
  professions Log Lovers has watched them use; how many whispers you have traded
  and the last one; times grouped; times traded and what changed hands; and a
  private note you can type. Classic has no API for another player's professions,
  so this is observation, not a lookup — it says "Seen using" and only ever lists
  what it actually watched. All of it can be switched off, or wiped, under
  General → People.
* **Alert words** — your name, plus any words you list, get picked out in your
  chosen colour, play a sound, and mark the tab they landed in.
* **Blocked words** — gold sellers and anything else you never want to see.
  Blocked lines are dropped before they are stored, and the filter only ever
  touches chat a stranger typed at you — never loot, system messages, your own
  typing, or (by default) your guild and group.
* **Repeat collapsing** — the same line pasted four times shows once, with
  `x4`. Whispers still ping and still update your `/r` target.
* Chat page: every chat setting in one place - behaviour, alert and blocked
  words, one-click join/leave for server channels, and colour overrides per
  message type and per channel.
* Optional chat fade-out, a jump-to-bottom button, adjustable wheel speed,
  alt-click a name to invite, and `[70]` before names whose level is known.
* Raid markers typed as `{rt1}`, `{skull}`, `{star}` and the rest render as
  icons, and turn back into text when you search or copy the line.
* The typing box names your whisper target quietly — `Name »` instead of
  Blizzard's `To Name:` — or says nothing at all, your choice.
* Chat history survives `/reload` and relogging.

## Analysis

* **Death recap** — a verdict first, the evidence underneath. The top of every
  recap answers the raid leader's questions in five lines: the killing blow with
  its overkill, what the last five seconds looked like (**burst** or
  **sustained**), the debuffs they died carrying, and the buffs they shed. Then
  two tables: **damage taken** by source and spell with share of total, and
  **healing received** by healer — *effective* healing, overheal beside it. Who
  didn't heal is visible from who did.
* **A timeline you can actually read.** The fifteen "loses X" lines when someone
  dies fold to one. A run of the same spell from the same source folds to one
  row with a count and the span it covered — `Gruul » Melee ×7  -4,200`. The
  killing blow is never folded; it is always the last line. Every row still
  leads with who did it, class-coloured and clickable. Feign Death is detected,
  not counted.
* The recap browser is **resizable** — drag the corner, and it remembers the
  size and place you left it. The list grows with the window, so long names have
  room; both panes take the mouse wheel.
* **Recaps survive logging out**, up to 200, and each kill records **what the
  corpse dropped** the moment you loot it — real item links you can hover and
  shift-click.
* **Save the ones that matter.** Right-click any recap (or use the buttons in
  the browser) to save it and give it a name. Saved recaps show in gold, are
  never rolled off by newer deaths, and survive even with history switched off.
  They do occupy a slot: 3 saved out of 200 leaves 197 rolling.
* **Stats browser** — damage, healing and damage taken per fight or overall,
  expandable to per-spell rows.
* **Spell highlights** — a colour *and* a sound of your choice per spell, from
  the game's own alerts, LibSharedMedia, or your own file.
* **Capture & export** — copy any window as text, or record every event to
  SavedVariables for offline analysis.
* **Profiles** — export your whole setup as one shareable string. An imported
  profile is parsed, never executed: it cannot run code, hang the client, or
  leave your settings half-replaced if it turns out to be malformed.

## Install

Copy the `LogLovers` folder into `World of Warcraft/_classic_/Interface/AddOns/`
so that `Interface/AddOns/LogLovers/LogLovers.toc` exists, then restart or
`/reload`. Type `/ll` for options (also under ESC → Options → AddOns).

## Commands

| Command | Effect |
|---|---|
| `/ll` | Open options |
| `/ll lock` · `/ll unlock` | Lock or unlock every window (also the first button on General) |
| `/ll me` | Flip every combat view between "just me" and "everyone" |
| `/ll aoe` | AoE farming mode — kills only |
| `/ll hidebuff` · `/ll showbuff` | Hide a buff/debuff everywhere · undo (no name lists them) |
| `/ll new` | New combat window |
| `/ll chat` | Show/hide chat · `on`/`off` toggles the module |
| `/ll stats` · `/ll deaths` | Stats browser · death recaps |
| `/ll search` · `/ll copy` | Search bar · copy window text |
| `/ll capture start`/`stop` | Record events to SavedVariables |
| `/ll profile export`/`import` | Share or load a settings profile |
| `/ll lock` · `/ll reset` · `/ll wipe` | Lock windows · reset positions · clear buffer |
| `/ll help` | Full command list |

## Files

```
Constants.lua   palette, categories, defaults      Windows.lua     combat windows
Util.lua        API shims, formatting helpers      Popups.lua      menus, tooltips, inspector
Core.lua        init, event buffer, slash commands DeathRecap.lua  death timelines
Filters.lua     the filter predicate               Stats.lua       stats browser
Format.lua      records -> interactive text        Export.lua      copy, capture, profiles
Events.lua      combat log parsing                 Chat*.lua       chat capture + windows
Players.lua     who you have met, and how          Options.lua     options UI
API.lua         the surface other addons talk to
```

MIT licence — do what you like with it, a credit is appreciated.

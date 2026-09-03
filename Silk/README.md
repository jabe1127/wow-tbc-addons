# Silk

Capsule unit frames for TBC Anniversary (2.5.5) with a custom fluid fill engine.
No sharp edges, anywhere.

## Install

1. Unzip so the `Silk` folder (the one containing `Silk.toc`) sits directly in:
   `World of Warcraft/_classic_/Interface/AddOns/`
   (on some Anniversary installs the game lives in `_classic_era_` — use whichever
   folder contains the client you actually launch)
2. Restart the game or `/reload`.
3. If Silk shows as out of date after a game patch, tick **Load out of date AddOns**
   on the AddOns screen at character select.

## First 60 seconds

- `/silk` — open the options panel (Look tab: corners, colors, glass, motion)
- `/silk unlock` — drag frames anywhere; each text gets its own little pill handle
- `/silk lock` — save positions (combat locks automatically)
- `/silk test` — 25 phantom raiders so you can style raid frames solo
- `/silk test party` — 4 phantom teammates for party frames

## Commands

| Command | Effect |
| --- | --- |
| `/silk` | toggle the options panel |
| `/silk unlock` / `/silk lock` | layout mode on / off |
| `/silk test` | toggle the animated raid preview |
| `/silk test party` | toggle the animated party preview |
| `/silk diag` | print font/outline/shadow state and any per-element overrides |
| `/silk roster` | compare the raid roster against what's actually on screen, and re-sync |
| `/silk reset` → `/silk reset confirm` | wipe this character's Silk settings |

## What's inside

- Player, pet, target, target-of-target, focus, party, and raid frames
- True capsule bars — circular ends at any size, with Soft and Square corner
  modes if pills aren't your thing
- A from-scratch fill engine: eased glide, a damage ghost trail that lingers
  for a beat, and an additive spark riding the leading edge
- Circular portraits with a luminous rank ring: gold elite, silver rare,
  crimson world boss — plus a small gem beside the level text
- Buffs/debuffs as rounded icons with school-colored rings and duration text
- Combo point pips (gold → ember) under the target, pulsing at five
- Hunter pet mood dot: green content, amber neutral, pulsing red when unhappy
- Party cells with dispellable-first debuff icons; raid cells with subgroup
  layout, dispellable outline tint, and range fading
- Everything colors and sizes live from the panel; settings are per character
- **Text & Bars tab**: pick any frame, then set anchor corner, X, Y, size, font,
  outline and color for the name, health, power and level text individually —
  plus X/Y offsets for the buff and debuff blocks. Party and raid text have the
  same controls in their own tabs.
- **Fonts**: any of the game's built-in faces, plus everything SharedMedia
  offers if you have it. Outline style (none/thin/thick) and shadow are global,
  and any single text element can override the font and outline.
- **Unified bar**: health and power share one capsule and one outline, with
  the power slice along the bottom following whatever corner style is set.
  Detach it and it becomes its own capsule you can place anywhere.
- **Grow direction**: party and raid blocks grow left/right and up/down from
  their anchor, so a block can sit flush in any screen corner.
- **Configurable border** around every bar: thickness, opacity, and dark,
  class-coloured or custom.
- **Detachable aura blocks**: buffs and debuffs on any frame can be pinned to
  the frame or cut loose and placed anywhere, each with its own grow direction,
  icon size and rows. Silk can draw your own buffs and hide the default ones.

## Notes

- Castbars are intentionally out of v1 (by request) — a clean slot for v2.
- Health text separators use a middle dot; if your font renders it oddly,
  switch the health text mode to Value or Percent in Look → Text.

## Changelog

### 1.1.0
- Fixed text rendering behind the bars — the text layer now takes an explicit
  frame level above the bar's inner capsule
- Fixed unreadable labels on accent-colored buttons and segmented controls:
  dark text no longer carries a black outline that smothered the glyphs
- Added a party preview (`/silk test party`, or the button in the Party tab)
- Added the Text & Auras tab: anchor, X, Y, size and show/hide for every text
  element on every frame, plus X/Y offsets for buff and debuff blocks
- Added text controls for party and raid cells
- Previews now report any error in chat instead of failing silently
- Existing settings migrate forward; nothing resets

### 1.2.0
- Party and raid frames grow in any direction from their anchor. For a
  top-right raid block: Raid tab → Direction → Horizontal `Left`,
  Vertical `Down`, then drag the anchor into the corner
- Full font control: font family picker (built-ins + SharedMedia), outline
  style, shadow, and per-element font/outline/color overrides
- The power bar can be detached from any unit frame, sized independently and
  positioned freely; its text follows it, and it gets its own drag handle in
  layout mode
- Fixed a load-order bug where party layout called a helper declared below it
- Font paths are probed before being offered, and an unavailable font falls
  back rather than erroring

### 1.3.0
- Buff and debuff blocks are now fully positionable: X/Y sliders for every
  frame, plus a Detach toggle that frees the block from the frame entirely
- Each block has its own grow direction (left/right, up/down), so it expands
  away from wherever you pinned it instead of drifting as auras come and go
- Buff blocks can override icon size and per-row independently of debuffs;
  debuff blocks gained spacing and max-shown sliders
- Detached blocks get their own drag handle in `/silk unlock`, and dropping one
  saves its growth corner rather than its center, so it doesn't jump
- Optional "Hide the default WoW buff frame" for using Silk's own buff block
- Aura blocks size themselves to their contents

### 1.3.1
- Fixed "FontString:SetText(): Font not set" when opening the options panel —
  the font picker set its label text before giving the label a font
- Every fontstring in the addon is now created through a factory that sets a
  font immediately, so the error can't recur elsewhere

### 1.4.0
- Font discovery rebuilt: Silk now harvests the file path out of every Font
  object the client or any addon has registered, probes a much wider list of
  built-ins including locale variants, and still reads SharedMedia. The list
  rescans every time the options panel opens, sorted and de-duplicated
- Silk has its own color picker — RGB sliders, hex entry, presets, live
  preview. The Blizzard picker's callback contract varies by client version
  and was silently doing nothing; this one always fires
- Added Monochrome rendering and full shadow control (offset X/Y, color,
  strength) so outline-free text still reads cleanly. Shadow now on by default

### 1.5.0
- **55 fonts now ship with Silk.** WoW installs only a handful of usable
  typefaces and gives addons no way to read a directory, so scanning can never
  find fonts that aren't there. The files are now bundled (OFL / Apache / UFL;
  see Media/Fonts/LICENSES.txt). Families published upstream only as variable
  fonts were instantiated to a static weight, since WoW cannot render variable
  fonts, and every file was validated as static TrueType before inclusion
- **Text backdrop** — a dark capsule behind any text element, global or
  per-element. On bright class-coloured bars this does more for legibility
  than any outline setting
- Font application is now verified: the result is read back from the client
  and alternative flag combinations are tried before giving up, instead of
  silently falling back
- Shadow is properly cleared when disabled, and its colour/offset apply
- **Clear all text overrides** button in the Layout tab. A per-element font or
  outline override silently masks the global setting, which makes the Look tab
  look broken; this resets every element to Auto
- `/silk diag` reports the font actually in use, the flags the client accepted,
  and any per-element overrides currently masking your global settings

### 1.6.0
- The power bar is now **part of the health bar** by default: one capsule, one
  outline, one silhouette. The power slice sits along the bottom and is clipped
  by the same cap masks, so it inherits the Capsule / Soft / Square corner
  style instead of floating underneath as a second pill
- A thin divider separates the two, and the health slice reclaims the full
  height whenever power is hidden or the unit has no power bar
- Detaching still works and now makes more sense: it splits the power bar out
  into its own capsule with its own position and size
- The Height slider applies in both modes — slice thickness when attached, bar
  height when detached
- Party, raid and preview cells use the same unified bar
- Bars were restructured into a shell (silhouette) plus segments (fills), which
  is what lets two fills share one outline

### 1.6.1
- Fixed a bar overflowing its frame — sometimes across the whole screen — when
  a unit's maximum power or health changed. Values carried the scale they were
  set at, so a bar still holding a big pool that was handed a small one drew a
  fill many times the track's width
- Values are now rescaled whenever the maximum changes, and fill and ghost
  widths are clamped to the track at draw time so it cannot recur by any route
- Target-of-target is polled rather than event-driven, so it now detects when
  the unit behind it changes and snaps instead of gliding from the previous
  unit's numbers
- Power above maximum (pet focus with talents) draws as full while the number
  still reports the true value

### 1.6.2
- Fixed raid frames showing the same player twice, and players who had left
  appearing to move to a different slot. Raid unit tokens pack down when
  someone leaves — the old raid4 becomes raid3 — so cells were repositioned
  but kept displaying the previous occupant until an unrelated event happened
  to fire for that token
- Cell contents now refresh on every roster change. The safe half of that work
  (text, colours, bar values) runs during combat too, so joins, leaves and
  replacements mid-fight are reflected immediately; only repositioning waits
  for combat to end
- A cell whose token is remapped rebuilds instead of animating from the
  previous player's health
- Cells that empty out are wiped, so nothing lingers if they show again
- The roster is re-read shortly after the event as well, since the client can
  fire it before the roster data settles, and the range ticker double-checks
  for remapped tokens as a safety net

### 1.7.0 — performance
- Bar updates no longer re-assert values that have not changed. Every width,
  alpha and shown-state write is guarded against the last value set, which cut
  per-frame work in a 25-man raid roughly in half (386 -> 200 client calls per
  frame, with redundant Show calls dropping from 149 to 18)
- The combo-point and pet-mood pulses attach their per-frame handler only while
  actually pulsing, and detach when hidden, so they cost nothing at rest
- The text backdrop caches its anchors and colour instead of re-applying them
  on every text change
- Measured results: 0 client calls per frame when idle, 0 once a fight settles,
  ~200 per frame only while dozens of bars are actively animating. No memory
  growth across sustained raid churn, and the aura icon pool is reused
- Font discovery walks the global namespace once instead of on every options
  panel open, so repeat opens no longer hitch
- `/silk diag` now reports how many bars are animating; it should read 0 when
  nothing is changing

### 1.7.1
- Fixed an empty gap in the raid grid while everyone was present. Layout handed
  a slot to all forty raid indices whether or not a unit was behind them, while
  visibility was decided separately, so any cell that got a position without
  being shown punched a hole in its group
- Occupied cells now pack from the first slot of their group, so an empty cell
  can never reserve a space. Empty cells queue after the occupied ones, which
  also stops a player who joins mid-combat from landing on top of someone
- Added a reconciliation pass that compares the roster against what is on
  screen every couple of seconds out of combat and re-syncs any cell whose
  secure unit watch has gone stale
- Added `/silk roster`, which prints roster entries against unit tokens and
  shown cells, flags mismatches, and re-syncs

### 1.8.0
- The empty part of a bar is now configurable. It used to always take a 14%
  wash of the bar's own colour, which reads yellow on a neutral mob and orange
  on a hunter. Look → Empty bar offers Match (with an adjustable strength),
  Dark (neutral charcoal whatever the bar is doing), or a Custom colour
- The damage trail colour is configurable too

### 1.8.1
- Fixed elite, rare and world boss targets washing the empty part of their
  health bar in gold or silver. With portraits off, rank is shown by tinting
  the bar's edge — but that texture sits behind the whole bar, and the
  translucent background let the colour flood the unfilled area. An opaque
  trough now covers the interior, so the tint reads as the 1px edge it was
  meant to be. Same fix applies to the dispellable-debuff tint on raid cells
- Added an Empty bar opacity slider under Look → Empty bar

### 1.8.2
- Fixed the raid gap properly. 1.7.1 stopped an empty cell from reserving a
  slot, but only recomputed the layout on roster events — and a cell's shown
  state is driven by the secure unit watch, which reacts to things that never
  produce one (a member going offline, zoning, or a token briefly failing to
  resolve). A cell could therefore vanish after the layout was built and leave
  the gap its slot had reserved
- Cells now request a fresh layout whenever they show or hide, debounced so a
  burst of changes costs one pass. A periodic check compares what's on screen
  against the roster as a backstop
- Repositioning is still deferred in combat since it's protected, but a gap
  that opens mid-fight now closes the moment combat ends
- `/silk roster` forces a relayout as well as reporting

### 1.9.0
- The raid gap is now impossible rather than merely unlikely. Previous attempts
  kept an empty cell from reserving a slot and recomputed layout on visibility
  changes, but both assumed a missing person should disappear. If the roster
  lists someone whose unit token will not resolve, Silk now holds their seat
  with a dimmed cell built from roster data — their name in class colour, and
  "away" or "offline" — and hands the seat back automatically when the token
  returns. A gap cannot form because the seat is never given up
- Party frames hiding in a raid is re-checked continuously instead of only on
  roster events, so converting to a raid mid-fight no longer leaves them up
- Added border controls under Look → Border: thickness (0–4), opacity, and
  dark, class-coloured or custom. Elite and rare rank colours and the raid
  dispel tint still override it, then return to your setting

### 1.9.1
- Fixed Blizzard's party frames showing alongside Silk's. The hide list only
  covered PartyMemberFrame1-4 and ran once at login, which misses the newer
  PartyFrame container with its MemberFrame children, the raid-style
  CompactPartyFrame used when "Use Raid-Style Party Frames" is on, and any
  frame the client builds the first time you actually join a group
- Hiding is now repeatable and re-runs on roster changes, zoning and CVar
  changes, deferring while in combat since reparenting is protected
- In-raid detection no longer depends on a single API: if IsInRaid is missing
  or errors, it falls back to the legacy raid count and then to whether raid
  unit tokens resolve. Party frames hide in a raid and show in a party either
  way
- `/silk diag` now lists which Blizzard frames have been hidden

### 1.10.0
- Fixed the last case of the raid gap: someone dropping out mid-fight. Raid
  cells no longer use RegisterUnitWatch. That watch hides a cell the instant
  its unit token stops resolving, and since repositioning secure frames is
  blocked in combat, the layout could not close the gap it left — so a raider
  disconnecting during a fight punched a hole for the rest of it
- Seats are now allocated out of combat and then held. During combat the
  visible set is frozen: a token that vanishes turns its cell into a dimmed
  placeholder keeping that raider's name, and nothing moves, so nothing can
  gap. The grid settles to the real roster once the fight ends
- `/silk roster` reports seats allocated versus roster size

### 1.10.1
- The raid grid now checks its own result instead of trusting the layout code.
  About once a second out of combat it verifies that every group's visible
  cells occupy slots 1..n with nothing skipped, overrules anything that has
  hidden an allocated seat, and rebuilds the layout if the packing is wrong
- The first time a gap is detected it says so in chat and asks for
  `/silk roster` output, so a cause that has not been identified surfaces
  rather than silently leaving a hole
- `/silk roster` reports whether the packing is contiguous, and heals it

## 2.0.0 — the art pass
- **Surface finishes.** The fill is no longer just flat colour: Satin (quiet
  sheen), Glass (lit top edge) and Velvet (soft bloom), all procedurally
  generated grayscale so they tint with whatever colour the bar is. Satin is
  the new default
- **Frame shadow.** A silhouette-matched soft shadow under every frame, per
  corner style, with reach and strength controls — the difference between a
  floating panel and a rectangle pasted on the world
- **Top rim light.** A one-pixel light edge along each bar's top
- **Halo text outlines.** Two new outline styles, Soft (4-direction) and Heavy
  (8-direction), drawn by Silk as the text's own silhouette rendered behind
  it — because the client's Thick outline is crude at small sizes. Available
  globally and per element
- **Font picker rebuilt.** The list was never limited — it was a 10-row
  dropdown with an invisible scroll. Now tall, with a visible scroll thumb, a
  type-to-filter search box, every row drawn in its own face, and duplicate
  names removed (76 unique fonts)
- **Live preview.** The Look tab opens with a real bar — fill, power slice,
  text, backdrop — that restyles instantly with every control and takes
  simulated damage so glide, ghost and spark are visible in the panel
- **Type an exact value.** Click any slider's number to enter it directly
- **Healer kit for raid frames.** Incoming-resurrection badge (gold, gently
  pulsing, per-unit event driven), health text gains Current alongside
  Deficit/Percent, name truncation, per-cell text size, and a configurable
  out-of-range fade level

### 2.1.0 — castbars and threat
- **Castbars for player, target and focus.** Built from the same shell as
  every other bar, so they inherit the corner style, surface finish, border,
  shadow and rim light automatically. A rounded spell icon sits in the left
  cap, spell name and time remaining alongside. Interruptible casts fill warm
  gold; casts you cannot interrupt go cold grey — the read that matters on
  bosses and in PvP. Channels drain instead of filling; delays and channel
  updates re-read the timing; an interrupted cast flashes red and melts away.
  Acquiring a target mid-cast picks the cast up immediately
- Each castbar attaches under its frame by default, or detaches to any
  position and width, draggable in /silk unlock — where a frozen sample
  appears so there is something to drag
- Per-frame options: enable, height, spell icon, time text, detach, width
- **Aggro highlighting on party and raid cells.** Tanking pulses the cell's
  border red; holding threat without tanking yet shows steady amber. Aggro
  outranks the dispel colour — a debuff can wait two seconds, aggro on a
  clothie can't — and the dispel colour returns the moment threat clears.
  Event-driven per unit, pulse attached only while someone is tanking

### 2.1.1
- Fixed out-of-range raid cells strobing between faded and full. Every grid
  refresh was resetting all cells to full alpha, and roster events refresh the
  grid three times (immediately plus two deferred re-reads), so any live raid
  made faded members flash constantly. Alpha is now decided in one place —
  refreshes apply the current decision instead of resetting it
- Range fading now has hysteresis: two consecutive out-of-range readings
  before the fade, so someone strafing along the range boundary no longer
  flickers, while coming back into range restores instantly
- Fixed names changing or blanking: a transient nil from the client no longer
  blanks a cell (the last known name holds), and a held seat's placeholder
  locks to one name instead of alternating between roster and fallback data

### 2.2.0 — swing timers
- **Player melee and ranged bars**, exact rather than estimated: the combat
  log gives the instant each swing or shot lands, and the client gives the
  speed. Main hand and off hand share one bar — off hand as a slice inside it,
  the same unified-capsule treatment as health and power — and it appears or
  vanishes as you equip or remove an off-hand weapon
- **Haste-aware.** A haste proc or a lost buff rescales the remaining swing
  the moment the speed changes, for melee and ranged alike
- **The Auto Shot bar** is built around the hunter's problem. The half-second
  aim window is drawn on the track, the fill warms to amber as it enters it,
  and a cast that pushes the shot — a Steady Shot started too late — snaps the
  bar to where the shot will really land, corrected by the combat log when it
  fires. Casters get their wand on the same bar; any class that shoots gets it
- **Enemy swing bars** on target (default on) and focus (opt-in). No API
  exposes a mob's attack speed, so the bar measures the gap between its swings,
  reads "calibrating" until it has two, blends new intervals so parry-haste
  doesn't yank it, and remembers each mob's cadence when you switch targets
- Bars stack under the castbar by default, or detach anywhere with their own
  width. Fade out after a grace period when idle, or stay up always. Layout
  mode shows samples so there is something to drag
- Weapon icons in the left cap: your main hand on the melee bar, your ranged
  weapon on the ranged bar
- Text writes and halo clones now skip redundant updates, which per-frame
  timers were hitting constantly; raid-combat cost dropped slightly as a result

### 2.2.1
- Swing bar stack order is now a setting: Auto puts the shot bar on top for
  hunters and melee on top for everyone else, or force either. A lone bar
  always sits at the top of the stack

### 2.3.1
- The Auto Shot bar now resets from the shot itself (UNIT_SPELLCAST_SUCCEEDED
  for Auto Shot / wand), not from the combat log. Damage events fire when the
  projectile lands, which at range is most of a second after the shot — the
  bar was tracking impacts, so it never lined up with your shots
- The bar no longer depends on the auto-repeat toggle events, which don't fire
  reliably on this client and were leaving it in its empty "off" state. It is
  live whenever shots are happening; "off" only after a stop AND an expired
  cycle
- Shots are recognised by spell id or by localized name, so it works in any
  client language
- `/silk swing` reports speed, shots seen, next fire, and the last event
  received, and says so plainly if no shot events have arrived

### 2.3.2
- **Multi-Shot now shows.** While Auto Shot is running, the client emits
  FAILED_QUIET and STOP events *for Auto Shot* the instant you cast anything
  else — exactly when Multi-Shot is on the bar. The castbar treated any
  stop/fail on the player as "the cast ended" and hid it. It now checks the
  cast id, as Blizzard's own bar does; the swing-timer overlay does the same
- A cast that completes holds the full bar for a third of a second and fades,
  so a half-second Multi-Shot leaves a visible trace for the GCD instead of
  blinking
- Blizzard's castbars (player, pet, target, focus) are hidden

### 2.3.3
- Castbar and swing overlay now work the way WeakAuras does: cast events are
  only a wake-up call, and what's drawn is whatever UnitCastingInfo says is
  being cast right now. Stray or id-less events for other casts can't touch
  it because they aren't consulted, and a missed START is recovered by any
  later event

### 2.3.4
- `/silk trace` records every cast event the client sends for the player,
  with the arguments and what UnitCastingInfo reports at that instant, for 25
  seconds — then opens a window you can copy from

### 2.4.0 — the cast takes the frame
- **Target and focus castbars now default to Inside**: while the unit casts,
  the cast takes over the frame's own capsule. The name and health fade out,
  the spell sweeps across in gold (cold grey when you can't interrupt it),
  the spell icon sets into the left cap, and the time remaining sits where
  the health text was. The frame's border does the framing — an elite's gold
  ring stays around the sweep — and a 150ms fade-in makes the takeover feel
  like a transition rather than a pop
- Completion holds the full bar for a beat and melts back to the frame;
  an interrupt flashes red first. Either way the name and health return
- **Placement is now a three-way setting** per frame: Inside, Below (a
  separate bar under the frame, the old look, still the player default),
  or Free (float it anywhere, drag with /silk unlock). Old profiles with
  the detach flag map to Free automatically

### 2.4.1
- Fixed the version label: the panel footer and the TOC had been stuck at
  2.2.1 since that release — each release bump replaced the exact previous
  string, so one silent miss broke every bump after it. The footer now reads
  the code's own ns.version, the TOC is rewritten by pattern, and the test
  suite fails if the TOC, the code, and the panel ever disagree again. The
  code you were running was genuinely 2.4.0; only the label lied

### 2.5.0 — Multi-Shot, from the ground truth
- A real client trace settled it: on this client **Multi-Shot never casts** —
  no UNIT_SPELLCAST_START, and UnitCastingInfo reports nothing while it
  happens. There is nothing for any castbar to draw, which is why every
  addon "fails" at this. The only signal is the success event, so that now
  drives the feedback:
  - the castbar **flashes Multi-Shot** — full gold bar, name and icon,
    fading over half a second — the moment it fires (never stomping a real
    cast in progress)
  - a **bright pin drops on the Auto Shot timeline** at the exact point in
    the cycle the Multi-Shot landed, fading over a beat — the weave, made
    visible
- The Auto Shot bar **blinks bright at the instant a shot fires**, so the
  shot itself is a visible event, not just a bar reset
- The user's trace is replayed **verbatim as a test**: shot cadence at 2.17s
  speed, the FAILED_QUIET storm for 75/37382, Kill Command failure spam, a
  hasted Steady Shot with a mid-cast stray, the pushed auto after it, and the
  START-less Multi-Shot — every line asserted
- The version stamp now has one source of truth (footer derives from it, the
  toc is checked against it by the test suite), so the label can never lie
  about the running version again

### 2.5.1
- On-next-swing attacks — Raptor Strike, Heroic Strike, Cleave, Maul, every
  rank — now reset the melee bar. They replace the white hit, landing as
  SPELL_DAMAGE with no SWING_DAMAGE at all, so the bar never saw the swing.
  Matched by id and by localized name (unknown ranks included); a missed one
  still counts, the off hand is untouched, and other spells can't trigger it

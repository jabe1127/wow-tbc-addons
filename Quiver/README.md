# Quiver

Hunter tools for WoW TBC Anniversary (Interface 20505). No dependencies.

## Install

Extract so the folder sits at
`World of Warcraft/_anniversary_/Interface/AddOns/Quiver/Quiver.toc`,
then restart or `/reload`. Settings carry over automatically from TrueShot.

## Cast feed

Every spell you cast pops as an icon that settles into place and fades, so
you get a running trail of what you pressed. Because it announces any
successful cast, new abilities work with no setup. Auto Shot and melee
swings aren't casts, so each has its own toggle. Icons carry a cooldown
sweep. Anything you don't want in the feed can be blocked by spell ID.

## Warnings

* **Melee range glow** - an orange band down from the top of the screen
  while you are inside melee range. Eased in and out so a probe blip at the
  boundary can't strobe it.
* **Swing fill** - a white band filling right to left with your melee swing,
  shown only while you are OUT of melee, so it answers "how long until a
  swing is worth stepping in for". The orange takes over in melee, so the
  two never overlap.
* **Wrong aspect** - Cheetah, Pack and Monkey called out while in combat.
* **Pet health** - a small readout when the pet is hurt, a large one when
  it's about to die.

All three text warnings are draggable while the options window is open.

## Commands (`/qv` or `/quiver`)

| Command | Effect |
|---|---|
| `/qv` | open the options window |
| `/qv unlock` / `lock` | move the anchor and warning text |
| `/qv test` | animated preview |
| `/qv size <px>` | icon size |
| `/qv auto` / `melee` | toggle Auto Shot / melee swing alerts |
| `/qv glow` / `swingfill` | toggle the glow / swing fill |
| `/qv aspect` / `pet` | toggle aspect / pet warnings |
| `/qv block [id]` | block a spell (no id = last one cast) |
| `/qv unblock <id>` | unblock a spell |
| `/qv blocked` | list blocked spells |
| `/qv sound` | toggle the alert sound |
| `/qv reset` | restore defaults |

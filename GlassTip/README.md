# GlassTip

A clean unit tooltip for TBC Anniversary. Dark glass background, 1px reaction/class-coloured
border, thin accent strip along the top, soft drop shadow, fade-in, and a health bar with
readable numbers.

## Install

Drop the `GlassTip` folder into `Interface\AddOns\`.

**TOC version:** the file ships with `## Interface: 20504`. If the addon shows as out of date,
either tick *Load out of date AddOns* on the character screen, or log in once and run:

```
/dump select(4, GetBuildInfo())
```

and paste that number into the first line of `GlassTip.toc`.

## Skins

Options → Skins. Four presets:

| Skin | Look |
|---|---|
| Vellum | Aged paper, double gold frame, Morpheus serif |
| Fel | Outland green on near-black, border bleeding light outward |
| Frostglass | Pale frosted panel, reads well over dark ground |
| Arcane | Deep indigo, gold frame with corner brackets, serif |

A skin stamps colours, frame, font, text palette and bar settings into your
active profile. Everything it sets stays editable on the other pages afterwards,
and **anchor settings are never touched by a skin** — pick a new look without
losing your positioning.

Vellum and Arcane lock the frame to gold and let the *name* carry the reaction
colour, since a red-bordered parchment tooltip looks wrong. Fel and Frostglass
keep the frame unit-coloured.

## Textures

`Media/` holds six generated 32-bit TGAs — soft glow edges and corners, film
grain, parchment, a gradient bar sheen, and a corner bracket. They are what make
the skins look like surfaces instead of flat rectangles. If a texture ever fails
to load, that layer simply doesn't draw; nothing errors.

## Profiles

Options → Profiles. Create, copy, delete, and switch. **Each character remembers
the profile it last used**, so your hunter and shadow priest can differ without
you touching anything. Deleting a profile moves any character using it back to
Default. Default can't be deleted.

Reset in the preview strip resets the *active profile only*, not all of them.

## Commands

| Command | Does |
|---|---|
| `/gtip` | open/close the options window |
| `/gtip unlock` | switch to fixed anchoring and unlock the anchor box for dragging |
| `/gtip lock` | lock the anchor box |
| `/gtip reset` | reset the active profile to defaults |
| `/gtip skin` | list skins; `/gtip skin fel` applies one |
| `/gtip profile` | list profiles; `/gtip profile Raid` switches |
| `/gtip debug` | report hook status and a live health reading |

There is also a **GlassTip** entry in the Blizzard AddOns settings list that just opens the window.

## What it shows

**Creatures:** name (reaction coloured, boss units get a skull), `Level 70 Elite Humanoid`
with the level number tinted by difficulty colour, and a health bar with `485k / 655k` and `74%`.

**Players:** name (class coloured, realm appended for cross-realm), guild name with rank,
`Level 70 Blood Elf Hunter`, and health.

Numbers over the abbreviation threshold (default 10,000) collapse to `485k`, then `1.2m`.
Threshold and on/off are in Options → Health.

> The client only reports real health values for units it wants you to see. For enemy players
> outside your group it hands back a max of 100, so the bar text falls back to a percentage
> automatically. That's a server-side limit, not a bug in the addon.

## Anchoring

Options → Anchor.

- **Follow the mouse cursor** — pick which corner of the tooltip is pinned to the cursor,
  then nudge it with the X and Y offset sliders (±300px). *Keep tooltip on screen* pushes it
  back inside the edges instead of letting it clip off.
- **Fixed screen position** — a draggable anchor box. Unlock it (button in the preview strip,
  or `/gtip unlock`), drag it where you want, lock it again. *Growth point* decides which
  corner of the tooltip sits on the anchor, i.e. which direction it grows as it gets taller.
  X/Y offsets apply on top of that.

Only tooltips that use the default anchor are moved — bag/spellbook/action bar item tooltips
keep their normal behaviour.

## Appearance

Scale, background colour and opacity, border thickness and colour source, accent strip,
drop shadow, glass sheen, fade in, font, outline, and separate name/body font sizes.
The panel at the bottom of the options window is a live preview and updates as you drag sliders.

## Notes / known rough edges

- Turning off the guild line hides the fontstring; on some builds that can leave a small
  empty gap rather than fully collapsing the tooltip. Turning off *guild rank* only is clean.
- The bar can sit at the top of the tooltip, but the top padding needed for that only exists
  on newer client builds. Bottom is the safe default.
- Fonts are limited to the four built into the game client. If you run LibSharedMedia I can
  wire that in and every shared font becomes selectable.

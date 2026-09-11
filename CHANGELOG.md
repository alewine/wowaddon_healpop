# Changelog

## 1.0.2
- Every action is now used on yourself. With a friendly target selected,
  targetable spells (Gift of the Naaru, Lay on Hands, Renew) and some healing
  trinkets could heal your target instead of you.
- Death Coil is removed from the spell list: it only heals by hitting an
  enemy, so it can't be used on yourself.
- Gift of the Naaru's heal amount now reads correctly instead of showing "?".
- The heal number on the button no longer overlaps the cooldown countdown.
- New option, off by default: split icon for left/right click. When the two
  clicks do different things, the button widens and shows both: left half is
  left-click, right half is right-click. Each half greys out when its action
  can't be used, and shows its own heal amount and countdown.
- Options now explain themselves on hover, and clicking a checkbox's label
  toggles it.

## 1.0.1
- Published builds now cover Classic Era as well as TBC Anniversary. The 1.0
  upload was listed for 2.5.6 only, so Era players could not find the addon
  even though it has always supported 1.15.x.
- Release builds generate a TOC per game flavor rather than collapsing to the
  single plain Interface value.

## 1.0 — 2026-09-11

Initial release.

- One-click button that fires your best available self-heal.
- Priority across six categories: spells, healthstones, potions, trinkets,
  food & tubers, bandages. Reorder, enable, or disable any of them.
- Per-entry enable/disable for everything the character can actually use.
- Mouseover panel (top / right / bottom / left) showing what's up next, how
  much it heals for, and time remaining on anything still cooling down.
- Healing amounts read from the live client tooltip, with shipped fallback
  values for Classic Era and TBC items.
- Auto-detects healing consumables in your bags that aren't in the tables.
- Draggable and scalable button, key bindable under Key Bindings.
- `/hp list` prints the full priority ranking with live cooldowns.
- Flyout re-sorts live so usable options rise and cooling ones sink.
- Items sharing a cooldown collapse to their strongest member, marked `+N`.
- Macro chains only within one cooldown group, so a click can never fire two
  actions: a spell and a healthstone are separate cooldowns and both used to
  fire off one click.
- Left-click chains your items, right-click chains your spells. Split by kind,
  since only spell → item crosses cooldown tracks and fires both.
- "One click, may spend extra" option restores a single all-in-one press, at
  the cost of possibly using more than one thing.
- Soulstones no longer read as healing items.
- Current default moved into the flyout header as a non-clickable readout.
- The flyout groups rows by the click that reaches them: the highlighted top
  entry and the rows under it are left-click, spells sit below a RIGHT-CLICK
  heading. In one-click mode there is a single chain, so it stays a flat list.
- Button face and flyout header show the best *item*, not the best entry
  overall, so they can never advertise a spell that a plain left-click will
  not fire.
- Opening the options window unlocks the button — gold border, drag to move,
  clicks suppressed — and closing it locks the button again. No cog, no
  separate lock setting.
- Button and options window both remember where you put them.
- Sliders for heal text size and font face.
- Spell guard: gates spell lines behind [combat] above a health threshold,
  so an idle click at full health can't burn a long cooldown.
- Escape closes the options window.
- Three-column options layout.

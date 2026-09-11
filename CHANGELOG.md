# Changelog

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

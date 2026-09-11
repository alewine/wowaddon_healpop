<p align="center"><img src="logo.png" width="180" alt="HealPop logo"></p>

# HealPop

A single panic button for WoW Classic. Click it (or bind a key to it) and it
uses the strongest thing you have available right now — an instant self-heal
spell first, then healthstones strongest to weakest, then healing potions
sorted by how much they actually restore.

Built for **Classic Era (1.15.x)** and **TBC Classic / Anniversary (2.5.x)**.

## What it picks

Six categories, in a priority order you control:

| Category | Default | Contents |
|---|---|---|
| Spells | on | Gift of the Naaru, Desperate Prayer, Lay on Hands, Last Stand, Frenzied Regeneration |
| Healthstones | on | Master → Minor, including Improved Healthstone variants |
| Potions | on | Fel Regeneration, Super, Volatile, Major, Superior, Greater, Healing, Lesser, Minor |
| Trinkets | off | Equipped trinkets with an on-use heal |
| Food & Tubers | off | Whipper Root Tuber, Crystal Restore, Fel Blossom |
| Bandages | off | Netherweave through Linen |

Within a category, entries are always sorted by how much health they restore,
strongest first. Between categories, you set the order.

**Items that share a cooldown are collapsed to one entry.** Using any
healthstone puts every healthstone down, and all healing potions share the
2-minute potion cooldown — so listing the weaker ones separately implies a
fallback that doesn't exist, and lets them eat macro slots that another
category should have had. Only the strongest of each group is shown, with a
dim `+N` marking how many it stands in for.

Healing amounts come from the client's own tooltip, so Improved Healthstone
ranks, Alchemist's Stone effects, and anything Blizzard retunes are picked up
automatically. The shipped tables are only a fallback for items whose tooltip
hasn't been cached yet.

Anything healing in your bags that isn't in the tables gets detected and
sorted into the right category automatically. Turn that off in the config if
you'd rather keep the list to known items.

## How the button works

WoW forbids addons from deciding what to cast during combat — a button's
action is locked the moment you enter combat. So HealPop keeps two macros
pointed at your best currently-usable options, rebuilding them whenever you're
out of combat.

### Left-click items, right-click spells

The two bindings are split by *kind*, and the reason is mechanical. Each side
only has to be safe internally, and both already are: a spell's global cooldown
blocks another spell, and an item's cooldown blocks another item. It's only
spell → item that crosses tracks, firing both and consuming both.

So each side chains freely within its own kind:

```
left-click                     right-click
/use Master Healthstone        /cast [combat] Desperate Prayer
/use Super Healing Potion      /cast [combat] Gift of the Naaru
/use Whipper Root Tuber
```

Left-click is the panic button: one press, best consumable you have, falling
through as they run out or sit on cooldown. Right-click spends your free
cooldowns. Neither can ever spend two things.

**Fallback depth** caps the lines on each side (default 3, max 6 — macros are
capped near 255 characters).

Attributes freeze in combat, so both macros hold whatever they had when you
pulled. The flyout still shows the live truth throughout.

### One click for absolutely everything

**"One click, may spend extra"** in the config drops the split and chains the
whole list into left-click:

```
/cast [combat] Desperate Prayer
/use Master Healthstone
/use Super Healing Potion
```

One press, healed by whatever you have — at the cost that a press can spend a
spell *and* a healthstone. At 20% health that's usually a trade worth making;
at 70% it's a wasted stone. Off by default, because spending your consumables
without asking is the worse surprise.

## The full-health problem

Using a healing item at full health fails harmlessly — the game refuses before
anything is consumed, and a failed line doesn't stop the rest of the macro.
Spells have no such protection: Desperate Prayer or Lay on Hands will cast at
100% health, heal nothing, and go on cooldown.

**Spell guard** (default: above 90%) handles this. Above the threshold, spell
lines are emitted with a `[combat]` conditional instead of plain:

```
/cast [combat] Desperate Prayer
/use Super Healing Potion
```

Note it *gates* the spell rather than dropping it. Dropping would be worse
than useless — you're almost always at full health when you pull, so the chain
you take into the fight would be the one without your cooldowns in it.
`[combat]` keeps them out of reach of an idle click while leaving them armed
for the fight.

Set the slider to 100% to switch it off.

## Config

`/healpop` (or `/hp`) opens the config.

- **Priority** — reorder categories with `^` / `v`, or uncheck to disable one.
- **Available to this character** — every spell and item HealPop found, with a
  checkbox each. Uncheck the ones you're saving.
- **Panel side** — top, right, bottom, or left of the button.
- **Scale, button size, background opacity, panel rows.**
- **Moving the button** — while this window is open the button is unlocked:
  it takes a gold border, drag it anywhere to reposition, and it will not fire
  a heal. Closing the window locks it again. There is no separate lock
  setting, and no cog to hunt for.
- **Heal text size** and **font** — applied live.
- **Spell guard** — see above; 100% disables it.
- **Always show panel** — pin the panel open instead of on mouseover.

Other commands:

```
/hp list       print the full priority ranking with cooldowns
/hp debug      print the button's live secure attributes
/hp macro      print the macro the button is currently holding
```

## Key binding

Key Bindings → HealPop → *Pop best heal*. Binding a key is the point of this
addon; clicking a button mid-pull is not.

## Install

Drop the `HealPop` folder into:

```
World of Warcraft/_classic_era_/Interface/AddOns/
World of Warcraft/_anniversary_/Interface/AddOns/
```

## License

MIT — see [LICENSE](LICENSE).

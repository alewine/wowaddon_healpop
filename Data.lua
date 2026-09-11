-- HealPop data tables.
--
-- Heal values here are FALLBACKS. At runtime we tooltip-scan every spell and
-- item and prefer what the client actually reports, so these only matter when
-- a tooltip can't be read (item not cached yet, odd locale, etc).
--
-- `heal` is a flat HP fallback. Spells whose value can't be read off a
-- tooltip ("heals for your total health") carry a `special` key instead.
--
-- Spells are keyed by a reference spellID purely to resolve the *localized*
-- name and icon. Actual availability comes from a spellbook scan, so rank IDs
-- never need listing -- `/cast <name>` always fires your highest known rank.

local ADDON, ns = ...

ns.CATEGORIES = {
    { key = "spells",    label = "Spells",       default = true  },
    { key = "stones",    label = "Healthstones", default = true  },
    { key = "potions",   label = "Potions",      default = true  },
    { key = "trinkets",  label = "Trinkets",     default = false },
    { key = "food",      label = "Food & Tubers",default = false },
    { key = "bandages",  label = "Bandages",     default = false },
}

ns.DEFAULT_CATEGORY_ORDER = { "spells", "stones", "potions", "trinkets", "food", "bandages" }

-- The four faces every client ships with, so no media library is needed.
ns.FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF"   },
    { name = "Skurri",        path = "Fonts\\SKURRI.TTF"   },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.TTF" },
}

-- ── Spells ───────────────────────────────────────────────────────────

ns.SPELLS = {
    { id = 28880 },                       -- Gift of the Naaru (Draenei racial)
    { id = 13908 },                       -- Desperate Prayer (Human/Dwarf priest)
    { id = 633,   special = "maxhealth" },-- Lay on Hands
    { id = 12975, special = "pct30" },    -- Last Stand (+30% max health)
    { id = 22842 },                       -- Frenzied Regeneration (bear form)

    -- Shipped off: no cooldown, or situational enough that leaving them on
    -- would permanently pin the top of the priority list.
    { id = 20577, off = true, special = "pct35" }, -- Cannibalize (Undead, needs a corpse)
    { id = 17,    off = true },           -- Power Word: Shield
    { id = 11426, off = true },           -- Ice Barrier
    { id = 139,   off = true },           -- Renew
    { id = 774,   off = true },           -- Rejuvenation
    { id = 6789,  off = true },           -- Death Coil (needs an enemy target)
}

-- ── Healthstones ─────────────────────────────────────────────────────
-- Three IDs per tier: base, Improved Healthstone rank 1 (+10%), rank 2 (+20%).
-- All three share a name, so the generated macro line is identical either way.

ns.HEALTHSTONES = {
    { id = 22103, heal = 2080 }, { id = 22104, heal = 2288 }, { id = 22105, heal = 2496 },
    { id = 9421,  heal = 1200 }, { id = 19012, heal = 1320 }, { id = 19013, heal = 1440 },
    { id = 5510,  heal = 800  }, { id = 19010, heal = 880  }, { id = 19011, heal = 960  },
    { id = 5509,  heal = 500  }, { id = 19008, heal = 550  }, { id = 19009, heal = 600  },
    { id = 5511,  heal = 250  }, { id = 19006, heal = 275  }, { id = 19007, heal = 300  },
    { id = 5512,  heal = 100  }, { id = 19004, heal = 110  }, { id = 19005, heal = 120  },
}

-- ── Potions ──────────────────────────────────────────────────────────

-- Engineering injectors belong here rather than in food: they carry the potion
-- effect and its shared cooldown, but GetItemInfo doesn't report them as
-- subtype "Potion", so auto-discovery drops them in the catch-all bucket.
ns.POTIONS = {
    { id = 31677, heal = 3200 },  -- Fel Regeneration Potion (over 12s, TBC)
    { id = 22829, heal = 2000 },  -- Super Healing Potion (1500-2500)
    { id = 33447, heal = 2000 },  -- Healing Potion Injector (1500-2500, TBC)
    { id = 28100, heal = 1400 },  -- Volatile Healing Potion (1050-1750)
    { id = 13446, heal = 1400 },  -- Major Healing Potion (1050-1750)
    { id = 3928,  heal = 800  },  -- Superior Healing Potion (700-900)
    { id = 1710,  heal = 520  },  -- Greater Healing Potion (455-585)
    { id = 929,   heal = 320  },  -- Healing Potion (280-360)
    { id = 858,   heal = 160  },  -- Lesser Healing Potion (140-180)
    { id = 118,   heal = 80   },  -- Minor Healing Potion (70-90)
}

-- ── Food, tubers, misc consumables (off the potion cooldown) ─────────

ns.FOOD = {
    { id = 11951, heal = 450 },   -- Whipper Root Tuber
    { id = 11563, heal = 400 },   -- Crystal Restore
    { id = 22645, heal = 400 },   -- Fel Blossom
}

-- ── Bandages ─────────────────────────────────────────────────────────

ns.BANDAGES = {
    { id = 21991, heal = 3400 },  -- Heavy Netherweave Bandage
    { id = 21990, heal = 2000 },  -- Netherweave Bandage
    { id = 14530, heal = 2000 },  -- Heavy Runecloth Bandage
    { id = 14529, heal = 1360 },  -- Runecloth Bandage
    { id = 8545,  heal = 800  },  -- Heavy Mageweave Bandage
    { id = 8544,  heal = 640  },  -- Mageweave Bandage
    { id = 6451,  heal = 400  },  -- Heavy Silk Bandage
    { id = 6450,  heal = 301  },  -- Silk Bandage
    { id = 3531,  heal = 240  },  -- Heavy Wool Bandage
    { id = 3530,  heal = 161  },  -- Wool Bandage
    { id = 2581,  heal = 114  },  -- Heavy Linen Bandage
    { id = 1251,  heal = 66   },  -- Linen Bandage
}

-- Items we know about but never want offered, even though their tooltip
-- mentions health (auto-discovery would otherwise pick them up).
ns.ITEM_BLACKLIST = {
    [19440] = true,  -- Powerful Anti-Venom
    [6452]  = true,  -- Anti-Venom
    [6453]  = true,  -- Strong Anti-Venom
    -- Soulstones. The tooltip's "resurrect upon death with 400 health" reads
    -- as a heal to any pattern loose enough to catch real ones; the reject
    -- patterns handle it too, but these are worth naming outright.
    [5232]  = true,  -- Minor Soulstone
    [16892] = true,  -- Lesser Soulstone
    [16893] = true,  -- Soulstone
    [16895] = true,  -- Greater Soulstone
    [16896] = true,  -- Major Soulstone
    [22116] = true,  -- Master Soulstone
}

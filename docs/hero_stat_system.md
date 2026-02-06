# Hero Stat System Design

## Overview

3 core stats: **HP**, **ATK**, **DEF**. Each hero has base values that vary by role. Stats can be increased by items and buffs during battle.

---

## Stats

### HP (Health Points)
- **Base HP**: 10-13 (varies by hero)
- **HP Multiplier**: ×11-15 (varies by class/hero)
- **Max HP** = `base_hp × hp_multiplier`
- When max HP increases (e.g., from items), **current HP stays the same** — it does not auto-fill
- Heals scale off caster's **max HP**

### ATK (Attack)
- **Range**: 10-18 (varies by class)
- Basic attacks and damage skills scale off ATK
- Items can increase ATK

### DEF (Defense)
- **Base DEF**: 0-5 (varies by class)
- **Max DEF**: 15 (achievable via items/buffs)
- Provides percentage-based damage reduction
- Shields scale off DEF
- Items can increase DEF

---

## Formulas

### Damage (Attack / Damage Skills)
```
raw_damage = caster_ATK × card_atk_multiplier
```

### Heal
```
heal_amount = caster_max_HP × card_hp_multiplier
```

### Shield
```
shield_amount = card_base_shield + (caster_DEF × card_def_multiplier)
```

### Damage Reduction (DEF)
```
reduction_percent = min(DEF × 2, 30)
final_damage = max(1, raw_damage × (1.0 - reduction_percent / 100))
```

- Every **1 DEF = 2% damage reduction**
- **Max reduction: 30%** (at 15 DEF)
- **Minimum damage: 1** (damage can never be fully negated)

| DEF | Reduction | 20 raw → takes | 36 raw → takes |
|-----|-----------|----------------|----------------|
| 0   | 0%        | 20             | 36             |
| 1   | 2%        | 20             | 35             |
| 2   | 4%        | 19             | 35             |
| 3   | 6%        | 19             | 34             |
| 4   | 8%        | 18             | 33             |
| 5   | 10%       | 18             | 32             |
| 8   | 16%       | 17             | 30             |
| 10  | 20%       | 16             | 29             |
| 12  | 24%       | 15             | 27             |
| 15  | 30%       | 14             | 25             |

---

## Scaling Rules

| Card Type       | Scales Off       | Formula                                  |
|-----------------|------------------|------------------------------------------|
| Basic Attack    | Caster ATK       | `ATK × multiplier`                       |
| Damage Skill    | Caster ATK       | `ATK × multiplier`                       |
| Heal            | Caster max HP    | `max_HP × multiplier`                    |
| Shield          | Caster DEF       | `card_base + (DEF × multiplier)`         |
| Incoming Damage | Target DEF       | `max(1, raw × (1 - min(DEF×2,30)/100))` |

---

## Hero Stat Distribution

| Role               | Base HP | HP Multi | Max HP | ATK | Base DEF |
|---------------------|---------|----------|--------|-----|----------|
| Tank (Squire)       | 12      | ×14      | 168    | 10  | 5        |
| Tank (Makash)       | 13      | ×15      | 195    | 10  | 5        |
| Tank (Stony)        | 13      | ×14      | 182    | 11  | 4        |
| DPS (Markswoman)    | 11      | ×13      | 143    | 18  | 1        |
| Mage (Caelum)       | 10      | ×12      | 120    | 16  | 0        |
| Mage (Raizel)       | 10      | ×13      | 130    | 15  | 1        |
| Support (Priest)    | 11      | ×12      | 132    | 12  | 3        |
| Scientist (Dana)    | 10      | ×11      | 110    | 14  | 1        |

### Role Identity
- **Tanks**: High HP, high DEF, low ATK — absorb damage, strong shields
- **DPS**: Medium HP, high ATK, low DEF — glass cannon
- **Mages**: Low HP, high ATK, very low DEF — burst damage, fragile
- **Support**: Medium HP, medium ATK, medium DEF — balanced, strong heals (high max HP scaling)
- **Scientist**: Low HP, medium ATK, low DEF — utility/debuff focused

---

## Item System

Items can boost **base stats**: `base_hp`, `ATK`, `DEF`.

HP items are **class-weighted** via the hp_multiplier:
- "+1 base HP" on Makash (×15) = **+15 effective max HP**
- "+1 base HP" on Caelum (×12) = **+12 effective max HP**

ATK/DEF items give flat increases regardless of class.

---

## All Skills — Current vs New Values

### Squire (Tank — ATK 10, DEF 5, Max HP 168)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(10) | ×1.0 | **10 dmg** |
| Shield Bash | attack+stun | ATK(10) | ×1.0 | 10 dmg | ATK(10) | ×1.0 | **10 dmg** |
| Rally | buff | — | — | empower | — | — | **empower** |
| Fortify | shield/all_ally | ATK(10) | shield×1.0 | 10 shield | DEF(5) | base 5 + ×3.0 | **20 shield** |
| EX: Guardian's Oath | attack+stun | ATK(10) | ×2.0 | 20 dmg | ATK(10) | ×2.0 | **20 dmg** |

### Priest (Support — ATK 12, DEF 3, Max HP 132)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(12) | ×1.0 | **12 dmg** |
| Heal | heal/single | ATK(10) | heal×2.0 | 20 heal | max_HP(132) | hp×0.15 | **20 heal** |
| Blessing | heal/all_ally | ATK(10) | heal×1.0 | 10 heal | max_HP(132) | hp×0.08 | **11 heal** |
| Purify | heal+cleanse | ATK(10) | heal×1.0 | 10 heal | max_HP(132) | hp×0.08 | **11 heal** |
| EX: Divine Light | revive+heal/all | ATK(10) | heal×3.0 | 30 heal | max_HP(132) | hp×0.30 | **40 heal** |

### Markswoman (DPS — ATK 18, DEF 1, Max HP 143)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(18) | ×1.0 | **18 dmg** |
| Aimed Shot | attack/single | ATK(10) | ×3.0 | 30 dmg | ATK(18) | ×2.0 | **36 dmg** |
| Rapid Shot | attack/all_enemy | ATK(10) | ×1.0 | 10 dmg ea | ATK(18) | ×0.7 | **13 dmg ea** |
| Focus | buff/self | — | — | empower | — | — | **empower** |
| EX: Bullseye | attack/single | ATK(10) | ×4.0 | 40 dmg | ATK(18) | ×3.0 | **54 dmg** |

### Dana (Scientist — ATK 14, DEF 1, Max HP 110)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(14) | ×1.0 | **14 dmg** |
| Dig | utility | — | — | dig 3 | — | — | **dig 3** |
| Repair | heal/single | ATK(10) | heal×2.0 | 20 heal | max_HP(110) | hp×0.18 | **20 heal** |
| Barrier | shield/single | ATK(10) | shield×2.0 | 20 shield | DEF(1) | base 15 + ×5.0 | **20 shield** |
| EX: Mech Overdrive | attack+empower_all | ATK(10) | ×2.0 | 20 dmg | ATK(14) | ×1.5 | **21 dmg** |

### Makash (Tank — ATK 10, DEF 5, Max HP 195)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(10) | ×1.0 | **10 dmg** |
| Killing Chop | attack/front | ATK(10) | ×1.0 | 10 dmg | ATK(10) | ×1.0 | **10 dmg** |
| Bull Rage | energy/self | — | flat 40 | 40 energy | — | flat 40 | **40 energy** |
| Bull Taunt | shield+taunt | ATK(10) | shield×2.0 | 20 shield | DEF(5) | base 5 + ×3.0 | **20 shield** |
| EX: Rampage | attack/all_enemy | ATK(10) | ×3.0 | 30 dmg ea | ATK(10) | ×3.0 | **30 dmg ea** |

### Stony (Tank — ATK 11, DEF 4, Max HP 182)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(11) | ×1.0 | **11 dmg** |
| Stone Call | taunt/self | — | — | taunt | — | — | **taunt** |
| Stone Punch | attack/front | ATK(10) | ×2.0 | 20 dmg | ATK(11) | ×2.0 | **22 dmg** |
| Stone Armor | shield/self | ATK(10) | shield×4.0 | 40 shield | DEF(4) | base 15 + ×6.0 | **39 shield** |
| EX: Stone Fortress | shield+taunt | ATK(10) | shield×6.0 | 60 shield | DEF(4) | base 20 + ×10.0 | **60 shield** |

### Caelum (Mage — ATK 16, DEF 0, Max HP 120)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(16) | ×1.0 | **16 dmg** |
| Mana Surge | attack (all mana) | ATK(10) | ×1.0/mana | 10/mana | ATK(16) | ×0.6/mana | **10/mana** |
| Arcane Bolt | attack/single | ATK(10) | ×2.0 | 20 dmg | ATK(16) | ×1.5 | **24 dmg** |
| Future Sight | draw/self | — | — | draw 1 | — | — | **draw 1** |
| EX: Arcane Storm | attack/all_enemy | ATK(10) | ×2.5 | 25 dmg ea | ATK(16) | ×1.6 | **26 dmg ea** |

### Raizel (Mage — ATK 15, DEF 1, Max HP 130)

| Card | Type | Old Scales | Old Multi | Old Value | New Scales | New Multi | New Value |
|------|------|-----------|-----------|-----------|-----------|-----------|-----------|
| Attack | basic_attack | ATK(10) | ×1.0 | 10 dmg | ATK(15) | ×1.0 | **15 dmg** |
| Thunder Strike | attack+thunder | ATK(10) | ×1.0 | 10 dmg | ATK(15) | ×0.7 | **11 dmg** |
| Thunder Punish | debuff/all_enemy | — | — | thunder all | — | — | **thunder all** |
| Thunder Stack | debuff/single | — | — | +2 stacks | — | — | **+2 stacks** |
| EX: Thunder God | thunder_detonate | — | — | detonate all | — | — | **detonate all** |

---

## Summary of Changes

### What changed
- **Damage cards**: ATK now varies per hero (10-18), multipliers adjusted to keep values near old balance
- **Heal cards**: Switched from `ATK × heal_multiplier` → `max_HP × hp_multiplier`
- **Shield cards**: Switched from `ATK × shield_multiplier` → `base_shield + DEF × def_multiplier`
- **DEF**: New stat, provides 2% damage reduction per point (max 30% at 15 DEF)

### What stayed the same
- Utility cards (taunt, empower, draw, energy, thunder) — no stat scaling
- Card costs unchanged
- Card effects (stun, cleanse, etc.) unchanged

### Key balance notes
- DPS (Markswoman) basic attack: 10 → **18** (+80%) — she's a glass cannon now
- Tank basic attacks stay low (10-11) — they're not damage dealers
- Priest heals scale off her own max HP (132), not ATK — supports heal well
- Tank shields scale off DEF (4-5) — they get the best shields
- Dana (DEF 1) Barrier uses high base_shield (15) to compensate for low DEF

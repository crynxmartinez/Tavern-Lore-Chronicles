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

## Examples

### Markswoman basic attack
```
ATK = 18, multiplier = 1.0
raw_damage = 18
vs Squire (DEF 5, 10% reduction): final = max(1, 18 × 0.90) = 16
vs Caelum (DEF 0, 0% reduction): final = 18
```

### Priest heal
```
max_HP = 132, multiplier = 0.15
heal = 132 × 0.15 = 19.8 → 20
```

### Squire shield card
```
card_base = 10, DEF = 5, def_multiplier = 3.0
shield = 10 + (5 × 3.0) = 25
```

### Squire shield card (with +3 DEF from items, DEF = 8)
```
shield = 10 + (8 × 3.0) = 34
```

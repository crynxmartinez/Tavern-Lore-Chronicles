# Tavern Lore Chronicles

A turn-based tactical card battle game built with **Godot 4.6 Stable**.

Draft your team of 3 heroes, build a combined deck from their unique cards, and battle your opponent in strategic 3v3 card combat. Each hero brings their own skills, EX abilities, and playstyle to the table.

## Gameplay

### Core Loop
1. **Draft Phase** — Select 3 heroes for your team from the roster
2. **Mulligan** — Redraw cards you don't want from your opening hand
3. **Rock-Paper-Scissors** — Determines who goes first
4. **Battle** — Take turns playing cards from your combined deck to defeat the enemy team

### Battle Mechanics
- **Mana System** — Start with 3 mana, gain +1 per turn (cap: 10). Cards cost mana to play.
- **Card Queue** — Cards resolve in order; plan your combos carefully.
- **EX Skills** — Each hero has a powerful ultimate ability. Build energy by attacking and taking hits (100 energy to activate).
- **Front-Line Targeting** — Attacks hit the front enemy hero unless a Taunt is active.
- **Equipment** — Equip items to heroes for passive bonuses (auto-revive, empower triggers, etc.)

### Card Types
- **Attack** — Deal damage to enemies (scales with hero ATK)
- **Heal** — Restore HP to allies (scales with hero max HP)
- **Buff** — Apply positive effects (Empower, Shield, Taunt, Regen, etc.)
- **Debuff** — Apply negative effects (Stun, Weak, Bleed, Burn, etc.)
- **Mana** — Gain extra mana for the turn
- **Energy** — Charge EX gauge faster

### Buffs
| Buff | Effect |
|------|--------|
| **Empower** | +50% damage dealt |
| **Empower Heal** | +50% healing done |
| **Empower Shield** | +50% shield given |
| **Shield** | Absorbs damage before HP |
| **Taunt** | Enemies must target this hero |
| **Regen** | Delayed heal at turn start (stacks) |
| **Counter** | Reflects 50% or 100% damage back to attacker |
| **Redirect** | 50% of damage taken is transferred to another ally |
| **Damage Link** | Damage taken is shared among all linked allies |
| **Crescent Moon** | At 4 stacks: consume all, fill EX gauge to max |
| **Eclipse** | Next EX this turn deals double damage |

### Debuffs
| Debuff | Effect |
|--------|--------|
| **Stun** | Cannot act next turn (cards show stun overlay) |
| **Weak** | -50% damage dealt |
| **Bleed** | Takes damage when playing a card (post-action) |
| **Burn** | Takes damage at turn end |
| **Poison** | Takes damage at turn start |
| **Frost** | +1 mana cost to all cards |
| **Chain** | Cannot use skills |
| **Break** | +50% damage taken |
| **Thunder** | Lightning strikes at turn end (stacks, 60% ATK per stack) |
| **Time Bomb** | Detonates at end of turn — damage and discards stack |
| **Marked** | Takes increased damage |

## Heroes (16 Playable)

### Tanks (Yellow)
- **Squire** (Joren Kydd) — EX: Guardian's Oath (200% ATK + Stun)
- **Makash** (Makash Barok) — EX: Rampage (300% ATK + Penetrate + Weak)
- **Stony** (Stony Granitefist) — EX: Goliath Strength (Taunt + Shield equal to current HP)
- **Gavran** (Sir Gavran Uldric) — EX: Boneforge Aegis (Counter 100% + Self Break)
- **Kalasag** (Captain Ramil Serrano) — EX: Tidal Bulwark (Shield all allies)

### DPS (Red)
- **Markswoman** (Rhea Valen) — EX: Bullseye (300% ATK single target)
- **Cinder** (Seraphine Azuela) — EX: Cinder Storm (Generate 3 Cinder Strike cards)
- **Dax** (Dax Aerwyn) — EX: Storm Lance (250% ATK, bypasses Shield)

### Mages (Blue)
- **Caelum** (Caelum Veyr) — EX: Arcane Storm (160% ATK to all enemies + Break)
- **Raizel** (Raizel Storme) — EX: Thunder God (2 Thunder stacks to all enemies)
- **Valen** (Valen Corvane) — EX: Crimson Verdict (300% ATK, lifesteal mechanics)
- **Nyxara** (Nyxara Vael) — EX: Total Eclipse (160% ATK to all enemies, Crescent Moon synergy)

### Support (Green)
- **Priest** (Sister Luciana Hale) — EX: Divine Light (Heal or Revive target)
- **Amihan** (Elder Amihan Dalisay) — EX: Bayani's Hymn (Cleanse all allies + Dispel all enemy buffs)
- **Ysolde** (Sister Ysolde Mirelle) — EX: Thread of Life (Damage Link all allies + Regen)

### Scientists (Purple/Violet)
- **Dana** (Engr. Elara Quinto) — EX: Mech Overdrive (150% ATK + Empower all allies)
- **Nyra** (Nyra Sato) — EX: Temporal Shift (Rewind all allies' HP to last turn + Revive)
- **Scrap** (Tomas Ibarra) — EX: Scrapyard Overflow (Draw 3, discard 2)

## Game Modes

### Practice Mode (vs AI)
- Play against AI-controlled opponents
- Practice tools: reset HP, fill EX, clear status, switch sides
- AI uses strategic card selection based on game state

### Multiplayer (1v1 via LAN)
- **Host-authoritative** model using Godot's built-in ENet
- Default port: **7777**
- Direct IP connection (ideal for LAN or VPN)

## How to Play Multiplayer

1. Both players install [Radmin VPN](https://www.radmin-vpn.com/) (free)
2. Create or join the same Radmin VPN network
3. **Host:** Click "HOST GAME" — share your Radmin VPN IP with your opponent
4. **Guest:** Enter the host's IP and click "JOIN"
5. Port: **7777** (no port forwarding needed with Radmin VPN)

## Project Structure

```
myturn/
├── asset/              # Art, sprites, icons, VFX, audio
│   ├── Hero/           # Hero sprites (idle, attack, cast, hit + flipped)
│   ├── buff debuff/    # Status effect icons
│   ├── card template/  # Card frame templates (color-coded per hero)
│   └── Others/         # Misc assets (RIP grave, backgrounds, etc.)
├── data/               # Game data (JSON)
│   ├── heroes.json     # Hero stats, sprites, EX skills, card lists
│   ├── cards.json      # Card definitions (cost, type, effects, multipliers)
│   ├── equipment.json  # Equipment items and passive effects
│   └── templates.json  # Card template frame definitions
├── scenes/             # Godot scene files (.tscn)
│   ├── account/        # Login screen
│   ├── battle/         # Battle scene + sub-components
│   ├── collection/     # Card collection viewer
│   ├── components/     # Reusable UI (Card, Hero, HeroStatCard)
│   ├── dashboard/      # Main menu / dashboard
│   ├── effects/        # VFX scenes
│   ├── team_editor/    # Team drafting / hero selection
│   └── ui/             # Multiplayer lobby
├── scripts/            # GDScript source
│   ├── autoload/       # Singletons (GameManager, databases, audio, networking)
│   ├── battle/         # Battle logic, AI, network manager, state management
│   ├── components/     # Card & Hero component scripts
│   ├── core/           # Game constants, shared utilities
│   ├── debug/          # Debug tools
│   ├── effects/        # VFX scripts
│   └── ui/             # UI scripts (lobby)
└── addons/             # Godot plugins (VFX library)
```

## Technical Details

- **Engine:** Godot 4.6 Stable
- **Language:** GDScript
- **Resolution:** 1920x1080 (viewport stretch, expand aspect)
- **Rendering:** Forward Plus
- **Networking:** ENet (Godot built-in), host-authoritative model
- **Data-driven:** Heroes, cards, and equipment defined in JSON

## Building from Source

1. Install [Godot 4.6 Stable](https://godotengine.org/download)
2. Clone this repository
3. Open `project.godot` in Godot
4. Run with F5 or export via Project > Export

## Exporting for Distribution

1. In Godot: **Editor > Manage Export Templates > Download and Install**
2. **Project > Export > Add... > Windows Desktop**
3. Click **Export Project** — generates `.exe` + `.pck`
4. Zip and upload to itch.io as a downloadable game

## License

All rights reserved. This is a private project.

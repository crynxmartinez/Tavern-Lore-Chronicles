# PVP Battle System Architecture

## HOST-AUTHORITATIVE MODEL (CRITICAL)

**The Host is the single source of truth for all game logic.**

### Flow Diagrams

```
HOST'S TURN:
┌──────────┐    execute     ┌──────────┐    send results   ┌──────────┐
│   HOST   │ ────────────►  │   HOST   │ ───────────────►  │  GUEST   │
│  clicks  │                │ executes │                   │ applies  │
│   card   │                │  logic   │                   │ results  │
└──────────┘                └──────────┘                   └──────────┘

GUEST'S TURN:
┌──────────┐  send request  ┌──────────┐    send results   ┌──────────┐
│  GUEST   │ ────────────►  │   HOST   │ ───────────────►  │  GUEST   │
│  clicks  │                │ executes │                   │ applies  │
│   card   │                │  logic   │                   │ results  │
└──────────┘                └──────────┘                   └──────────┘
                                 │
                                 ▼
                            Host also applies
                            results locally
```

### Key Rules

1. **Host ALWAYS executes game logic** (damage calc, buff application, etc.)
2. **Guest NEVER executes game logic** for PVP actions - only sends requests
3. **Both clients apply RESULTS identically** (just set HP, add buffs - no calculation)
4. **Results contain final values** (not formulas or multipliers)

### Message Types

```gdscript
# Guest → Host: ACTION REQUEST
{
    "msg_type": "action_request",
    "action_type": "play_card",  # or "end_turn", "use_ex_skill"
    "card_data": { ... },        # Full card data
    "source_hero_id": "makash",
    "target_hero_id": "enemy_priest",
    "timestamp": 1234567890
}

# Host → Guest: ACTION RESULT (also applied by Host locally)
{
    "msg_type": "action_result",
    "action_type": "play_card",
    "success": true,
    "card_data": { ... },        # Card that was played
    "source_hero_id": "makash",
    "target_hero_id": "enemy_priest",
    "effects": [
        { "type": "damage", "hero_id": "enemy_priest", "amount": 25, "new_hp": 75 },
        { "type": "buff", "hero_id": "makash", "buff_type": "thorns", "duration": 2 },
        { "type": "block", "hero_id": "makash", "amount": 10, "new_block": 10 }
    ],
    "mana_spent": 2,
    "new_mana": 3
}
```

---

## Overview

This document describes the complete OOP architecture for the PVP battle system.

## Design Principles
- **Command Pattern**: All actions are objects (serializable, replayable)
- **Strategy Pattern**: Effects are interchangeable (easy to add new types)
- **Observer Pattern**: Events decouple logic from UI
- **Single Source of Truth**: One GameState, synced to all clients

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         BATTLE CONTROLLER                           │
│                         (Orchestrator)                              │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
         ▼                     ▼                     ▼
  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
  │   ACTION    │      │    STATE    │      │   EFFECT    │
  │   SYSTEM    │ ───► │   SYSTEM    │ ◄─── │   SYSTEM    │
  │             │      │             │      │             │
  │ PlayCard    │      │ GameState   │      │ Damage      │
  │ UseEXSkill  │      │ PlayerState │      │ Heal        │
  │ EndTurn     │      │ HeroState   │      │ Buff/Debuff │
  └─────────────┘      └─────────────┘      └─────────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │     EVENT BUS       │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌───────────┐    ┌───────────┐    ┌───────────┐
       │  NETWORK  │    │    UI     │    │   AUDIO   │
       └───────────┘    └───────────┘    └───────────┘
```

---

## Key Concept: No Enemy Deck in PVP

```
Player 1 (Host)                       Player 2 (Guest)
┌─────────────────┐                   ┌─────────────────┐
│ MY Heroes (left)│ ◄── Team Sync ──► │ MY Heroes (left)│
│ Enemy (right)   │                   │ Enemy (right)   │
├─────────────────┤                   ├─────────────────┤
│ MY Deck/Hand    │                   │ MY Deck/Hand    │
│ (only I see)    │                   │ (only I see)    │
├─────────────────┤                   ├─────────────────┤
│ Enemy Hand      │                   │ Enemy Hand      │
│ COUNT only (5)  │                   │ COUNT only (5)  │
└─────────────────┘                   └─────────────────┘
```

---

## State Classes

### GameState
- battle_id, turn_number, current_player_index
- phase: MULLIGAN, PLAYING, GAME_OVER
- players: Array[PlayerState]
- action_history: Array[ActionRecord]

### PlayerState
- player_index, client_id, username, is_host
- mana, max_mana
- heroes: Array[HeroState]
- deck_count, hand_count, hand: Array[CardData]

### HeroState
- hero_id, owner_index, position
- hp, max_hp, attack, base_attack
- energy, max_energy, block, is_dead
- buffs: Array[BuffState], debuffs: Array[DebuffState]

### BuffState / DebuffState
- type, value, duration, source_hero_id, stack_count

---

## Action Classes (Command Pattern)

### BaseAction (Abstract)
- action_type, player_index, timestamp
- validate(game_state) → ValidationResult
- execute(game_state) → ActionResult
- serialize() → Dictionary

### PlayCardAction
- card_data, source_hero_id, target_hero_id, hand_index

### UseEXSkillAction
- source_hero_id, target_hero_id, skill_type

### EndTurnAction
- (no extra data)

### MulliganAction
- card_indices: Array[int]

---

## Effect Classes (Strategy Pattern)

### BaseEffect (Abstract)
- effect_type, base_value
- can_apply(), get_modified_value(), apply()

### Effect Types
- DamageEffect - reduces HP, blocked by shield
- HealEffect - restores HP
- BuffEffect - adds buff to target
- DebuffEffect - adds debuff to target
- ShieldEffect - adds block
- EnergyEffect - adds energy
- DrawEffect - draw cards
- DispelEffect - remove buffs/debuffs

---

## Effect Pipeline

```
Input: EffectData
    │
    ▼
┌─────────────────────────────────────┐
│ 1. CREATE EFFECT                    │
│    EffectFactory.create(data)       │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 2. PRE-EFFECT CHECKS                │
│    - Target alive? Immune?          │
│    - Shields/barriers?              │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 3. CALCULATE MODIFIERS              │
│    - Attack buffs/debuffs           │
│    - Defense buffs/debuffs          │
│    - Equipment modifiers            │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 4. APPLY EFFECT                     │
│    - Update HeroState               │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 5. POST-EFFECT TRIGGERS             │
│    - Thorns, lifesteal, on-kill     │
│    - Death check                    │
└─────────────────────────────────────┘
    │
    ▼
Output: EffectResult
```

---

## Event Bus (Observer Pattern)

### Game Events
- battle_started, turn_started, turn_ended, battle_ended

### Action Events
- action_executed, action_received

### Effect Events
- damage_dealt, heal_applied, buff_applied, debuff_applied
- shield_gained, shield_broken

### Hero Events
- hero_hp_changed, hero_energy_changed, hero_died, hero_ex_ready

### Card Events
- card_played, card_drawn, hand_changed

### Network Events
- opponent_connected, opponent_disconnected, sync_completed

---

## Network Sync: Result Sync Strategy

```
Player 1 (Local)                      Player 2 (Remote)
┌─────────────────┐                   
│ 1. Create Action│                   
│ 2. Validate     │                   
│ 3. Execute      │                   
│ 4. Update State │                   
│ 5. Emit Events  │                   
│ 6. Send Action  │ ─────────────────► 7. Receive
│    + Result     │                      Action+Result
└─────────────────┘                   │ 8. Apply Result
                                      │ 9. Update State
                                      │ 10. Emit Events
                                      └─────────────────┘

KEY: Receiver applies RESULT directly, no re-execution
```

---

## Perspective Translation

Each player sees THEIR heroes on LEFT.

```
HeroIdentifier {
  hero_id: "priest",
  owner_index: 0  # 0 = host's hero, 1 = guest's hero
}
```

Player 1 attacking Player 2's priest:
- Send: { hero_id: "priest", owner_index: 1 }
- Player 1 sees: enemy priest (right)
- Player 2 sees: my priest (left)

---

## Folder Structure (IMPLEMENTED)

```
scripts/battle/
├── battle_controller.gd      ✅ CREATED
├── battle_ui_adapter.gd      ✅ CREATED
├── battle_network_manager.gd ✅ UPDATED
│
├── state/
│   ├── game_state.gd         ✅ CREATED
│   ├── player_state.gd       ✅ CREATED
│   ├── hero_state.gd         ✅ CREATED
│   └── buff_state.gd         ✅ CREATED
│
├── actions/
│   ├── base_action.gd        ✅ CREATED
│   ├── play_card_action.gd   ✅ CREATED
│   ├── use_ex_skill_action.gd ✅ CREATED
│   ├── end_turn_action.gd    ✅ CREATED
│   └── action_factory.gd     ✅ CREATED
│
├── effects/
│   ├── base_effect.gd        ✅ CREATED
│   ├── damage_effect.gd      ✅ CREATED
│   ├── heal_effect.gd        ✅ CREATED
│   ├── buff_effect.gd        ✅ CREATED
│   ├── shield_effect.gd      ✅ CREATED
│   ├── energy_effect.gd      ✅ CREATED
│   ├── effect_pipeline.gd    ✅ CREATED
│   └── effect_factory.gd     ✅ CREATED
│
└── events/
    └── battle_event_bus.gd   ✅ CREATED
```

---

## Implementation Phases

### Phase 1: State Classes
- game_state.gd, player_state.gd, hero_state.gd, buff_state.gd

### Phase 2: Event System
- battle_event_bus.gd

### Phase 3: Effect System
- base_effect.gd, damage_effect.gd, heal_effect.gd, etc.
- effect_pipeline.gd, effect_factory.gd

### Phase 4: Action System
- base_action.gd, play_card_action.gd, etc.
- action_factory.gd

### Phase 5: Battle Controller
- battle_controller.gd (orchestrator)

### Phase 6: Network Integration
- Update battle_network_manager.gd

### Phase 7: UI Integration
- Connect battle.gd to event bus

### Phase 8: Testing
- Test AI mode, Test PVP mode

---
name: Effects System (Data-Driven)
description: Data-driven effect architecture for cards, debuffs, triggers, and multiplayer replication
---

# Goals

- Make new hero mechanics (e.g. `hp_cost_pct`, `bleed` triggers, conditional heals) implementable by adding **effect handlers** and referencing them from JSON.
- Keep cards/EX definitions as **data** (`cards.json`, `heroes.json`) with minimal bespoke battle code.
- Unify:
	- Validation (can this action be taken?)
	- Execution (what happens?)
	- Replication (host → guest)
	- AI usage
- Preserve backward compatibility with existing `effects: ["stun", "weak", ...]` string arrays.

# Non-Goals (for now)

- Rewrite all battle logic.
- Replace all existing card types (attack/heal/buff/etc.).
- Remove existing legacy effect string handling immediately.

# Glossary

- **EffectSpec**: the data describing an effect to execute.
- **Op**: a normalized state change record used for host execution and guest replication.
- **EffectContext**: all inputs required to evaluate/execute an effect.

# Data Model

## Implementation Status

- Phase 0 (conventions + normalization): Implemented in `scripts/battle/battle.gd`
	- Added canonical effect type constants
	- Added `_normalize_effects(raw_effects, source, primary_target)`
	- No gameplay behavior changes yet (normalization only)

- Phase 1 (Op structures + single guest apply entry point): Implemented in `scripts/battle/battle.gd`
	- Added Op type constants (`OP_DAMAGE`, `OP_HEAL`, `OP_BLOCK`, `OP_BUFF`, `OP_DEBUFF`, `OP_ENERGY`, `OP_CLEANSE`, `OP_DRAW`)
	- Added `_apply_ops(ops)` and routed Guest result application through it
	- No gameplay behavior changes yet (still applies the same per-op logic via `_apply_effect`)

- Phase 2 (EffectRegistry + initial handlers): Implemented in `scripts/battle/battle.gd`
	- Added `_effect_registry` mapping `EffectSpec.type` -> handler callable
	- Added `_init_effect_registry()` and called it from `_ready()`
	- Added `_dispatch_effect_spec(ctx, spec)`
	- Added initial handlers that return Ops (apply_buff/apply_debuff/cleanse/cleanse_all/dispel/dispel_all/damage/heal)
	- Not wired into card execution yet (Phase 3)

- Phase 3 (pipeline wiring - partial): In progress in `scripts/battle/battle.gd`
	- `_collect_effects_snapshot(...)` now:
		- normalizes legacy `effects` using `_normalize_effects(...)`
		- dispatches common EffectSpecs via `_dispatch_effect_spec(...)` to emit Ops
		- skips legacy duplicate snapshotting for effects already emitted
	- Normalization now supports targeting + multi-target:
		- `empower`/`taunt` correctly target `source`
		- `empower_target`, `empower_all`, `thunder_all` normalize to structured apply_* specs
	- Registry handlers support `target` modes: `source`, `primary`, `all_targets`, `allies`, `enemies`

- Phase 4 (hp_cost_pct + bleed trigger as effects): Implemented in `scripts/battle/battle.gd`
	- Added effect types: `hp_cost_pct`, `bleed_on_action`
	- Added handlers: `_eh_hp_cost_pct`, `_eh_bleed_on_action`
	- Host execution now applies these pre-action self effects via registry and emits `damage` Ops
	- Single-player + AI now use `_apply_pre_action_self_effects(...)` (registry-backed)

- Phase 5 (Ops-driven replication consolidation): Started in `scripts/battle/battle.gd`
	- Reduced Host precompute mutations by only calling `_apply_effects(...)` during precompute when needed for special-cases (e.g. `penetrate`)
	- Guest now supports applying `dispel` Ops by clearing buffs
	- Normalized additional special effects:
		- `draw_1` -> `draw` (registry + Ops)
		- `thunder_stack_2` -> handler-backed effect (registry + Ops)
	- `_collect_effects_snapshot(...)` legacy match reduced further to true special-cases

- Phase 6 (Valen content): Implemented
	- Added Valen cards to `data/cards.json` (`valen_attack`, `valen_sk1-3`, `valen_ex`)
	- Added Valen hero to `data/heroes.json` wired to those cards
	- Documented Valen kit in `docs/skills_reference.txt`

## EffectSpec (recommended format)

Cards and EX skills should support structured effects:

```json
{
  "type": "apply_debuff",
  "id": "bleed",
  "stacks": 1,
  "duration": 1,
  "expire_on": "own_turn_end"
}
```

### Recommended common EffectSpec shapes

- `{"type":"apply_debuff","id":"bleed","stacks":1,"duration":1,"expire_on":"own_turn_end"}`
- `{"type":"apply_buff","id":"empower","stacks":1,"duration":1,"expire_on":"own_turn_end"}`
- `{"type":"damage","amount":10,"true":true}`
- `{"type":"heal","amount":15}`
- `{"type":"cleanse"}`
- `{"type":"cleanse_all"}`
- `{"type":"dispel"}` (remove buffs)
- `{"type":"dispel_all"}`

## Legacy effects compatibility

Existing cards may use:

```json
"effects": ["stun", "weak", "bleed"]
```

These should be normalized into EffectSpec objects by a single function:

- `"stun"` → `{"type":"apply_debuff","id":"stun","stacks":1,"duration":1,"expire_on":"own_turn_end"}`
- `"bleed"` → `{"type":"apply_debuff","id":"bleed","stacks":1,"duration":1,"expire_on":"own_turn_end"}`

# Execution Model

## EffectContext (runtime input)

Effect handlers receive a context dictionary treated as a struct:

- `source: Hero`
- `primary_target: Hero | null`
- `targets: Array[Hero]` (pre-resolved multi-target list)
- `card_data: Dictionary`
- `is_ex: bool`
- `battle: Node` (battle.gd instance, for access to teams, utilities)

## Op (normalized result) — the replication format

All state changes must be expressed as Ops. Guests apply Ops without re-running game logic.

Examples:

- Damage (with updated HP and block)

```json
{ "type":"damage", "hero_id":"x", "instance_id":"...", "is_host_hero":true,
  "amount":10, "new_hp":90, "new_block":5 }
```

- Debuff

```json
{ "type":"debuff", "hero_id":"x", "instance_id":"...", "is_host_hero":true,
  "debuff_type":"bleed", "duration":1, "expire_on":"own_turn_end", "value":0 }
```

- Buff

```json
{ "type":"buff", "hero_id":"x", "instance_id":"...", "is_host_hero":true,
  "buff_type":"empower", "duration":1, "expire_on":"own_turn_end", "value":0 }
```

## EffectRegistry (handler map)

A single registry maps effect `type` → handler.

Implementation options:

- `Dictionary[String, Callable]`
- Autoload singleton `EffectRegistry.gd`

Handlers should have two responsibilities:

- `validate(ctx, spec) -> bool` (optional)
- `execute(ctx, spec) -> Array[Op]`

# Proposed Pipeline

## 1) Normalize effects

- If card has `effects` as strings → convert to EffectSpec array.
- If card has `effects` as dictionaries → use as-is.

## 2) Validate

- Run any handler `validate()`.
- Central validation includes:
	- mana availability (existing)
	- stun checks (existing)
	- `hp_cost_pct` checks via effect handler

## 3) Execute (Host-authoritative)

- Host computes Ops and sends them to Guest BEFORE animations.
- Host applies Ops locally.
- Guest receives Ops and applies them locally.

## 4) Animations

- Animations can be driven by:
	- card type
	- Ops (e.g. damage/heal)

# Migration Strategy

## Phase A — Add engine without breaking old cards

- Add `normalize_effects()`.
- Add `EffectRegistry` + a small set of handlers:
	- apply_debuff
	- apply_buff
	- damage
	- heal
	- cleanse / cleanse_all
	- dispel / dispel_all
	- hp_cost_pct
- Keep existing `_apply_effects()` for legacy; gradually route through the new engine.

## Phase B — Convert new heroes (Valen) to structured effects

- Valen cards use EffectSpec objects.
- Older heroes remain unchanged until needed.

## Phase C — Reduce duplication

- Remove hand-maintained snapshot code once Ops are the only replication path.

# Notes for Valen Mechanics

- `hp_cost_pct` should be modeled as a pre-action effect that emits a `damage` Op on the **source** with `true: true`.
- `bleed` is a debuff applied via `apply_debuff`.
- Bleed trigger should be represented as a trigger on action (`on_action`) that emits a true-damage Op on self, but never runs on EX actions.

# Acceptance Criteria

- Adding a new effect requires:
	- one handler implementation
	- one registry entry
	- JSON reference in a card
- Multiplayer Guest behavior matches Host exactly via Ops.
- Existing cards still function (legacy string effects).

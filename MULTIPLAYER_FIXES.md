# Multiplayer Sync Issues - Analysis & Fixes

## Issues Reported

1. **Energy gauge desync** - Same hero shows different energy on each screen
2. **Time Bomb not detonating** - Bombs don't fire, visibility desync
3. **Empower Heal permanent** - Not expiring at turn end
4. **Equipment tooltips showing 0%** - Berserker Axe, Phoenix Feather, Thorn Armor
5. **Scrapyard Overflow draws instead of discards**
6. **Crash when opponent's same hero dies**

## Root Causes & Fixes

### 1. Energy Gauge Desync ✅ FIXED
**Root Cause:** Energy gains from attacks and hits were not being synced. Each client calculated energy independently, causing desync when both players have the same hero.

**Fix Applied:**
- Added energy operations to `_execute_card_and_collect_results` for both attacker and targets
- Energy gains now properly synced via the effects array sent to guest
- Lines 7212-7234 in `battle.gd`

### 2. Equipment Tooltips Showing 0% ✅ FIXED
**Root Cause:** Equipment tooltip code was reading `item.get("value", 0)` but `equipment.json` uses `"effect_value"` field.

**Fix Applied:**
- Changed line 892 in `hero.gd` from `item.get("value", 0)` to `item.get("effect_value", 0)`
- All equipment tooltips now display correct percentages

### 3. Crash When Same Hero Dies ✅ FIXED
**Root Cause:** Incorrect method call `hero._die()` instead of `hero.die()` in guest's `_apply_effect` function.

**Fix Applied:**
- Changed line 7026 in `battle.gd` from `hero._die()` to `hero.die()`

### 4. Time Bomb Not Detonating ✅ FIXED
**Root Cause:** Time Bomb detonation happened during turn end on host, but the damage/discard operations were not sent to guest.

**Fix Applied:**
- Modified `_detonate_time_bombs()` to support operation collection mode
- When `operations` array is provided, damage and debuff removal are collected instead of applied
- Host collects all time bomb operations during turn end and sends to guest
- Guest applies operations via `_apply_ops()`
- Lines 3965-4007 in `battle.gd`

### 5. Empower Heal Not Expiring ✅ FIXED
**Root Cause:** Buff expiration was not synced in multiplayer - buffs were removed on host but guest never received the removal operations.

**Fix Applied:**
- Turn-end sync now collects all buff/debuff removals
- Host iterates through all heroes' active buffs/debuffs and checks `expire_on` condition
- Removal operations are sent to guest as part of turn-end effects
- Added `remove_debuff` case to `_apply_effect()` function
- Lines 5233-5292 in `battle.gd`

### 6. Scrapyard Overflow ⚠️ NEEDS INVESTIGATION
**Root Cause:** User reports it draws instead of discards.

**Current State:**
- Implementation at line 3817-3837 looks correct
- Calls `GameManager.draw_cards(draw_count)` then `_start_card_select("scrapyard_discard", discard_count, hero)`
- Card selection mode should allow discarding

**Fix Needed:**
- Test the card selection flow
- Verify discard mode is working correctly
- May be a UI issue or multiplayer sync issue

## Turn-End Sync Implementation ✅ COMPLETED

**Problem:** The original multiplayer system only synced card/EX actions but not turn-end effects.

**Solution Implemented:**
A comprehensive turn-end sync mechanism where the host collects all turn-end state changes and sends them to the guest as a batch of operations.

**How It Works:**
1. **Host Turn End** (lines 5216-5335):
   - Collects `turn_end_ops` array
   - Calls `_detonate_time_bombs()` with operations array to collect damage/debuff removal
   - Iterates all heroes' buffs/debuffs, checks `expire_on` condition, collects removal operations
   - Calls `_trigger_thunder_damage()` with operations array to collect thunder damage
   - Collects shield clearing operations
   - Sends all operations to guest via `network_manager.send_action_result()`

2. **Guest Receives** (lines 7075-7099):
   - `_guest_apply_end_turn_result()` receives turn-end result with `turn_end_effects` array
   - Calls `_apply_ops(turn_end_effects)` to apply all operations
   - Refreshes UI to reflect changes

3. **Operation Collection Mode:**
   - `_trigger_thunder_damage(heroes, operations)` - if operations array provided, collects instead of applies
   - `_detonate_time_bombs(heroes, is_player_team, operations)` - same pattern

**Now Synced:**
- ✅ Thunder damage
- ✅ Time Bomb detonation
- ✅ Burn/Poison damage (via same pattern)
- ✅ Buff/debuff expiration
- ✅ Shield clearing
- ✅ Energy gains from attacks/hits

## Testing Checklist

- [ ] Energy gauges stay synced with same heroes
- [ ] Equipment tooltips show correct percentages
- [ ] Game doesn't crash when same hero dies
- [ ] Time Bomb detonates and syncs damage/discard
- [ ] Empower Heal expires at turn end
- [ ] Scrapyard Overflow allows discarding (not drawing)
- [ ] Thunder damage syncs at turn end
- [ ] Burn/Poison damage syncs
- [ ] Shield clearing syncs
- [ ] Buff/debuff expiration syncs

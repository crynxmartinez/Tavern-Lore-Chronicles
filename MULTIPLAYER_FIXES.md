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

### 4. Time Bomb Not Detonating ⚠️ NEEDS MULTIPLAYER SYNC
**Root Cause:** Time Bomb detonation happens during turn end on host, but the damage/discard operations are not sent to guest.

**Current State:**
- `_detonate_time_bombs()` function works correctly in singleplayer
- Detonation happens at lines 5217, 5434, 8963
- Operations are not synced to guest

**Fix Needed:**
- Turn end operations need to be collected and sent to guest
- Requires adding turn end sync mechanism similar to card/EX sync

### 5. Empower Heal Not Expiring ⚠️ NEEDS INVESTIGATION
**Root Cause:** Unknown - configuration looks correct.

**Current State:**
- `_get_buff_expire_on("empower_heal")` returns `"own_turn_end"` (line 4026)
- Buff expiration logic should work via `hero.on_own_turn_end()`
- May be a multiplayer sync issue where buffs aren't being removed on guest

**Fix Needed:**
- Verify buff expiration is synced in multiplayer
- Check if `on_own_turn_end()` is being called on guest heroes

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

## Fundamental Multiplayer Architecture Issue

The current multiplayer system only syncs:
- Card play results
- EX skill results
- Damage/heal/buff/debuff from cards

**Not synced:**
- Turn end effects (Time Bomb detonation, Thunder damage, Burn, Poison)
- Buff/debuff expiration
- Shield clearing
- Energy gains from passive sources
- Equipment triggers

**Solution Needed:**
A comprehensive turn end sync mechanism where the host collects all turn-end state changes and sends them to the guest as a batch of operations.

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

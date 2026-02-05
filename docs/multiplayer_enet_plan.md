# Multiplayer Implementation Plan: Godot ENet

## Overview
Switching from GD-Sync to Godot's built-in ENet multiplayer for reliable testing.
Later will transition to Nakama for production.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      INSTANCE 1 (HOST)                       │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ Main Menu       │───▶│ ENetMultiplayerManager          │ │
│  │ [Host Game]     │    │ - create_server(PORT)           │ │
│  └─────────────────┘    │ - Wait for client               │ │
│                         └─────────────────────────────────┘ │
│                                      │                       │
│                                      ▼                       │
│                         ┌─────────────────────────────────┐ │
│                         │ Battle Scene                    │ │
│                         │ - @rpc functions for sync       │ │
│                         │ - Host executes game logic      │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ ENet Connection (localhost:7777)
                              │
┌─────────────────────────────────────────────────────────────┐
│                      INSTANCE 2 (CLIENT)                     │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ Main Menu       │───▶│ ENetMultiplayerManager          │ │
│  │ [Join Game]     │    │ - create_client(IP, PORT)       │ │
│  └─────────────────┘    │ - Connect to host               │ │
│                         └─────────────────────────────────┘ │
│                                      │                       │
│                                      ▼                       │
│                         ┌─────────────────────────────────┐ │
│                         │ Battle Scene                    │ │
│                         │ - @rpc functions for sync       │ │
│                         │ - Client sends requests to Host │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### Step 1: Create ENetMultiplayerManager (Autoload)
**File:** `scripts/autoload/enet_multiplayer_manager.gd`

Responsibilities:
- Create server (Host)
- Create client (Join)
- Handle peer_connected / peer_disconnected signals
- Track is_host, opponent_id
- Emit signals for battle scene

### Step 2: Update Main Menu
**File:** `scripts/ui/main_menu.gd` (or create new)

Add buttons:
- **Host Game** → Creates server, waits for opponent
- **Join Game** → Shows IP input (default: 127.0.0.1), connects

Flow:
1. Player 1 clicks "Host Game" → Server starts on port 7777
2. Player 2 clicks "Join Game" → Connects to 127.0.0.1:7777
3. Both transition to Battle scene

### Step 3: Refactor BattleNetworkManager
**File:** `scripts/battle/battle_network_manager.gd`

Replace GD-Sync calls with @rpc:
```gdscript
# OLD (GD-Sync)
_gdsync.call_func_on(opponent_id, _receive_action, [data])

# NEW (ENet)
_receive_action.rpc_id(opponent_id, data)
```

Key @rpc functions:
- `@rpc("any_peer", "reliable") func receive_team(team: Array)`
- `@rpc("any_peer", "reliable") func receive_rps_choice(choice: int)`
- `@rpc("any_peer", "reliable") func receive_action_request(request: Dictionary)`
- `@rpc("any_peer", "reliable") func receive_action_result(result: Dictionary)`
- `@rpc("any_peer", "reliable") func receive_turn_end()`

### Step 4: Update Battle Scene
**File:** `scripts/battle/battle.gd`

- Remove GD-Sync initialization
- Use multiplayer.get_unique_id() for peer ID
- Use multiplayer.is_server() for is_host check
- Connect to multiplayer.peer_connected signal

### Step 5: Testing
1. Run Instance 1 → Click "Host Game"
2. Run Instance 2 → Click "Join Game" (IP: 127.0.0.1)
3. Both should enter battle
4. Test RPS, card plays, turn end

## Port Configuration
- **Default Port:** 7777
- **For same PC testing:** Both instances use localhost (127.0.0.1)

## Files to Create/Modify

### New Files:
1. `scripts/autoload/enet_multiplayer_manager.gd` - Connection handling
2. `scenes/ui/multiplayer_lobby.tscn` - Host/Join UI

### Modified Files:
1. `scripts/battle/battle_network_manager.gd` - Replace GD-Sync with @rpc
2. `scripts/battle/battle.gd` - Update multiplayer initialization
3. `project.godot` - Add ENetMultiplayerManager to autoloads

## RPC Cheat Sheet

```gdscript
# Define an RPC function
@rpc("any_peer", "reliable")  # any_peer = clients can call, reliable = guaranteed delivery
func my_function(data):
    pass

# Call on ALL other peers
my_function.rpc(data)

# Call on SPECIFIC peer
my_function.rpc_id(peer_id, data)

# Call on server only
my_function.rpc_id(1, data)  # Server is always ID 1
```

## Timeline
- Step 1-2: 30 minutes (ENetMultiplayerManager + UI)
- Step 3-4: 1 hour (Refactor network code)
- Step 5: 30 minutes (Testing)

**Total: ~2 hours**

## Future: Nakama Transition
Once ENet testing is complete and multiplayer logic is solid:
1. Replace ENetMultiplayerManager with NakamaManager
2. Add authentication (guest/account)
3. Add matchmaking
4. Deploy Nakama server (Docker or Heroic Cloud)

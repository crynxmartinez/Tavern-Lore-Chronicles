# Account System Documentation

## Overview
The account system provides player authentication, stats tracking, and cloud sync capabilities. It's designed to work offline first, with GD-Sync integration ready for multiplayer.

## Files Created

### Autoloads
- `scripts/autoload/player_data.gd` - Local player data storage
- `scripts/autoload/account_manager.gd` - Authentication wrapper (GD-Sync ready)

### Scenes
- `scenes/account/login.tscn` - Login/Register UI
- `scripts/account/login.gd` - Login screen logic

### Modified Files
- `project.godot` - Added PlayerData and AccountManager autoloads
- `scenes/dashboard/dashboard.tscn` - Added player profile panel
- `scenes/dashboard/dashboard.gd` - Added profile display and account button
- `scenes/battle/battle_summary.tscn` - Added stats display
- `scripts/battle/battle_summary.gd` - Added stats update function
- `scripts/battle/battle.gd` - Added win/loss recording

## Features

### PlayerData Autoload
- **Profile**: player_id, username, avatar_id, timestamps
- **Stats**: wins, losses, win rate, streaks (total, PvP, AI)
- **Settings**: audio volumes, gameplay preferences
- **Saved Teams**: up to 3 team loadouts (for future use)
- **Save/Load**: JSON persistence to `user://player_data.save`

### AccountManager Autoload
- **Login/Register**: Local simulation (GD-Sync ready)
- **Guest Play**: Play without account
- **Cloud Sync**: Placeholder for GD-Sync integration
- **Session Restore**: Auto-login on app start

### Login Screen
- Username/password fields
- Login and Register modes
- Guest play option
- Error handling and status messages

### Dashboard Integration
- Player profile panel (top-right)
- Shows username, win/loss stats
- "Account Settings" button to access login screen

### Battle Integration
- Records wins/losses after each battle
- Shows stats in battle summary screen
- Tracks AI vs PvP games separately

## How to Test

1. **Run the game** - Dashboard shows "Player (Guest)" initially
2. **Click "Account Settings"** - Opens login screen
3. **Register/Login** - Creates local account
4. **Play a battle** - Win or lose
5. **Check stats** - Battle summary shows updated stats
6. **Return to dashboard** - Profile shows new stats

## GD-Sync Integration (Future)

When ready to add GD-Sync:

1. Install GD-Sync from Godot Asset Library
2. Get API key from gd-sync.com
3. Update `account_manager.gd`:
   - Uncomment GD-Sync checks in `_check_gdsync_availability()`
   - Replace `_simulate_login()` with actual GD-Sync calls
   - Implement cloud sync functions

## Data Flow

```
User Action → AccountManager → PlayerData → Local Save
                    ↓
              (Future: GD-Sync Cloud)
```

## Save File Location
- Windows: `%APPDATA%\Godot\app_userdata\My Turn\player_data.save`
- macOS: `~/Library/Application Support/Godot/app_userdata/My Turn/player_data.save`
- Linux: `~/.local/share/godot/app_userdata/My Turn/player_data.save`

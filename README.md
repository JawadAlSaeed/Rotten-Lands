# Rotten Lands

Co-op (1 to 3 players) turn-based RPG roguelike with real-time parry, dodge and jump defence,
inspired by Clair Obscur: Expedition 33. Made with Godot 4.7.2. "Rotten Lands" is a placeholder
name and all art and sound are placeholders for now.

- Design: [docs/DESIGN.md](docs/DESIGN.md)
- Conventions for contributors: [CLAUDE.md](CLAUDE.md)

## Run it

1. Install Godot 4.7.2 (standard build, not .NET).
2. Double-click `run_game.bat` (edit the path at the top if Godot lives elsewhere, or set the
   `GODOT` environment variable).
3. Or open the editor with `open_editor.bat` and press F5.

## Controls (phase 1)

| | Keyboard | Xbox pad |
|---|---|---|
| Parry | Space | RB |
| Dodge | Left Shift | B |
| Jump | W | A |
| Menu move | Arrows / WASD | D-pad / left stick |
| Confirm | Enter / E | A |
| Back | Esc / Q | B |
| Debug overlay | F1 | View |

## Tests

Double-click `run_tests.bat`. It runs every unit test without opening a window.

## Tuning

All timing windows and damage numbers are in `data/tuning/tuning.tres`. Open it in the Godot
editor (double-click it in the FileSystem panel) and change values in the Inspector.

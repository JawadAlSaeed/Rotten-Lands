# Rotten Lands: project conventions

Co-op (1 to 3 players) turn-based RPG roguelike. Combat is modelled on Clair Obscur: Expedition 33,
the look on Octopath Traveler (HD-2D). Full design: `docs/DESIGN.md`. Keep that file current
whenever a decision is made or changed.

## The person you work with

- Not a game developer and has never used Godot. They test builds and give feedback; you write
  all code, scenes and data.
- Whenever they must do something by hand (install, click in the editor, test, map a controller),
  give exact numbered steps. The first time any editor feature comes up, say where it is on screen
  and what to click.
- Work in phases (see DESIGN.md). Stop after each phase, explain how to test it, wait for feedback.

## Git and GitHub

- Repo: https://github.com/JawadAlSaeed/Rotten-Lands (public). Branch: `main`.
- Commits are authored by the user as Jawad Al-Saeed <39744682+JawadAlSaeed@users.noreply.github.com>
  (repo-local `user.email`). GitHub blocks pushes that expose the private Gmail address.
- **Never credit Claude or Anthropic anywhere in git or GitHub.** No `Co-Authored-By` trailer, no
  "Generated with Claude Code" line, no session links, in commits, PRs, issues or release notes.
  This is enforced by `.claude/settings.json` (attribution off) and by `.githooks/commit-msg`
  (strips such lines). After a fresh clone run `git config core.hooksPath .githooks`.
- Commit or push only when the user asks, or at the end of a phase they approved.

## Tools

- Godot 4.7.2 stable, GDScript only. Editor: `C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64.exe`.
  Console build (for headless runs): `C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe`.
  Override either with the `GODOT` environment variable.
- Tests: GUT 9.7.1 in `addons/gut`. Always run them with `run_tests.bat --no-pause` (from bash:
  `cmd //c run_tests.bat --no-pause`). It imports first (a fresh clone or a new `class_name` makes
  plain GUT skip files silently) and fails if any test file did not load or the log shows a
  script error. Run `--headless --path . --import` before any `-s` tool script too.
- Tests must pass headless before you tell the user a phase is done.
- `run_game.bat` runs the game, `open_editor.bat` opens the editor.
- Smoke test the whole fight without a human: run the game with `-- --autoplay` (bot defends
  perfectly), `-- --autoplay=miss` (never defends) or `-- --autoplay=mash` (mashes buttons). Add
  `--quit-on-end` to exit when the fight is over. Works with `--headless`. A good run prints
  `AUTOPLAY_RESULT` and no `ERROR` / `AUTOPLAY_ERROR` lines; a missing result line means a hang.
- Always run headless Godot commands with a timeout (`timeout 120 ...`): a script error in a
  `-s` script leaves Godot running forever.

## Architecture rules (do not break these)

1. **Combat logic is a deterministic state machine driven by commands** (`scripts/combat/core/`).
   - Core classes extend `RefCounted`. They never touch `Node`, the scene tree, `Input`, `Time`,
     `OS`, signals to presentation, `randi()`/`randf()` or anything frame-dependent.
   - All randomness goes through `CombatRng` (seeded). HP, AP and damage are integers.
   - The only way to change combat state is `CombatEngine.submit(command)`. It returns a list of
     events. Commands and events are plain `Dictionary` values (easy to send over the network).
   - Same seed + same commands = same events. A test checks this.
2. **Real-time defence is judged outside the core** (`scripts/combat/timing/`), by pure classes
   (`DefenseJudge`, `AttackClock`) fed with input timestamps and the prompts the engine declared
   (windows, impact times). Results go to the core as a `resolve_prompts` command. This is what
   lets each network client judge its own player later. Local feedback (popups, hit-stop, sounds)
   comes from the judge at press time, never from engine events.
3. **Judge timing from input event timestamps, never frame polling.** Godot 4.7 input events carry
   no OS timestamp, so `DefenseInput._input()` stamps each press with `Time.get_ticks_usec()` the
   moment it arrives, and the judge compares that stamp with the hit's scheduled time on the same
   clock. Never use `Input.is_action_just_pressed()` for defence or timed presses.
4. **Content is data.** Characters, enemies, enemy attacks, abilities, encounters and sound cues are
   `Resource` files in `data/`. Scripts for them live in `scripts/data/`. Never hardcode content.
5. **Every global number lives in data, never in code.** Rules and judging numbers go in
   `data/tuning/tuning.tres` (script `scripts/data/tuning.gd`): timing windows, lockout, lag
   compensation and its bounds, base damage and HP, AP economy, counter percentages, hit-stop,
   cue on/off defaults, pacing. Presentation-only feel goes in
   `data/presentation/combat_visuals.tres` (script `scripts/data/combat_visuals.gd`): art paths,
   stage layout, camera, enemy choreography feel, pose lengths, flash/shake strengths, popup and
   banner feel, the calibration procedure. Per-move shapes (hit count, hit timing, percentages)
   live in that move's data file as integer percentages of the tuning values. Pure animation-curve
   shape constants (for example a share of a pose) may stay as named consts. Change values in the
   `.tres` files, never by editing the defaults in the scripts.
6. **Art and audio load from paths stored in data.** Replacing a placeholder means dropping a file
   with the same name into `assets/`. Missing files fall back to a visible placeholder and a
   warning, never a crash. Placeholders are generated by `tools/gen_placeholders.gd`.
7. Presentation (`scripts/combat/presentation/`) reads `CombatMirror` (built from events in playback
   order), never the engine. It changes combat state only by submitting commands through
   `CombatController`.
8. Rules maths uses integers only (`CombatMath.percent`); no floats in `scripts/combat/core/`.

## Code style

- Follow the official GDScript style guide. Static typing everywhere (`var hp: int = 0`,
  typed function signatures, typed arrays where practical).
- Files and folders `snake_case`, classes `PascalCase` with `class_name` for data and core classes.
- Short doc comments (`##`) on public classes and functions. Comment the why, not the what.
- Input actions are defined in `project.godot`; see the table in DESIGN.md. Keyboard and gamepad
  must both work for every action.

## Folder map

- `data/` content resources (`.tres`), including `tuning/tuning.tres` and
  `presentation/combat_visuals.tres`
- `assets/` sprites, audio (placeholders until real art arrives)
- `scripts/data/` resource class scripts
- `scripts/core/` shared helpers (asset loading)
- `scripts/combat/core/` deterministic combat engine
- `scripts/combat/timing/` defence timing judges
- `scripts/combat/presentation/` combat scene, views, HUD, camera, feedback
- `scripts/combat/input/` input stamping
- `scripts/autoload/` global singletons (`Audio`, `UserSettings` = `PlayerSettings`, saved per
  machine in `user://settings.cfg`)
- `scenes/` scenes
- `tests/unit/` GUT tests
- `tools/` headless helper scripts (placeholder generation, data bootstrap)
- `docs/` design docs

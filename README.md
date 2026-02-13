# Chord Progression Notebook

A transparent, REAPER-native chord progression notebook built with ReaScript Lua + ReaImGui.

## Compatibility

- REAPER with ReaScript (Lua).
- ReaImGui installed via ReaPack.
- Script is single-instance guarded (starting it twice shows an "already running" message).

## Install and Run

1. Place this folder anywhere REAPER can access.
2. In REAPER: `Actions` -> `Show action list`.
3. Click `ReaScript: Load...` and choose `chord_notebook.lua`.
4. Run the action `Chord Progression Notebook`.

## Persistence

- Library: `<project_dir>/.chord_notebook/library.json`
- Unsaved project fallback: `<REAPER resource path>/ChordNotebook/unsaved/library.json`
- UI prefs: REAPER ExtState section `ChordNotebook`

## Architecture

- `chord_notebook.lua`: bootstrap, state lifecycle, request dispatch, and defer loop.
- `lib/storage.lua`: JSON persistence and UI prefs I/O.
- `lib/reaper_api.lua`: REAPER environment and filesystem wrappers.
- `lib/chord_model.lua`: note naming, qualities, scale/degree utilities, symbol formatting.
- `lib/harmony_engine.lua`: scoring and rule-based reharmonisation suggestions.
- `lib/midi_writer.lua`: MIDI insertion and selected-item chord detection.
- `lib/ui/ui_main.lua`: top-level 3-panel UI orchestration and style/background.
- `lib/ui/ui_library.lua`: progression list + key/mode controls.
- `lib/ui/ui_progression_lane.lua`: progression lane, DnD reorder, context actions.
- `lib/ui/ui_inspector.lua`: progression/chord inspector editors.
- `lib/ui/ui_circle_of_fifths.lua`: circle geometry, overlays, functional visualization.

## REAPER/ReaPack Conformance

- Entry script contains ReaPack metadata header (`@description`, `@version`, `@provides`).
- All timeline/item edits are wrapped in undo blocks in MIDI writer paths.
- ReaImGui missing dependency is handled with a graceful message and early return.
- UI runs via `reaper.defer` loop with explicit shutdown path and preview-note cleanup.
- Persistence follows REAPER conventions:
  - project-local data when project is saved
  - resource-path fallback for unsaved projects
  - ExtState for UI preferences

## Release Workflow

1. Update script header version in `chord_notebook.lua`.
2. Update `README.md` changelog/release notes if behavior changed.
3. Validate syntax:
   - `luac -p chord_notebook.lua`
   - `luac -p lib/*.lua`
   - `luac -p lib/ui/*.lua`
4. Format changed files with `stylua`.
5. Smoke-test in REAPER:
   - launch/quit
   - insert chord / insert progression
   - detect from selected MIDI
   - library save/reload
6. Publish through ReaPack index using files listed in `@provides`.

## Deep Test Routine

Use the scripted test routine for long-term support and regression checks:

- Run all checks: `./scripts/run_tests.sh`
- Outputs:
  - syntax report: `tests/logs/syntax_YYYYMMDD_HHMMSS.log`
  - run log: `tests/logs/run_YYYYMMDD_HHMMSS.log`
  - Lua test cases: `tests/logs/test_YYYYMMDD_HHMMSS.log`

Coverage includes:
- Core harmony model (`lib/chord_model.lua`)
- Suggestion engine (`lib/harmony_engine.lua`)
- JSON persistence codec (`lib/json.lua`)
- Regression checks for Roman numeral labelling behavior

## Maintenance Guidelines

- Keep UI and engine modules separated (no MIDI/timeline writes in UI modules).
- Avoid direct REAPER API usage in multiple places when wrappers already exist.
- Prefer explicit, small helper functions over hidden side effects.
- Keep compatibility guards around optional ImGui calls.
- Preserve non-destructive behavior in the project worktree; never force-reset user data.

## Roadmap TODO

- Voice-leading optimizer.
- Similarity search across library progressions.
- Audition/preview playback without MIDI insertion.

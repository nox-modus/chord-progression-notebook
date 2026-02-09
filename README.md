# Chord Progression Notebook

A transparent, REAPER-native chord progression notebook built with ReaScript Lua + ReaImGui.

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

## Roadmap TODO

- Voice-leading optimizer.
- Similarity search across library progressions.
- Audition/preview playback without MIDI insertion.

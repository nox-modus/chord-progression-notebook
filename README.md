**UI preferences**
- Stored in REAPER ExtState (`ChordNotebook` section)

No external dependencies.  
No global filesystem writes beyond the REAPER resource path.

---

## Undo & Safety

- All MIDI/timeline edits are wrapped in proper Undo blocks.
- No destructive operations on existing project data.
- No forced resets of user content.
- Clean shutdown with preview-note cleanup.
- UI runs inside a controlled `reaper.defer` loop.

---

## Script Structure

**Entry point**
- `chord_notebook.lua`

**Core modules**
- `lib/chord_model.lua` – chord symbols, scales, degrees
- `lib/harmony_engine.lua` – rule-based reharmonisation suggestions
- `lib/midi_writer.lua` – MIDI insertion and detection
- `lib/storage.lua` – JSON persistence
- `lib/reaper_api.lua` – REAPER API wrappers

**UI modules**
- `lib/ui/ui_main.lua`
- `lib/ui/ui_library.lua`
- `lib/ui/ui_progression_lane.lua`
- `lib/ui/ui_inspector.lua`
- `lib/ui/ui_circle_of_fifths.lua`

UI and engine layers are separated.  
UI modules do not directly modify the REAPER timeline.

---

## ReaPack Conformance

- Entry script contains proper ReaPack metadata (`@description`, `@version`, `@provides`)
- All distributed files are listed in `@provides`
- ReaImGui dependency handled safely
- Project-aware persistence model
- No hardcoded system paths

---

## Planned Features

- Voice-leading optimisation
- Progression similarity search
- Audition playback without MIDI insertion
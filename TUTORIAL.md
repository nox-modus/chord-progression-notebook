# Chord Progression Notebook Tutorial

## 1. Launch
1. Open REAPER.
2. Open `Actions -> Show action list`.
3. Run `Scripts/Nox-Modus/Chord Progression Notebook/chord_notebook.lua`.

## 2. Library Model (Important)
1. **Reference library (immutable source):**
`Scripts/Nox-Modus/Chord Progression Notebook/data/library.json`
2. **Project library (editable, project-specific):**
- Saved project: `<project_dir>/.chord_notebook/library.json`
- Unsaved project: `<REAPER resource path>/ChordNotebook/unsaved/library.json`
3. Each REAPER project can have a different local project library.
4. The plugin can show the active path from menu: `Show Library Path`.

## 3. Reference to Project Workflow
1. In `Reference Library (Read-Only)`, select a progression.
2. Click `Add To Project` to create a new copy in `Project Library`.
3. Repeat `Add To Project` if you want multiple copies.
4. Edit only in `Project Library`.

## 4. Basic Project Editing
1. In `Project Library`, click `New Progression` (or select an existing row).
2. Use inspector to edit name, tempo, tags, notes, chord parameters.
3. Use progression list to add/delete/reorder chords.
4. Use `Save` (or top menu `Save Library`) to persist local project changes.

## 5. Search and Filters
1. Use `Tag Search` in the Library panel.
2. Enter one or more tokens (space or comma separated).
3. Filtering is case-insensitive.
4. Click `Clear Tags` to reset.
5. Use provenance filter dropdown to narrow by source type.

## 6. Restore from Immutable Reference
Use this when a project progression was modified unintentionally.

1. In the library list, right-click a progression row.
2. Click `Restore From Reference`.
3. The project progression is replaced by the reference version (when mapping exists).
4. Click `Save`.

Note: The row context menu currently contains only `Restore From Reference`.

## 7. Import from Another Project (Merge Mode)
You can import in two places:
1. Library panel button: `Import From Project`
2. Top menu entry: `Import Library From Project...`

Steps:
1. Click one of the import actions.
2. Pick another project `.rpp` file (or a `library.json` directly).
3. The script reads:
`<selected_project_dir>/.chord_notebook/library.json`
4. Import runs in **merge mode**:
- existing local entries remain
- only new, non-duplicate progressions are added
- no automatic replacement/deletion
5. Review import result dialog.
6. Click `Save`.

## 8. Playback
1. Select a progression in either reference or project list.
2. Click `Play Selected` to audition.
3. Click `Stop` to stop preview.
4. Toggle `Loop` to repeat playback.
5. If `Voice Leading` is enabled, playback and insertion use smoother chord motion.

## 9. Reharm and Key Controls
1. In left settings, choose `Key` and major/minor mode.
2. Enable `On-the-fly Reharm` to remap chord roots when key/mode changes.
3. Choose a `Reharm Mode` for suggestion behavior.
4. Toggle `Roman Numerals` for degree display.

## 10. Undo
1. Use top menu `Undo Last Change` to revert the latest project-library edit.
2. Undo applies to project mutations (editing, add/delete, import merge additions, key/mode remap, inspector changes).
3. If stack is empty, plugin reports `Nothing to undo`.

## 11. Data Safety
1. Project libraries are normalized on load/runtime to prevent broken entries from crashing UI.
2. Save uses atomic write behavior and keeps backup fallback (`library.json.bak`).
3. If main library file is corrupted, loader can recover from backup.

## 12. Recommended Workflow
1. Browse in `Reference Library`.
2. Move wanted material to `Project Library`.
3. Reharm/edit locally.
4. Use `Undo Last Change` when needed.
5. Save frequently.
6. Import from other projects only when you want to merge ideas.

## 13. Troubleshooting
1. **I still see old progressions**
You are likely viewing that project’s local project library, not the immutable reference file.
2. **Restore failed**
That progression has no unique reference mapping.
3. **Import added 0 progressions**
Imported entries were already present (duplicate by signature/ref_id).
4. **Playback has no sound**
Check MIDI routing/instrument on selected track and monitor settings.
5. **Library path confusion**
Use menu `Show Library Path` to confirm where current project library is stored.

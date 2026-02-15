# Chord Progression Notebook Tutorial

## 1. Start the Plug-In
1. Open REAPER.
2. Run `Scripts/Nox-Modus/Chord Progression Notebook/chord_notebook.lua` from the Action List.
3. The main window opens with `Library`, progression lane, and inspector.

## 2. Understand the Two Library Types
1. **Reference library (immutable source):**
`Scripts/Nox-Modus/Chord Progression Notebook/data/library.json`
2. **Working library (your editable data):**
- Saved project: `<project_dir>/.chord_notebook/library.json`
- Unsaved project: `<REAPER resource path>/ChordNotebook/unsaved/library.json`

## 3. Create and Edit Progressions
1. In `Library`, click `New Progression`.
2. Select the progression in the list.
3. Edit `Name`, `Tags`, key, chords, and notes in the inspector and left controls.
4. Click `Save` to write changes to the working library file.

## 4. Search by Tag
1. In `Library`, use `Tag Search`.
2. Type one or multiple tokens (space or comma separated).
3. The list filters in real time.
4. Click `Clear Tags` to reset the filter.

## 5. Restore a Progression from Reference
Use this when a progression was accidentally changed.

1. In the Library list, right-click the progression row.
2. Click `Restore From Reference`.
3. The selected local progression is replaced with its reference version (if linked).
4. Click `Save` to persist restored content.

## 6. Import Library from Another Project
Use this to reuse progressions across projects.

1. In `Library`, click `Import From Project`.
2. Choose a `.rpp` project file from another project.
3. The plug-in resolves and reads:
`<chosen_project_dir>/.chord_notebook/library.json`
4. New (non-duplicate) progressions are merged into your current working library.
5. A result dialog shows how many were imported.
6. Click `Save` to persist.

Tip: You can also select a `library.json` directly in the file dialog.

## 7. Safe Workflow Recommendation
1. Keep building your custom data in project-local working libraries.
2. Use the immutable reference as backup for seeded progressions.
3. Periodically import from other projects to consolidate ideas.
4. Save after major edits/imports/restores.

## 8. Troubleshooting
1. **Only old progressions appear:**
You are likely opening a project with an older local working library.
2. **Restore fails:**
The progression may not map to a unique reference entry.
3. **Import says no new progressions:**
Everything from the selected project is already present (or equivalent) in current working library.

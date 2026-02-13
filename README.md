# Chord Progression Notebook

A REAPER-native chord progression notebook built with ReaScript (Lua) and ReaImGui.

Designed for storing, editing, visualising, and inserting chord progressions directly inside REAPER.

---

## Requirements

- REAPER (with Lua ReaScript enabled)
- ReaImGui (install via ReaPack)

If ReaImGui is not installed, the script displays a clear message and exits safely.

---

## Installation (via ReaPack – Recommended)

1. Install from the ReaTeam repository using ReaPack.
2. Open **Actions → Show action list**.
3. Run:  
   `Chord Progression Notebook`

The script is single-instance guarded. Launching it twice will show an “already running” message.

---

## Features

- Project-local progression library
- Chord editing via inspector panel
- Circle of Fifths with functional harmony (T–S–D) overlay
- Optional Roman numeral display
- Rule-based reharmonisation suggestions
- MIDI insertion (single chord or full progression)
- Chord detection from selected MIDI items
- Drag & drop reordering
- Clean project-safe persistence

---

## Data Storage

The script follows REAPER conventions:

**Project-local library**
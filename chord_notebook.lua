-- @description Chord Progression Notebook
-- @version 0.5.0
-- @author NOX-Chords
-- @changelog Maintenance hardening: single-instance lock, safer lifecycle/error handling, deployment metadata.
-- @about
--   Transparent chord progression notebook for REAPER.
--   Features progression editing, Roman numerals, circle-of-fifths interaction,
--   MIDI insertion and suggestion workflow with ReaImGui UI.
-- @provides
--   [main] chord_notebook.lua
--   [nomain] lib/*.lua
--   [nomain] lib/ui/*.lua
--   [nomain] data/library.json

local info = debug.getinfo(1, "S")
local script_path = info.source:match("^@?(.*[\\/])") or ""

package.path = table.concat({
	script_path .. "?.lua",
	script_path .. "lib/?.lua",
	script_path .. "lib/ui/?.lua",
	package.path,
}, ";")

local reaper_api = require("lib.reaper_api")
if not reaper_api.has_imgui() then
	reaper_api.msg("ReaImGui is required. Install it via ReaPack and restart REAPER.")
	return
end

local json = require("lib.json")
local midi_writer = require("lib.midi_writer")
local storage = require("lib.storage")
local ui_main = require("lib.ui.ui_main")

local WINDOW_TITLE = "Chord Progression Notebook"
local LOCK_SECTION = "ChordNotebook"
local LOCK_KEY = "instance_lock"

local function acquire_instance_lock()
	local current = reaper.GetExtState(LOCK_SECTION, LOCK_KEY)
	if current and current ~= "" then
		return false
	end
	reaper.SetExtState(LOCK_SECTION, LOCK_KEY, tostring(reaper.time_precise()), false)
	return true
end

local function release_instance_lock()
	if reaper.DeleteExtState then
		reaper.DeleteExtState(LOCK_SECTION, LOCK_KEY, false)
	else
		reaper.SetExtState(LOCK_SECTION, LOCK_KEY, "", false)
	end
end

if not acquire_instance_lock() then
	reaper_api.msg("Chord Progression Notebook is already running.")
	return
end

local function new_state()
	return {
		library = { progressions = {} },
		selected_progression = 1,
		selected_chord = 1,
		show_roman = false,
		reharm_mode = "diatonic_rotate",
		grain_enabled = false,
		ui_open = true,
		dirty = false,

		save_requested = false,
		insert_chord_requested = false,
		insert_progression_requested = false,
		detect_requested = false,
	}
end

local state = new_state()
local ctx = reaper.ImGui_CreateContext(WINDOW_TITLE)
local is_shutdown = false

local function load_seed_library()
	local seed_path = script_path .. "data/library.json"
	local content = reaper_api.read_file(seed_path)
	if not content then
		return { progressions = {} }
	end

	local ok, decoded = pcall(json.decode, content)
	if ok and type(decoded) == "table" and type(decoded.progressions) == "table" then
		return decoded
	end

	return { progressions = {} }
end

local function normalize_library(library)
	library = type(library) == "table" and library or {}
	library.progressions = type(library.progressions) == "table" and library.progressions or {}

	if #library.progressions == 0 then
		local seed = load_seed_library()
		library.progressions = seed.progressions or {}
	end

	if #library.progressions == 0 then
		library.progressions = {
			{
				name = "New Progression",
				key_root = 0,
				mode = "major",
				tempo = 120,
				tags = {},
				notes = "",
				chords = { { root = 0, quality = "major", duration = 1 } },
				audio_refs = {},
			},
		}
	end

	return library
end

local function load_library()
	local loaded = storage.load_library()
	return normalize_library(loaded)
end

local function save_library_if_needed(force)
	if not state.library then
		return
	end
	if force or state.dirty then
		local ok = storage.save_library(state.library)
		if ok then
			state.dirty = false
		else
			reaper_api.msg("Failed to save library:\n" .. storage.get_library_path())
		end
	end
end

local function load_prefs()
	local prefs = storage.load_ui_prefs()
	if type(prefs) ~= "table" then
		return
	end

	state.show_roman = prefs.show_roman == true
	state.reharm_mode = prefs.reharm_mode or state.reharm_mode
	state.grain_enabled = prefs.grain_enabled == true
end

local function save_prefs()
	storage.save_ui_prefs({
		show_roman = state.show_roman,
		reharm_mode = state.reharm_mode,
		grain_enabled = state.grain_enabled,
	})
end

local function clamp_selection()
	local progressions = state.library and state.library.progressions or {}
	local pcount = #progressions
	if pcount < 1 then
		state.selected_progression = 1
		state.selected_chord = 1
		return
	end

	if state.selected_progression < 1 then
		state.selected_progression = 1
	elseif state.selected_progression > pcount then
		state.selected_progression = pcount
	end

	local prog = progressions[state.selected_progression]
	local chord_count = prog and prog.chords and #prog.chords or 0
	if chord_count < 1 then
		state.selected_chord = 1
	elseif state.selected_chord < 1 then
		state.selected_chord = 1
	elseif state.selected_chord > chord_count then
		state.selected_chord = chord_count
	end
end

local function handle_save_request()
	if state.save_requested then
		save_library_if_needed(true)
		state.save_requested = false
	end
end

local function handle_insert_chord_request()
	if not state.insert_chord_requested then
		return
	end

	local prog = state.library.progressions[state.selected_progression]
	local chord = prog and prog.chords and prog.chords[state.selected_chord]
	if chord then
		midi_writer.insert_chord_at_cursor(chord)
	end

	state.insert_chord_requested = false
end

local function handle_insert_progression_request()
	if not state.insert_progression_requested then
		return
	end

	local prog = state.library.progressions[state.selected_progression]
	if prog then
		midi_writer.insert_progression(nil, nil, prog)
	end

	state.insert_progression_requested = false
end

local function handle_detect_request()
	if not state.detect_requested then
		return
	end

	local chords, err = midi_writer.detect_from_selected_item()
	if chords then
		local prog = state.library.progressions[state.selected_progression]
		if prog then
			prog.chords = chords
			state.selected_chord = 1
			state.dirty = true
		end
	else
		reaper_api.msg(err or "Failed to detect chords from selected MIDI item.")
	end

	state.detect_requested = false
end

local function handle_requests()
	handle_save_request()
	handle_insert_chord_request()
	handle_insert_progression_request()
	handle_detect_request()
end

local function shutdown()
	if is_shutdown then
		return
	end
	is_shutdown = true

	save_prefs()
	save_library_if_needed(false)
	midi_writer.stop_preview()

	if reaper.ImGui_DestroyContext then
		pcall(reaper.ImGui_DestroyContext, ctx)
	end

	release_instance_lock()
end

local function run_frame()
	clamp_selection()
	ui_main.draw(ctx, state)
	handle_requests()
	midi_writer.update_preview()
end

local function main()
	if not state.ui_open then
		shutdown()
		return
	end

	local ok, err = xpcall(run_frame, debug.traceback)
	if not ok then
		reaper_api.msg("Chord Progression Notebook crashed:\n\n" .. tostring(err))
		state.ui_open = false
		shutdown()
		return
	end

	reaper.defer(main)
end

state.library = load_library()
load_prefs()
reaper.defer(main)

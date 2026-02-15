-- @description Chord Progression Notebook
-- @version 0.5.0
-- @author Nox-Modus
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
		tag_search = "",
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

local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local out = {}
	for k, v in pairs(value) do
		out[k] = deep_copy(v)
	end
	return out
end

local function chord_signature(chord)
	if type(chord) ~= "table" then
		return "?"
	end

	local root = tostring(chord.root or "")
	local quality = tostring(chord.quality or "")
	local duration = tostring(chord.duration or "")
	local extensions = tostring(chord.extensions or "")
	local bass = tostring(chord.bass or "")
	return table.concat({ root, quality, duration, extensions, bass }, ":")
end

local function progression_signature(prog)
	if type(prog) ~= "table" then
		return "?"
	end

	local parts = {
		tostring(prog.name or ""),
		tostring(prog.key_root or ""),
		tostring(prog.mode or ""),
	}
	local chords = type(prog.chords) == "table" and prog.chords or {}
	for _, chord in ipairs(chords) do
		parts[#parts + 1] = chord_signature(chord)
	end
	return table.concat(parts, "|")
end

local function reference_id_for_progression(prog)
	return progression_signature(prog)
end

local function ensure_reference_links(library, seed)
	local changed = false
	local seed_list = (type(seed) == "table" and seed.progressions) or {}
	if type(seed_list) ~= "table" then
		return false
	end

	local seed_ref_ids = {}
	local seed_name_refs = {}
	for _, seed_prog in ipairs(seed_list) do
		local ref_id = reference_id_for_progression(seed_prog)
		seed_ref_ids[ref_id] = true
		local name = tostring(seed_prog.name or "")
		seed_name_refs[name] = seed_name_refs[name] or {}
		seed_name_refs[name][#seed_name_refs[name] + 1] = ref_id
	end

	local list = library.progressions or {}
	for _, prog in ipairs(list) do
		local current_ref = type(prog.ref_id) == "string" and prog.ref_id or nil
		if current_ref and seed_ref_ids[current_ref] then
			-- Already linked to known immutable reference.
		else
			local ref_by_signature = reference_id_for_progression(prog)
			if seed_ref_ids[ref_by_signature] then
				prog.ref_id = ref_by_signature
				changed = true
			else
				local name_matches = seed_name_refs[tostring(prog.name or "")]
				if name_matches and #name_matches == 1 then
					prog.ref_id = name_matches[1]
					changed = true
				end
			end
		end
	end

	return changed
end

local function merge_seed_progressions(library, seed)
	local list = library.progressions or {}
	local seed_list = (type(seed) == "table" and seed.progressions) or {}
	if type(seed_list) ~= "table" or #seed_list == 0 then
		return false
	end

	local existing = {}
	local existing_ref_ids = {}
	for _, prog in ipairs(list) do
		existing[progression_signature(prog)] = true
		if type(prog.ref_id) == "string" and prog.ref_id ~= "" then
			existing_ref_ids[prog.ref_id] = true
		end
	end

	local changed = false
	for _, prog in ipairs(seed_list) do
		local sig = progression_signature(prog)
		local ref_id = reference_id_for_progression(prog)
		if not existing[sig] and not existing_ref_ids[ref_id] then
			local copy = deep_copy(prog)
			copy.ref_id = ref_id
			list[#list + 1] = copy
			existing[sig] = true
			existing_ref_ids[ref_id] = true
			changed = true
		end
	end

	library.progressions = list
	return changed
end

local function normalize_library(library)
	library = type(library) == "table" and library or {}
	library.progressions = type(library.progressions) == "table" and library.progressions or {}

	local seed = load_seed_library()
	local linked_seed = ensure_reference_links(library, seed)
	local merged_seed = merge_seed_progressions(library, seed)
	if #library.progressions == 0 then
		library.progressions = deep_copy(seed.progressions or {})
		for _, prog in ipairs(library.progressions) do
			prog.ref_id = reference_id_for_progression(prog)
		end
		merged_seed = #library.progressions > 0
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

	return library, (merged_seed or linked_seed)
end

local function load_library()
	local loaded = storage.load_library()
	local library, merged_seed = normalize_library(loaded)
	if merged_seed and loaded then
		state.dirty = true
	end
	return library
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
	state.tag_search = tostring(prefs.tag_search or "")
end

local function save_prefs()
	storage.save_ui_prefs({
		show_roman = state.show_roman,
		reharm_mode = state.reharm_mode,
		grain_enabled = state.grain_enabled,
		tag_search = state.tag_search,
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
state.reference_library = load_seed_library()
load_prefs()
reaper.defer(main)

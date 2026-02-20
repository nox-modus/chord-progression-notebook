-- @description Chord Progression Notebook
-- @version 0.9.3
-- @author Nox-Modus
-- @changelog Hotfix: collapse/minimize lifecycle fix in ImGui guard (avoid End/EndChild when Begin returns false); prevents End()/PopStyleColor context errors.
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
local library_safety = require("lib.library_safety")
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
		reference_library = { progressions = {} },
		selected_progression = 1,
		selected_reference_progression = 1,
		selected_chord = 1,
		show_roman = false,
		reharm_mode = "diatonic_rotate",
		on_the_fly_reharm = true,
		voice_leading_enabled = true,
		grain_enabled = false,
		tag_search = "",
		provenance_filter = "all",
		playback_loop = true,
		library_player = {
			active = false,
			source = nil,
			progression_index = 1,
			chord_index = 1,
			next_change_time = 0,
		},
		undo_stack = {},
		undo_limit = 40,
		ui_open = true,
		dirty = false,

		save_requested = false,
		undo_requested = false,
		insert_chord_requested = false,
		insert_progression_requested = false,
		detect_requested = false,
	}
end

local state = new_state()
local ctx = reaper.ImGui_CreateContext(WINDOW_TITLE)
local is_shutdown = false

local function snapshot_library(library)
	if type(library) ~= "table" then
		return nil
	end
	local ok_encode, encoded = pcall(json.encode, library)
	if not ok_encode or type(encoded) ~= "string" then
		return nil
	end
	local ok_decode, decoded = pcall(json.decode, encoded)
	if not ok_decode or type(decoded) ~= "table" then
		return nil
	end
	return decoded
end

local function library_fingerprint(library)
	local ok, encoded = pcall(json.encode, library)
	if ok and type(encoded) == "string" then
		return encoded
	end
	return ""
end

local function push_undo_snapshot(label)
	local snap = snapshot_library(state.library)
	if not snap then
		return
	end

	local fp = library_fingerprint(snap)
	local top = state.undo_stack[#state.undo_stack]
	if top and top.fingerprint == fp then
		return
	end

	state.undo_stack[#state.undo_stack + 1] = {
		library = snap,
		selected_progression = state.selected_progression or 1,
		selected_chord = state.selected_chord or 1,
		fingerprint = fp,
		label = label or "Edit",
	}

	while #state.undo_stack > (state.undo_limit or 40) do
		table.remove(state.undo_stack, 1)
	end
end

local function undo_last_change()
	local top = state.undo_stack[#state.undo_stack]
	if not top then
		return false
	end
	table.remove(state.undo_stack, #state.undo_stack)
	state.library = snapshot_library(top.library) or top.library
	state.selected_progression = top.selected_progression or 1
	state.selected_chord = top.selected_chord or 1
	state.dirty = true
	return true
end

local function load_seed_library()
	local seed_path = script_path .. "data/library.json"
	local content = reaper_api.read_file(seed_path)
	if not content then
		return { progressions = {} }
	end

	local ok, decoded = pcall(json.decode, content)
	if ok and type(decoded) == "table" and type(decoded.progressions) == "table" then
		local safe = library_safety.sanitize_library(decoded)
		return safe
	end

	return { progressions = {} }
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

local function normalize_library(library)
	local sanitized_changed
	library, sanitized_changed = library_safety.sanitize_library(library)

	local seed = load_seed_library()
	local linked_seed = ensure_reference_links(library, seed)

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

	return library, (linked_seed or sanitized_changed)
end

local function load_library()
	local loaded = storage.load_library()
	local library, migration_changed = normalize_library(loaded)
	if migration_changed and loaded then
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
	state.on_the_fly_reharm = (prefs.on_the_fly_reharm ~= false)
	state.voice_leading_enabled = (prefs.voice_leading_enabled ~= false)
	state.grain_enabled = prefs.grain_enabled == true
	state.tag_search = tostring(prefs.tag_search or "")
	state.provenance_filter = tostring(prefs.provenance_filter or state.provenance_filter)
	state.playback_loop = (prefs.playback_loop ~= false)
end

local function save_prefs()
	storage.save_ui_prefs({
		show_roman = state.show_roman,
		reharm_mode = state.reharm_mode,
		on_the_fly_reharm = state.on_the_fly_reharm,
		voice_leading_enabled = state.voice_leading_enabled,
		grain_enabled = state.grain_enabled,
		tag_search = state.tag_search,
		provenance_filter = state.provenance_filter,
		playback_loop = state.playback_loop,
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

	local refs = state.reference_library and state.reference_library.progressions or {}
	local rcount = #refs
	if rcount < 1 then
		state.selected_reference_progression = 1
	elseif state.selected_reference_progression < 1 then
		state.selected_reference_progression = 1
	elseif state.selected_reference_progression > rcount then
		state.selected_reference_progression = rcount
	end
end

local function handle_save_request()
	if state.save_requested then
		save_library_if_needed(true)
		state.save_requested = false
	end
end

local function handle_undo_request()
	if not state.undo_requested then
		return
	end
	if not undo_last_change() then
		reaper_api.msg("Nothing to undo.")
	end
	state.undo_requested = false
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
		midi_writer.insert_progression(nil, nil, prog, {
			voice_leading = state.voice_leading_enabled == true,
		})
	end

	state.insert_progression_requested = false
end

local function handle_detect_request()
	if not state.detect_requested then
		return
	end

	local chords, err = midi_writer.detect_from_selected_item()
	if chords then
		push_undo_snapshot("Detect Chords")
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
	handle_undo_request()
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
	local sanitized
	state.library, sanitized = library_safety.sanitize_library(state.library)
	if sanitized then
		state.dirty = true
	end

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
state.push_undo_snapshot = push_undo_snapshot
load_prefs()
reaper.defer(main)

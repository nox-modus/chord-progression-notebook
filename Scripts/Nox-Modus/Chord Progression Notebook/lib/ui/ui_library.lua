local chord_model = require("lib.chord_model")
local json = require("lib.json")
local library_safety = require("lib.library_safety")
local midi_writer = require("lib.midi_writer")
local undo = require("lib.undo")

local ui_library = {}

local function pack_rgba(r, g, b, a)
	return (r << 24) | (g << 16) | (b << 8) | a
end

local ROW_SELECTED_BG = pack_rgba(96, 126, 168, 230)
local ROW_SELECTED_HOVER = pack_rgba(112, 144, 188, 235)
local ROW_SELECTED_ACTIVE = pack_rgba(126, 160, 206, 240)
local ROW_SELECTED_TEXT = pack_rgba(244, 248, 252, 255)

local PROVENANCE_FILTER_OPTIONS = {
	{ value = "all", label = "All" },
	{ value = "source_exact", label = "Source Exact" },
	{ value = "source_based", label = "Source Based" },
	{ value = "derived_template", label = "Derived Template" },
}

local function trim(s)
	return tostring(s or ""):match("^%s*(.-)%s*$")
end

local function parse_filter_tokens(text)
	local tokens = {}
	for token in tostring(text or ""):gmatch("[^,%s]+") do
		token = trim(token):lower()
		if token ~= "" then
			tokens[#tokens + 1] = token
		end
	end
	return tokens
end

local function progression_matches_tag_filter(prog, filter_tokens)
	if #filter_tokens == 0 then
		return true
	end

	local tags = type(prog.tags) == "table" and prog.tags or {}
	if #tags == 0 then
		return false
	end

	for _, token in ipairs(filter_tokens) do
		local token_found = false
		for _, tag in ipairs(tags) do
			local normalized_tag = tostring(tag or ""):lower()
			if normalized_tag:find(token, 1, true) then
				token_found = true
				break
			end
		end
		if not token_found then
			return false
		end
	end

	return true
end

local function progression_matches_provenance_filter(prog, provenance_filter)
	local active = tostring(provenance_filter or "all")
	if active == "all" or active == "" then
		return true
	end

	local p = type(prog.provenance) == "table" and prog.provenance or {}
	return tostring(p.type or "") == active
end

local function progression_matches_filters(prog, filter_tokens, provenance_filter)
	return progression_matches_tag_filter(prog, filter_tokens)
		and progression_matches_provenance_filter(prog, provenance_filter)
end

local function first_matching_progression_index(progressions, filter_tokens, provenance_filter)
	for i, prog in ipairs(progressions or {}) do
		if progression_matches_filters(prog, filter_tokens, provenance_filter) then
			return i
		end
	end
	return nil
end

local function count_matching_progressions(progressions, filter_tokens, provenance_filter)
	local count = 0
	for _, prog in ipairs(progressions or {}) do
		if progression_matches_filters(prog, filter_tokens, provenance_filter) then
			count = count + 1
		end
	end
	return count
end

local function maybe_repair_aeolian_example(prog)
	if type(prog) ~= "table" then
		return false
	end

	local name = tostring(prog.name or "")
	local mode = chord_model.normalize_mode(prog.mode)
	if mode ~= "minor" then
		return false
	end
	if not name:find("Aeolian", 1, true) then
		return false
	end
	if not name:find("i", 1, true) or not name:find("VII", 1, true) or not name:find("VI", 1, true) then
		return false
	end

	local key = prog.key_root or 0
	local expected = {
		{ root = chord_model.wrap12(key + 0), quality = "minor" },
		{ root = chord_model.wrap12(key + 10), quality = "major" },
		{ root = chord_model.wrap12(key + 8), quality = "major" },
		{ root = chord_model.wrap12(key + 10), quality = "major" },
	}

	local expected_roman = { "i", "VII", "VI", "VII" }
	local needs_repair = type(prog.chords) ~= "table" or #prog.chords < 4
	if not needs_repair then
		for i = 1, 4 do
			local chord = prog.chords[i]
			if type(chord) ~= "table" then
				needs_repair = true
				break
			end
			local roman = chord_model.roman_symbol(chord, key, prog.mode)
			if roman ~= expected_roman[i] then
				needs_repair = true
				break
			end
		end
	end

	if not needs_repair then
		return false
	end

	local repaired = {}
	for i = 1, 4 do
		local src = prog.chords and prog.chords[i] or nil
		repaired[i] = {
			root = expected[i].root,
			quality = expected[i].quality,
			duration = (src and src.duration) or 1,
			extensions = src and src.extensions or "",
			bass = src and src.bass or nil,
		}
	end
	prog.chords = repaired
	return true
end

local function new_progression_template()
	return {
		name = "New Progression",
		key_root = 0,
		mode = "major",
		tempo = 120,
		tags = {},
		notes = "",
		chords = { { root = 0, quality = "major", duration = 1 } },
		audio_refs = {},
	}
end

local function progression_name_from_chords(prog)
	if type(prog) ~= "table" or type(prog.chords) ~= "table" then
		return "New Progression"
	end

	local parts = {}
	for _, chord in ipairs(prog.chords) do
		if type(chord) == "table" then
			local symbol = chord_model.roman_symbol({
				root = chord.root,
				quality = chord.quality,
				extensions = "",
			}, prog.key_root or 0, prog.mode or "major")
			-- Compact display for diminished degrees in titles.
			symbol = tostring(symbol):gsub("dim", "°")
			parts[#parts + 1] = symbol
		end
	end

	if #parts == 0 then
		return "New Progression"
	end
	return table.concat(parts, "-")
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

local function find_reference_progression(state, prog)
	local refs = (state.reference_library and state.reference_library.progressions) or {}
	if type(refs) ~= "table" or #refs == 0 or type(prog) ~= "table" then
		return nil, nil
	end

	local ref_id = type(prog.ref_id) == "string" and prog.ref_id or nil
	if ref_id and ref_id ~= "" then
		for _, ref in ipairs(refs) do
			if progression_signature(ref) == ref_id then
				return ref, ref_id
			end
		end
	end

	local by_name = {}
	local target_name = tostring(prog.name or "")
	for _, ref in ipairs(refs) do
		if tostring(ref.name or "") == target_name then
			by_name[#by_name + 1] = ref
		end
	end
	if #by_name == 1 then
		local single = by_name[1]
		return single, progression_signature(single)
	end

	return nil, nil
end

local function restore_progression_from_reference(state, index)
	local list = state.library.progressions or {}
	local current = list[index]
	if not current then
		return false
	end

	local ref, ref_id = find_reference_progression(state, current)
	if not ref then
		return false
	end

	undo.push(state, "Restore From Reference")
	local restored = deep_copy(ref)
	restored.ref_id = ref_id
	list[index] = restored
	state.selected_progression = index
	state.selected_chord = 1
	state.dirty = true
	return true
end

local function add_reference_to_project(state, reference_index, force_duplicate)
	local refs = (state.reference_library and state.reference_library.progressions) or {}
	local source = refs[reference_index]
	if not source then
		return false, "No reference progression selected."
	end

	local list = state.library.progressions or {}
	local source_sig = progression_signature(source)
	if not force_duplicate then
		for i, prog in ipairs(list) do
			local ref_id = type(prog.ref_id) == "string" and prog.ref_id or ""
			if ref_id == source_sig or progression_signature(prog) == source_sig then
				state.selected_progression = i
				state.selected_chord = 1
				return false, "Progression already exists in project library."
			end
		end
	end

	local copy = deep_copy(source)
	undo.push(state, force_duplicate and "Duplicate Reference To Project" or "Add Reference To Project")
	copy.ref_id = source_sig
	list[#list + 1] = copy
	state.library.progressions = list
	state.selected_progression = #list
	state.selected_chord = 1
	state.dirty = true
	return true, nil
end

local function draw_row_context_menu(ctx, state, index, prog)
	local popup_id = "library_context_" .. tostring(index)
	if not reaper.ImGui_BeginPopupContextItem(ctx, popup_id) then
		return
	end

	if reaper.ImGui_MenuItem(ctx, "Restore From Reference") then
		if not restore_progression_from_reference(state, index) then
			reaper.ShowMessageBox(
				"No immutable reference found for this progression.",
				"Chord Progression Notebook",
				0
			)
		end
	end

	reaper.ImGui_EndPopup(ctx)
end

local function get_progression_for_player(state, source, index)
	if source == "reference" then
		local refs = (state.reference_library and state.reference_library.progressions) or {}
		return refs[index]
	end
	local list = (state.library and state.library.progressions) or {}
	return list[index]
end

local function stop_player(state)
	local player = state.library_player or {}
	player.active = false
	player.source = nil
	player.progression_index = 1
	player.chord_index = 1
	player.next_change_time = 0
	player.prev_pitches = nil
	state.library_player = player
	midi_writer.stop_preview()
end

local function start_player(state, source, index)
	local prog = get_progression_for_player(state, source, index)
	if not prog or type(prog.chords) ~= "table" or #prog.chords == 0 then
		reaper.ShowMessageBox("Selected progression has no chords to play.", "Chord Progression Notebook", 0)
		return
	end

	local player = state.library_player or {}
	player.active = true
	player.source = source
	player.progression_index = index
	player.chord_index = 1
	player.next_change_time = 0
	player.prev_pitches = nil
	state.library_player = player
end

local function start_selected_player(state)
	local source = state.last_selected_library or "project"
	local index = source == "reference" and (state.selected_reference_progression or 1) or (state.selected_progression or 1)
	local prog = get_progression_for_player(state, source, index)
	if not prog then
		if source == "reference" then
			source = "project"
			index = state.selected_progression or 1
		else
			source = "reference"
			index = state.selected_reference_progression or 1
		end
	end
	start_player(state, source, index)
end

local function update_player(state)
	local player = state.library_player or {}
	if not player.active then
		return
	end

	local prog = get_progression_for_player(state, player.source, player.progression_index)
	if not prog or type(prog.chords) ~= "table" or #prog.chords == 0 then
		stop_player(state)
		return
	end

	local now = reaper.time_precise()
	if now < (player.next_change_time or 0) then
		return
	end

	local chord_idx = player.chord_index or 1
	if chord_idx < 1 or chord_idx > #prog.chords then
		chord_idx = 1
	end
	local chord = prog.chords[chord_idx]
	if type(chord) ~= "table" then
		stop_player(state)
		return
	end

	local tempo = tonumber(prog.tempo) or 120
	if tempo <= 0 then
		tempo = 120
	end
	local qn_duration = tonumber(chord.duration) or 1
	if qn_duration <= 0 then
		qn_duration = 1
	end

	local chord_seconds = qn_duration * (60.0 / tempo)
	local preview_seconds = math.max(0.05, chord_seconds * 0.92)
	local pitches = nil
	if state.voice_leading_enabled == true then
		pitches = midi_writer.voice_lead_pitches(chord, player.prev_pitches, 4)
		player.prev_pitches = pitches
	end
	midi_writer.preview_chord(chord, {
		duration = preview_seconds,
		velocity = 108,
		octave = 4,
		channel = 0,
		pitches = pitches,
	})

	local next_idx = chord_idx + 1
	if next_idx > #prog.chords then
		if state.playback_loop == true then
			next_idx = 1
		else
			stop_player(state)
			return
		end
	end

	player.chord_index = next_idx
	player.next_change_time = now + chord_seconds
	state.library_player = player
end

local function draw_reference_list(ctx, state, filter_tokens, provenance_filter)
	local refs = (state.reference_library and state.reference_library.progressions) or {}
	local visible = 0
	for i, prog in ipairs(refs) do
		if progression_matches_filters(prog, filter_tokens, provenance_filter) then
			visible = visible + 1
			local label = string.format("%d: %s", i, prog.name or "(unnamed)")
			local selected = state.selected_reference_progression == i
			local style_count = 0
			if selected and reaper.ImGui_PushStyleColor then
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), ROW_SELECTED_BG)
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), ROW_SELECTED_HOVER)
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), ROW_SELECTED_ACTIVE)
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), ROW_SELECTED_TEXT)
				style_count = 4
			end

			if reaper.ImGui_Selectable(ctx, label, selected) then
				state.selected_reference_progression = i
				state.last_selected_library = "reference"
			end

			if style_count > 0 and reaper.ImGui_PopStyleColor then
				reaper.ImGui_PopStyleColor(ctx, style_count)
			end
		end
	end

	if visible == 0 then
		reaper.ImGui_TextDisabled(ctx, "No reference progressions match current tag filter.")
	end

	return visible
end

local function read_text_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

local function decode_library_from_path(path)
	local content = read_text_file(path)
	if not content then
		return nil
	end

	local ok, decoded = pcall(json.decode, content)
	if not ok or type(decoded) ~= "table" or type(decoded.progressions) ~= "table" then
		return nil
	end
	local safe = library_safety.sanitize_library(decoded)
	return safe
end

local function project_dir_from_path(path)
	if type(path) ~= "string" or path == "" then
		return nil
	end
	return path:match("^(.*)[/\\][^/\\]+$")
end

local function imported_library_path(selected_path)
	local lower = tostring(selected_path or ""):lower()
	if lower:sub(-12) == "library.json" then
		return selected_path
	end

	local project_dir = project_dir_from_path(selected_path)
	if not project_dir then
		return nil
	end
	return project_dir .. "/.chord_notebook/library.json"
end

local function merge_imported_progressions(state, imported)
	local target = state.library.progressions or {}
	local source = imported.progressions or {}
	local existing_sig = {}
	local existing_ref = {}

	for _, prog in ipairs(target) do
		existing_sig[progression_signature(prog)] = true
		local ref_id = type(prog.ref_id) == "string" and prog.ref_id or ""
		if ref_id ~= "" then
			existing_ref[ref_id] = true
		end
	end

	local added = 0
	for _, prog in ipairs(source) do
		local sig = progression_signature(prog)
		local ref_id = type(prog.ref_id) == "string" and prog.ref_id or ""
		local ref_exists = (ref_id ~= "") and existing_ref[ref_id] or false
		if not existing_sig[sig] and not ref_exists then
			if added == 0 then
				undo.push(state, "Import From Project")
			end
			target[#target + 1] = deep_copy(prog)
			existing_sig[sig] = true
			if ref_id ~= "" then
				existing_ref[ref_id] = true
			end
			added = added + 1
		end
	end

	state.library.progressions = target
	return added
end

local function import_library_from_project_dialog(state)
	local ok, selected_path = reaper.GetUserFileNameForRead("", "Import Library From Project", ".rpp")
	if not ok or not selected_path or selected_path == "" then
		return
	end

	local lib_path = imported_library_path(selected_path)
	if not lib_path then
		reaper.ShowMessageBox("Could not resolve project library path.", "Chord Progression Notebook", 0)
		return
	end

	local imported = decode_library_from_path(lib_path)
	if not imported then
		reaper.ShowMessageBox(
			"Could not load library from:\n" .. lib_path,
			"Chord Progression Notebook",
			0
		)
		return
	end

	local added = merge_imported_progressions(state, imported)
	if added > 0 then
		state.dirty = true
		reaper.ShowMessageBox(
			string.format("Imported %d progression(s) from:\n%s", added, lib_path),
			"Chord Progression Notebook",
			0
		)
	else
		reaper.ShowMessageBox("No new progressions found to import.", "Chord Progression Notebook", 0)
	end
end

function ui_library.import_from_project(state)
	import_library_from_project_dialog(state)
end

function ui_library.add_selected_reference_to_project(state, force_duplicate)
	local ok, message = add_reference_to_project(state, state.selected_reference_progression or 1, force_duplicate == true)
	if (not ok) and message and message ~= "" then
		reaper.ShowMessageBox(message, "Chord Progression Notebook", 0)
	end
	return ok
end

local function draw_progression_list(ctx, state, filter_tokens, provenance_filter)
	local visible = 0
	for i, prog in ipairs(state.library.progressions) do
		if progression_matches_filters(prog, filter_tokens, provenance_filter) then
			visible = visible + 1
			local label = string.format("%d: %s", i, prog.name or "(unnamed)")
			local selected = state.selected_progression == i
			local style_count = 0
			if selected and reaper.ImGui_PushStyleColor then
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), ROW_SELECTED_BG)
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), ROW_SELECTED_HOVER)
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), ROW_SELECTED_ACTIVE)
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), ROW_SELECTED_TEXT)
				style_count = 4
			end

			if reaper.ImGui_Selectable(ctx, label, selected) then
				state.selected_progression = i
				state.selected_chord = 1
				state.last_selected_library = "project"
				if maybe_repair_aeolian_example(prog) then
					state.dirty = true
				end
			end
			draw_row_context_menu(ctx, state, i, prog)

			if style_count > 0 and reaper.ImGui_PopStyleColor then
				reaper.ImGui_PopStyleColor(ctx, style_count)
			end
		end
	end

	if visible == 0 then
		local total = #(state.library.progressions or {})
		if total == 0 then
			reaper.ImGui_TextDisabled(ctx, "Project library is empty.")
			reaper.ImGui_TextDisabled(ctx, "Use 'Add To Project' from Reference Library above.")
		else
			reaper.ImGui_TextDisabled(ctx, "No project progressions match current tag filter.")
		end
	end

	return visible
end

function ui_library.draw(ctx, state)
	if not state.library or not state.reference_library then
		return
	end

	update_player(state)

	reaper.ImGui_Text(ctx, "Tag Search")

	local clear_button_w = 84
	local control_gap = 6
	local avail_w = reaper.ImGui_GetContentRegionAvail(ctx) or 0
	local inline_clear = avail_w >= (clear_button_w + 160)
	local input_w = inline_clear and math.max(80, avail_w - clear_button_w - control_gap) or -1

	if reaper.ImGui_SetNextItemWidth then
		reaper.ImGui_SetNextItemWidth(ctx, input_w)
	end
	local filter_changed, next_filter = reaper.ImGui_InputText(ctx, "##tag_search", state.tag_search or "")
	if filter_changed then
		state.tag_search = next_filter or ""
	end

	if inline_clear then
		reaper.ImGui_SameLine(ctx, nil, control_gap)
	end
	if reaper.ImGui_Button(ctx, "Clear Tags", clear_button_w, 0) then
		state.tag_search = ""
		filter_changed = true
	end

	local active_provenance = tostring(state.provenance_filter or "all")
	local preview_label = "All"
	for _, item in ipairs(PROVENANCE_FILTER_OPTIONS) do
		if item.value == active_provenance then
			preview_label = item.label
			break
		end
	end
	if reaper.ImGui_SetNextItemWidth then
		reaper.ImGui_SetNextItemWidth(ctx, -1)
	end
	if reaper.ImGui_BeginCombo(ctx, "##provenance_filter", preview_label) then
		for _, item in ipairs(PROVENANCE_FILTER_OPTIONS) do
			if reaper.ImGui_Selectable(ctx, item.label, item.value == active_provenance) then
				state.provenance_filter = item.value
				active_provenance = item.value
				filter_changed = true
			end
		end
		reaper.ImGui_EndCombo(ctx)
	end

	local filter_tokens = parse_filter_tokens(state.tag_search)
	if filter_changed and not progression_matches_filters(
		state.library.progressions[state.selected_progression] or {},
		filter_tokens,
		state.provenance_filter
	) then
		local match_index = first_matching_progression_index(
			state.library.progressions,
			filter_tokens,
			state.provenance_filter
		)
		if match_index then
			state.selected_progression = match_index
			state.selected_chord = 1
		end
	end

	local shown = count_matching_progressions(state.library.progressions, filter_tokens, state.provenance_filter)
	local refs_total = #(state.reference_library.progressions or {})
	local refs_shown = count_matching_progressions(
		state.reference_library.progressions or {},
		filter_tokens,
		state.provenance_filter
	)
	reaper.ImGui_TextDisabled(
		ctx,
		string.format(
			"Reference matches: %d/%d   Project matches: %d/%d",
			refs_shown,
			refs_total,
			shown,
			#state.library.progressions
		)
	)

	reaper.ImGui_Separator(ctx)
	reaper.ImGui_Text(ctx, "Reference Library (Read-Only)")

	if reaper.ImGui_Button(ctx, "Add To Project") then
		local ok, message = add_reference_to_project(state, state.selected_reference_progression, false)
		if (not ok) and message and message ~= "" then
			reaper.ShowMessageBox(message, "Chord Progression Notebook", 0)
		end
	end

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Duplicate To Project") then
		local ok, message = add_reference_to_project(state, state.selected_reference_progression, true)
		if (not ok) and message and message ~= "" then
			reaper.ShowMessageBox(message, "Chord Progression Notebook", 0)
		end
	end

	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0
	local ref_h = math.max(80, math.floor(avail_h * 0.34))
	reaper.ImGui_BeginChild(ctx, "##library_reference_list", -1, ref_h, 1)
	draw_reference_list(ctx, state, filter_tokens, state.provenance_filter)
	reaper.ImGui_EndChild(ctx)

	reaper.ImGui_Separator(ctx)
	reaper.ImGui_Text(ctx, "Project Library")

	if reaper.ImGui_Button(ctx, "New Progression") then
		undo.push(state, "New Progression")
		state.library.progressions[#state.library.progressions + 1] = new_progression_template()
		state.selected_progression = #state.library.progressions
		state.selected_chord = 1
		state.dirty = true
	end

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Save") then
		state.save_requested = true
	end

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Import From Project") then
		import_library_from_project_dialog(state)
	end

	if reaper.ImGui_Button(ctx, "Delete") then
		local list = state.library.progressions
		undo.push(state, "Delete Progression")
		if #list > 1 then
			table.remove(list, state.selected_progression)
			if state.selected_progression > #list then
				state.selected_progression = #list
			end
		else
			list[1] = new_progression_template()
			state.selected_progression = 1
		end
		state.selected_chord = 1
		state.dirty = true
	end

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Auto Name") then
		local prog = state.library.progressions[state.selected_progression]
		if prog then
			undo.push(state, "Auto Name Progression")
			prog.name = progression_name_from_chords(prog)
			state.dirty = true
		end
	end

	local project_avail_w, project_avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	project_avail_w = project_avail_w or 0
	project_avail_h = project_avail_h or 0
	local playback_h = 52
	local list_h = math.max(60, project_avail_h - playback_h - 6)

	reaper.ImGui_BeginChild(ctx, "##library_progression_list", -1, list_h, 1)
	draw_progression_list(ctx, state, filter_tokens, state.provenance_filter)
	reaper.ImGui_EndChild(ctx)

	local source_label = (state.last_selected_library == "reference") and "Reference selected" or "Project selected"
	reaper.ImGui_TextDisabled(ctx, source_label)

	if reaper.ImGui_Button(ctx, "Play Selected") then
		start_selected_player(state)
	end

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Stop") then
		stop_player(state)
	end

	local line_avail = reaper.ImGui_GetContentRegionAvail(ctx) or 0
	if line_avail > 80 then
		reaper.ImGui_SameLine(ctx)
	end
	local changed_loop
	changed_loop, state.playback_loop = reaper.ImGui_Checkbox(ctx, "Loop", state.playback_loop == true)
end

return ui_library

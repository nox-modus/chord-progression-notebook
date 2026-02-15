local chord_model = require("lib.chord_model")
local json = require("lib.json")

local ui_library = {}

local function pack_rgba(r, g, b, a)
	return (r << 24) | (g << 16) | (b << 8) | a
end

local ROW_SELECTED_BG = pack_rgba(96, 126, 168, 230)
local ROW_SELECTED_HOVER = pack_rgba(112, 144, 188, 235)
local ROW_SELECTED_ACTIVE = pack_rgba(126, 160, 206, 240)
local ROW_SELECTED_TEXT = pack_rgba(244, 248, 252, 255)

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

local function first_matching_progression_index(progressions, filter_tokens)
	for i, prog in ipairs(progressions or {}) do
		if progression_matches_tag_filter(prog, filter_tokens) then
			return i
		end
	end
	return nil
end

local function count_matching_progressions(progressions, filter_tokens)
	local count = 0
	for _, prog in ipairs(progressions or {}) do
		if progression_matches_tag_filter(prog, filter_tokens) then
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

	local restored = deep_copy(ref)
	restored.ref_id = ref_id
	list[index] = restored
	state.selected_progression = index
	state.selected_chord = 1
	state.dirty = true
	return true
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
	return decoded
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

local function draw_progression_list(ctx, state, filter_tokens)
	local visible = 0
	for i, prog in ipairs(state.library.progressions) do
		if progression_matches_tag_filter(prog, filter_tokens) then
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
		reaper.ImGui_TextDisabled(ctx, "No progressions match current tag filter.")
	end

	return visible
end

function ui_library.draw(ctx, state)
	if not state.library then
		return
	end

	reaper.ImGui_Text(ctx, "Library")

	if reaper.ImGui_Button(ctx, "New Progression") then
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

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Delete") then
		local list = state.library.progressions
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
			prog.name = progression_name_from_chords(prog)
			state.dirty = true
		end
	end

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

	local filter_tokens = parse_filter_tokens(state.tag_search)
	if filter_changed and not progression_matches_tag_filter(
		state.library.progressions[state.selected_progression] or {},
		filter_tokens
	) then
		local match_index = first_matching_progression_index(state.library.progressions, filter_tokens)
		if match_index then
			state.selected_progression = match_index
			state.selected_chord = 1
		end
	end

	local shown = count_matching_progressions(state.library.progressions, filter_tokens)
	reaper.ImGui_TextDisabled(ctx, string.format("Showing %d/%d", shown, #state.library.progressions))

	reaper.ImGui_BeginChild(ctx, "##library_progression_list", -1, -1, 1)
	draw_progression_list(ctx, state, filter_tokens)
	reaper.ImGui_EndChild(ctx)
end

return ui_library

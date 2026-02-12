local chord_model = require("lib.chord_model")

local ui_library = {}

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

local function draw_progression_list(ctx, state)
	for i, prog in ipairs(state.library.progressions) do
		local label = string.format("%d: %s", i, prog.name or "(unnamed)")
		if reaper.ImGui_Selectable(ctx, label, state.selected_progression == i) then
			state.selected_progression = i
			state.selected_chord = 1
			if maybe_repair_aeolian_example(prog) then
				state.dirty = true
			end
		end
	end
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

	reaper.ImGui_BeginChild(ctx, "##library_progression_list", -1, -1, 1)
	draw_progression_list(ctx, state)
	reaper.ImGui_EndChild(ctx)
end

return ui_library

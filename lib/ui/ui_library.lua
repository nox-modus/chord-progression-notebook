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

local function draw_key_mode_controls(ctx, state, prog)
	reaper.ImGui_Text(ctx, "Key")
	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_BeginCombo(ctx, "##libkey", chord_model.note_name(prog.key_root or 0)) then
		for pc = 0, 11 do
			if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), pc == (prog.key_root or 0)) then
				prog.key_root = pc
				state.dirty = true
			end
		end
		reaper.ImGui_EndCombo(ctx)
	end

	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_BeginCombo(ctx, "##libmode", prog.mode or "major") then
		for _, mode in ipairs(chord_model.MODES) do
			if reaper.ImGui_Selectable(ctx, mode, mode == (prog.mode or "major")) then
				prog.mode = mode
				state.dirty = true
			end
		end
		reaper.ImGui_EndCombo(ctx)
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

	reaper.ImGui_Separator(ctx)

	-- Keep key/mode controls visually anchored while the progression list scrolls.
	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local gap_h = 8
	local fit_slack_h = 6
	local min_key_block_h = 56
	local pref_key_block_h = 76
	local usable_h = math.max(1, avail_h - fit_slack_h)
	local key_block_h = math.min(pref_key_block_h, math.max(min_key_block_h, usable_h - gap_h - 1))
	local list_h = math.max(1, usable_h - key_block_h - gap_h)

	reaper.ImGui_BeginChild(ctx, "##library_progression_list", -1, list_h, 1)
	draw_progression_list(ctx, state)
	reaper.ImGui_EndChild(ctx)

	if gap_h > 0 then
		reaper.ImGui_Dummy(ctx, 0, gap_h)
	end

	local prog = state.library.progressions[state.selected_progression]
	reaper.ImGui_BeginChild(ctx, "##library_key_controls", -1, key_block_h, 0)
	reaper.ImGui_Separator(ctx)
	if prog then
		draw_key_mode_controls(ctx, state, prog)
	end
	reaper.ImGui_EndChild(ctx)
end

return ui_library

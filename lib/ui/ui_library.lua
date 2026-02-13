local chord_model = require("lib.chord_model")

local ui_library = {}

local function pack_rgba(r, g, b, a)
	return (r << 24) | (g << 16) | (b << 8) | a
end

local ROW_SELECTED_BG = pack_rgba(96, 126, 168, 230)
local ROW_SELECTED_HOVER = pack_rgba(112, 144, 188, 235)
local ROW_SELECTED_ACTIVE = pack_rgba(126, 160, 206, 240)
local ROW_SELECTED_TEXT = pack_rgba(244, 248, 252, 255)

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

local function draw_progression_list(ctx, state)
	for i, prog in ipairs(state.library.progressions) do
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

		if style_count > 0 and reaper.ImGui_PopStyleColor then
			reaper.ImGui_PopStyleColor(ctx, style_count)
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

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Auto Name") then
		local prog = state.library.progressions[state.selected_progression]
		if prog then
			prog.name = progression_name_from_chords(prog)
			state.dirty = true
		end
	end

	reaper.ImGui_BeginChild(ctx, "##library_progression_list", -1, -1, 1)
	draw_progression_list(ctx, state)
	reaper.ImGui_EndChild(ctx)
end

return ui_library

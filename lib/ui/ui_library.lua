local chord_model = require("lib.chord_model")

local ui_library = {}

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
	draw_progression_list(ctx, state)
	reaper.ImGui_Separator(ctx)

	local prog = state.library.progressions[state.selected_progression]
	if prog then
		draw_key_mode_controls(ctx, state, prog)
	end
end

return ui_library

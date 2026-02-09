local chord_model = require("lib.chord_model")
local harmony_engine = require("lib.harmony_engine")

local ui_progression_lane = {}

local function swap(tbl, a, b)
	tbl[a], tbl[b] = tbl[b], tbl[a]
end

local function chord_label(state, prog, chord)
	local symbol
	if state.show_roman then
		symbol = chord_model.roman_symbol(chord, prog.key_root, prog.mode)
	else
		symbol = chord_model.chord_symbol(chord)
	end

	local tension = harmony_engine.tension_score(chord)
	local brightness = harmony_engine.brightness_score(chord)
	return string.format("%s  [T:%d B:%d]", symbol, tension, brightness)
end

local function apply_reharm(state, prog, chord)
	chord.key_root = prog.key_root
	chord.mode = prog.mode

	local updated = harmony_engine.reharmonize(chord, state.reharm_mode)
	for k, v in pairs(updated) do
		chord[k] = v
	end

	state.dirty = true
end

local function draw_context_menu(ctx, state, chords, chord, index)
	if not reaper.ImGui_BeginPopupContextItem(ctx, "context") then
		return
	end

	if reaper.ImGui_MenuItem(ctx, "Insert MIDI at Cursor") then
		state.selected_chord = index
		state.insert_chord_requested = true
	end

	if reaper.ImGui_MenuItem(ctx, "Duplicate") then
		local copy = {}
		for k, v in pairs(chord) do
			copy[k] = v
		end
		table.insert(chords, index + 1, copy)
		state.dirty = true
	end

	if reaper.ImGui_MenuItem(ctx, "Delete") then
		table.remove(chords, index)
		if state.selected_chord > #chords then
			state.selected_chord = #chords
		end
		state.dirty = true
	end

	reaper.ImGui_EndPopup(ctx)
end

local function draw_dragdrop(ctx, state, chords, label, index)
	if reaper.ImGui_BeginDragDropSource(ctx) then
		reaper.ImGui_SetDragDropPayload(ctx, "CHORD_INDEX", tostring(index))
		reaper.ImGui_Text(ctx, label)
		reaper.ImGui_EndDragDropSource(ctx)
	end

	if not reaper.ImGui_BeginDragDropTarget(ctx) then
		return
	end

	local accepted, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "CHORD_INDEX")
	if type(accepted) == "string" and payload == nil then
		payload = accepted
		accepted = true
	end

	if accepted and payload then
		local from_idx = tonumber(payload)
		if from_idx and from_idx ~= index then
			swap(chords, from_idx, index)
			state.selected_chord = index
			state.dirty = true
		end
	end

	reaper.ImGui_EndDragDropTarget(ctx)
end

function ui_progression_lane.draw(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		return
	end

	reaper.ImGui_Text(ctx, "Progression")
	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Insert Progression MIDI") then
		state.insert_progression_requested = true
	end
	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Detect From Selected MIDI") then
		state.detect_requested = true
	end

	reaper.ImGui_Separator(ctx)

	local chords = prog.chords or {}
	for i, chord in ipairs(chords) do
		reaper.ImGui_PushID(ctx, i)

		local label = chord_label(state, prog, chord)
		local selected = state.selected_chord == i

		if reaper.ImGui_Selectable(ctx, label, selected, reaper.ImGui_SelectableFlags_AllowDoubleClick()) then
			state.selected_chord = i
			if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
				state.insert_chord_requested = true
			end
		end

		draw_dragdrop(ctx, state, chords, label, i)
		draw_context_menu(ctx, state, chords, chord, i)

		if reaper.ImGui_IsItemHovered(ctx) then
			local wheel = 0
			if reaper.ImGui_GetMouseWheel then
				wheel = reaper.ImGui_GetMouseWheel(ctx)
			else
				local io = reaper.ImGui_GetIO(ctx)
				wheel = io and io.MouseWheel or 0
			end

			if wheel ~= 0 then
				apply_reharm(state, prog, chord)
			end
		end

		reaper.ImGui_PopID(ctx)
	end

	if reaper.ImGui_Button(ctx, "+ Add Chord") then
		chords[#chords + 1] = {
			root = prog.key_root or 0,
			quality = "major",
			duration = 1,
		}
		state.selected_chord = #chords
		state.dirty = true
	end
end

return ui_progression_lane

local chord_model = require("lib.chord_model")
local harmony_engine = require("lib.harmony_engine")
local midi_writer = require("lib.midi_writer")
local undo = require("lib.undo")

local ui_progression_lane = {}

local function pack_rgba(r, g, b, a)
	return (r << 24) | (g << 16) | (b << 8) | a
end

local ROW_SELECTED_BG = pack_rgba(96, 126, 168, 230)
local ROW_SELECTED_HOVER = pack_rgba(112, 144, 188, 235)
local ROW_SELECTED_ACTIVE = pack_rgba(126, 160, 206, 240)
local ROW_SELECTED_TEXT = pack_rgba(244, 248, 252, 255)

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

local function draw_context_menu(ctx, state, chords, chord, index)
	if not reaper.ImGui_BeginPopupContextItem(ctx, "context") then
		return
	end

	if reaper.ImGui_MenuItem(ctx, "Insert MIDI at Cursor") then
		state.selected_chord = index
		state.insert_chord_requested = true
	end

	if reaper.ImGui_MenuItem(ctx, "Duplicate") then
		undo.push(state, "Duplicate Chord")
		local copy = {}
		for k, v in pairs(chord) do
			copy[k] = v
		end
		table.insert(chords, index + 1, copy)
		state.dirty = true
	end

	if reaper.ImGui_MenuItem(ctx, "Delete") then
		undo.push(state, "Delete Chord")
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
			undo.push(state, "Reorder Chords")
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

	ui_progression_lane.draw_toolbar(ctx, state)
	reaper.ImGui_Separator(ctx)
	ui_progression_lane.draw_list(ctx, state)
end

function ui_progression_lane.draw_toolbar(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		return
	end

	if reaper.ImGui_Button(ctx, "Insert Progression MIDI") then
		state.insert_progression_requested = true
	end
	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_Button(ctx, "Detect From Selected MIDI") then
		state.detect_requested = true
	end
end

function ui_progression_lane.draw_list(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		return
	end

	local chords = prog.chords or {}
	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local gap_h = 6
	local button_h = 26
	local list_h = math.max(1, avail_h - button_h - gap_h)

	reaper.ImGui_BeginChild(ctx, "##chord_list_scroll", -1, list_h, 0)
	for i, chord in ipairs(chords) do
		reaper.ImGui_PushID(ctx, i)

		local label = chord_label(state, prog, chord)
		local selected = state.selected_chord == i
		local style_count = 0

		if selected and reaper.ImGui_PushStyleColor then
			reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), ROW_SELECTED_BG)
			reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), ROW_SELECTED_HOVER)
			reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), ROW_SELECTED_ACTIVE)
			reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), ROW_SELECTED_TEXT)
			style_count = 4
		end

		if reaper.ImGui_Selectable(ctx, label, selected, reaper.ImGui_SelectableFlags_AllowDoubleClick()) then
			state.selected_chord = i
			midi_writer.preview_click(chord)
			if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
				state.insert_chord_requested = true
			end
		end

		if style_count > 0 and reaper.ImGui_PopStyleColor then
			reaper.ImGui_PopStyleColor(ctx, style_count)
		end

		draw_dragdrop(ctx, state, chords, label, i)
		draw_context_menu(ctx, state, chords, chord, i)

		reaper.ImGui_PopID(ctx)
	end
	reaper.ImGui_EndChild(ctx)

	if gap_h > 0 then
		reaper.ImGui_Dummy(ctx, 0, gap_h)
	end

	local row_w = reaper.ImGui_GetContentRegionAvail(ctx) or -1
	local btn_gap = 6
	local btn_w = -1
	if row_w and row_w > 0 then
		btn_w = math.max(60, (row_w - btn_gap) * 0.5)
	end

	if reaper.ImGui_Button(ctx, "+ Add Chord", btn_w, button_h) then
		undo.push(state, "Add Chord")
		chords[#chords + 1] = {
			root = prog.key_root or 0,
			quality = "major",
			duration = 1,
		}
		state.selected_chord = #chords
		state.dirty = true
	end

	reaper.ImGui_SameLine(ctx, nil, btn_gap)
	if reaper.ImGui_Button(ctx, "Delete Chord", btn_w, button_h) then
		local idx = state.selected_chord or #chords
		if #chords > 0 and idx >= 1 and idx <= #chords then
			undo.push(state, "Delete Chord")
			table.remove(chords, idx)
			if idx > #chords then
				idx = #chords
			end
			if idx < 1 then
				idx = 1
			end
			state.selected_chord = idx
			state.dirty = true
		end
	end
end

return ui_progression_lane

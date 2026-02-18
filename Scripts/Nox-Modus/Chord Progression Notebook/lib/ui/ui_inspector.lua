local chord_model = require("lib.chord_model")
local undo = require("lib.undo")
local imgui_guard = require("lib.ui.imgui_guard")

local ui_inspector = {}

local function tags_to_string(tags)
	if type(tags) ~= "table" then
		return ""
	end
	return table.concat(tags, ", ")
end

local function string_to_tags(text)
	local out = {}
	for token in string.gmatch(text or "", "[^,]+") do
		out[#out + 1] = token:gsub("^%s+", ""):gsub("%s+$", "")
	end
	return out
end

local function draw_root_combo(ctx, state, chord)
	local did_root_combo = imgui_guard.begin_combo(
		ctx,
		state,
		"Root",
		chord_model.note_name(chord.root or 0),
		"ui_inspector.combo.root"
	)
	if not did_root_combo then
		return
	end

	for pc = 0, 11 do
		if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), pc == (chord.root or 0)) then
			undo.push(state, "Edit Chord Root")
			chord.root = pc
			state.dirty = true
		end
	end

	imgui_guard.end_combo(ctx, state, did_root_combo, "ui_inspector.combo.root")
end

local function draw_quality_combo(ctx, state, chord)
	local selected = chord.quality or "major"
	local did_quality_combo =
		imgui_guard.begin_combo(ctx, state, "Quality", selected, "ui_inspector.combo.quality")
	if not did_quality_combo then
		return
	end

	for _, quality in ipairs(chord_model.QUALITY_ORDER) do
		if reaper.ImGui_Selectable(ctx, quality, quality == selected) then
			undo.push(state, "Edit Chord Quality")
			chord.quality = quality
			state.dirty = true
		end
	end

	imgui_guard.end_combo(ctx, state, did_quality_combo, "ui_inspector.combo.quality")
end

local function draw_bass_combo(ctx, state, chord)
	local preview = chord.bass and chord_model.note_name(chord.bass) or "(none)"
	local did_bass_combo = imgui_guard.begin_combo(ctx, state, "Bass", preview, "ui_inspector.combo.bass")
	if not did_bass_combo then
		return
	end

	if reaper.ImGui_Selectable(ctx, "(none)", chord.bass == nil) then
		undo.push(state, "Edit Chord Bass")
		chord.bass = nil
		state.dirty = true
	end

	for pc = 0, 11 do
		if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), chord.bass == pc) then
			undo.push(state, "Edit Chord Bass")
			chord.bass = pc
			state.dirty = true
		end
	end

	imgui_guard.end_combo(ctx, state, did_bass_combo, "ui_inspector.combo.bass")
end

local function draw_audio_refs(ctx, state, prog)
	reaper.ImGui_Separator(ctx)
	reaper.ImGui_Text(ctx, "Audio Links")

	prog.audio_refs = prog.audio_refs or {}
	for i, ref in ipairs(prog.audio_refs) do
		reaper.ImGui_PushID(ctx, i)

		local changed_path, path = reaper.ImGui_InputText(ctx, "##path", ref.path or "")
		if changed_path then
			undo.push(state, "Edit Audio Ref")
			ref.path = path
			state.dirty = true
		end

		reaper.ImGui_SameLine(ctx)
		if reaper.ImGui_Button(ctx, "Remove") then
			undo.push(state, "Remove Audio Ref")
			table.remove(prog.audio_refs, i)
			state.dirty = true
		end

		reaper.ImGui_PopID(ctx)
	end

	if reaper.ImGui_Button(ctx, "Add Audio Ref") then
		undo.push(state, "Add Audio Ref")
		prog.audio_refs[#prog.audio_refs + 1] = { path = "" }
		state.dirty = true
	end
end

local function draw_notes_field(ctx, prog)
	return reaper.ImGui_InputText(ctx, "Notes", prog.notes or "")
end

function ui_inspector.draw(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		return
	end

	reaper.ImGui_Text(ctx, "Inspector")
	reaper.ImGui_Separator(ctx)

	local changed_name, name = reaper.ImGui_InputText(ctx, "Name", prog.name or "")
	if changed_name then
		undo.push(state, "Edit Name")
		prog.name = name
		state.dirty = true
	end

	local changed_tempo, tempo = reaper.ImGui_InputInt(ctx, "Tempo", prog.tempo or 120)
	if changed_tempo then
		undo.push(state, "Edit Tempo")
		prog.tempo = math.max(20, tempo)
		state.dirty = true
	end

	local changed_tags, tags = reaper.ImGui_InputText(ctx, "Tags", tags_to_string(prog.tags))
	if changed_tags then
		undo.push(state, "Edit Tags")
		prog.tags = string_to_tags(tags)
		state.dirty = true
	end

	local changed_notes, notes = draw_notes_field(ctx, prog)
	if changed_notes then
		undo.push(state, "Edit Notes")
		prog.notes = notes
		state.dirty = true
	end

	reaper.ImGui_Separator(ctx)
	reaper.ImGui_Text(ctx, "Chord")

	local chord = prog.chords[state.selected_chord or 1]
	if chord then
		draw_root_combo(ctx, state, chord)
		draw_quality_combo(ctx, state, chord)

		local changed_ext, ext = reaper.ImGui_InputText(ctx, "Extensions", chord.extensions or "")
		if changed_ext then
			undo.push(state, "Edit Chord Extensions")
			chord.extensions = ext
			state.dirty = true
		end

		draw_bass_combo(ctx, state, chord)

		local changed_duration, duration =
			reaper.ImGui_InputDouble(ctx, "Duration (beats)", chord.duration or 1, 0.25, 1.0, "%.2f")
		if changed_duration then
			undo.push(state, "Edit Chord Duration")
			chord.duration = math.max(0.25, duration)
			state.dirty = true
		end
	end

	draw_audio_refs(ctx, state, prog)
end

return ui_inspector

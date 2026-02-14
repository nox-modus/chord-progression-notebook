local chord_model = require("lib.chord_model")

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
	if not reaper.ImGui_BeginCombo(ctx, "Root", chord_model.note_name(chord.root or 0)) then
		return
	end

	for pc = 0, 11 do
		if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), pc == (chord.root or 0)) then
			chord.root = pc
			state.dirty = true
		end
	end

	reaper.ImGui_EndCombo(ctx)
end

local function draw_quality_combo(ctx, state, chord)
	local selected = chord.quality or "major"
	if not reaper.ImGui_BeginCombo(ctx, "Quality", selected) then
		return
	end

	for _, quality in ipairs(chord_model.QUALITY_ORDER) do
		if reaper.ImGui_Selectable(ctx, quality, quality == selected) then
			chord.quality = quality
			state.dirty = true
		end
	end

	reaper.ImGui_EndCombo(ctx)
end

local function draw_bass_combo(ctx, state, chord)
	local preview = chord.bass and chord_model.note_name(chord.bass) or "(none)"
	if not reaper.ImGui_BeginCombo(ctx, "Bass", preview) then
		return
	end

	if reaper.ImGui_Selectable(ctx, "(none)", chord.bass == nil) then
		chord.bass = nil
		state.dirty = true
	end

	for pc = 0, 11 do
		if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), chord.bass == pc) then
			chord.bass = pc
			state.dirty = true
		end
	end

	reaper.ImGui_EndCombo(ctx)
end

local function draw_audio_refs(ctx, state, prog)
	reaper.ImGui_Separator(ctx)
	reaper.ImGui_Text(ctx, "Audio Links")

	prog.audio_refs = prog.audio_refs or {}
	for i, ref in ipairs(prog.audio_refs) do
		reaper.ImGui_PushID(ctx, i)

		local changed_path, path = reaper.ImGui_InputText(ctx, "##path", ref.path or "")
		if changed_path then
			ref.path = path
			state.dirty = true
		end

		reaper.ImGui_SameLine(ctx)
		if reaper.ImGui_Button(ctx, "Remove") then
			table.remove(prog.audio_refs, i)
			state.dirty = true
		end

		reaper.ImGui_PopID(ctx)
	end

	if reaper.ImGui_Button(ctx, "Add Audio Ref") then
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
		prog.name = name
		state.dirty = true
	end

	local changed_tempo, tempo = reaper.ImGui_InputInt(ctx, "Tempo", prog.tempo or 120)
	if changed_tempo then
		prog.tempo = math.max(20, tempo)
		state.dirty = true
	end

	local changed_tags, tags = reaper.ImGui_InputText(ctx, "Tags", tags_to_string(prog.tags))
	if changed_tags then
		prog.tags = string_to_tags(tags)
		state.dirty = true
	end

	local changed_notes, notes = draw_notes_field(ctx, prog)
	if changed_notes then
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
			chord.extensions = ext
			state.dirty = true
		end

		draw_bass_combo(ctx, state, chord)

		local changed_duration, duration =
			reaper.ImGui_InputDouble(ctx, "Duration (beats)", chord.duration or 1, 0.25, 1.0, "%.2f")
		if changed_duration then
			chord.duration = math.max(0.25, duration)
			state.dirty = true
		end
	end

	draw_audio_refs(ctx, state, prog)
end

return ui_inspector

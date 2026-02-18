local chord_model = require("lib.chord_model")
local harmony_engine = require("lib.harmony_engine")
local midi_writer = require("lib.midi_writer")
local storage = require("lib.storage")
local undo = require("lib.undo")
local ui_circle = require("lib.ui.ui_circle_of_fifths")
local imgui_guard = require("lib.ui.imgui_guard")
local ui_inspector = require("lib.ui.ui_inspector")
local ui_library = require("lib.ui.ui_library")
local ui_progression_lane = require("lib.ui.ui_progression_lane")

local ui_main = {}
local MIN_WINDOW_W = 860
local MIN_WINDOW_H = 560
local MIN_CIRCLE_DRAW_SIZE = 206

local function ASSERT_CTX(ctx, where)
	if type(ctx) ~= "userdata" then
		reaper.ShowConsoleMsg(("[ChordNotebook] BAD CTX at %s, type=%s\n"):format(where, type(ctx)))
	end
end

-- Keep packing stable with current project color usage.
local function pack_rgba(r, g, b, a)
	return (r << 24) | (g << 16) | (b << 8) | a
end

local PALETTE = {
	bg_base = pack_rgba(39, 41, 46, 255),
	bg_panel = pack_rgba(43, 45, 50, 220),
	bg_vignette = pack_rgba(10, 12, 14, 120),
	grain_dot = pack_rgba(245, 248, 255, 10),
	wedge_hover = pack_rgba(55, 68, 86, 200),
	wedge_sel = pack_rgba(86, 124, 178, 220),
	btn_accent = pack_rgba(154, 92, 44, 255),
	btn_accent_hover = pack_rgba(178, 108, 52, 255),
	btn_accent_active = pack_rgba(198, 122, 58, 255),
	border = pack_rgba(130, 150, 180, 50),
	text = pack_rgba(210, 218, 228, 255),
}

local STYLE_COLORS = {
	{ "ImGui_Col_WindowBg", "bg_base" },
	{ "ImGui_Col_MenuBarBg", "bg_panel" },
	{ "ImGui_Col_TitleBg", "bg_panel" },
	{ "ImGui_Col_TitleBgActive", "bg_panel" },
	{ "ImGui_Col_TitleBgCollapsed", "bg_panel" },
	{ "ImGui_Col_ChildBg", "bg_panel" },
	{ "ImGui_Col_FrameBg", "bg_panel" },
	{ "ImGui_Col_FrameBgHovered", "wedge_hover" },
	{ "ImGui_Col_FrameBgActive", "wedge_sel" },
	{ "ImGui_Col_Button", "btn_accent" },
	{ "ImGui_Col_ButtonHovered", "btn_accent_hover" },
	{ "ImGui_Col_ButtonActive", "btn_accent_active" },
	{ "ImGui_Col_Header", "bg_panel" },
	{ "ImGui_Col_HeaderHovered", "wedge_hover" },
	{ "ImGui_Col_HeaderActive", "wedge_sel" },
	{ "ImGui_Col_Separator", "border" },
	{ "ImGui_Col_Border", "border" },
	{ "ImGui_Col_Text", "text" },
	{ "ImGui_Col_TextDisabled", "text" },
	{ "ImGui_Col_ScrollbarBg", "bg_panel" },
	{ "ImGui_Col_ScrollbarGrab", "border" },
	{ "ImGui_Col_ScrollbarGrabHovered", "wedge_hover" },
	{ "ImGui_Col_ScrollbarGrabActive", "wedge_sel" },
}

local function draw_background(ctx, state)
	if not reaper.ImGui_GetWindowDrawList then
		return
	end

	local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
	local wx, wy = reaper.ImGui_GetWindowPos(ctx)
	local ww, wh = reaper.ImGui_GetWindowSize(ctx)

	wx = wx or 0
	wy = wy or 0
	ww = ww or 0
	wh = wh or 0

	reaper.ImGui_DrawList_AddRectFilled(draw_list, wx, wy, wx + ww, wy + wh, PALETTE.bg_base)

	local band = 36
	reaper.ImGui_DrawList_AddRectFilled(draw_list, wx, wy, wx + ww, wy + band, PALETTE.bg_vignette)
	reaper.ImGui_DrawList_AddRectFilled(draw_list, wx, wy + wh - band, wx + ww, wy + wh, PALETTE.bg_vignette)
	reaper.ImGui_DrawList_AddRectFilled(draw_list, wx, wy, wx + band, wy + wh, PALETTE.bg_vignette)
	reaper.ImGui_DrawList_AddRectFilled(draw_list, wx + ww - band, wy, wx + ww, wy + wh, PALETTE.bg_vignette)
end

local function push_style(ctx)
	if not reaper.ImGui_PushStyleColor then
		return 0
	end

	local count = 0
	for _, spec in ipairs(STYLE_COLORS) do
		local enum_fn = reaper[spec[1]]
		local col = PALETTE[spec[2]]
		if enum_fn and col then
			reaper.ImGui_PushStyleColor(ctx, enum_fn(), col)
			count = count + 1
		end
	end
	return count
end

local function pop_style(ctx, count)
	if reaper.ImGui_PopStyleColor and count > 0 then
		reaper.ImGui_PopStyleColor(ctx, count)
	end
end

local function draw_suggestions(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	local chord = prog and prog.chords and prog.chords[state.selected_chord or 1]
	if not chord then
		return
	end

	reaper.ImGui_Text(ctx, "Suggestions")

	local actions = {
		{
			label = "Diatonic Subs",
			run = function()
				state.suggestions = harmony_engine.suggest_diatonic_subs(chord, prog.key_root, prog.mode)
			end,
		},
		{
			label = "Secondary Dom",
			run = function()
				state.suggestions = { harmony_engine.secondary_dominant(chord) }
			end,
		},
		{
			label = "Tritone Sub",
			run = function()
				state.suggestions = { harmony_engine.tritone_sub(chord) }
			end,
		},
		{
			label = "Modal Interchange",
			run = function()
				local alt = harmony_engine.modal_interchange(chord, prog.key_root)
				state.suggestions = alt and { alt } or {}
			end,
		},
		{
			label = "Dim Passing",
			run = function()
				state.suggestions = { harmony_engine.diminished_passing(chord) }
			end,
		},
	}

	local max_label_w = 0
	if reaper.ImGui_CalcTextSize then
		for _, item in ipairs(actions) do
			local ok, w = pcall(reaper.ImGui_CalcTextSize, ctx, item.label)
			if ok and type(w) == "number" and w > max_label_w then
				max_label_w = w
			end
		end
	end
	local button_w = math.max(110, math.floor(max_label_w + 20))

	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local gap = 8
	local left_w = math.min(math.max(button_w + 12, 124), math.floor(avail_w * 0.45))
	local right_w = avail_w - left_w - gap
	local panel_h = math.max(1, avail_h)

	if right_w < 80 then
		for _, item in ipairs(actions) do
			if reaper.ImGui_Button(ctx, item.label, button_w, 0) then
				item.run()
			end
		end
	else
		local did_actions_child =
			imgui_guard.begin_child(ctx, state, "##suggest_actions", left_w, panel_h, 1, nil, "ui_main.child.suggest_actions")
		if did_actions_child then
			for _, item in ipairs(actions) do
				if reaper.ImGui_Button(ctx, item.label, button_w, 0) then
					item.run()
				end
			end
		end
		imgui_guard.end_child(ctx, state, did_actions_child, "ui_main.child.suggest_actions")

		reaper.ImGui_SameLine(ctx, nil, gap)

		local did_results_child =
			imgui_guard.begin_child(ctx, state, "##suggest_results", right_w, panel_h, 1, nil, "ui_main.child.suggest_results")
		if did_results_child then
			if not state.suggestions or #state.suggestions == 0 then
				reaper.ImGui_TextDisabled(ctx, "No suggestions yet.")
			else
				for i, suggestion in ipairs(state.suggestions) do
					local symbol
					if state.show_roman then
						symbol = chord_model.roman_symbol(suggestion, prog.key_root, prog.mode)
					else
						symbol = chord_model.chord_symbol(suggestion)
					end

					local label = string.format("%d) %s", i, symbol)
					if reaper.ImGui_Selectable(ctx, label, false) then
						undo.push(state, "Apply Suggestion")
						for k, v in pairs(suggestion) do
							chord[k] = v
						end
						state.dirty = true
						midi_writer.preview_click(chord)
					end
				end
			end
		end
		imgui_guard.end_child(ctx, state, did_results_child, "ui_main.child.suggest_results")
	end
end

local function draw_menu(ctx, state)
	local did_menubar = imgui_guard.begin_menubar(ctx, state, "ui_main.menubar.main")
	if not did_menubar then
		return
	end

	if reaper.ImGui_MenuItem(ctx, "Save Library") then
		state.save_requested = true
	end

	if reaper.ImGui_MenuItem(ctx, "Undo Last Change") then
		undo.request(state)
	end

	if reaper.ImGui_MenuItem(ctx, "Import Library From Project...") then
		ui_library.import_from_project(state)
	end

	if reaper.ImGui_MenuItem(ctx, "Show Library Path") then
		local path = storage.get_library_path()
		reaper.ShowMessageBox("Active working library path:\n" .. tostring(path), "Chord Progression Notebook", 0)
	end

	if reaper.ImGui_MenuItem(ctx, "Quit") then
		state.ui_open = false
	end

	imgui_guard.end_menubar(ctx, state, did_menubar, "ui_main.menubar.main")
end

local function draw_left_key_controls(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		reaper.ImGui_TextDisabled(ctx, "No project progression selected.")
		reaper.ImGui_TextDisabled(ctx, "Add one from Reference Library or create a new one.")
		return
	end

	local function scale_degree_for_relative_pc(mode, rel_pc)
		local scale = chord_model.get_scale_degrees(mode)
		for i, pc in ipairs(scale) do
			if chord_model.wrap12(pc) == chord_model.wrap12(rel_pc) then
				return i
			end
		end
		return nil
	end

	local function remap_progression_for_key_change(prog_ref, old_key, new_key, old_mode, new_mode)
		local old_scale = chord_model.get_scale_degrees(old_mode)
		local new_scale = chord_model.get_scale_degrees(new_mode)
		local delta = chord_model.wrap12((new_key or 0) - (old_key or 0))

		for _, chord in ipairs(prog_ref.chords or {}) do
			local old_rel = chord_model.wrap12((chord.root or 0) - (old_key or 0))
			local degree = scale_degree_for_relative_pc(old_mode, old_rel)
			if degree and old_scale[degree] and new_scale[degree] then
				chord.root = chord_model.wrap12((new_key or 0) + new_scale[degree])
			else
				chord.root = chord_model.wrap12((chord.root or 0) + delta)
			end

			-- Keep slash-bass movement coherent when transposing key center.
			if chord.bass ~= nil then
				chord.bass = chord_model.wrap12((chord.bass or 0) + delta)
			end
		end
	end

	reaper.ImGui_Text(ctx, "Key")
	reaper.ImGui_SameLine(ctx)

	local did_key_root_combo =
		imgui_guard.begin_combo(ctx, state, "##left_key_root", chord_model.note_name(prog.key_root or 0), "ui_main.combo.left_key_root")
	if did_key_root_combo then
		for pc = 0, 11 do
			if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), pc == (prog.key_root or 0)) then
				local old_key = prog.key_root or 0
				local old_mode = prog.mode or "major"
				undo.push(state, "Change Key")
				if state.on_the_fly_reharm == true then
					remap_progression_for_key_change(prog, old_key, pc, old_mode, old_mode)
				end
				prog.key_root = pc
				state.dirty = true
			end
		end
	end
	imgui_guard.end_combo(ctx, state, did_key_root_combo, "ui_main.combo.left_key_root")

	reaper.ImGui_SameLine(ctx)
	local did_key_mode_combo =
		imgui_guard.begin_combo(ctx, state, "##left_key_mode", prog.mode or "major", "ui_main.combo.left_key_mode")
	if did_key_mode_combo then
		for _, mode in ipairs(chord_model.MODES) do
			if reaper.ImGui_Selectable(ctx, mode, mode == (prog.mode or "major")) then
				local old_key = prog.key_root or 0
				local old_mode = prog.mode or "major"
				undo.push(state, "Change Mode")
				if state.on_the_fly_reharm == true then
					remap_progression_for_key_change(prog, old_key, old_key, old_mode, mode)
				end
				prog.mode = mode
				state.dirty = true
			end
		end
	end
	imgui_guard.end_combo(ctx, state, did_key_mode_combo, "ui_main.combo.left_key_mode")
end

local function draw_left_panel(ctx, state)
	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local gap_h = 1
	-- Keep enough height for Key + View/Reharm controls without excessive empty space.
	local controls_h = math.max(152, math.floor(avail_h * 0.20))
	local lib_h = math.max(80, avail_h - controls_h - gap_h)

	local did_library_child =
		imgui_guard.begin_child(ctx, state, "##left_library_area", -1, lib_h, 0, nil, "ui_main.child.left_library_area")
	if did_library_child then
		ui_library.draw(ctx, state)
	end
	imgui_guard.end_child(ctx, state, did_library_child, "ui_main.child.left_library_area")

	reaper.ImGui_Dummy(ctx, 0, gap_h)

	local settings_flags = 0
	if reaper.ImGui_WindowFlags_NoScrollbar then
		settings_flags = settings_flags | reaper.ImGui_WindowFlags_NoScrollbar()
	end
	if reaper.ImGui_WindowFlags_NoScrollWithMouse then
		settings_flags = settings_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
	end

	local did_settings_child =
		imgui_guard.begin_child(ctx, state, "##left_settings_area", -1, -1, 1, settings_flags, "ui_main.child.left_settings_area")
	if did_settings_child then
		draw_left_key_controls(ctx, state)
		reaper.ImGui_Separator(ctx)
		reaper.ImGui_Text(ctx, "View / Reharm")

		local changed_show
		changed_show, state.show_roman = reaper.ImGui_Checkbox(ctx, "Roman Numerals", state.show_roman)
		if changed_show then
			state.dirty = true
		end

		local changed_reharm_live
		changed_reharm_live, state.on_the_fly_reharm =
			reaper.ImGui_Checkbox(ctx, "On-the-fly Reharm", state.on_the_fly_reharm == true)
		if changed_reharm_live then
			state.dirty = true
		end

		local changed_voice_leading
		changed_voice_leading, state.voice_leading_enabled =
			reaper.ImGui_Checkbox(ctx, "Voice Leading", state.voice_leading_enabled == true)
		if changed_voice_leading then
			state.dirty = true
		end

		local modes = {
			"diatonic_rotate",
			"function_preserving",
			"chromatic_approach",
			"modal_interchange",
		}

		local did_reharm_combo =
			imgui_guard.begin_combo(ctx, state, "Reharm Mode", state.reharm_mode or modes[1], "ui_main.combo.reharm_mode")
		if did_reharm_combo then
			for _, mode in ipairs(modes) do
				if reaper.ImGui_Selectable(ctx, mode, mode == state.reharm_mode) then
					state.reharm_mode = mode
				end
			end
		end
		imgui_guard.end_combo(ctx, state, did_reharm_combo, "ui_main.combo.reharm_mode")
	end
	imgui_guard.end_child(ctx, state, did_settings_child, "ui_main.child.left_settings_area")
end

local function draw_center_panel(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		local did_empty_child =
			imgui_guard.begin_child(ctx, state, "##center_empty_state", -1, -1, 1, nil, "ui_main.child.center_empty_state")
		if did_empty_child then
			reaper.ImGui_TextDisabled(ctx, "Project library is empty.")
			reaper.ImGui_Separator(ctx)
			reaper.ImGui_TextWrapped(ctx, "Use 'Add To Project' in the Reference Library,")
			reaper.ImGui_TextWrapped(ctx, "or click 'New Progression' in Project Library.")
			reaper.ImGui_Dummy(ctx, 0, 8)
			if reaper.ImGui_Button(ctx, "Add Selected Reference", 200, 0) then
				ui_library.add_selected_reference_to_project(state, false)
			end
			reaper.ImGui_SameLine(ctx)
			if reaper.ImGui_Button(ctx, "New Progression", 160, 0) then
				undo.push(state, "New Progression")
				state.library.progressions[#state.library.progressions + 1] = {
					name = "New Progression",
					key_root = 0,
					mode = "major",
					tempo = 120,
					tags = {},
					notes = "",
					chords = { { root = 0, quality = "major", duration = 1 } },
					audio_refs = {},
				}
				state.selected_progression = #state.library.progressions
				state.selected_chord = 1
				state.dirty = true
			end
		end
		imgui_guard.end_child(ctx, state, did_empty_child, "ui_main.child.center_empty_state")
		return
	end

	ui_progression_lane.draw_toolbar(ctx, state)
	reaper.ImGui_Separator(ctx)

	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local min_list_h = 90
	local min_circle_h = MIN_CIRCLE_DRAW_SIZE
	local spacing_h = 6
	local total_h = math.max(0, avail_h)
	local max_circle_from_list = math.max(0, total_h - spacing_h - min_list_h)

	-- Keep circle area square when possible (anchors the ring against all sides
	-- of its frame), while preserving room for progression list below.
	local circle_h = math.min(avail_w, max_circle_from_list)
	circle_h = math.max(min_circle_h, circle_h)
	if circle_h > max_circle_from_list then
		circle_h = max_circle_from_list
	end

	local did_circle_child =
		imgui_guard.begin_child(ctx, state, "##center_circle_area", -1, circle_h, 1, nil, "ui_main.child.center_circle_area")
	if did_circle_child then
		ui_circle.draw(ctx, state)
	end
	imgui_guard.end_child(ctx, state, did_circle_child, "ui_main.child.center_circle_area")

	reaper.ImGui_Dummy(ctx, 0, spacing_h)

	-- Fill the remaining height exactly to avoid scrollbar oscillation.
	local prog_flags = 0
	if reaper.ImGui_WindowFlags_NoScrollbar then
		prog_flags = prog_flags | reaper.ImGui_WindowFlags_NoScrollbar()
	end
	if reaper.ImGui_WindowFlags_NoScrollWithMouse then
		prog_flags = prog_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
	end
	local did_bottom_child = imgui_guard.begin_child(
		ctx,
		state,
		"##progression_bottom_left",
		-1,
		-1,
		1,
		prog_flags,
		"ui_main.child.progression_bottom_left"
	)
	if did_bottom_child then
		ui_progression_lane.draw_list(ctx, state)
	end
	imgui_guard.end_child(ctx, state, did_bottom_child, "ui_main.child.progression_bottom_left")
end

local function draw_right_panel(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		reaper.ImGui_TextDisabled(ctx, "Inspector unavailable: no project progression selected.")
		reaper.ImGui_Separator(ctx)
		reaper.ImGui_TextDisabled(ctx, "Suggestions unavailable until a progression is selected.")
		return
	end

	ui_inspector.draw(ctx, state)
	reaper.ImGui_Separator(ctx)
	draw_suggestions(ctx, state)
end

local function draw_three_panel_layout(ctx, state)
	local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
	local left_w = 286
	local right_w = 360
	local gap = 8
	local center_w = avail_w - left_w - right_w - 2 * gap
	if center_w < 160 then
		center_w = 160
	end

	local left_flags = 0
	if reaper.ImGui_WindowFlags_NoScrollbar then
		left_flags = left_flags | reaper.ImGui_WindowFlags_NoScrollbar()
	end
	if reaper.ImGui_WindowFlags_NoScrollWithMouse then
		left_flags = left_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
	end
	local did_left_child = imgui_guard.begin_child(ctx, state, "##left", left_w, -1, 1, left_flags, "ui_main.child.layout_left")
	if did_left_child then
		draw_left_panel(ctx, state)
	end
	imgui_guard.end_child(ctx, state, did_left_child, "ui_main.child.layout_left")

	reaper.ImGui_SameLine(ctx, nil, gap)

	local did_center_child =
		imgui_guard.begin_child(ctx, state, "##center", center_w, -1, 1, nil, "ui_main.child.layout_center")
	if did_center_child then
		draw_center_panel(ctx, state)
	end
	imgui_guard.end_child(ctx, state, did_center_child, "ui_main.child.layout_center")

	reaper.ImGui_SameLine(ctx, nil, gap)

	local did_right_child = imgui_guard.begin_child(ctx, state, "##right", right_w, -1, 1, nil, "ui_main.child.layout_right")
	if did_right_child then
		draw_right_panel(ctx, state)
	end
	imgui_guard.end_child(ctx, state, did_right_child, "ui_main.child.layout_right")
end

function ui_main.draw(ctx, state)
	ASSERT_CTX(ctx, "ui_main.draw entry")
	if not state.library then
		return
	end

	local style_count = push_style(ctx)

	if reaper.ImGui_SetNextWindowSizeConstraints then
		reaper.ImGui_SetNextWindowSizeConstraints(ctx, MIN_WINDOW_W, MIN_WINDOW_H, 10000, 10000)
	end

	local did_window, visible, open = imgui_guard.begin_window(
		ctx,
		state,
		"Chord Progression Notebook",
		true,
		reaper.ImGui_WindowFlags_MenuBar(),
		"ui_main.window.main"
	)
	state.ui_open = open == nil and true or open

	if did_window and visible then
		draw_background(ctx, state)
		draw_menu(ctx, state)
		draw_three_panel_layout(ctx, state)
	end

	imgui_guard.end_window(ctx, state, did_window, "ui_main.window.main")
	pop_style(ctx, style_count)
end

return ui_main

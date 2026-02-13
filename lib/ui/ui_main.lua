local chord_model = require("lib.chord_model")
local harmony_engine = require("lib.harmony_engine")
local midi_writer = require("lib.midi_writer")
local ui_circle = require("lib.ui.ui_circle_of_fifths")
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
		reaper.ImGui_BeginChild(ctx, "##suggest_actions", left_w, panel_h, 1)
		for _, item in ipairs(actions) do
			if reaper.ImGui_Button(ctx, item.label, button_w, 0) then
				item.run()
			end
		end
		reaper.ImGui_EndChild(ctx)

		reaper.ImGui_SameLine(ctx, nil, gap)

		reaper.ImGui_BeginChild(ctx, "##suggest_results", right_w, panel_h, 1)
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
					for k, v in pairs(suggestion) do
						chord[k] = v
					end
					state.dirty = true
					midi_writer.preview_click(chord)
				end
			end
		end
		reaper.ImGui_EndChild(ctx)
	end
end

local function draw_menu(ctx, state)
	if not reaper.ImGui_BeginMenuBar or not reaper.ImGui_BeginMenuBar(ctx) then
		return
	end

	if reaper.ImGui_MenuItem(ctx, "Save Library") then
		state.save_requested = true
	end

	if reaper.ImGui_MenuItem(ctx, "Quit") then
		state.ui_open = false
	end

	reaper.ImGui_EndMenuBar(ctx)
end

local function draw_left_key_controls(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		return
	end

	reaper.ImGui_Text(ctx, "Key")
	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_BeginCombo(ctx, "##left_key_root", chord_model.note_name(prog.key_root or 0)) then
		for pc = 0, 11 do
			if reaper.ImGui_Selectable(ctx, chord_model.note_name(pc), pc == (prog.key_root or 0)) then
				prog.key_root = pc
				state.dirty = true
			end
		end
		reaper.ImGui_EndCombo(ctx)
	end

	reaper.ImGui_SameLine(ctx)
	if reaper.ImGui_BeginCombo(ctx, "##left_key_mode", prog.mode or "major") then
		for _, mode in ipairs(chord_model.MODES) do
			if reaper.ImGui_Selectable(ctx, mode, mode == (prog.mode or "major")) then
				prog.mode = mode
				state.dirty = true
			end
		end
		reaper.ImGui_EndCombo(ctx)
	end
end

local function draw_left_panel(ctx, state)
	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local gap_h = 1
	local controls_h = 120
	local lib_h = math.max(1, avail_h - controls_h - gap_h)

	reaper.ImGui_BeginChild(ctx, "##left_library_area", -1, lib_h, 0)
	ui_library.draw(ctx, state)
	reaper.ImGui_EndChild(ctx)

	reaper.ImGui_Dummy(ctx, 0, gap_h)

	local settings_flags = 0
	if reaper.ImGui_WindowFlags_NoScrollbar then
		settings_flags = settings_flags | reaper.ImGui_WindowFlags_NoScrollbar()
	end
	if reaper.ImGui_WindowFlags_NoScrollWithMouse then
		settings_flags = settings_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
	end

	reaper.ImGui_BeginChild(ctx, "##left_settings_area", -1, -1, 1, settings_flags)
	draw_left_key_controls(ctx, state)
	reaper.ImGui_Separator(ctx)
	reaper.ImGui_Text(ctx, "View / Reharm")

	local changed_show
	changed_show, state.show_roman = reaper.ImGui_Checkbox(ctx, "Roman Numerals", state.show_roman)
	if changed_show then
		state.dirty = true
	end

	local modes = {
		"diatonic_rotate",
		"function_preserving",
		"chromatic_approach",
		"modal_interchange",
	}

	if reaper.ImGui_BeginCombo(ctx, "Reharm Mode", state.reharm_mode or modes[1]) then
		for _, mode in ipairs(modes) do
			if reaper.ImGui_Selectable(ctx, mode, mode == state.reharm_mode) then
				state.reharm_mode = mode
			end
		end
		reaper.ImGui_EndCombo(ctx)
	end
	reaper.ImGui_EndChild(ctx)
end

local function draw_center_panel(ctx, state)
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

	reaper.ImGui_BeginChild(ctx, "##center_circle_area", -1, circle_h, 1)
	ui_circle.draw(ctx, state)
	reaper.ImGui_EndChild(ctx)

	reaper.ImGui_Dummy(ctx, 0, spacing_h)

	-- Fill the remaining height exactly to avoid scrollbar oscillation.
	local prog_flags = 0
	if reaper.ImGui_WindowFlags_NoScrollbar then
		prog_flags = prog_flags | reaper.ImGui_WindowFlags_NoScrollbar()
	end
	if reaper.ImGui_WindowFlags_NoScrollWithMouse then
		prog_flags = prog_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
	end
	reaper.ImGui_BeginChild(ctx, "##progression_bottom_left", -1, -1, 1, prog_flags)
	ui_progression_lane.draw_list(ctx, state)
	reaper.ImGui_EndChild(ctx)
end

local function draw_right_panel(ctx, state)
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
	reaper.ImGui_BeginChild(ctx, "##left", left_w, -1, 1, left_flags)
	draw_left_panel(ctx, state)
	reaper.ImGui_EndChild(ctx)

	reaper.ImGui_SameLine(ctx, nil, gap)

	reaper.ImGui_BeginChild(ctx, "##center", center_w, -1, 1)
	draw_center_panel(ctx, state)
	reaper.ImGui_EndChild(ctx)

	reaper.ImGui_SameLine(ctx, nil, gap)

	reaper.ImGui_BeginChild(ctx, "##right", right_w, -1, 1)
	draw_right_panel(ctx, state)
	reaper.ImGui_EndChild(ctx)
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

	local visible, open =
		reaper.ImGui_Begin(ctx, "Chord Progression Notebook", true, reaper.ImGui_WindowFlags_MenuBar())
	state.ui_open = open == nil and true or open

	if visible then
		draw_background(ctx, state)
		draw_menu(ctx, state)
		draw_three_panel_layout(ctx, state)
	end

	reaper.ImGui_End(ctx)
	pop_style(ctx, style_count)
end

return ui_main

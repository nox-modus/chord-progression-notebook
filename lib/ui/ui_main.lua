local chord_model = require("lib.chord_model")
local harmony_engine = require("lib.harmony_engine")
local ui_circle = require("lib.ui.ui_circle_of_fifths")
local ui_inspector = require("lib.ui.ui_inspector")
local ui_library = require("lib.ui.ui_library")
local ui_progression_lane = require("lib.ui.ui_progression_lane")

local ui_main = {}

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
	{ "ImGui_Col_Button", "bg_panel" },
	{ "ImGui_Col_ButtonHovered", "wedge_hover" },
	{ "ImGui_Col_ButtonActive", "wedge_sel" },
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

	if reaper.ImGui_Button(ctx, "Diatonic Subs") then
		state.suggestions = harmony_engine.suggest_diatonic_subs(chord, prog.key_root, prog.mode)
	end
	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_Button(ctx, "Secondary Dom") then
		state.suggestions = { harmony_engine.secondary_dominant(chord) }
	end
	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_Button(ctx, "Tritone Sub") then
		state.suggestions = { harmony_engine.tritone_sub(chord) }
	end
	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_Button(ctx, "Modal Interchange") then
		local alt = harmony_engine.modal_interchange(chord, prog.key_root)
		state.suggestions = alt and { alt } or {}
	end
	reaper.ImGui_SameLine(ctx)

	if reaper.ImGui_Button(ctx, "Dim Passing") then
		state.suggestions = { harmony_engine.diminished_passing(chord) }
	end

	if not state.suggestions then
		return
	end

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
		end
	end
end

local function draw_menu(ctx, state)
	if not reaper.ImGui_BeginMenuBar or not reaper.ImGui_BeginMenuBar(ctx) then
		return
	end

	if reaper.ImGui_MenuItem(ctx, "Toggle Roman Numerals", nil, state.show_roman) then
		state.show_roman = not state.show_roman
		state.dirty = true
	end

	if reaper.ImGui_MenuItem(ctx, "Save Library") then
		state.save_requested = true
	end

	if reaper.ImGui_MenuItem(ctx, "Quit") then
		state.ui_open = false
	end

	reaper.ImGui_EndMenuBar(ctx)
end

local function draw_left_panel(ctx, state)
	ui_library.draw(ctx, state)

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
end

local function draw_center_panel(ctx, state)
	ui_progression_lane.draw_toolbar(ctx, state)
	reaper.ImGui_Separator(ctx)

	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	avail_w = avail_w or 0
	avail_h = avail_h or 0

	local min_list_h = 90
	local min_circle_h = 140
	local spacing_h = 6
	local total_h = math.max(0, avail_h)

	-- Default target: circle : progression = 3 : 1,
	-- then clamp by width to avoid dead zone below the circle.
	local circle_h = total_h * 0.75
	circle_h = math.min(circle_h, avail_w)
	circle_h = math.max(min_circle_h, circle_h)

	-- Ensure list retains usable minimum height.
	local max_circle_from_list = math.max(0, total_h - spacing_h - min_list_h)
	if circle_h > max_circle_from_list then
		circle_h = max_circle_from_list
	end
	if circle_h < 80 then
		circle_h = math.max(0, total_h - spacing_h - min_list_h)
	end

	reaper.ImGui_BeginChild(ctx, "##center_circle_area", -1, circle_h, 1)
	ui_circle.draw(ctx, state)
	reaper.ImGui_EndChild(ctx)

	reaper.ImGui_Dummy(ctx, 0, spacing_h)

	-- Fill the remaining height exactly to avoid scrollbar oscillation.
	reaper.ImGui_BeginChild(ctx, "##progression_bottom_left", -1, -1, 1)
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
	local left_w = 260
	local right_w = 360
	local gap = 8
	local center_w = avail_w - left_w - right_w - 2 * gap
	if center_w < 200 then
		center_w = 200
	end

	reaper.ImGui_BeginChild(ctx, "##left", left_w, -1, 1)
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

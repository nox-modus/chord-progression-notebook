local chord_model = require("lib.chord_model")

local ui_circle = {}

local function pack_rgba(r, g, b, a)
	return (r << 24) | (g << 16) | (b << 8) | a
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function alpha_mul(col, mul)
	local r = (col >> 24) & 0xFF
	local g = (col >> 16) & 0xFF
	local b = (col >> 8) & 0xFF
	local a = col & 0xFF
	local na = math.floor(a * mul)
	if na < 0 then
		na = 0
	end
	if na > 255 then
		na = 255
	end
	return pack_rgba(r, g, b, na)
end

local PALETTE = {
	ring_key = pack_rgba(58, 66, 78, 200),
	ring_key_alt = pack_rgba(52, 60, 72, 200),
	ring_func = pack_rgba(46, 54, 66, 210),
	ring_inner = pack_rgba(30, 33, 38, 255),
	border = pack_rgba(120, 135, 150, 80),
	border_str = pack_rgba(150, 165, 180, 110),
	select = pack_rgba(96, 126, 168, 200),
	select_soft = pack_rgba(78, 104, 140, 170),
	text_major = pack_rgba(220, 226, 232, 255),
	text_minor = pack_rgba(200, 206, 214, 255),
	text_roman = pack_rgba(190, 198, 206, 220),
	text_func = pack_rgba(220, 226, 232, 235),
	text_dim = pack_rgba(196, 204, 214, 255),
	dim_accent = pack_rgba(188, 196, 206, 245),
	glow = pack_rgba(120, 150, 190, 90),
	fun_t = pack_rgba(88, 118, 160, 110),
	fun_s = pack_rgba(86, 130, 122, 110),
	fun_d = pack_rgba(104, 118, 170, 110),
	fun_band_t = pack_rgba(88, 118, 160, 190),
	fun_band_s = pack_rgba(86, 130, 122, 170),
	fun_band_d = pack_rgba(104, 118, 170, 170),
	band_border = pack_rgba(150, 170, 190, 160),
	arrow = pack_rgba(150, 170, 200, 110),
}

local CIRCLE_PC_BY_SECTOR = { 0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5 }

local SECTOR_COUNT = 12
local SECTOR_ANGLE = (2 * math.pi) / SECTOR_COUNT
local START_ANGLE = -math.pi / 2 - (SECTOR_ANGLE * 0.5)
local CURRENT_START_ANGLE = START_ANGLE

local PC_TO_SECTOR = {}
for sector = 1, #CIRCLE_PC_BY_SECTOR do
	PC_TO_SECTOR[CIRCLE_PC_BY_SECTOR[sector]] = sector
end

local function rotated_start_angle(selected_key_pc)
	local selected_sector = PC_TO_SECTOR[selected_key_pc or 0] or 1
	return START_ANGLE - ((selected_sector - 1) * SECTOR_ANGLE)
end

local function minor_name(pc)
	return chord_model.note_name(pc) .. "m"
end

local function dim_name(pc)
	return chord_model.note_name(pc) .. "dim"
end

local function family_for_degree(degree, mode)
	if mode == "minor" then
		if degree == 1 or degree == 3 or degree == 6 then
			return "T"
		end
		if degree == 2 or degree == 4 then
			return "S"
		end
		if degree == 5 or degree == 7 then
			return "D"
		end
	else
		if degree == 1 or degree == 3 or degree == 6 then
			return "T"
		end
		if degree == 2 or degree == 4 then
			return "S"
		end
		if degree == 5 or degree == 7 then
			return "D"
		end
	end
	return "T"
end

local function wrap_pi(a)
	while a <= -math.pi do
		a = a + 2 * math.pi
	end
	while a > math.pi do
		a = a - 2 * math.pi
	end
	return a
end

local function sector_a0(index)
	return CURRENT_START_ANGLE + (index - 1) * SECTOR_ANGLE
end

local function sector_a1(index)
	return sector_a0(index) + SECTOR_ANGLE
end

local function sector_ac(index)
	return sector_a0(index) + (SECTOR_ANGLE * 0.5)
end

local function xy_on_circle(cx, cy, radius, angle)
	return cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
end

local function safe_text_size(ctx, text)
	local ok, w, h = pcall(reaper.ImGui_CalcTextSize, ctx, text)
	if ok then
		return w or 0, h or 0
	end

	ok, w, h = pcall(reaper.ImGui_CalcTextSize, text)
	if ok then
		return w or 0, h or 0
	end

	return 0, 0
end

local function draw_text_center(ctx, draw_list, text, x, y, col)
	local tw, th = safe_text_size(ctx, text)
	reaper.ImGui_DrawList_AddText(draw_list, x - tw * 0.5, y - th * 0.5, col, text)
end

local function draw_text_center_scaled(ctx, draw_list, text, x, y, col, scale)
	if reaper.ImGui_SetWindowFontScale then
		reaper.ImGui_SetWindowFontScale(ctx, scale)
		draw_text_center(ctx, draw_list, text, x, y, col)
		reaper.ImGui_SetWindowFontScale(ctx, 1.0)
	else
		draw_text_center(ctx, draw_list, text, x, y, col)
	end
end

local function draw_ring_slice(draw_list, cx, cy, r_outer, r_inner, a0, a1, col, arc_steps)
	reaper.ImGui_DrawList_PathClear(draw_list)
	reaper.ImGui_DrawList_PathArcTo(draw_list, cx, cy, r_outer, a0, a1, arc_steps)
	reaper.ImGui_DrawList_PathArcTo(draw_list, cx, cy, r_inner, a1, a0, arc_steps)
	reaper.ImGui_DrawList_PathFillConvex(draw_list, col)
end

local function draw_arc_outline(draw_list, cx, cy, radius, a0, a1, col, thickness)
	local steps = 24
	local px, py
	for i = 0, steps do
		local angle = lerp(a0, a1, i / steps)
		local x, y = xy_on_circle(cx, cy, radius, angle)
		if px then
			reaper.ImGui_DrawList_AddLine(draw_list, px, py, x, y, col, thickness)
		end
		px, py = x, y
	end
end

local function draw_arc_band(draw_list, cx, cy, r_inner, r_outer, a0, a1, col)
	local slices = 24
	for i = 1, slices do
		local t0 = (i - 1) / slices
		local t1 = i / slices
		local sa0 = lerp(a0, a1, t0)
		local sa1 = lerp(a0, a1, t1)
		draw_ring_slice(draw_list, cx, cy, r_outer, r_inner, sa0, sa1, col, 8)
	end
end

local function draw_arc_arrow(draw_list, cx, cy, radius, a0, a1, col)
	local steps = 18
	local px, py
	for i = 0, steps do
		local angle = lerp(a0, a1, i / steps)
		local x, y = xy_on_circle(cx, cy, radius, angle)
		if px then
			reaper.ImGui_DrawList_AddLine(draw_list, px, py, x, y, col, 1.0)
		end
		px, py = x, y
	end

	local tip_x, tip_y = xy_on_circle(cx, cy, radius, a1)
	local left_x, left_y = xy_on_circle(cx, cy, radius - 6, a1 - 0.18)
	local right_x, right_y = xy_on_circle(cx, cy, radius - 6, a1 + 0.18)
	reaper.ImGui_DrawList_AddLine(draw_list, left_x, left_y, tip_x, tip_y, col, 1.0)
	reaper.ImGui_DrawList_AddLine(draw_list, right_x, right_y, tip_x, tip_y, col, 1.0)
end

local function build_radii(size)
	local base = size * 0.48
	local major_outer = base
	local major_inner = base * 0.86
	local minor_outer = major_inner
	local minor_thickness = (major_inner - (base * 0.72)) * 1.20
	local minor_inner = minor_outer - minor_thickness
	local diatonic_outer = minor_inner - 2
	local roman_thickness_current = ((base * 0.72) - 2) - (base * 0.50)
	local diatonic_inner = diatonic_outer - (roman_thickness_current * 0.80)
	local func_outer_offset = 14 * 2.0736
	local func_inner_offset = 6 * 2.0736

	return {
		major_outer = major_outer,
		major_inner = major_inner,
		minor_outer = minor_outer,
		minor_inner = minor_inner,
		key_outer = major_outer,
		key_inner = minor_inner,
		diatonic_outer = diatonic_outer,
		diatonic_inner = diatonic_inner,
		func_band_outer = major_outer + func_outer_offset,
		func_band_inner = major_outer + func_inner_offset,
		text_key_major = (major_outer + major_inner) * 0.5,
		text_key_minor = (minor_outer + minor_inner) * 0.5,
		text_roman = (diatonic_outer + diatonic_inner) * 0.5,
		center_inner = base * 0.28,
		vii_pill = diatonic_inner - 18,
	}
end

local function build_degree_map(key_root)
	local k = key_root or 0
	local degree_pc = {
		[1] = (k + 0) % 12,
		[2] = (k + 2) % 12,
		[3] = (k + 4) % 12,
		[4] = (k + 5) % 12,
		[5] = (k + 7) % 12,
		[6] = (k + 9) % 12,
		[7] = (k + 11) % 12,
	}

	local degree_sector = {}
	for degree = 1, 7 do
		degree_sector[degree] = PC_TO_SECTOR[degree_pc[degree]]
	end

	return degree_pc, degree_sector
end

local function degree_for_pc(pc, key_root, mode)
	local scale = chord_model.get_scale_degrees(mode or "major")
	local rel = chord_model.wrap12((pc or 0) - (key_root or 0))
	for degree = 1, 7 do
		if chord_model.wrap12(scale[degree]) == rel then
			return degree
		end
	end
	return nil
end

local function make_set(indices)
	local set = {}
	for _, index in ipairs(indices) do
		set[index] = true
	end
	return set
end

local function hit_test_sector(mouse_x, mouse_y, cx, cy, r_inner, r_outer)
	local dx = mouse_x - cx
	local dy = mouse_y - cy
	local r = math.sqrt(dx * dx + dy * dy)

	if r < r_inner or r > r_outer then
		return nil
	end

	local angle = math.atan(dy, dx)
	local offset = (angle - CURRENT_START_ANGLE + (2 * math.pi)) % (2 * math.pi)
	return math.floor(offset / SECTOR_ANGLE) + 1
end

local function relative_bounds(indices, tonic_angle)
	local min_rel, max_rel
	for _, index in ipairs(indices) do
		local rel = wrap_pi(sector_ac(index) - tonic_angle)
		if not min_rel or rel < min_rel then
			min_rel = rel
		end
		if not max_rel or rel > max_rel then
			max_rel = rel
		end
	end

	local half = SECTOR_ANGLE * 0.5
	return tonic_angle + min_rel - half, tonic_angle + max_rel + half
end

local function average_relative_angle(indices, tonic_angle)
	local sum = 0
	for _, index in ipairs(indices) do
		sum = sum + wrap_pi(sector_ac(index) - tonic_angle)
	end
	return tonic_angle + (sum / #indices)
end

local function draw_outer_ring(draw_list, prog, hovered_index, primary_set, secondary_set, radii, center_x, center_y)
	for index = 1, 12 do
		local pc = CIRCLE_PC_BY_SECTOR[index]
		local a0 = sector_a0(index)
		local a1 = sector_a1(index)

		local fill = (index % 2 == 0) and PALETTE.ring_key or PALETTE.ring_key_alt
		if hovered_index == index then
			fill = PALETTE.select_soft
		end

		if (prog.key_root or 0) == pc then
			fill = PALETTE.select
		elseif not primary_set[index] and not secondary_set[index] then
			fill = alpha_mul(fill, 0.55)
		end

		local minor_fill = alpha_mul(fill, 0.95)
		draw_ring_slice(draw_list, center_x, center_y, radii.major_outer, radii.major_inner, a0, a1, fill, 20)
		draw_ring_slice(draw_list, center_x, center_y, radii.minor_outer, radii.minor_inner, a0, a1, minor_fill, 20)
	end

	reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radii.major_outer, PALETTE.border_str, 48, 2.0)
	reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radii.major_inner, PALETTE.border, 48, 1.0)
	reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radii.minor_inner, PALETTE.border, 48, 1.0)
end

local function draw_diatonic_base(draw_list, primary_set, secondary_set, radii, center_x, center_y)
	for index = 1, 12 do
		local a0 = sector_a0(index)
		local a1 = sector_a1(index)
		local col = PALETTE.ring_func

		if primary_set[index] then
			col = alpha_mul(col, 1.0)
		elseif secondary_set[index] then
			col = alpha_mul(col, 0.25)
		else
			col = alpha_mul(col, 0.10)
		end

		draw_ring_slice(draw_list, center_x, center_y, radii.diatonic_outer, radii.diatonic_inner, a0, a1, col, 10)

		if primary_set[index] or secondary_set[index] then
			local border = alpha_mul(PALETTE.border_str, primary_set[index] and 0.9 or 0.45)
			draw_arc_outline(draw_list, center_x, center_y, radii.diatonic_outer, a0, a1, border, 1.4)
			draw_arc_outline(draw_list, center_x, center_y, radii.diatonic_inner, a0, a1, border, 1.2)
		end
	end
end

local function draw_function_bands(draw_list, tonic_angle, t_indices, s_indices, d_indices, radii, center_x, center_y)
	local s0, s1 = relative_bounds(s_indices, tonic_angle)
	local t0, t1 = relative_bounds(t_indices, tonic_angle)
	local d0, d1 = relative_bounds(d_indices, tonic_angle)

	draw_arc_band(
		draw_list,
		center_x,
		center_y,
		radii.func_band_inner,
		radii.func_band_outer,
		s0,
		s1,
		PALETTE.fun_band_s
	)
	draw_arc_band(
		draw_list,
		center_x,
		center_y,
		radii.func_band_inner,
		radii.func_band_outer,
		t0,
		t1,
		PALETTE.fun_band_t
	)
	draw_arc_band(
		draw_list,
		center_x,
		center_y,
		radii.func_band_inner,
		radii.func_band_outer,
		d0,
		d1,
		PALETTE.fun_band_d
	)

	reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radii.func_band_outer, PALETTE.band_border, 48, 1.0)
end

local function draw_function_tints(
	draw_list,
	mode,
	degree_sector,
	primary_set,
	secondary_set,
	radii,
	center_x,
	center_y
)
	for degree = 1, 7 do
		local family = family_for_degree(degree, mode)
		local col = PALETTE.fun_t
		if family == "S" then
			col = PALETTE.fun_s
		end
		if family == "D" then
			col = PALETTE.fun_d
		end

		local sector = degree_sector[degree]
		if primary_set[sector] then
			col = alpha_mul(col, 0.9)
		elseif secondary_set[sector] then
			col = alpha_mul(col, 0.25)
		else
			col = alpha_mul(col, 0.10)
		end

		draw_ring_slice(
			draw_list,
			center_x,
			center_y,
			radii.diatonic_outer,
			radii.diatonic_inner,
			sector_a0(sector),
			sector_a1(sector),
			col,
			10
		)
	end
end

local function draw_key_labels(ctx, draw_list, prog, radii, center_x, center_y)
	for sector = 1, 12 do
		local pc = CIRCLE_PC_BY_SECTOR[sector]
		local angle = sector_ac(sector)

		local x_major, y_major = xy_on_circle(center_x, center_y, radii.text_key_major, angle)
		local x_minor, y_minor = xy_on_circle(center_x, center_y, radii.text_key_minor, angle)

		local major = chord_model.note_name(pc)
		local minor = minor_name(chord_model.wrap12(pc + 9))

		local major_col = ((prog.key_root or 0) == pc) and PALETTE.text_major or alpha_mul(PALETTE.text_major, 0.92)
		local minor_col = ((prog.key_root or 0) == pc) and PALETTE.text_major or alpha_mul(PALETTE.text_minor, 0.90)

		draw_text_center(ctx, draw_list, major, x_major, y_major, major_col)
		draw_text_center(ctx, draw_list, minor, x_minor, y_minor, minor_col)
	end
end

local function draw_function_labels(ctx, draw_list, idx_i, idx_iv, idx_v, radii, center_x, center_y)
	local angle_i = sector_ac(idx_i)
	local angle_iv = sector_ac(idx_iv)
	local angle_v = sector_ac(idx_v)

	-- Direct didactic alignment: S -> IV, T -> I, D -> V.
	local s_angle = angle_iv
	local t_angle = angle_i
	local d_angle = angle_v
	local radius = (radii.func_band_inner + radii.func_band_outer) * 0.5

	local tx, ty = xy_on_circle(center_x, center_y, radius, t_angle)
	draw_text_center(ctx, draw_list, "T", tx, ty, PALETTE.text_func)

	local sx, sy = xy_on_circle(center_x, center_y, radius, s_angle)
	draw_text_center(ctx, draw_list, "S", sx, sy, PALETTE.text_func)

	local dx, dy = xy_on_circle(center_x, center_y, radius, d_angle)
	draw_text_center(ctx, draw_list, "D", dx, dy, PALETTE.text_func)
end

local function draw_roman_labels(ctx, draw_list, degree_sector, primary_set, secondary_set, radii, center_x, center_y)
	local degree_items = {
		{ degree = 1, text = "I" },
		{ degree = 2, text = "ii" },
		{ degree = 3, text = "iii" },
		{ degree = 4, text = "IV" },
		{ degree = 5, text = "V" },
		{ degree = 6, text = "vi" },
		{ degree = 7, text = "vii°" },
	}

	for _, item in ipairs(degree_items) do
		local sector = degree_sector[item.degree]
		local angle = sector_ac(sector)
		local x, y = xy_on_circle(center_x, center_y, radii.text_roman, angle)

		local col = item.text:find("°") and PALETTE.text_dim or PALETTE.text_roman
		if primary_set[sector] then
			col = alpha_mul(col, 0.90)
		elseif secondary_set[sector] then
			col = alpha_mul(col, 0.72)
		else
			col = alpha_mul(col, 0.50)
		end

		draw_text_center_scaled(ctx, draw_list, item.text, x, y, col, 0.75)
	end
end

local function draw_vii_pill(ctx, draw_list, degree_pc, degree_sector, size, radii, center_x, center_y)
	local sector = degree_sector[7]
	local angle = sector_ac(sector)
	local x, y = xy_on_circle(center_x, center_y, radii.vii_pill, angle)

	local label = "vii° " .. dim_name(degree_pc[7])
	local bg_col = alpha_mul(PALETTE.ring_inner, 0.42)
	local text_col = alpha_mul(PALETTE.dim_accent, 0.95)

	reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, size * 0.030, bg_col, 24)
	draw_text_center_scaled(ctx, draw_list, label, x, y, text_col, 0.70)
end

function ui_circle.draw(ctx, state)
	local prog = state.library.progressions[state.selected_progression]
	if not prog then
		return
	end
	CURRENT_START_ANGLE = rotated_start_angle(prog.key_root or 0)

	if not reaper.ImGui_DrawList_PathArcTo then
		reaper.ImGui_Text(ctx, "Circle widget requires ImGui draw list path API.")
		return
	end

	local draw_list = reaper.ImGui_GetWindowDrawList(ctx)

	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	if avail_w == nil and type(avail_h) == "number" then
		avail_w = avail_h
	end
	if avail_h == nil and type(avail_w) == "number" then
		avail_h = avail_w
	end

	local max_dim = math.min(avail_w or 200, (avail_h or 200) * 0.9)
	local size = math.max(220, max_dim)
	local radii = build_radii(size)
	local draw_size = (radii.func_band_outer + 2) * 2

	-- Keep the enlarged functional ring fully inside the widget box to avoid
	-- overlap with neighbouring UI elements.
	if draw_size > max_dim and max_dim > 120 then
		local scale = max_dim / draw_size
		size = math.max(120, size * scale)
		radii = build_radii(size)
		draw_size = (radii.func_band_outer + 2) * 2
	end

	local cursor_x, cursor_y = reaper.ImGui_GetCursorScreenPos(ctx)
	cursor_x = cursor_x or 0
	cursor_y = cursor_y or 0

	local offset_x = math.max(0, ((avail_w or draw_size) - draw_size) * 0.5)
	-- Anchor to top edge so the circle visually connects to the frame on resize.
	local offset_y = 0
	local draw_x = cursor_x + offset_x
	local draw_y = cursor_y + offset_y

	if reaper.ImGui_SetCursorScreenPos then
		reaper.ImGui_SetCursorScreenPos(ctx, draw_x, draw_y)
	end

	local center_x = draw_x + draw_size * 0.5
	local center_y = draw_y + draw_size * 0.5

	reaper.ImGui_InvisibleButton(ctx, "circle", draw_size, draw_size)

	local hovered_index = nil
	if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_GetMousePos then
		local mx, my = reaper.ImGui_GetMousePos(ctx)
		mx = mx or 0
		my = my or 0

		hovered_index = hit_test_sector(mx, my, center_x, center_y, radii.key_inner, radii.key_outer)
		if hovered_index then
			local clicked_pc = CIRCLE_PC_BY_SECTOR[hovered_index]

			-- Right click: select key/root for the progression.
			if reaper.ImGui_IsMouseClicked(ctx, 1) then
				prog.key_root = clicked_pc
				state.dirty = true
			end

			-- Left click: assign chord on current progression slot and expose it in inspector.
			if reaper.ImGui_IsMouseClicked(ctx, 0) then
				prog.chords = prog.chords or {}
				if #prog.chords == 0 then
					prog.chords[1] = { root = clicked_pc, quality = "major", duration = 1 }
					state.selected_chord = 1
				end

				local idx = state.selected_chord or 1
				if idx < 1 then
					idx = 1
				end
				if idx > #prog.chords then
					idx = #prog.chords
				end

				local chord = prog.chords[idx]
				chord.root = clicked_pc
				local degree = degree_for_pc(clicked_pc, prog.key_root or 0, prog.mode or "major")
				if degree then
					chord.quality = chord_model.diatonic_chord_quality(degree, prog.mode or "major")
				end

				state.selected_chord = idx
				state.dirty = true
			end
		end
	end

	local degree_pc, degree_sector = build_degree_map(prog.key_root or 0)

	local idx_i = degree_sector[1]
	local idx_ii = degree_sector[2]
	local idx_iii = degree_sector[3]
	local idx_iv = degree_sector[4]
	local idx_v = degree_sector[5]
	local idx_vi = degree_sector[6]
	local idx_vii = degree_sector[7]

	local primary_set = make_set({ idx_iv, idx_i, idx_v })
	local secondary_set = make_set({ idx_ii, idx_vi, idx_iii })

	local tonic_angle = sector_ac(idx_i)
	local arc_span = 3 * SECTOR_ANGLE
	local arc_start = tonic_angle - (arc_span * 0.5)
	local arc_end = tonic_angle + (arc_span * 0.5)

	draw_outer_ring(draw_list, prog, hovered_index, primary_set, secondary_set, radii, center_x, center_y)

	draw_diatonic_base(draw_list, primary_set, secondary_set, radii, center_x, center_y)
	draw_arc_outline(
		draw_list,
		center_x,
		center_y,
		radii.diatonic_outer,
		arc_start,
		arc_end,
		alpha_mul(PALETTE.border_str, 0.95),
		1.5
	)
	draw_arc_outline(
		draw_list,
		center_x,
		center_y,
		radii.diatonic_inner,
		arc_start,
		arc_end,
		alpha_mul(PALETTE.border_str, 0.95),
		1.3
	)

	local t_indices = { idx_i }
	local s_indices = { idx_ii, idx_iv }
	local d_indices = { idx_v, idx_vii }

	draw_function_bands(draw_list, tonic_angle, t_indices, s_indices, d_indices, radii, center_x, center_y)
	draw_function_tints(
		draw_list,
		prog.mode or "major",
		degree_sector,
		primary_set,
		secondary_set,
		radii,
		center_x,
		center_y
	)

	reaper.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radii.center_inner, PALETTE.ring_inner, 48)
	reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radii.center_inner, PALETTE.border, 48, 1.0)
	reaper.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radii.key_outer + 1, PALETTE.glow, 48, 2.0)

	draw_key_labels(ctx, draw_list, prog, radii, center_x, center_y)
	draw_function_labels(ctx, draw_list, idx_i, idx_iv, idx_v, radii, center_x, center_y)
	draw_roman_labels(ctx, draw_list, degree_sector, primary_set, secondary_set, radii, center_x, center_y)
	draw_vii_pill(ctx, draw_list, degree_pc, degree_sector, size, radii, center_x, center_y)

	local key_label = chord_model.note_name(prog.key_root or 0) .. " " .. (prog.mode or "major")
	draw_text_center(ctx, draw_list, key_label, center_x, center_y, PALETTE.text_major)
end

return ui_circle

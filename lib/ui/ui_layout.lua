local ui_theme = require("lib.ui.ui_theme")

local ui_layout = {}

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function begin_child(ctx, label, w, h)
	if not reaper.ImGui_BeginChild then
		return true, false
	end
	local ok, res = pcall(reaper.ImGui_BeginChild, ctx, label, w, h)
	if ok then
		return res, true
	end
	ok, res = pcall(reaper.ImGui_BeginChild, label, w, h)
	if ok then
		return res, true
	end
	return true, false
end

local function end_child(ctx, opened)
	if not opened then
		return
	end
	if reaper.ImGui_EndChild then
		pcall(reaper.ImGui_EndChild, ctx)
		pcall(reaper.ImGui_EndChild)
	end
end

function ui_layout.draw(ctx, state, draw_left, draw_center, draw_right)
	local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
	local left_w = clamp(avail_w * 0.22, ui_theme.sizes.rail_min, ui_theme.sizes.rail_max)
	local right_w = clamp(avail_w * 0.26, ui_theme.sizes.inspector_min, ui_theme.sizes.inspector_max)
	local center_w = math.max(100, avail_w - left_w - right_w - ui_theme.spacing.inner * 2)
	local function flag(fn)
		return (reaper[fn] and reaper[fn]()) or 0
	end

	if reaper.ImGui_BeginTable then
		if reaper.ImGui_BeginTable(ctx, "layout_table", 3, flag("ImGui_TableFlags_SizingFixedFit")) then
			reaper.ImGui_TableSetupColumn(ctx, "left", flag("ImGui_TableColumnFlags_WidthFixed"), left_w)
			reaper.ImGui_TableSetupColumn(ctx, "center", flag("ImGui_TableColumnFlags_WidthFixed"), center_w)
			reaper.ImGui_TableSetupColumn(ctx, "right", flag("ImGui_TableColumnFlags_WidthFixed"), right_w)

			reaper.ImGui_TableNextColumn(ctx)
			local open_left, did_left = begin_child(ctx, "left_rail", left_w, avail_h)
			if open_left then
				draw_left(ctx)
			end
			end_child(ctx, did_left)

			reaper.ImGui_TableNextColumn(ctx)
			local open_center, did_center = begin_child(ctx, "center_panel", center_w, avail_h)
			if open_center then
				draw_center(ctx)
			end
			end_child(ctx, did_center)

			reaper.ImGui_TableNextColumn(ctx)
			local open_right, did_right = begin_child(ctx, "right_panel", right_w, avail_h)
			if open_right then
				draw_right(ctx)
			end
			end_child(ctx, did_right)

			reaper.ImGui_EndTable(ctx)
		end
	else
		local open_left, did_left = begin_child(ctx, "left_rail", avail_w, 0)
		if open_left then
			draw_left(ctx)
		end
		end_child(ctx, did_left)
		local open_center, did_center = begin_child(ctx, "center_panel", avail_w, 0)
		if open_center then
			draw_center(ctx)
		end
		end_child(ctx, did_center)
		local open_right, did_right = begin_child(ctx, "right_panel", avail_w, 0)
		if open_right then
			draw_right(ctx)
		end
		end_child(ctx, did_right)
	end
end

return ui_layout

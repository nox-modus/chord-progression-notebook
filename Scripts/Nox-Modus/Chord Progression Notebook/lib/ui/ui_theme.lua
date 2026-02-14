local ui_theme = {}

ui_theme.spacing = {
	outer = 12,
	inner = 8,
	item = 6,
}

ui_theme.sizes = {
	rail_min = 220,
	rail_max = 300,
	inspector_min = 260,
	inspector_max = 360,
}

ui_theme.colors = {
	bg = 0xFF14161A,
	panel = 0xFF1B1F24,
	panel_alt = 0xFF20252B,
	border = 0xFF2B323A,
	text = 0xFFE6E6E6,
	text_dim = 0xFFB0B6BE,
	accent = 0xFF4DD2FF,
	accent_soft = 0x6638B9FF,
	select = 0xFF5BB0FF,
	warn = 0xFFFFB86B,
	good = 0xFF6BD69B,
}

function ui_theme.PushTheme(ctx)
	if not reaper.ImGui_PushStyleVar then
		return
	end
	ui_theme._pushed_vars = 0
	ui_theme._pushed_cols = 0
	local function push_style_var(var, a, b)
		if b ~= nil then
			local ok = pcall(reaper.ImGui_PushStyleVar, ctx, var, a, b)
			if not ok then
				ok = pcall(reaper.ImGui_PushStyleVar, var, a, b)
			end
			if ok then
				ui_theme._pushed_vars = ui_theme._pushed_vars + 1
			end
		else
			local ok = pcall(reaper.ImGui_PushStyleVar, ctx, var, a)
			if not ok then
				ok = pcall(reaper.ImGui_PushStyleVar, var, a)
			end
			if ok then
				ui_theme._pushed_vars = ui_theme._pushed_vars + 1
			end
		end
	end

	push_style_var(reaper.ImGui_StyleVar_WindowPadding(), ui_theme.spacing.outer, ui_theme.spacing.outer)
	push_style_var(reaper.ImGui_StyleVar_ItemSpacing(), ui_theme.spacing.item, ui_theme.spacing.item)
	push_style_var(reaper.ImGui_StyleVar_FramePadding(), 8, 6)
	push_style_var(reaper.ImGui_StyleVar_ChildRounding(), 6)
	push_style_var(reaper.ImGui_StyleVar_FrameRounding(), 5)

	if reaper.ImGui_PushStyleColor then
		local function push_style_color(col, val)
			local ok = pcall(reaper.ImGui_PushStyleColor, ctx, col, val)
			if not ok then
				ok = pcall(reaper.ImGui_PushStyleColor, col, val)
			end
			if ok then
				ui_theme._pushed_cols = ui_theme._pushed_cols + 1
			end
		end

		push_style_color(reaper.ImGui_Col_WindowBg(), ui_theme.colors.bg)
		push_style_color(reaper.ImGui_Col_ChildBg(), ui_theme.colors.panel)
		push_style_color(reaper.ImGui_Col_Border(), ui_theme.colors.border)
		push_style_color(reaper.ImGui_Col_Text(), ui_theme.colors.text)
		push_style_color(reaper.ImGui_Col_TextDisabled(), ui_theme.colors.text_dim)
		push_style_color(reaper.ImGui_Col_Header(), ui_theme.colors.panel_alt)
		push_style_color(reaper.ImGui_Col_HeaderHovered(), ui_theme.colors.accent_soft)
		push_style_color(reaper.ImGui_Col_HeaderActive(), ui_theme.colors.accent)
		push_style_color(reaper.ImGui_Col_FrameBg(), ui_theme.colors.panel_alt)
		push_style_color(reaper.ImGui_Col_FrameBgHovered(), ui_theme.colors.panel_alt + 0x00040404)
		push_style_color(reaper.ImGui_Col_FrameBgActive(), ui_theme.colors.panel_alt + 0x00080808)
		push_style_color(reaper.ImGui_Col_Button(), ui_theme.colors.panel_alt)
		push_style_color(reaper.ImGui_Col_ButtonHovered(), ui_theme.colors.accent_soft)
		push_style_color(reaper.ImGui_Col_ButtonActive(), ui_theme.colors.accent)
		push_style_color(reaper.ImGui_Col_Separator(), ui_theme.colors.border)
		push_style_color(reaper.ImGui_Col_SeparatorHovered(), ui_theme.colors.accent_soft)
		push_style_color(reaper.ImGui_Col_SeparatorActive(), ui_theme.colors.accent)
	end
end

function ui_theme.PopTheme(ctx)
	if reaper.ImGui_PopStyleColor then
		local n = ui_theme._pushed_cols or 0
		if n > 0 then
			local ok = pcall(reaper.ImGui_PopStyleColor, ctx, n)
			if not ok then
				pcall(reaper.ImGui_PopStyleColor, n)
			end
		end
	end
	if reaper.ImGui_PopStyleVar then
		local n = ui_theme._pushed_vars or 0
		if n > 0 then
			local ok = pcall(reaper.ImGui_PopStyleVar, ctx, n)
			if not ok then
				pcall(reaper.ImGui_PopStyleVar, n)
			end
		end
	end
end

return ui_theme

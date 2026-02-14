local ui_sections = {}

function ui_sections.BeginSection(ctx, title, default_open)
	if reaper.ImGui_CollapsingHeader then
		local flags = 0
		if default_open and reaper.ImGui_TreeNodeFlags_DefaultOpen then
			flags = reaper.ImGui_TreeNodeFlags_DefaultOpen()
		end
		return reaper.ImGui_CollapsingHeader(ctx, title, flags)
	end

	reaper.ImGui_Text(ctx, title)
	reaper.ImGui_Separator(ctx)
	return true
end

function ui_sections.EndSection(ctx) end

return ui_sections

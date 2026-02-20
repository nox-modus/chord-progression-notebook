local reaper_api = require("lib.reaper_api")

local imgui_guard = {}

local function ensure_guard_state(state)
	if type(state) ~= "table" then
		return nil, nil
	end
	if type(state._imgui_guard_seen) ~= "table" then
		state._imgui_guard_seen = {}
	end
	if type(state._imgui_guard_counts) ~= "table" then
		state._imgui_guard_counts = {}
	end
	return state._imgui_guard_seen, state._imgui_guard_counts
end

local function report_failure(state, kind, callsite, detail)
	local key = tostring(callsite or kind or "unknown")
	local seen, counts = ensure_guard_state(state)
	if counts then
		counts[key] = (counts[key] or 0) + 1
	end
	if seen and seen[key] then
		return
	end
	if seen then
		seen[key] = true
	end

	local message = string.format(
		"ImGui guard: %s failed at %s.\nDetails: %s",
		tostring(kind or "begin"),
		key,
		tostring(detail or "n/a")
	)
	reaper_api.msg(message)
end

function imgui_guard.begin_window(ctx, state, label, p_open, flags, callsite)
	if type(reaper.ImGui_Begin) ~= "function" then
		report_failure(state, "ImGui_Begin", callsite, "API unavailable")
		return false, false, p_open
	end

	local ok, visible, open = pcall(reaper.ImGui_Begin, ctx, label, p_open, flags)
	if not ok then
		report_failure(state, "ImGui_Begin", callsite, visible)
		return false, false, p_open
	end
	if type(visible) ~= "boolean" then
		report_failure(state, "ImGui_Begin", callsite, "Unexpected visible return type: " .. type(visible))
		return false, false, p_open
	end
	return visible == true, visible, open
end

function imgui_guard.end_window(ctx, state, did_begin, callsite)
	if not did_begin then
		return
	end
	local ok, err = pcall(reaper.ImGui_End, ctx)
	if not ok then
		report_failure(state, "ImGui_End", callsite, err)
	end
end

function imgui_guard.begin_child(ctx, state, id, w, h, border, flags, callsite)
	if type(reaper.ImGui_BeginChild) ~= "function" then
		report_failure(state, "ImGui_BeginChild", callsite, "API unavailable")
		return false
	end

	local ok, visible = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border, flags)
	if not ok then
		report_failure(state, "ImGui_BeginChild", callsite, visible)
		return false
	end
	if type(visible) ~= "boolean" then
		report_failure(state, "ImGui_BeginChild", callsite, "Unexpected visible return type: " .. type(visible))
		return false
	end
	return visible == true
end

function imgui_guard.end_child(ctx, state, did_begin, callsite)
	if not did_begin then
		return
	end
	local ok, err = pcall(reaper.ImGui_EndChild, ctx)
	if not ok then
		report_failure(state, "ImGui_EndChild", callsite, err)
	end
end

function imgui_guard.begin_combo(ctx, state, label, preview, callsite)
	if type(reaper.ImGui_BeginCombo) ~= "function" then
		report_failure(state, "ImGui_BeginCombo", callsite, "API unavailable")
		return false
	end

	local ok, opened = pcall(reaper.ImGui_BeginCombo, ctx, label, preview)
	if not ok then
		report_failure(state, "ImGui_BeginCombo", callsite, opened)
		return false
	end
	if type(opened) ~= "boolean" then
		report_failure(state, "ImGui_BeginCombo", callsite, "Unexpected open return type: " .. type(opened))
		return false
	end
	return opened
end

function imgui_guard.end_combo(ctx, state, did_begin, callsite)
	if not did_begin then
		return
	end
	local ok, err = pcall(reaper.ImGui_EndCombo, ctx)
	if not ok then
		report_failure(state, "ImGui_EndCombo", callsite, err)
	end
end

function imgui_guard.begin_menubar(ctx, state, callsite)
	if type(reaper.ImGui_BeginMenuBar) ~= "function" then
		report_failure(state, "ImGui_BeginMenuBar", callsite, "API unavailable")
		return false
	end

	local ok, opened = pcall(reaper.ImGui_BeginMenuBar, ctx)
	if not ok then
		report_failure(state, "ImGui_BeginMenuBar", callsite, opened)
		return false
	end
	if type(opened) ~= "boolean" then
		report_failure(state, "ImGui_BeginMenuBar", callsite, "Unexpected open return type: " .. type(opened))
		return false
	end
	return opened
end

function imgui_guard.end_menubar(ctx, state, did_begin, callsite)
	if not did_begin then
		return
	end
	local ok, err = pcall(reaper.ImGui_EndMenuBar, ctx)
	if not ok then
		report_failure(state, "ImGui_EndMenuBar", callsite, err)
	end
end

return imgui_guard

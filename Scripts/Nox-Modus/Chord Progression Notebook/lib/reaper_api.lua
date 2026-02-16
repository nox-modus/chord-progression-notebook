local reaper_api = {}

function reaper_api.has_imgui()
	return type(reaper.ImGui_CreateContext) == "function"
end

function reaper_api.get_project_path()
	local _, project_file = reaper.EnumProjects(-1, "")
	if not project_file or project_file == "" then
		return nil
	end
	return project_file:match("^(.*)[/\\]")
end

function reaper_api.get_resource_path()
	return reaper.GetResourcePath()
end

function reaper_api.ensure_dir(path)
	if not path or path == "" then
		return false
	end
	reaper.RecursiveCreateDirectory(path, 0)
	return true
end

function reaper_api.read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()
	return content
end

function reaper_api.write_file(path, content)
	local file = io.open(path, "wb")
	if not file then
		return false
	end

	file:write(content)
	file:close()
	return true
end

local function file_exists(path)
	local file = io.open(path, "rb")
	if not file then
		return false
	end
	file:close()
	return true
end

function reaper_api.write_file_atomic(path, content)
	local tmp_path = tostring(path) .. ".tmp"
	local bak_path = tostring(path) .. ".bak"

	if not reaper_api.write_file(tmp_path, content) then
		return false
	end

	local had_old = file_exists(path)
	if had_old then
		os.remove(bak_path)
		os.rename(path, bak_path)
	end

	local renamed = os.rename(tmp_path, path)
	if renamed then
		return true
	end

	os.remove(tmp_path)
	if had_old then
		os.rename(bak_path, path)
	end
	return reaper_api.write_file(path, content)
end

function reaper_api.msg(text)
	reaper.ShowMessageBox(tostring(text), "Chord Progression Notebook", 0)
end

return reaper_api

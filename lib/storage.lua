local json = require("lib.json")
local reaper_api = require("lib.reaper_api")

local storage = {}

local EXTSTATE_SECTION = "ChordNotebook"
local EXTSTATE_KEY_UI_PREFS = "ui_prefs"
local SUBDIR_NAME = ".chord_notebook"
local UNSAVED_DIR = "ChordNotebook/unsaved"
local LIBRARY_FILENAME = "library.json"

local function ensure_root_dir(path)
	reaper_api.ensure_dir(path)
	return path
end

function storage.get_root_dir()
	local project_dir = reaper_api.get_project_path()
	if project_dir then
		return ensure_root_dir(project_dir .. "/" .. SUBDIR_NAME)
	end
	return ensure_root_dir(reaper_api.get_resource_path() .. "/" .. UNSAVED_DIR)
end

function storage.get_library_path()
	return storage.get_root_dir() .. "/" .. LIBRARY_FILENAME
end

function storage.load_library()
	local content = reaper_api.read_file(storage.get_library_path())
	if not content then
		return nil
	end

	local ok, decoded = pcall(json.decode, content)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	return decoded
end

function storage.save_library(library)
	local encoded = json.encode(library)
	return reaper_api.write_file(storage.get_library_path(), encoded)
end

function storage.load_ui_prefs()
	local raw = reaper.GetExtState(EXTSTATE_SECTION, EXTSTATE_KEY_UI_PREFS)
	if not raw or raw == "" then
		return {}
	end

	local ok, decoded = pcall(json.decode, raw)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return {}
end

function storage.save_ui_prefs(prefs)
	local encoded = json.encode(prefs or {})
	reaper.SetExtState(EXTSTATE_SECTION, EXTSTATE_KEY_UI_PREFS, encoded, true)
end

return storage

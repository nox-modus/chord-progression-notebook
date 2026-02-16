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

local function decode_library(content)
	if not content then
		return nil
	end
	local ok, decoded = pcall(json.decode, content)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	return decoded
end

function storage.load_library()
	local library_path = storage.get_library_path()
	local content = reaper_api.read_file(library_path)
	local decoded = decode_library(content)
	if decoded then
		return decoded
	end

	local backup_content = reaper_api.read_file(library_path .. ".bak")
	return decode_library(backup_content)
end

function storage.save_library(library)
	local ok, encoded = pcall(json.encode, library)
	if not ok or type(encoded) ~= "string" then
		return false
	end
	return reaper_api.write_file_atomic(storage.get_library_path(), encoded)
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

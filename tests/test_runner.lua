local info = debug.getinfo(1, "S")
local this_file = info.source:match("^@?(.*)$") or ""
local script_dir = this_file:match("^(.*[\\/])") or "./"

local root_dir = script_dir:gsub("tests[\\/]?$", "")
if root_dir == "" then
	root_dir = "."
end
if root_dir:sub(-1) ~= "/" and root_dir:sub(-1) ~= "\\" then
	root_dir = root_dir .. "/"
end

local SEP = package.config:sub(1, 1)

local function path_join(a, b)
	if a:sub(-1) == SEP then
		return a .. b
	end
	return a .. SEP .. b
end

local root_clean = root_dir:gsub("[\\/]$", "")
local package_dir = path_join(path_join(path_join(root_clean, "Scripts"), "Nox-Modus"), "Chord Progression Notebook")

package.path = table.concat({
	package_dir .. SEP .. "?.lua",
	package_dir .. SEP .. "lib" .. SEP .. "?.lua",
	package_dir .. SEP .. "lib" .. SEP .. "ui" .. SEP .. "?.lua",
	package.path,
}, ";")

local function ensure_dir(path)
	if SEP == "\\" then
		os.execute(('if not exist "%s" mkdir "%s"'):format(path, path))
	else
		os.execute(('mkdir -p "%s"'):format(path))
	end
end

local lines = {}
local total = 0
local failed = 0

local function log(msg)
	lines[#lines + 1] = tostring(msg)
	print(msg)
end

local function assert_true(v, msg)
	if not v then
		error(msg or "expected true, got false/nil", 2)
	end
end

local function assert_eq(actual, expected, msg)
	if actual ~= expected then
		error(msg or ("expected %s, got %s"):format(tostring(expected), tostring(actual)), 2)
	end
end

local function assert_contains(text, needle, msg)
	if not tostring(text):find(needle, 1, true) then
		error(msg or ("expected '%s' to include '%s'"):format(tostring(text), tostring(needle)), 2)
	end
end

local function assert_not_contains(text, needle, msg)
	if tostring(text):find(needle, 1, true) then
		error(msg or ("expected '%s' to not include '%s'"):format(tostring(text), tostring(needle)), 2)
	end
end

local function run_case(name, fn)
	total = total + 1
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		log(("[PASS] %s"):format(name))
	else
		failed = failed + 1
		log(("[FAIL] %s"):format(name))
		log(err)
	end
end

local function require_module(name)
	local ok, mod = pcall(require, name)
	if not ok then
		log(("[FATAL] failed to require '%s'"):format(name))
		log(mod)
		os.exit(1)
	end
	return mod
end

local chord_model = require_module("lib.chord_model")
local harmony_engine = require_module("lib.harmony_engine")
local imgui_guard = require_module("lib.ui.imgui_guard")
local json = require_module("lib.json")
local library_safety = require_module("lib.library_safety")
local undo = require_module("lib.undo")

log("Chord Progression Notebook - Deep Test Routine")
log(("Lua runtime: %s"):format(_VERSION))
log(("Timestamp: %s"):format(os.date("%Y-%m-%d %H:%M:%S")))
log(("Root: %s"):format(root_dir))
log("")

run_case("chord_model.normalize_mode aliases", function()
	assert_eq(chord_model.normalize_mode("Aeolian"), "minor")
	assert_eq(chord_model.normalize_mode("ionian"), "major")
	assert_eq(chord_model.normalize_mode("mixolydian"), "mixolydian")
end)

run_case("chord_model.wrap12 and note_name", function()
	assert_eq(chord_model.wrap12(-1), 11)
	assert_eq(chord_model.note_name(-1), "B")
	assert_eq(chord_model.note_name(12), "C")
end)

run_case("chord_model.degree_to_roman quality markers", function()
	assert_eq(chord_model.degree_to_roman(7, "diminished"), "viidim")
	assert_eq(chord_model.degree_to_roman(2, "minor"), "ii")
	assert_eq(chord_model.degree_to_roman(3, "augmented"), "III+")
end)

run_case("chord_model.roman_symbol regression for aeolian sequence", function()
	local key_root = 9 -- A
	local mode = "minor"
	local chords = {
		{ root = 9, quality = "minor" }, -- i
		{ root = 7, quality = "major" }, -- VII
		{ root = 5, quality = "major" }, -- VI
		{ root = 7, quality = "major" }, -- VII
	}
	local romans = {}
	for _, chord in ipairs(chords) do
		romans[#romans + 1] = chord_model.roman_symbol(chord, key_root, mode)
	end
	assert_eq(table.concat(romans, "-"), "i-VII-VI-VII")
end)

run_case("chord_model.roman_symbol diatonic and chromatic", function()
	assert_eq(chord_model.roman_symbol({ root = 7, quality = "major" }, 0, "major"), "V")
	assert_eq(chord_model.roman_symbol({ root = 6, quality = "major" }, 0, "major"), "bV")
	assert_eq(chord_model.roman_symbol({ root = 7, quality = "major" }, 9, "minor"), "VII")
end)

run_case("chord_model.chord_symbol formatting", function()
	local out = chord_model.chord_symbol({
		root = 0,
		quality = "major7",
		extensions = "(9)",
		bass = 7,
	})
	assert_eq(out, "Cmaj7(9)/G")
end)

run_case("chord_model.default_chord_for_degree major/minor", function()
	local d1 = chord_model.default_chord_for_degree(1, 0, "major")
	local d2 = chord_model.default_chord_for_degree(2, 9, "minor")
	assert_eq(d1.root, 0)
	assert_eq(d1.quality, "major")
	assert_eq(d2.root, 11)
	assert_eq(d2.quality, "diminished")
end)

run_case("chord_model.chord_pitches triad/extensions", function()
	local triad = chord_model.chord_pitches({ root = 0, quality = "major" }, 4)
	assert_eq(#triad, 3)
	assert_eq(triad[1], 48)
	assert_eq(triad[2], 52)
	assert_eq(triad[3], 55)

	local ext = chord_model.chord_pitches({ root = 0, quality = "major7", extensions = "9 11 13" }, 4)
	assert_eq(#ext, 7)
	assert_eq(ext[7], 69)
end)

run_case("harmony_engine scores move with quality/extensions", function()
	local base_t = harmony_engine.tension_score({ quality = "major" })
	local ext_t = harmony_engine.tension_score({ quality = "major", extensions = "9" })
	assert_true(ext_t > base_t)

	local base_b = harmony_engine.brightness_score({ quality = "minor" })
	local ext_b = harmony_engine.brightness_score({ quality = "minor", extensions = "11" })
	assert_true(ext_b > base_b)
end)

run_case("harmony_engine.suggest_diatonic_subs excludes source root", function()
	local chord = { root = 0, quality = "major", duration = 1 }
	local subs = harmony_engine.suggest_diatonic_subs(chord, 0, "major")
	assert_eq(#subs, 6)
	for _, suggestion in ipairs(subs) do
		assert_true(suggestion.root ~= 0, "source root must not be included in substitutions")
	end
end)

run_case("harmony_engine.secondary/tritone transformations", function()
	local sd = harmony_engine.secondary_dominant({ root = 0, duration = 1 })
	assert_eq(sd.root, 7)
	assert_eq(sd.quality, "dominant7")

	local tr = harmony_engine.tritone_sub({ root = 0, quality = "dominant7", duration = 1 })
	assert_eq(tr.root, 6)
	assert_eq(tr.quality, "dominant7")
end)

run_case("harmony_engine.modal_interchange + diminished passing", function()
	local modal = harmony_engine.modal_interchange({ root = 9, quality = "minor", duration = 2 }, 9)
	assert_true(modal ~= nil)
	assert_eq(modal.duration, 2)

	local pass = harmony_engine.diminished_passing({ root = 5, duration = 2 })
	assert_eq(pass.root, 6)
	assert_eq(pass.duration, 1)
	assert_eq(pass.quality, "dim7")
end)

run_case("harmony_engine.reharmonize mode dispatch", function()
	local chord = { root = 0, quality = "major", duration = 1, key_root = 0, mode = "major" }
	local d1 = harmony_engine.reharmonize(chord, "diatonic_rotate")
	local d2 = harmony_engine.reharmonize(chord, "function_preserving")
	local d3 = harmony_engine.reharmonize(chord, "chromatic_approach")
	assert_true(d1 ~= nil and d2 ~= nil and d3 ~= nil)
	assert_eq(d2.quality, "dominant7")
end)

run_case("json roundtrip encode/decode", function()
	local data = {
		name = "roundtrip",
		num = 42,
		ok = true,
		list = { 1, 2, 3 },
		obj = { mode = "major" },
	}
	local encoded = json.encode(data)
	local decoded = json.decode(encoded)
	assert_eq(decoded.name, "roundtrip")
	assert_eq(decoded.num, 42)
	assert_eq(decoded.ok, true)
	assert_eq(decoded.list[2], 2)
	assert_eq(decoded.obj.mode, "major")
end)

run_case("json parse unicode + invalid payload", function()
	local payload = '{"text":"\\u0043hord"}'
	local decoded = json.decode(payload)
	assert_eq(decoded.text, "Chord")

	local ok, err = pcall(function()
		json.decode('{"a":1,,}')
	end)
	assert_true(not ok, "invalid JSON must fail decode")
	assert_contains(err, "JSON decode error")
end)

run_case("library_safety normalizes malformed progression", function()
	local lib, changed = library_safety.sanitize_library({
		progressions = {
			{
				name = 42,
				key_root = -14,
				mode = "aeolian",
				tempo = 999,
				tags = { "  Bach  ", "", 7 },
				notes = 777,
				chords = {
					{ root = "2", quality = "minor", duration = 0, extensions = 9, bass = "x" },
					{ root = 14, quality = "unknown", duration = 2.5 },
				},
				audio_refs = { { path = 12 }, "bad" },
			},
		},
	})

	assert_true(changed == true)
	assert_eq(#lib.progressions, 1)
	local p = lib.progressions[1]
	assert_eq(p.name, "42")
	assert_eq(p.key_root, 10)
	assert_eq(p.mode, "minor")
	assert_eq(p.tempo, 320)
	assert_eq(p.tags[1], "Bach")
	assert_eq(p.tags[2], "7")
	assert_eq(p.notes, "777")
	assert_eq(p.chords[1].duration, 1)
	assert_eq(p.chords[1].extensions, "9")
	assert_true(p.chords[1].bass == nil)
	assert_eq(p.chords[2].quality, "major")
	assert_eq(p.audio_refs[1].path, "12")
end)

run_case("undo helper pushes/requests safely", function()
	local calls = 0
	local last_label = nil
	local state = {
		push_undo_snapshot = function(label)
			calls = calls + 1
			last_label = label
		end,
		undo_requested = false,
	}

	assert_true(undo.push(state, "Edit") == true)
	assert_eq(calls, 1)
	assert_eq(last_label, "Edit")
	assert_true(undo.request(state) == true)
	assert_true(state.undo_requested == true)
	assert_true(undo.push({}, "Noop") == false)
end)

run_case("ui modules avoid raw ImGui End* lifecycle calls", function()
	local ui_files = {
		"Scripts/Nox-Modus/Chord Progression Notebook/lib/ui/ui_main.lua",
		"Scripts/Nox-Modus/Chord Progression Notebook/lib/ui/ui_library.lua",
		"Scripts/Nox-Modus/Chord Progression Notebook/lib/ui/ui_inspector.lua",
		"Scripts/Nox-Modus/Chord Progression Notebook/lib/ui/ui_progression_lane.lua",
	}

	for _, rel in ipairs(ui_files) do
		local path = path_join(root_clean, rel)
		local fh = io.open(path, "rb")
		assert_true(fh ~= nil, "missing UI source file: " .. rel)
		local src = fh:read("*a") or ""
		fh:close()

		assert_not_contains(src, "ImGui_End(", rel .. " should use imgui_guard.end_window")
		assert_not_contains(src, "ImGui_EndChild(", rel .. " should use imgui_guard.end_child")
		assert_not_contains(src, "ImGui_EndCombo(", rel .. " should use imgui_guard.end_combo")
		assert_not_contains(src, "ImGui_EndMenuBar(", rel .. " should use imgui_guard.end_menubar")
	end
end)

run_case("imgui_guard begin failure is safe and logs once per callsite", function()
	local old_reaper = _G.reaper
	local ok, err = xpcall(function()
		local shown_messages = {}
		local begin_calls = 0
		local combo_calls = 0
		local end_calls = 0

		_G.reaper = {
			ImGui_Begin = function()
				begin_calls = begin_calls + 1
				error("begin failed")
			end,
			ImGui_BeginCombo = function()
				combo_calls = combo_calls + 1
				error("combo begin failed")
			end,
			ImGui_End = function()
				end_calls = end_calls + 1
			end,
			ShowMessageBox = function(msg)
				shown_messages[#shown_messages + 1] = tostring(msg)
				return 0
			end,
		}

		local state = {}
		local did_begin_1, visible_1, open_1 = imgui_guard.begin_window(
			{},
			state,
			"Chord Progression Notebook",
			true,
			0,
			"test.window.main"
		)
		local did_begin_2 = imgui_guard.begin_combo({}, state, "Any", "Preview", "test.window.main")

		assert_true(did_begin_1 == false)
		assert_true(visible_1 == false)
		assert_true(open_1 == true)
		assert_true(did_begin_2 == false)
		assert_eq(begin_calls, 1)
		assert_eq(combo_calls, 1)
		assert_eq(end_calls, 0)
		assert_eq(#shown_messages, 1)
		assert_contains(shown_messages[1], "test.window.main")
		assert_true(type(state._imgui_guard_seen) == "table")
		assert_true(type(state._imgui_guard_counts) == "table")
		assert_eq(state._imgui_guard_counts["test.window.main"], 2)

		imgui_guard.end_window({}, state, did_begin_1, "test.window.main")
		assert_eq(end_calls, 0)
	end, debug.traceback)
	_G.reaper = old_reaper
	assert_true(ok, err)
end)

run_case("imgui_guard end calls are conditional on successful begin", function()
	local old_reaper = _G.reaper
	local ok, err = xpcall(function()
		local child_begin_calls = 0
		local child_end_calls = 0
		local combo_begin_calls = 0
		local combo_end_calls = 0
		local menu_begin_calls = 0
		local menu_end_calls = 0

		_G.reaper = {
			ImGui_BeginChild = function()
				child_begin_calls = child_begin_calls + 1
				return true
			end,
			ImGui_EndChild = function()
				child_end_calls = child_end_calls + 1
			end,
			ImGui_BeginCombo = function()
				combo_begin_calls = combo_begin_calls + 1
				return false
			end,
			ImGui_EndCombo = function()
				combo_end_calls = combo_end_calls + 1
			end,
			ImGui_BeginMenuBar = function()
				menu_begin_calls = menu_begin_calls + 1
				return true
			end,
			ImGui_EndMenuBar = function()
				menu_end_calls = menu_end_calls + 1
			end,
			ShowMessageBox = function()
				return 0
			end,
		}

		local state = {}
		local did_child = imgui_guard.begin_child({}, state, "id", 10, 10, 0, 0, "test.child")
		local did_combo = imgui_guard.begin_combo({}, state, "label", "preview", "test.combo")
		local did_menu = imgui_guard.begin_menubar({}, state, "test.menu")

		assert_true(did_child == true)
		assert_true(did_combo == false)
		assert_true(did_menu == true)

		imgui_guard.end_child({}, state, did_child, "test.child")
		imgui_guard.end_combo({}, state, did_combo, "test.combo")
		imgui_guard.end_menubar({}, state, did_menu, "test.menu")

		assert_eq(child_begin_calls, 1)
		assert_eq(child_end_calls, 1)
		assert_eq(combo_begin_calls, 1)
		assert_eq(combo_end_calls, 0)
		assert_eq(menu_begin_calls, 1)
		assert_eq(menu_end_calls, 1)
	end, debug.traceback)
	_G.reaper = old_reaper
	assert_true(ok, err)
end)

log("")
log(("Result: %d total, %d failed, %d passed"):format(total, failed, total - failed))

local logs_dir = path_join(path_join(root_dir:gsub("[\\/]$", ""), "tests"), "logs")
ensure_dir(logs_dir)
local log_path = path_join(logs_dir, ("test_%s.log"):format(os.date("%Y%m%d_%H%M%S")))

local fh = io.open(log_path, "wb")
if fh then
	fh:write(table.concat(lines, "\n"))
	fh:write("\n")
	fh:close()
	log(("Log file: %s"):format(log_path))
else
	log("Log file: <failed to write>")
end

if failed > 0 then
	os.exit(1)
end
os.exit(0)

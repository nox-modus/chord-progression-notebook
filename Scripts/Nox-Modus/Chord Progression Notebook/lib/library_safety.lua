local chord_model = require("lib.chord_model")

local library_safety = {}

local VALID_MODES = {}
for _, mode in ipairs(chord_model.MODES or {}) do
	VALID_MODES[chord_model.normalize_mode(mode)] = true
end

local VALID_QUALITIES = {}
for quality, _ in pairs(chord_model.QUALITIES or {}) do
	VALID_QUALITIES[quality] = true
end

local function as_number(v, fallback)
	local n = tonumber(v)
	if n == nil then
		return fallback
	end
	return n
end

local function normalize_mode(mode)
	local normalized = chord_model.normalize_mode(mode)
	if VALID_MODES[normalized] then
		return normalized
	end
	return "major"
end

local function sanitize_tags(tags)
	local out = {}
	local changed = false

	if type(tags) ~= "table" then
		return out, true
	end

	for _, tag in ipairs(tags) do
		local t = tostring(tag or ""):match("^%s*(.-)%s*$")
		if type(tag) ~= "string" then
			changed = true
		end
		if t ~= "" then
			out[#out + 1] = t
		else
			changed = true
		end
	end

	return out, changed
end

local function sanitize_audio_refs(audio_refs)
	local out = {}
	local changed = false

	if type(audio_refs) ~= "table" then
		return out, true
	end

	for _, ref in ipairs(audio_refs) do
		if type(ref) == "table" then
			if type(ref.path) ~= "string" then
				changed = true
			end
			out[#out + 1] = { path = tostring(ref.path or "") }
		else
			changed = true
		end
	end

	return out, changed
end

function library_safety.sanitize_chord(chord, key_root)
	local changed = false
	local src = type(chord) == "table" and chord or {}
	if type(chord) ~= "table" then
		changed = true
	end

	local default_root = chord_model.wrap12(as_number(key_root, 0))
	local root = chord_model.wrap12(as_number(src.root, default_root))
	if src.root ~= root then
		changed = true
	end

	local quality = tostring(src.quality or "major")
	if not VALID_QUALITIES[quality] then
		quality = "major"
		changed = true
	end

	local duration = as_number(src.duration, 1)
	if duration <= 0 then
		duration = 1
		changed = true
	elseif src.duration ~= duration then
		changed = true
	end

	local bass = src.bass
	if bass ~= nil then
		local b = tonumber(bass)
		if b == nil then
			bass = nil
			changed = true
		else
			bass = chord_model.wrap12(b)
			if src.bass ~= bass then
				changed = true
			end
		end
	end

	local extensions = tostring(src.extensions or "")
	if src.extensions ~= nil and type(src.extensions) ~= "string" then
		changed = true
	end

	local out = {
		root = root,
		quality = quality,
		duration = duration,
		extensions = extensions,
		bass = bass,
	}

	return out, changed
end

function library_safety.sanitize_progression(prog)
	local changed = false
	local p = type(prog) == "table" and prog or {}
	if type(prog) ~= "table" then
		changed = true
	end

	local key_root = chord_model.wrap12(as_number(p.key_root, 0))
	if p.key_root ~= key_root then
		changed = true
	end

	local mode = normalize_mode(p.mode)
	if tostring(p.mode or "") ~= mode then
		changed = true
	end

	local tempo = math.floor(as_number(p.tempo, 120))
	if tempo < 20 then
		tempo = 20
		changed = true
	elseif tempo > 320 then
		tempo = 320
		changed = true
	end

	local tags, tags_changed = sanitize_tags(p.tags)
	if tags_changed then
		changed = true
	end

	local notes = tostring(p.notes or "")
	if p.notes ~= nil and type(p.notes) ~= "string" then
		changed = true
	end

	local audio_refs, refs_changed = sanitize_audio_refs(p.audio_refs)
	if refs_changed then
		changed = true
	end

	local chords = {}
	if type(p.chords) ~= "table" then
		changed = true
	else
		for i, chord in ipairs(p.chords) do
			local clean_chord, chord_changed = library_safety.sanitize_chord(chord, key_root)
			chords[#chords + 1] = clean_chord
			if chord_changed then
				changed = true
			end
		end
	end
	if #chords == 0 then
		chords[1] = {
			root = key_root,
			quality = "major",
			duration = 1,
			extensions = "",
			bass = nil,
		}
		changed = true
	end

	local out = p
	out.name = tostring(p.name or "New Progression")
	out.key_root = key_root
	out.mode = mode
	out.tempo = tempo
	out.tags = tags
	out.notes = notes
	out.chords = chords
	out.audio_refs = audio_refs

	if type(p.provenance) == "table" then
		p.provenance = {
			type = tostring(p.provenance.type or ""),
			source = tostring(p.provenance.source or ""),
			notes = tostring(p.provenance.notes or ""),
		}
	end

	return out, changed
end

function library_safety.sanitize_library(library)
	local changed = false
	local lib = type(library) == "table" and library or {}
	if type(library) ~= "table" then
		changed = true
	end

	local progressions = {}
	if type(lib.progressions) ~= "table" then
		changed = true
	else
		for _, prog in ipairs(lib.progressions) do
			local clean_prog, prog_changed = library_safety.sanitize_progression(prog)
			progressions[#progressions + 1] = clean_prog
			if prog_changed then
				changed = true
			end
		end
	end

	lib.progressions = progressions
	return lib, changed
end

return library_safety

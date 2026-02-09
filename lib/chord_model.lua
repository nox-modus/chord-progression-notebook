local chord_model = {}

chord_model.NOTE_NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
chord_model.MODES = { "major", "minor", "dorian", "phrygian", "lydian", "mixolydian", "locrian" }
chord_model.DEGREES = { "I", "II", "III", "IV", "V", "VI", "VII" }
chord_model.QUALITY_ORDER = {
	"major",
	"minor",
	"diminished",
	"augmented",
	"sus2",
	"sus4",
	"dominant7",
	"major7",
	"minor7",
	"halfdim7",
	"dim7",
}

chord_model.QUALITIES = {
	major = { label = "maj", intervals = { 0, 4, 7 } },
	minor = { label = "min", intervals = { 0, 3, 7 } },
	diminished = { label = "dim", intervals = { 0, 3, 6 } },
	augmented = { label = "aug", intervals = { 0, 4, 8 } },
	sus2 = { label = "sus2", intervals = { 0, 2, 7 } },
	sus4 = { label = "sus4", intervals = { 0, 5, 7 } },
	dominant7 = { label = "7", intervals = { 0, 4, 7, 10 } },
	major7 = { label = "maj7", intervals = { 0, 4, 7, 11 } },
	minor7 = { label = "m7", intervals = { 0, 3, 7, 10 } },
	halfdim7 = { label = "m7b5", intervals = { 0, 3, 6, 10 } },
	dim7 = { label = "dim7", intervals = { 0, 3, 6, 9 } },
}

chord_model.DIATONIC = {
	major = { "major", "minor", "minor", "major", "major", "minor", "diminished" },
	minor = { "minor", "diminished", "major", "minor", "minor", "major", "major" },
	dorian = { "minor", "minor", "major", "major", "minor", "diminished", "major" },
	phrygian = { "minor", "major", "major", "minor", "diminished", "major", "minor" },
	lydian = { "major", "major", "minor", "diminished", "major", "minor", "minor" },
	mixolydian = { "major", "minor", "diminished", "major", "minor", "minor", "major" },
	locrian = { "diminished", "major", "minor", "minor", "major", "major", "minor" },
}

local SCALE_STEPS = {
	major = { 0, 2, 4, 5, 7, 9, 11 },
	minor = { 0, 2, 3, 5, 7, 8, 10 },
	dorian = { 0, 2, 3, 5, 7, 9, 10 },
	phrygian = { 0, 1, 3, 5, 7, 8, 10 },
	lydian = { 0, 2, 4, 6, 7, 9, 11 },
	mixolydian = { 0, 2, 4, 5, 7, 9, 10 },
	locrian = { 0, 1, 3, 5, 6, 8, 10 },
}

function chord_model.wrap12(n)
	return (n % 12 + 12) % 12
end

function chord_model.note_name(pc)
	return chord_model.NOTE_NAMES[chord_model.wrap12(pc) + 1]
end

function chord_model.degree_to_roman(deg, quality)
	local roman = chord_model.DEGREES[deg] or "I"

	if quality == "minor" or quality == "diminished" or quality == "halfdim7" then
		roman = roman:lower()
	end

	if quality == "diminished" or quality == "halfdim7" then
		roman = roman .. "dim"
	elseif quality == "augmented" then
		roman = roman .. "+"
	end

	return roman
end

function chord_model.chord_symbol(chord)
	local root = chord_model.note_name(chord.root or 0)
	local quality_name = chord.quality or "major"
	local quality = chord_model.QUALITIES[quality_name]
	local suffix = quality and quality.label or quality_name
	local extensions = chord.extensions or ""
	local bass = chord.bass and ("/" .. chord_model.note_name(chord.bass)) or ""

	return root .. suffix .. extensions .. bass
end

function chord_model.get_scale_degrees(mode)
	return SCALE_STEPS[mode or "major"] or SCALE_STEPS.major
end

function chord_model.roman_symbol(chord, key_root, mode)
	local rel_pc = chord_model.wrap12((chord.root or 0) - (key_root or 0))
	local scale = chord_model.get_scale_degrees(mode or "major")

	local degree = 1
	for i, pc in ipairs(scale) do
		if chord_model.wrap12(pc) == rel_pc then
			degree = i
			break
		end
	end

	return chord_model.degree_to_roman(degree, chord.quality or "major") .. (chord.extensions or "")
end

function chord_model.diatonic_chord_quality(deg, mode)
	local list = chord_model.DIATONIC[mode or "major"] or chord_model.DIATONIC.major
	return list[deg] or "major"
end

function chord_model.default_chord_for_degree(deg, key_root, mode)
	local scale = chord_model.get_scale_degrees(mode or "major")
	local root = chord_model.wrap12((key_root or 0) + (scale[deg] or 0))
	return {
		root = root,
		quality = chord_model.diatonic_chord_quality(deg, mode),
		duration = 1,
	}
end

function chord_model.chord_pitches(chord, octave)
	local quality = chord_model.QUALITIES[chord.quality or "major"]
	local intervals = quality and quality.intervals or { 0, 4, 7 }
	local base = (octave or 4) * 12 + (chord.root or 0)

	local out = {}
	for _, interval in ipairs(intervals) do
		out[#out + 1] = base + interval
	end

	local ext = chord.extensions or ""
	if ext ~= "" then
		if ext:find("9") then
			out[#out + 1] = base + 14
		end
		if ext:find("11") then
			out[#out + 1] = base + 17
		end
		if ext:find("13") then
			out[#out + 1] = base + 21
		end
	end

	return out
end

return chord_model

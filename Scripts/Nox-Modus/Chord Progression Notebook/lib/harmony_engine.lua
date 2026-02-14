local chord_model = require("lib.chord_model")

local harmony_engine = {}

local TENSION_BY_QUALITY = {
	major = 1,
	minor = 2,
	dominant7 = 4,
	major7 = 3,
	minor7 = 3,
	diminished = 5,
	halfdim7 = 5,
	dim7 = 5,
}

local BRIGHTNESS_BY_QUALITY = {
	major = 3,
	minor = 2,
	dominant7 = 3,
	major7 = 4,
	minor7 = 2,
	diminished = 1,
	halfdim7 = 1,
	dim7 = 1,
	augmented = 4,
}

local function with_duration(template, duration)
	local out = {}
	for k, v in pairs(template) do
		out[k] = v
	end
	out.duration = duration or out.duration or 1
	return out
end

function harmony_engine.tension_score(chord)
	local quality = chord.quality or "major"
	local score = TENSION_BY_QUALITY[quality] or 1
	if chord.extensions and chord.extensions ~= "" then
		score = score + 1
	end
	return score
end

function harmony_engine.brightness_score(chord)
	local quality = chord.quality or "major"
	local score = BRIGHTNESS_BY_QUALITY[quality] or 3
	if chord.extensions and chord.extensions ~= "" then
		score = score + 1
	end
	return score
end

function harmony_engine.suggest_diatonic_subs(chord, key_root, mode)
	local suggestions = {}
	local root_pc = key_root or 0
	local diatonic_mode = mode or "major"
	local scale = chord_model.get_scale_degrees(diatonic_mode)

	for degree = 1, 7 do
		local root = chord_model.wrap12(root_pc + scale[degree])
		if root ~= chord.root then
			suggestions[#suggestions + 1] = {
				root = root,
				quality = chord_model.diatonic_chord_quality(degree, diatonic_mode),
				duration = chord.duration or 1,
			}
		end
	end

	return suggestions
end

function harmony_engine.secondary_dominant(chord)
	return with_duration({
		root = chord_model.wrap12((chord.root or 0) + 7),
		quality = "dominant7",
	}, chord.duration)
end

function harmony_engine.tritone_sub(chord)
	return with_duration({
		root = chord_model.wrap12((chord.root or 0) + 6),
		quality = chord.quality or "dominant7",
	}, chord.duration)
end

function harmony_engine.modal_interchange(chord, key_root)
	local center = key_root or 0
	local relative = chord_model.wrap12((chord.root or 0) - center)
	local minor_scale = chord_model.get_scale_degrees("minor")
	local major_scale = chord_model.get_scale_degrees("major")

	local matched_degree = nil
	for i, pc in ipairs(minor_scale) do
		if chord_model.wrap12(pc) == relative then
			matched_degree = i
			break
		end
	end

	if not matched_degree then
		return nil
	end

	return with_duration({
		root = chord_model.wrap12(center + major_scale[matched_degree]),
		quality = chord.quality or "major",
	}, chord.duration)
end

function harmony_engine.diminished_passing(chord)
	return with_duration({
		root = chord_model.wrap12((chord.root or 0) + 1),
		quality = "dim7",
	}, (chord.duration or 1) * 0.5)
end

function harmony_engine.reharmonize(chord, mode)
	if mode == "diatonic_rotate" then
		local suggestions = harmony_engine.suggest_diatonic_subs(chord, chord.key_root or 0, chord.mode or "major")
		return suggestions[1] or chord
	end

	if mode == "function_preserving" then
		return harmony_engine.secondary_dominant(chord)
	end

	if mode == "chromatic_approach" then
		return harmony_engine.diminished_passing(chord)
	end

	if mode == "modal_interchange" then
		return harmony_engine.modal_interchange(chord, chord.key_root or 0) or chord
	end

	return chord
end

return harmony_engine

local chord_model = require("lib.chord_model")

local midi_writer = {}
local preview_noteoffs = {}
local PREVIEW_CLICK_OPTS = {
	duration = 0.40,
	velocity = 112,
	octave = 4,
}

local function sort_numeric(list)
	table.sort(list, function(a, b)
		return a < b
	end)
	return list
end

local function copy_list(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = v
	end
	return out
end

local function clamp7(v)
	v = math.floor(tonumber(v) or 0)
	if v < 0 then
		return 0
	end
	if v > 127 then
		return 127
	end
	return v
end

local function dispatch_live_midi(status, data1, data2)
	if reaper.StuffMIDIMessage then
		-- Mode 0 and 1 are both used in the wild across REAPER setups.
		reaper.StuffMIDIMessage(0, status, data1, data2)
		reaper.StuffMIDIMessage(1, status, data1, data2)
	end
	if reaper.CSurf_OnMidiInput then
		-- Additional route for control-surface style MIDI input handling.
		pcall(reaper.CSurf_OnMidiInput, status, data1, data2)
	end
end

local function send_note_on(channel, pitch, velocity)
	local ch = clamp7(channel) % 16
	local p = clamp7(pitch)
	local v = clamp7(velocity)
	dispatch_live_midi(0x90 | ch, p, v)
end

local function send_note_off(channel, pitch)
	local ch = clamp7(channel) % 16
	local p = clamp7(pitch)
	dispatch_live_midi(0x80 | ch, p, 0)
end

local function clear_preview_now(channel)
	for i = #preview_noteoffs, 1, -1 do
		local evt = preview_noteoffs[i]
		if channel == nil or evt.channel == channel then
			send_note_off(evt.channel, evt.pitch)
			table.remove(preview_noteoffs, i)
		end
	end
end

local function ensure_track()
	local track = reaper.GetSelectedTrack(0, 0)
	if track then
		return track
	end

	track = reaper.GetTrack(0, 0)
	if track then
		return track
	end

	reaper.InsertTrackAtIndex(0, true)
	return reaper.GetTrack(0, 0)
end

local function qn_length_to_time_span(start_time, qn_length)
	local start_qn = reaper.TimeMap2_timeToQN(0, start_time)
	local end_time = reaper.TimeMap2_QNToTime(0, start_qn + qn_length)
	return end_time - start_time
end

local function insert_chord_notes(take, chord, start_time, end_time, pitches)
	local ppq_start = reaper.MIDI_GetPPQPosFromProjTime(take, start_time)
	local ppq_end = reaper.MIDI_GetPPQPosFromProjTime(take, end_time)
	local out_pitches = pitches or chord_model.chord_pitches(chord, 4)

	for _, pitch in ipairs(out_pitches) do
		reaper.MIDI_InsertNote(take, false, false, ppq_start, ppq_end, 0, pitch, 100, false)
	end
end

function midi_writer.insert_chord_at_cursor(chord, qn_duration)
	local track = ensure_track()
	local start_time = reaper.GetCursorPosition()
	local qn = qn_duration or chord.duration or 1
	local length_time = qn_length_to_time_span(start_time, qn)

	reaper.Undo_BeginBlock()

	local item = reaper.CreateNewMIDIItemInProj(track, start_time, start_time + length_time, false)
	local take = item and reaper.GetActiveTake(item)

	if take and reaper.TakeIsMIDI(take) then
		insert_chord_notes(take, chord, start_time, start_time + length_time)
		reaper.MIDI_Sort(take)
	end

	reaper.Undo_EndBlock("Insert chord", -1)
end

function midi_writer.voice_lead_pitches(chord, prev_pitches, octave)
	local current = sort_numeric(chord_model.chord_pitches(chord, octave or 4))
	if type(prev_pitches) ~= "table" or #prev_pitches == 0 then
		return copy_list(current)
	end

	local prev = sort_numeric(copy_list(prev_pitches))
	local voiced = {}
	for i, base_pitch in ipairs(current) do
		local ref = prev[math.min(i, #prev)]
		local best = base_pitch
		local best_dist = math.abs(base_pitch - ref)
		for k = -3, 3 do
			local cand = base_pitch + 12 * k
			local dist = math.abs(cand - ref)
			if dist < best_dist then
				best = cand
				best_dist = dist
			end
		end
		voiced[i] = best
	end

	for i = 2, #voiced do
		while voiced[i] <= voiced[i - 1] do
			voiced[i] = voiced[i] + 12
		end
	end

	return voiced
end

function midi_writer.preview_chord(chord, opts)
	opts = opts or {}
	local channel = opts.channel or 0
	local velocity = opts.velocity or 100
	local duration = opts.duration or 0.35
	local octave = opts.octave or 4
	local now = reaper.time_precise()
	local off_time = now + duration

	-- Keep preview monophonic per channel to avoid stacked/stuck notes on rapid clicks.
	clear_preview_now(channel)

	local pitches = opts.pitches or chord_model.chord_pitches(chord, octave)
	for _, pitch in ipairs(pitches) do
		send_note_on(channel, pitch, velocity)
		preview_noteoffs[#preview_noteoffs + 1] = {
			channel = channel,
			pitch = pitch,
			off_time = off_time,
		}
	end
end

function midi_writer.preview_click(chord)
	if not chord then
		return
	end
	midi_writer.preview_chord(chord, PREVIEW_CLICK_OPTS)
end

function midi_writer.update_preview()
	if #preview_noteoffs == 0 then
		return
	end
	local now = reaper.time_precise()
	for i = #preview_noteoffs, 1, -1 do
		local evt = preview_noteoffs[i]
		if now >= evt.off_time then
			send_note_off(evt.channel, evt.pitch)
			table.remove(preview_noteoffs, i)
		end
	end
end

function midi_writer.stop_preview()
	clear_preview_now(nil)
end

function midi_writer.insert_progression(track, start_pos, progression, opts)
	opts = opts or {}
	local target_track = track or ensure_track()
	local start_time = start_pos or reaper.GetCursorPosition()

	local total_qn = 0
	for _, chord in ipairs(progression.chords or {}) do
		total_qn = total_qn + (chord.duration or 1)
	end

	local end_time = reaper.TimeMap2_QNToTime(0, reaper.TimeMap2_timeToQN(0, start_time) + total_qn)

	reaper.Undo_BeginBlock()

	local item = reaper.CreateNewMIDIItemInProj(target_track, start_time, end_time, false)
	local take = item and reaper.GetActiveTake(item)

	if take and reaper.TakeIsMIDI(take) then
		local current_qn = reaper.TimeMap2_timeToQN(0, start_time)
		local prev_pitches = nil
		for _, chord in ipairs(progression.chords or {}) do
			local qn_len = chord.duration or 1
			local chord_start = reaper.TimeMap2_QNToTime(0, current_qn)
			local chord_end = reaper.TimeMap2_QNToTime(0, current_qn + qn_len)
			local pitches = nil
			if opts.voice_leading == true then
				pitches = midi_writer.voice_lead_pitches(chord, prev_pitches, 4)
				prev_pitches = copy_list(pitches)
			end
			insert_chord_notes(take, chord, chord_start, chord_end, pitches)
			current_qn = current_qn + qn_len
		end
		reaper.MIDI_Sort(take)
	end

	reaper.Undo_EndBlock("Insert progression", -1)
end

local function collect_midi_notes(take)
	local notes = {}
	local _, note_count = reaper.MIDI_CountEvts(take)

	for i = 0, note_count - 1 do
		local ok, _, _, start_ppq, end_ppq, _, pitch = reaper.MIDI_GetNote(take, i)
		if ok then
			notes[#notes + 1] = { start = start_ppq, ending = end_ppq, pitch = pitch }
		end
	end

	table.sort(notes, function(a, b)
		return a.start < b.start
	end)

	return notes
end

local function cluster_notes(notes, window)
	local clusters = {}

	for _, note in ipairs(notes) do
		local placed = false
		for _, cluster in ipairs(clusters) do
			if math.abs(note.start - cluster.start) <= window then
				cluster.notes[#cluster.notes + 1] = note
				placed = true
				break
			end
		end

		if not placed then
			clusters[#clusters + 1] = {
				start = note.start,
				notes = { note },
			}
		end
	end

	return clusters
end

local function pitch_classes_from_cluster(cluster)
	local pcs = {}
	for _, note in ipairs(cluster.notes) do
		pcs[note.pitch % 12] = true
	end
	return pcs
end

function midi_writer.guess_chord(pcs)
	local best = { score = -1, root = 0, quality = "major" }

	for root = 0, 11 do
		for quality_name, quality in pairs(chord_model.QUALITIES) do
			local score = 0
			for _, interval in ipairs(quality.intervals) do
				if pcs[(root + interval) % 12] then
					score = score + 1
				end
			end
			if score > best.score then
				best = { score = score, root = root, quality = quality_name }
			end
		end
	end

	return {
		root = best.root,
		quality = best.quality,
	}
end

function midi_writer.detect_from_selected_item()
	local item = reaper.GetSelectedMediaItem(0, 0)
	if not item then
		return nil, "No selected item"
	end

	local take = reaper.GetActiveTake(item)
	if not take or not reaper.TakeIsMIDI(take) then
		return nil, "Selected item is not MIDI"
	end

	local notes = collect_midi_notes(take)
	local clusters = cluster_notes(notes, 60)

	local chords = {}
	for _, cluster in ipairs(clusters) do
		local pcs = pitch_classes_from_cluster(cluster)
		local chord = midi_writer.guess_chord(pcs)
		chord.duration = 1
		chords[#chords + 1] = chord
	end

	return chords
end

return midi_writer

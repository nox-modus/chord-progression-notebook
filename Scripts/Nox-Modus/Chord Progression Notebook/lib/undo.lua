local undo = {}

function undo.push(state, label)
	if type(state) ~= "table" then
		return false
	end
	local fn = state.push_undo_snapshot
	if type(fn) ~= "function" then
		return false
	end
	fn(label)
	return true
end

function undo.request(state)
	if type(state) ~= "table" then
		return false
	end
	state.undo_requested = true
	return true
end

return undo

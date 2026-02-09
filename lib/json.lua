local json = {}

local escape_char_map = {
	["\\"] = "\\\\",
	['"'] = '\\"',
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function escape_str(s)
	return s:gsub('[\\"\b\f\n\r\t]', function(c)
		return escape_char_map[c] or c
	end)
end

local function is_array(t)
	if type(t) ~= "table" then
		return false
	end
	local n = 0
	for k, _ in pairs(t) do
		if type(k) ~= "number" then
			return false
		end
		if k > n then
			n = k
		end
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

local function encode_value(v)
	local tv = type(v)
	if tv == "nil" then
		return "null"
	end
	if tv == "number" then
		return tostring(v)
	end
	if tv == "boolean" then
		return v and "true" or "false"
	end
	if tv == "string" then
		return '"' .. escape_str(v) .. '"'
	end
	if tv == "table" then
		if is_array(v) then
			local out = {}
			for i = 1, #v do
				out[#out + 1] = encode_value(v[i])
			end
			return "[" .. table.concat(out, ",") .. "]"
		else
			local out = {}
			for k, val in pairs(v) do
				out[#out + 1] = '"' .. escape_str(tostring(k)) .. '":' .. encode_value(val)
			end
			return "{" .. table.concat(out, ",") .. "}"
		end
	end
	return "null"
end

function json.encode(tbl)
	return encode_value(tbl)
end

local function decode_error(str, idx, msg)
	error("JSON decode error at " .. tostring(idx) .. ": " .. msg .. " near '" .. str:sub(idx, idx + 10) .. "'", 0)
end

local function skip_ws(str, idx)
	local _, e = str:find("^[ \n\r\t]+", idx)
	if e then
		return e + 1
	end
	return idx
end

local function parse_null(str, idx)
	if str:sub(idx, idx + 3) == "null" then
		return nil, idx + 4
	end
	decode_error(str, idx, "expected null")
end

local function parse_true(str, idx)
	if str:sub(idx, idx + 3) == "true" then
		return true, idx + 4
	end
	decode_error(str, idx, "expected true")
end

local function parse_false(str, idx)
	if str:sub(idx, idx + 4) == "false" then
		return false, idx + 5
	end
	decode_error(str, idx, "expected false")
end

local function parse_number(str, idx)
	local s, e = str:find("^-?%d+%.?%d*[eE]?[+-]?%d*", idx)
	if not s then
		decode_error(str, idx, "bad number")
	end
	local num = tonumber(str:sub(s, e))
	return num, e + 1
end

local function parse_string(str, idx)
	idx = idx + 1
	local out = {}
	while idx <= #str do
		local c = str:sub(idx, idx)
		if c == '"' then
			return table.concat(out), idx + 1
		elseif c == "\\" then
			local nxt = str:sub(idx + 1, idx + 1)
			local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
			if map[nxt] then
				out[#out + 1] = map[nxt]
				idx = idx + 2
			elseif nxt == "u" then
				local hex = str:sub(idx + 2, idx + 5)
				if not hex:match("%x%x%x%x") then
					decode_error(str, idx, "bad unicode")
				end
				out[#out + 1] = utf8.char(tonumber(hex, 16))
				idx = idx + 6
			else
				decode_error(str, idx, "bad escape")
			end
		else
			out[#out + 1] = c
			idx = idx + 1
		end
	end
	decode_error(str, idx, "unterminated string")
end

local function parse_array(str, idx)
	idx = idx + 1
	local out = {}
	idx = skip_ws(str, idx)
	if str:sub(idx, idx) == "]" then
		return out, idx + 1
	end
	while true do
		local val
		val, idx = json.decode_at(str, idx)
		out[#out + 1] = val
		idx = skip_ws(str, idx)
		local c = str:sub(idx, idx)
		if c == "]" then
			return out, idx + 1
		end
		if c ~= "," then
			decode_error(str, idx, "expected , or ]")
		end
		idx = skip_ws(str, idx + 1)
	end
end

local function parse_object(str, idx)
	idx = idx + 1
	local out = {}
	idx = skip_ws(str, idx)
	if str:sub(idx, idx) == "}" then
		return out, idx + 1
	end
	while true do
		local key
		if str:sub(idx, idx) ~= '"' then
			decode_error(str, idx, "expected string key")
		end
		key, idx = parse_string(str, idx)
		idx = skip_ws(str, idx)
		if str:sub(idx, idx) ~= ":" then
			decode_error(str, idx, "expected :")
		end
		idx = skip_ws(str, idx + 1)
		local val
		val, idx = json.decode_at(str, idx)
		out[key] = val
		idx = skip_ws(str, idx)
		local c = str:sub(idx, idx)
		if c == "}" then
			return out, idx + 1
		end
		if c ~= "," then
			decode_error(str, idx, "expected , or }")
		end
		idx = skip_ws(str, idx + 1)
	end
end

function json.decode_at(str, idx)
	idx = skip_ws(str, idx)
	local c = str:sub(idx, idx)
	if c == "{" then
		return parse_object(str, idx)
	end
	if c == "[" then
		return parse_array(str, idx)
	end
	if c == '"' then
		return parse_string(str, idx)
	end
	if c == "n" then
		return parse_null(str, idx)
	end
	if c == "t" then
		return parse_true(str, idx)
	end
	if c == "f" then
		return parse_false(str, idx)
	end
	if c:match("[-%d]") then
		return parse_number(str, idx)
	end
	decode_error(str, idx, "unexpected character")
end

function json.decode(str)
	if type(str) ~= "string" then
		return nil
	end
	local res, idx = json.decode_at(str, 1)
	idx = skip_ws(str, idx)
	if idx <= #str then
		decode_error(str, idx, "trailing garbage")
	end
	return res
end

return json

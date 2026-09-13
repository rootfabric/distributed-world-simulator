extends RefCounted

# Opt-in research transport; never changes canonical Construction/Matter hashes.
# Every node is tagged, so user dictionaries cannot collide with float envelopes.
# No bytes_to_var / object decoding. JSON transports only arrays and strings.
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "dws.fabric.r3.lossless-json.v1"
const MAX_NODES := 100000
const MAX_DEPTH := 64
const MAX_TEXT_BYTES := 8388608
const FIELDS: Array[String] = ["schema", "payload", "checksum"]

static func encode(value) -> Dictionary:
	var budget := {"nodes": 0, "text_bytes": 0, "error": ""}
	var node := _encode_node(value, 0, budget)
	if not str(budget.error).is_empty(): return _failure(budget.error)
	var wire := {"schema": SCHEMA, "payload": node}
	wire["checksum"] = NetworkUtils.payload_hash(wire)
	if str(wire.checksum).is_empty(): return _failure("WIRE_HASH_FAILED")
	return _success(wire)

static func decode(wire: Dictionary) -> Dictionary:
	if not NetworkUtils.validate_exact_fields(wire, FIELDS).success or wire.get("schema") != SCHEMA:
		return _failure("WIRE_SCHEMA")
	if not _is_hex(wire.get("checksum"), 64): return _failure("WIRE_CHECKSUM_SHAPE")
	var budget := {"nodes": 0, "text_bytes": 0, "error": ""}
	var value = _decode_node(wire.payload, 0, budget)
	if not str(budget.error).is_empty(): return _failure(budget.error)
	# Structural/budget validation precedes recursive hashing of untrusted nodes.
	if wire.checksum != NetworkUtils.payload_hash({"schema": SCHEMA, "payload": wire.payload}):
		return _failure("WIRE_CHECKSUM_MISMATCH")
	return _success(value)

static func canonical_json(value) -> String:
	var encoded := encode(value)
	if not encoded.success: return ""
	var text := JSON.stringify(encoded.value, "", true, true)
	return text if text.to_utf8_buffer().size() <= MAX_TEXT_BYTES else ""

static func parse_json(text: String) -> Dictionary:
	if text.length() > MAX_TEXT_BYTES or text.to_utf8_buffer().size() > MAX_TEXT_BYTES:
		return _failure("WIRE_TEXT_BUDGET")
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return _failure("WIRE_JSON_INVALID")
	# Reject duplicate top-level keys and noncanonical spellings, not just the
	# parser's last-wins object. The only accepted text is our canonical wire.
	if JSON.stringify(parser.data, "", true, true) != text:
		return _failure("WIRE_JSON_NONCANONICAL")
	return decode(parser.data)

static func payload_hash(value) -> String:
	var encoded := encode(value)
	return str(encoded.value.checksum) if encoded.success else ""

static func _visit(depth: int, budget: Dictionary) -> bool:
	budget.nodes += 1
	if depth > MAX_DEPTH or budget.nodes > MAX_NODES:
		budget.error = "WIRE_NODE_OR_DEPTH_BUDGET"
	return str(budget.error).is_empty()

static func _text(value: String, budget: Dictionary) -> bool:
	if value.length() > MAX_TEXT_BYTES:
		budget.error = "WIRE_TEXT_BUDGET"
		return false
	budget.text_bytes += value.to_utf8_buffer().size()
	if budget.text_bytes > MAX_TEXT_BYTES: budget.error = "WIRE_TEXT_BUDGET"
	return str(budget.error).is_empty()

static func _encode_node(value, depth: int, budget: Dictionary) -> Array:
	if not _visit(depth, budget): return []
	match typeof(value):
		TYPE_NIL: return ["n"]
		TYPE_BOOL: return ["b", "1" if value else "0"]
		TYPE_STRING:
			if not _text(value, budget): return []
			return ["s", value]
		TYPE_INT:
			if not NetworkUtils.is_json_integer(value): budget.error = "WIRE_INTEGER_RANGE"; return []
			return ["i", str(value)]
		TYPE_FLOAT:
			if not is_finite(value): budget.error = "WIRE_NONFINITE"; return []
			if value == floor(value) and not NetworkUtils.is_json_integer(value):
				budget.error = "WIRE_INTEGER_RANGE"; return []
			var buffer := StreamPeerBuffer.new()
			buffer.big_endian = false
			buffer.put_double(value)
			return ["f64le", buffer.data_array.hex_encode()]
		TYPE_ARRAY:
			if value.size() > MAX_NODES: budget.error = "WIRE_NODE_OR_DEPTH_BUDGET"; return []
			var nodes: Array = []
			for child in value:
				nodes.append(_encode_node(child, depth + 1, budget))
				if not str(budget.error).is_empty(): return []
			return ["a", nodes]
		TYPE_DICTIONARY:
			if value.size() > MAX_NODES: budget.error = "WIRE_NODE_OR_DEPTH_BUDGET"; return []
			var keys: Array = value.keys()
			for key in keys:
				if typeof(key) != TYPE_STRING: budget.error = "WIRE_KEY_TYPE"; return []
			keys.sort()
			var pairs: Array = []
			for key in keys:
				if not _text(key, budget): return []
				pairs.append([key, _encode_node(value[key], depth + 1, budget)])
				if not str(budget.error).is_empty(): return []
			return ["d", pairs]
		_:
			budget.error = "WIRE_VARIANT_FORBIDDEN"
			return []

static func _decode_node(node, depth: int, budget: Dictionary):
	if not _visit(depth, budget): return null
	if not node is Array or node.is_empty() or typeof(node[0]) != TYPE_STRING:
		budget.error = "WIRE_NODE_SHAPE"; return null
	if node[0] == "n":
		if node.size() != 1: budget.error = "WIRE_NODE_SHAPE"
		return null
	if node.size() != 2: budget.error = "WIRE_NODE_SHAPE"; return null
	var value = node[1]
	match node[0]:
		"b":
			if typeof(value) != TYPE_STRING or not value in ["0", "1"]:
				budget.error = "WIRE_BOOL_SHAPE"; return null
			return value == "1"
		"s":
			if typeof(value) != TYPE_STRING: budget.error = "WIRE_STRING_SHAPE"; return null
			if not _text(value, budget): return null
			return value
		"i":
			if typeof(value) != TYPE_STRING or value.length() > 17 or not value.is_valid_int():
				budget.error = "WIRE_INTEGER_SHAPE"; return null
			var integer := int(value)
			if str(integer) != value or not NetworkUtils.is_json_integer(integer):
				budget.error = "WIRE_INTEGER_RANGE"; return null
			return integer
		"f64le":
			if not _is_hex(value, 16): budget.error = "WIRE_FLOAT_SHAPE"; return null
			var buffer := StreamPeerBuffer.new()
			buffer.big_endian = false
			buffer.data_array = value.hex_decode()
			var number := buffer.get_double()
			if not is_finite(number): budget.error = "WIRE_NONFINITE"; return null
			if number == floor(number) and not NetworkUtils.is_json_integer(number):
				budget.error = "WIRE_INTEGER_RANGE"; return null
			return number
		"a":
			if not value is Array or value.size() > MAX_NODES:
				budget.error = "WIRE_ARRAY_BUDGET_OR_SHAPE"; return null
			var children: Array = []
			for child in value:
				children.append(_decode_node(child, depth + 1, budget))
				if not str(budget.error).is_empty(): return null
			return children
		"d":
			if not value is Array or value.size() > MAX_NODES:
				budget.error = "WIRE_DICTIONARY_BUDGET_OR_SHAPE"; return null
			var result := {}
			var previous := ""
			for index in range(value.size()):
				var pair = value[index]
				if not pair is Array or pair.size() != 2 or typeof(pair[0]) != TYPE_STRING:
					budget.error = "WIRE_KEY_SHAPE"; return null
				var key: String = pair[0]
				if index > 0 and key <= previous: budget.error = "WIRE_KEYS_NOT_SORTED_UNIQUE"; return null
				if not _text(key, budget): return null
				previous = key
				result[key] = _decode_node(pair[1], depth + 1, budget)
				if not str(budget.error).is_empty(): return null
			return result
		_:
			budget.error = "WIRE_UNKNOWN_TAG"
			return null

static func _is_hex(value, length: int) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != length: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true

static func _success(value) -> Dictionary:
	return {"success": true, "value": value, "error": ""}

static func _failure(code: String) -> Dictionary:
	return {"success": false, "value": null, "error": code}

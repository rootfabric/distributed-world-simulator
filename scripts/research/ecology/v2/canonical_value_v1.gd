extends RefCounted
## Integer-only canonical data. IDs stay strings; JSON numeric coercion is confined to decode().
const MAX_INT := 9007199254740991
const MAX_BYTES := 2097152

static func integer(value: Variant, low: int, high: int) -> bool:
	return typeof(value) == TYPE_INT and value >= low and value <= high

static func keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:/-":
			return false
	return true

static func vector(value: Variant, bound: int) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for part in value:
		if not integer(part, -bound, bound):
			return false
	return true

static func encode(value: Variant, depth: int = 0) -> String:
	if depth > 24:
		return ""
	match typeof(value):
		TYPE_INT:
			return str(value) if value >= -MAX_INT and value <= MAX_INT else ""
		TYPE_BOOL, TYPE_STRING, TYPE_NIL:
			return JSON.stringify(value)
		TYPE_ARRAY:
			if value.size() > 4096:
				return ""
			var parts := PackedStringArray()
			for item in value:
				var encoded := encode(item, depth + 1)
				if encoded.is_empty():
					return ""
				parts.append(encoded)
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			if value.size() > 4096:
				return ""
			var names: Array = value.keys()
			for name in names:
				if not name is String:
					return ""
			names.sort()
			var parts := PackedStringArray()
			for name in names:
				var encoded := encode(value[name], depth + 1)
				if encoded.is_empty():
					return ""
				parts.append(JSON.stringify(name) + ":" + encoded)
			return "{" + ",".join(parts) + "}"
	return ""

static func digest(value: Variant) -> String:
	var text := encode(value)
	return "" if text.is_empty() else text.sha256_text()

static func decode(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"success": false, "error": "INPUT_TOO_LARGE"}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"success": false, "error": "INVALID_JSON"}
	var result := _normalize(parser.data, 0)
	if not result.success:
		return result
	# Reject duplicate keys, noncanonical numbers/escaping and integer precision loss.
	# Import is intentionally a canonical format, not arbitrary permissive JSON.
	if encode(result.value) != text.strip_edges():
		return {"success": false, "error": "NONCANONICAL_JSON"}
	return result

static func _normalize(value: Variant, depth: int) -> Dictionary:
	if depth > 24:
		return {"success": false, "error": "DEPTH_LIMIT"}
	if typeof(value) == TYPE_FLOAT:
		if not is_finite(value) or absf(value) > float(MAX_INT) or floor(value) != value:
			return {"success": false, "error": "NONEXACT_INTEGER"}
		return {"success": true, "value": int(value)}
	if value is Array or value is Dictionary:
		if value.size() > 4096:
			return {"success": false, "error": "CONTAINER_LIMIT"}
		var out: Variant = [] if value is Array else {}
		for key in range(value.size()) if value is Array else value.keys():
			var item := _normalize(value[key], depth + 1)
			if not item.success:
				return item
			if out is Array:
				out.append(item.value)
			else:
				out[key] = item.value
		return {"success": true, "value": out}
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING]:
		return {"success": true, "value": value}
	return {"success": false, "error": "INVALID_VALUE"}

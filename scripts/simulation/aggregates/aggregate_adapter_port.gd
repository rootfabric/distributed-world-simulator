extends RefCounted

const REQUIRED_METHODS: Array[String] = [
	"get_aggregate_kind",
	"supports_aggregate",
	"validate_snapshot",
	"validate_delta",
	"export_snapshot",
	"export_delta",
]


static func validate_adapter(adapter) -> Dictionary:
	if adapter == null:
		return _failure("AGGREGATE_ADAPTER_REQUIRED")
	for method in REQUIRED_METHODS:
		if not adapter.has_method(method):
			return _failure("AGGREGATE_ADAPTER_METHOD_MISSING", {"method": method})
	var kind = adapter.call("get_aggregate_kind")
	if typeof(kind) != TYPE_STRING or not _is_kind(String(kind)):
		return _failure("INVALID_AGGREGATE_ADAPTER_KIND")
	return _success({"aggregate_kind": String(kind)})


static func _is_kind(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges().to_upper():
		return false
	for character in value:
		if not String(character) in ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "_"]:
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}

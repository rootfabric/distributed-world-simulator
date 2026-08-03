extends RefCounted

const REQUIRED_METHODS: Array[String] = [
	"setup",
	"apply_plan",
	"get_item_projection",
	"get_construct_snapshot",
	"export_state",
	"load_state",
]

static func validate_adapter(adapter) -> Dictionary:
	if adapter == null:
		return _failure("CONSTRUCTION_ITEM_GRAPH_ADAPTER_REQUIRED")
	for method_name in REQUIRED_METHODS:
		if not adapter.has_method(method_name):
			return _failure("CONSTRUCTION_ITEM_GRAPH_ADAPTER_METHOD_MISSING", {"method": method_name})
	return _success()

static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result

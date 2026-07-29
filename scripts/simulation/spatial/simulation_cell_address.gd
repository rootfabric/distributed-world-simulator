extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")

const SCHEMA: String = "planet_simulator.simulation_cell_address.v1"
const FIELDS: Array[String] = [
	"schema",
	"universe_id",
	"instance_id",
	"space_id",
	"grid_id",
	"grid_revision",
	"root_id",
	"level",
	"path",
	"cell_id",
]


static func create(
	universe_id: String,
	instance_id: String,
	space_id: String,
	grid_id: String,
	grid_revision: int,
	root_id: String,
	path: Array = []
) -> Dictionary:
	var normalized_path: Array = []
	for value in path:
		normalized_path.append(int(value))
	var result: Dictionary = {
		"schema": SCHEMA,
		"universe_id": universe_id.strip_edges().to_lower(),
		"instance_id": instance_id.strip_edges().to_lower(),
		"space_id": space_id.strip_edges().to_lower(),
		"grid_id": grid_id.strip_edges().to_lower(),
		"grid_revision": grid_revision,
		"root_id": root_id.strip_edges().to_lower(),
		"level": normalized_path.size(),
		"path": normalized_path,
		"cell_id": "",
	}
	result["cell_id"] = compute_cell_id(result)
	return result


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_SIMULATION_CELL_ADDRESS_SCHEMA")
	for field in ["universe_id", "instance_id", "space_id", "grid_id", "root_id"]:
		if not SpatialUtilsScript.is_lower_segment(String(value.get(field, "")), true):
			return _failure("INVALID_SIMULATION_CELL_ADDRESS_IDENTIFIER", {"field": field})
	for field in ["grid_revision", "level"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)):
			return _failure("INVALID_SIMULATION_CELL_ADDRESS_INTEGER", {"field": field})
	if int(value["grid_revision"]) < 1:
		return _failure("INVALID_SIMULATION_CELL_GRID_REVISION")
	var level: int = int(value["level"])
	if level < 0 or level > SpatialUtilsScript.MAX_HIERARCHY_LEVEL:
		return _failure("INVALID_SIMULATION_CELL_LEVEL")
	if typeof(value.get("path")) != TYPE_ARRAY or value["path"].size() != level:
		return _failure("SIMULATION_CELL_PATH_LEVEL_MISMATCH")
	for index in range(value["path"].size()):
		var entry = value["path"][index]
		if not NetworkUtilsScript.is_json_integer(entry):
			return _failure("INVALID_SIMULATION_CELL_PATH_ENTRY", {"index": index})
		var child_index: int = int(entry)
		if child_index < 0 or child_index > SpatialUtilsScript.MAX_CHILD_INDEX:
			return _failure("INVALID_SIMULATION_CELL_PATH_ENTRY", {"index": index})
	if typeof(value.get("cell_id")) != TYPE_STRING or not SpatialUtilsScript.is_canonical_id(value["cell_id"], 2):
		return _failure("INVALID_SIMULATION_CELL_ID")
	if String(value["cell_id"]) != compute_cell_id(value):
		return _failure("SIMULATION_CELL_ID_MISMATCH")
	return NetworkUtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	return Dictionary(round_trip.get("value", {})) if bool(round_trip.get("success", false)) else {}


static func compute_cell_id(value: Dictionary) -> String:
	var path_value = value.get("path", [])
	if typeof(path_value) != TYPE_ARRAY:
		return ""
	var path_tokens: Array[String] = []
	for child_index in path_value:
		if not NetworkUtilsScript.is_json_integer(child_index):
			return ""
		path_tokens.append(str(int(child_index)))
	var path_text: String = "root" if path_tokens.is_empty() else ".".join(path_tokens)
	return "universe/%s/instance/%s/space/%s/grid/%s/revision/%d/root/%s/level/%d/path/%s" % [
		String(value.get("universe_id", "")).strip_edges().to_lower(),
		String(value.get("instance_id", "")).strip_edges().to_lower(),
		String(value.get("space_id", "")).strip_edges().to_lower(),
		String(value.get("grid_id", "")).strip_edges().to_lower(),
		int(value.get("grid_revision", 0)),
		String(value.get("root_id", "")).strip_edges().to_lower(),
		int(value.get("level", -1)),
		path_text,
	]


static func parent(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)) or int(value["level"]) == 0:
		return {}
	var path: Array = Array(value["path"]).duplicate()
	path.pop_back()
	return create(
		String(value["universe_id"]),
		String(value["instance_id"]),
		String(value["space_id"]),
		String(value["grid_id"]),
		int(value["grid_revision"]),
		String(value["root_id"]),
		path
	)


static func child(value: Dictionary, child_index: int) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	if child_index < 0 or child_index > SpatialUtilsScript.MAX_CHILD_INDEX:
		return {}
	if int(value["level"]) >= SpatialUtilsScript.MAX_HIERARCHY_LEVEL:
		return {}
	var path: Array = Array(value["path"]).duplicate()
	path.append(child_index)
	return create(
		String(value["universe_id"]),
		String(value["instance_id"]),
		String(value["space_id"]),
		String(value["grid_id"]),
		int(value["grid_revision"]),
		String(value["root_id"]),
		path
	)


static func is_ancestor(ancestor: Dictionary, descendant: Dictionary) -> bool:
	if not bool(validate(ancestor).get("success", false)) or not bool(validate(descendant).get("success", false)):
		return false
	for field in ["universe_id", "instance_id", "space_id", "grid_id", "grid_revision", "root_id"]:
		if ancestor[field] != descendant[field]:
			return false
	var ancestor_level: int = int(ancestor["level"])
	if ancestor_level >= int(descendant["level"]):
		return false
	for index in range(ancestor_level):
		if int(ancestor["path"][index]) != int(descendant["path"][index]):
			return false
	return true


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

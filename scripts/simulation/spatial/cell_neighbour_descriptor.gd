extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")

const SCHEMA: String = "planet_simulator.cell_neighbour_descriptor.v1"
const RELATION_FACE: String = "FACE"
const RELATION_EDGE: String = "EDGE"
const RELATION_CORNER: String = "CORNER"
const RELATION_PORTAL: String = "PORTAL"
const RELATION_PARENT_CHILD: String = "PARENT_CHILD"
const RELATION_KINDS: Array[String] = [
	RELATION_FACE,
	RELATION_EDGE,
	RELATION_CORNER,
	RELATION_PORTAL,
	RELATION_PARENT_CHILD,
]
const FIELDS: Array[String] = [
	"schema",
	"neighbour_id",
	"source_cell_id",
	"target_cell_id",
	"relation_kind",
	"source_boundary_key",
	"target_boundary_key",
	"bidirectional",
	"topology_revision",
]


static func create(
	neighbour_id: String,
	source_cell_id: String,
	target_cell_id: String,
	relation_kind: String,
	source_boundary_key: String,
	target_boundary_key: String,
	bidirectional: bool,
	topology_revision: int = 1
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"neighbour_id": neighbour_id.strip_edges().to_lower(),
		"source_cell_id": source_cell_id.strip_edges().to_lower(),
		"target_cell_id": target_cell_id.strip_edges().to_lower(),
		"relation_kind": relation_kind.strip_edges().to_upper(),
		"source_boundary_key": source_boundary_key.strip_edges().to_lower(),
		"target_boundary_key": target_boundary_key.strip_edges().to_lower(),
		"bidirectional": bidirectional,
		"topology_revision": topology_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_CELL_NEIGHBOUR_SCHEMA")
	for field in ["neighbour_id", "source_cell_id", "target_cell_id", "source_boundary_key", "target_boundary_key"]:
		if not SpatialUtilsScript.is_canonical_id(value.get(field), 2):
			return _failure("INVALID_CELL_NEIGHBOUR_IDENTIFIER", {"field": field})
	if String(value["source_cell_id"]) == String(value["target_cell_id"]):
		return _failure("CELL_NEIGHBOUR_SELF_LINK")
	if typeof(value.get("relation_kind")) != TYPE_STRING or not RELATION_KINDS.has(String(value["relation_kind"])):
		return _failure("INVALID_CELL_NEIGHBOUR_RELATION")
	if typeof(value.get("bidirectional")) != TYPE_BOOL:
		return _failure("INVALID_CELL_NEIGHBOUR_DIRECTIONALITY")
	if not NetworkUtilsScript.is_json_integer(value.get("topology_revision")) or int(value["topology_revision"]) < 1:
		return _failure("INVALID_CELL_NEIGHBOUR_TOPOLOGY_REVISION")
	return NetworkUtilsScript.validation_success()


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}

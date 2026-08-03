extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const StateScript = preload("res://scripts/construction/geometry_edit/construction_local_geometry_state.gd")

const SCHEMA := "planet_simulator.construction_geometry_edit_record.v1"
const FIELDS: Array[String] = ["schema", "edit_id", "operation_id", "request_checksum", "member_instance_id", "item_instance_id", "construct_id", "part_id", "before_member_checksum", "after_member_checksum", "before_item_revision", "after_item_revision", "before_construct_checksum", "after_construct_revision", "before_state", "after_state", "mass_delta_kg", "volume_delta_m3", "material_deltas", "metadata", "checksum"]
const MATERIAL_DELTA_FIELDS: Array[String] = ["material_id", "before_mass_kg", "after_mass_kg", "delta_mass_kg"]

static func create(request: Dictionary, before_instance: Dictionary, after_instance: Dictionary, before_state: Dictionary, after_state: Dictionary, before_item_revision: int, before_construct_checksum: String, after_construct_revision: int, material_deltas: Array) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"edit_id": String(request.get("edit_id", "")),
		"operation_id": String(request.get("operation_id", "")),
		"request_checksum": String(request.get("checksum", "")),
		"member_instance_id": String(before_instance.get("member_instance_id", "")),
		"item_instance_id": String(before_instance.get("item_instance_id", "")),
		"construct_id": String(request.get("construct_id", "")),
		"part_id": String(request.get("part_id", "")),
		"before_member_checksum": String(before_instance.get("checksum", "")),
		"after_member_checksum": String(after_instance.get("checksum", "")),
		"before_item_revision": before_item_revision,
		"after_item_revision": before_item_revision + 1,
		"before_construct_checksum": before_construct_checksum,
		"after_construct_revision": after_construct_revision,
		"before_state": before_state.duplicate(true),
		"after_state": after_state.duplicate(true),
		"mass_delta_kg": ParametricUtils.metric(float(after_instance.get("mass_kg", 0.0)) - float(before_instance.get("mass_kg", 0.0))),
		"volume_delta_m3": ParametricUtils.metric(float(after_instance.get("geometry", {}).get("volume_m3", 0.0)) - float(before_instance.get("geometry", {}).get("volume_m3", 0.0))),
		"material_deltas": _sorted_deltas(material_deltas),
		"metadata": Dictionary(request.get("metadata", {})).duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_GEOMETRY_EDIT_RECORD_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("edit_id", "")), "geometry-edit/") or not ParametricUtils.path_id(String(value.get("operation_id", "")), "operation/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_ID")
	if typeof(value.get("request_checksum")) != TYPE_STRING or String(value["request_checksum"]).length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_REQUEST_CHECKSUM")
	if not ParametricUtils.path_id(String(value.get("member_instance_id", "")), "parametric-member/") or not ParametricUtils.path_id(String(value.get("item_instance_id", "")), "item/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_MEMBER")
	if not ParametricUtils.path_id(String(value.get("construct_id", "")), "construct/") or not ParametricUtils.path_id(String(value.get("part_id", "")), "part/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_TARGET")
	for field in ["before_member_checksum", "after_member_checksum", "before_construct_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_CHECKSUM")
	if String(value["before_member_checksum"]) == String(value["after_member_checksum"]): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_RECORD_NO_MEMBER_CHANGE")
	if not UtilsScript.is_json_integer(value.get("after_construct_revision")) or int(value["after_construct_revision"]) < 1: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_CONSTRUCT_REVISION")
	for field in ["before_item_revision", "after_item_revision"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_REVISION")
	if int(value["after_item_revision"]) != int(value["before_item_revision"]) + 1: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_RECORD_REVISION_CHAIN_MISMATCH")
	for field in ["before_state", "after_state"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_STATE")
		var checked := StateScript.validate(value[field]); if not bool(checked.get("success", false)): return checked
	if int(value["after_state"]["edit_revision"]) != int(value["before_state"]["edit_revision"]) + 1: return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_STATE_REVISION_CHAIN_MISMATCH")
	for field in ["mass_delta_kg", "volume_delta_m3"]:
		if typeof(value.get(field)) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(value[field])) or is_inf(float(value[field])): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_DELTA")
	if typeof(value.get("material_deltas")) != TYPE_ARRAY or value["material_deltas"] != _sorted_deltas(value["material_deltas"]): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_GEOMETRY_EDIT_MATERIAL_DELTAS")
	var previous := ""
	for delta in value["material_deltas"]:
		if typeof(delta) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_MATERIAL_DELTA")
		var checked := UtilsScript.validate_exact_fields(delta, MATERIAL_DELTA_FIELDS); if not bool(checked.get("success", false)): return checked
		var material_id := String(delta.get("material_id", "")); if not ParametricUtils.path_id(material_id, "material/") or (not previous.is_empty() and material_id <= previous): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_MATERIAL_DELTA_ORDER")
		for field in ["before_mass_kg", "after_mass_kg", "delta_mass_kg"]:
			if typeof(delta.get(field)) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(delta[field])) or is_inf(float(delta[field])): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_MATERIAL_DELTA")
		if not ParametricUtils.nearly_equal(float(delta["after_mass_kg"]) - float(delta["before_mass_kg"]), float(delta["delta_mass_kg"])): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_MATERIAL_DELTA_MISMATCH")
		previous = material_id
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_RECORD_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_RECORD_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted_deltas(values: Array) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a,b): return String(a.get("material_id", "")) < String(b.get("material_id", ""))); return output

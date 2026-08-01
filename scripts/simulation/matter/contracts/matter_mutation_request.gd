extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const AddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")

const SCHEMA: String = "planet_simulator.matter_mutation_request.v1"
const OPERATION_TYPES: Array[String] = ["EXCAVATE", "DEPOSIT", "FRACTURE", "COMPACT", "MELT", "FREEZE"]
const SHAPE_KINDS: Array[String] = ["SPHERE", "CAPSULE", "BOX"]
const FIELDS: Array[String] = [
	"schema",
	"operation_id",
	"body_id",
	"actor_id",
	"tool_id",
	"operation_type",
	"target_bricks",
	"expected_revisions",
	"shape",
	"source_container_id",
	"destination_container_id",
	"requested_mass_kg",
	"energy_budget_j",
	"client_tick",
	"checksum",
]
const SHAPE_FIELDS: Array[String] = [
	"kind", "start_position_m", "end_position_m", "radius_m", "half_extents_m",
]


static func create(data: Dictionary) -> Dictionary:
	var target_bricks: Array = Array(data.get("target_bricks", [])).duplicate(true)
	target_bricks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("address_id", "")) < String(b.get("address_id", ""))
	)
	var expected_by_address: Dictionary = Dictionary(data.get("expected_revision_by_address", {}))
	var expected_revisions: Array = []
	for address in target_bricks:
		expected_revisions.append(int(expected_by_address.get(String(address.get("address_id", "")), 0)))
	var value: Dictionary = {
		"schema": SCHEMA,
		"operation_id": String(data.get("operation_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"actor_id": String(data.get("actor_id", "")).strip_edges().to_lower(),
		"tool_id": String(data.get("tool_id", "")).strip_edges().to_lower(),
		"operation_type": String(data.get("operation_type", "")).strip_edges().to_upper(),
		"target_bricks": target_bricks,
		"expected_revisions": expected_revisions,
		"shape": Dictionary(data.get("shape", {})).duplicate(true),
		"source_container_id": String(data.get("source_container_id", "")).strip_edges().to_lower(),
		"destination_container_id": String(data.get("destination_container_id", "")).strip_edges().to_lower(),
		"requested_mass_kg": float(data.get("requested_mass_kg", 0.0)),
		"energy_budget_j": float(data.get("energy_budget_j", 0.0)),
		"client_tick": int(data.get("client_tick", 0)),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func create_shape(
	kind: String,
	start_position_m: Array,
	end_position_m: Array,
	radius_m: float = 0.0,
	half_extents_m: Array = [0.0, 0.0, 0.0]
) -> Dictionary:
	return {
		"kind": kind.strip_edges().to_upper(),
		"start_position_m": start_position_m.duplicate(),
		"end_position_m": end_position_m.duplicate(),
		"radius_m": radius_m,
		"half_extents_m": half_extents_m.duplicate(),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_MUTATION_REQUEST_SCHEMA")
	for field in ["operation_id", "body_id", "actor_id", "tool_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_ID", {"field": field})
	if typeof(value.get("operation_type")) != TYPE_STRING or not String(value["operation_type"]) in OPERATION_TYPES:
		return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_TYPE")
	if typeof(value.get("target_bricks")) != TYPE_ARRAY or value["target_bricks"].is_empty():
		return MatterUtilsScript.failure("EMPTY_MATTER_MUTATION_TARGETS")
	if typeof(value.get("expected_revisions")) != TYPE_ARRAY \
		or value["expected_revisions"].size() != value["target_bricks"].size():
		return MatterUtilsScript.failure("MATTER_EXPECTED_REVISION_SIZE_MISMATCH")
	var previous_address_id: String = ""
	for index in range(value["target_bricks"].size()):
		var address = value["target_bricks"][index]
		if typeof(address) != TYPE_DICTIONARY or not bool(AddressScript.validate(address).get("success", false)):
			return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_TARGET", {"index": index})
		var address_id: String = String(address["address_id"])
		if index > 0 and address_id <= previous_address_id:
			return MatterUtilsScript.failure("MATTER_MUTATION_TARGETS_NOT_SORTED_UNIQUE", {"index": index})
		var expected_revision = value["expected_revisions"][index]
		if not MatterUtilsScript.is_json_integer(expected_revision) or int(expected_revision) < 0:
			return MatterUtilsScript.failure("INVALID_MATTER_EXPECTED_REVISION", {"index": index})
		previous_address_id = address_id
	var shape_result: Dictionary = _validate_shape(value.get("shape"))
	if not bool(shape_result.get("success", false)):
		return shape_result
	for field in ["source_container_id", "destination_container_id"]:
		if typeof(value.get(field)) != TYPE_STRING:
			return MatterUtilsScript.failure("INVALID_MATTER_CONTAINER_ID", {"field": field})
		if not String(value[field]).is_empty() and not MatterUtilsScript.is_canonical_id(value[field], 2):
			return MatterUtilsScript.failure("INVALID_MATTER_CONTAINER_ID", {"field": field})
	for field in ["requested_mass_kg", "energy_budget_j"]:
		if not MatterUtilsScript.is_non_negative_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_QUANTITY", {"field": field})
	if not MatterUtilsScript.is_json_integer(value.get("client_tick")) or int(value["client_tick"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_CLIENT_TICK")
	if String(value["operation_type"]) == "DEPOSIT":
		if float(value["requested_mass_kg"]) <= 0.0 or String(value["source_container_id"]).is_empty():
			return MatterUtilsScript.failure("DEPOSIT_REQUIRES_SOURCE_MASS")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_mutation_request")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)


static func validate_shape(shape) -> Dictionary:
	return _validate_shape(shape)


static func _validate_shape(shape) -> Dictionary:
	if typeof(shape) != TYPE_DICTIONARY:
		return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_SHAPE")
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(shape, SHAPE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	var kind: String = String(shape.get("kind", ""))
	if not kind in SHAPE_KINDS:
		return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_SHAPE_KIND")
	for field in ["start_position_m", "end_position_m", "half_extents_m"]:
		if not MatterUtilsScript.is_vector3_array(shape.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_VECTOR", {"field": field})
	if not MatterUtilsScript.is_non_negative_number(shape.get("radius_m")):
		return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_RADIUS")
	var half_extents: Array = shape["half_extents_m"]
	if kind in ["SPHERE", "CAPSULE"] and float(shape["radius_m"]) <= 0.0:
		return MatterUtilsScript.failure("MISSING_MATTER_MUTATION_RADIUS")
	if kind == "BOX":
		for extent in half_extents:
			if float(extent) <= 0.0:
				return MatterUtilsScript.failure("INVALID_MATTER_MUTATION_HALF_EXTENTS")
	return MatterUtilsScript.success()

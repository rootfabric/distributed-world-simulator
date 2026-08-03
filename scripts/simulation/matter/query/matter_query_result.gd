extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CellAddressScript = preload("res://scripts/simulation/spatial/simulation_cell_address.gd")
const BrickAddressScript = preload("res://scripts/simulation/matter/contracts/matter_brick_address.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")

const SCHEMA: String = "planet_simulator.matter_query_result.v1"
const SOURCES: Array[String] = ["PROCEDURAL_BASE", "MATERIALIZED_BRICK"]
const FIELDS: Array[String] = [
	"schema",
	"query_id",
	"body_id",
	"body_frame_id",
	"body_definition_hash",
	"grid_profile_hash",
	"generator_version",
	"generator_seed",
	"local_position_m",
	"requested_level",
	"source",
	"cell_address",
	"brick_address",
	"sample_lattice_index",
	"state_revision",
	"sample",
	"checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var position: Vector3 = data.get("local_position_m", Vector3.ZERO)
	var value: Dictionary = {
		"schema": SCHEMA,
		"query_id": String(data.get("query_id", "")).strip_edges().to_lower(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_frame_id": String(data.get("body_frame_id", "")).strip_edges().to_lower(),
		"body_definition_hash": String(data.get("body_definition_hash", "")).strip_edges().to_lower(),
		"grid_profile_hash": String(data.get("grid_profile_hash", "")).strip_edges().to_lower(),
		"generator_version": String(data.get("generator_version", "")).strip_edges(),
		"generator_seed": int(data.get("generator_seed", 0)),
		"local_position_m": [position.x, position.y, position.z],
		"requested_level": int(data.get("requested_level", -1)),
		"source": String(data.get("source", "")).strip_edges().to_upper(),
		"cell_address": Dictionary(data.get("cell_address", {})).duplicate(true),
		"brick_address": Dictionary(data.get("brick_address", {})).duplicate(true),
		"sample_lattice_index": Array(data.get("sample_lattice_index", [-1, -1, -1])).duplicate(),
		"state_revision": int(data.get("state_revision", 0)),
		"sample": Dictionary(data.get("sample", {})).duplicate(true),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_QUERY_RESULT_SCHEMA")
	for field in ["query_id", "body_id", "body_frame_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_QUERY_ID", {"field": field})
	for field in ["body_definition_hash", "grid_profile_hash"]:
		if not MatterUtilsScript.is_lower_hex_64(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_QUERY_HASH", {"field": field})
	if not MatterUtilsScript.is_semantic_version(value.get("generator_version")):
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_GENERATOR_VERSION")
	if not MatterUtilsScript.is_json_integer(value.get("generator_seed")):
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_GENERATOR_SEED")
	if not MatterUtilsScript.is_vector3_array(value.get("local_position_m")):
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_POSITION")
	if not MatterUtilsScript.is_json_integer(value.get("requested_level")) \
		or int(value["requested_level"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_LEVEL")
	if typeof(value.get("source")) != TYPE_STRING or not String(value["source"]) in SOURCES:
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_SOURCE")
	if typeof(value.get("cell_address")) != TYPE_DICTIONARY \
		or not bool(CellAddressScript.validate(value["cell_address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_CELL")
	if typeof(value.get("brick_address")) != TYPE_DICTIONARY \
		or not bool(BrickAddressScript.validate(value["brick_address"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_BRICK")
	if int(value["cell_address"]["level"]) != int(value["requested_level"]):
		return MatterUtilsScript.failure("MATTER_QUERY_LEVEL_CELL_MISMATCH")
	if value["brick_address"]["cell_address"] != value["cell_address"]:
		return MatterUtilsScript.failure("MATTER_QUERY_CELL_BRICK_MISMATCH")
	if int(value["brick_address"]["storage_level"]) != int(value["requested_level"]):
		return MatterUtilsScript.failure("MATTER_QUERY_LEVEL_BRICK_MISMATCH")
	if typeof(value.get("sample_lattice_index")) != TYPE_ARRAY \
		or value["sample_lattice_index"].size() != 3:
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_LATTICE_INDEX")
	for component in value["sample_lattice_index"]:
		if not MatterUtilsScript.is_json_integer(component) or int(component) < -1:
			return MatterUtilsScript.failure("INVALID_MATTER_QUERY_LATTICE_INDEX")
	if not MatterUtilsScript.is_json_integer(value.get("state_revision")) \
		or int(value["state_revision"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_REVISION")
	if typeof(value.get("sample")) != TYPE_DICTIONARY \
		or not bool(SampleScript.validate(value["sample"]).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_QUERY_SAMPLE")
	if String(value["source"]) == "PROCEDURAL_BASE":
		if value["sample_lattice_index"] != [-1, -1, -1] or int(value["state_revision"]) != 0:
			return MatterUtilsScript.failure("PROCEDURAL_QUERY_HAS_BRICK_STATE")
	else:
		for component in value["sample_lattice_index"]:
			if int(component) < 0:
				return MatterUtilsScript.failure("MATERIALIZED_QUERY_MISSING_LATTICE_INDEX")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_query_result")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)

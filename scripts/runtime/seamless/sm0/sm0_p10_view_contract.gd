extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "distributed_world_simulator.sm0_p10_projection_source.v1"
const AUTHORITIES: Array[String] = ["authority/sm0/a", "authority/sm0/b", "authority/sm0/c"]
const SOURCE_ROLES: Array[String] = ["LOCAL", "FOREIGN"]
const ENTITY_KINDS: Array[String] = ["PLAYER", "NPC", "VEHICLE", "ITEM", "DYNAMIC"]
const LODS: Array[String] = ["COARSE", "FINE"]

const REQUIRED_FIELDS: Array[String] = [
	"schema",
	"source_authority_id",
	"source_authority_epoch",
	"source_role",
	"projection_sequence",
	"generated_tick",
	"entities",
	"representations",
	"checksum",
]

static func create_snapshot(
	source_authority_id: String,
	source_authority_epoch: int,
	source_role: String,
	projection_sequence: int,
	generated_tick: int,
	entities: Array,
	representations: Array
) -> Dictionary:
	return Utils.finalize_json_checksum({
		"schema": SCHEMA,
		"source_authority_id": source_authority_id,
		"source_authority_epoch": source_authority_epoch,
		"source_role": source_role,
		"projection_sequence": projection_sequence,
		"generated_tick": generated_tick,
		"entities": entities.duplicate(true),
		"representations": representations.duplicate(true),
		"checksum": "",
	})

static func entity(
	entity_id: String,
	kind: String,
	position: Dictionary,
	priority: int,
	state_revision: int
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"kind": kind,
		"world_position": position.duplicate(true),
		"priority": priority,
		"state_revision": state_revision,
		"read_only": true,
	}

static func representation(
	representation_id: String,
	subject_id: String,
	lod: String,
	position: Dictionary,
	priority: int,
	byte_size: int,
	artifact_hash: String,
	ready: bool
) -> Dictionary:
	return {
		"representation_id": representation_id,
		"subject_id": subject_id,
		"lod": lod,
		"world_position": position.duplicate(true),
		"priority": priority,
		"byte_size": byte_size,
		"artifact_hash": artifact_hash,
		"ready": ready,
		"cacheable": true,
		"presentation_only": true,
	}

static func validate(snapshot: Dictionary) -> Dictionary:
	var fields: Dictionary = Utils.validate_exact_fields(snapshot, REQUIRED_FIELDS)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P10_FIELDS_INVALID", {"cause": fields})
	if String(snapshot.get("schema", "")) != SCHEMA:
		return _failure("SM0_P10_SCHEMA_INVALID")
	var authority_id := String(snapshot.get("source_authority_id", ""))
	if authority_id not in AUTHORITIES:
		return _failure("SM0_P10_SOURCE_AUTHORITY_INVALID")
	if not Utils.is_json_integer(snapshot.get("source_authority_epoch")) or int(snapshot.get("source_authority_epoch", 0)) < 1:
		return _failure("SM0_P10_SOURCE_EPOCH_INVALID")
	if String(snapshot.get("source_role", "")) not in SOURCE_ROLES:
		return _failure("SM0_P10_SOURCE_ROLE_INVALID")
	if not Utils.is_json_integer(snapshot.get("projection_sequence")) or int(snapshot.get("projection_sequence", 0)) < 1:
		return _failure("SM0_P10_SEQUENCE_INVALID")
	if not Utils.is_json_integer(snapshot.get("generated_tick")) or int(snapshot.get("generated_tick", -1)) < 0:
		return _failure("SM0_P10_TICK_INVALID")
	if not snapshot.get("entities") is Array:
		return _failure("SM0_P10_ENTITIES_INVALID")
	if not snapshot.get("representations") is Array:
		return _failure("SM0_P10_REPRESENTATIONS_INVALID")
	var entity_ids: Dictionary = {}
	for raw_entity in Array(snapshot.get("entities", [])):
		if not raw_entity is Dictionary:
			return _failure("SM0_P10_ENTITY_INVALID")
		var validation := _validate_entity(Dictionary(raw_entity))
		if not bool(validation.get("success", false)):
			return validation
		var entity_id := String(Dictionary(raw_entity).get("entity_id", ""))
		if entity_ids.has(entity_id):
			return _failure("SM0_P10_ENTITY_DUPLICATE", {"entity_id": entity_id})
		entity_ids[entity_id] = true
	var representation_ids: Dictionary = {}
	for raw_rep in Array(snapshot.get("representations", [])):
		if not raw_rep is Dictionary:
			return _failure("SM0_P10_REPRESENTATION_INVALID")
		var validation := _validate_representation(Dictionary(raw_rep))
		if not bool(validation.get("success", false)):
			return validation
		var representation_id := String(Dictionary(raw_rep).get("representation_id", ""))
		if representation_ids.has(representation_id):
			return _failure("SM0_P10_REPRESENTATION_DUPLICATE", {"representation_id": representation_id})
		representation_ids[representation_id] = true
	var expected_checksum := String(snapshot.get("checksum", ""))
	var payload := snapshot.duplicate(true)
	payload.erase("checksum")
	if expected_checksum.is_empty() or expected_checksum != Utils.payload_hash(payload):
		return _failure("SM0_P10_CHECKSUM_MISMATCH")
	return _success()

static func _validate_entity(value: Dictionary) -> Dictionary:
	var required: Array[String] = ["entity_id", "kind", "world_position", "priority", "state_revision", "read_only"]
	var fields: Dictionary = Utils.validate_exact_fields(value, required)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P10_ENTITY_FIELDS_INVALID")
	if String(value.get("entity_id", "")).strip_edges().is_empty():
		return _failure("SM0_P10_ENTITY_ID_REQUIRED")
	if String(value.get("kind", "")) not in ENTITY_KINDS:
		return _failure("SM0_P10_ENTITY_KIND_INVALID")
	if not _validate_vec3(value.get("world_position")):
		return _failure("SM0_P10_ENTITY_POSITION_INVALID")
	if not Utils.is_json_integer(value.get("priority")) or int(value.get("priority", -1)) < 0 or int(value.get("priority", 101)) > 100:
		return _failure("SM0_P10_ENTITY_PRIORITY_INVALID")
	if not Utils.is_json_integer(value.get("state_revision")) or int(value.get("state_revision", 0)) < 1:
		return _failure("SM0_P10_ENTITY_REVISION_INVALID")
	if value.get("read_only") != true:
		return _failure("SM0_P10_ENTITY_MUST_BE_READ_ONLY")
	return _success()

static func _validate_representation(value: Dictionary) -> Dictionary:
	var required: Array[String] = ["representation_id", "subject_id", "lod", "world_position", "priority", "byte_size", "artifact_hash", "ready", "cacheable", "presentation_only"]
	var fields: Dictionary = Utils.validate_exact_fields(value, required)
	if not bool(fields.get("success", false)):
		return _failure("SM0_P10_REPRESENTATION_FIELDS_INVALID")
	if String(value.get("representation_id", "")).strip_edges().is_empty() or String(value.get("subject_id", "")).strip_edges().is_empty():
		return _failure("SM0_P10_REPRESENTATION_ID_REQUIRED")
	if String(value.get("lod", "")) not in LODS:
		return _failure("SM0_P10_REPRESENTATION_LOD_INVALID")
	if not _validate_vec3(value.get("world_position")):
		return _failure("SM0_P10_REPRESENTATION_POSITION_INVALID")
	if not Utils.is_json_integer(value.get("priority")) or int(value.get("priority", -1)) < 0 or int(value.get("priority", 101)) > 100:
		return _failure("SM0_P10_REPRESENTATION_PRIORITY_INVALID")
	if not Utils.is_json_integer(value.get("byte_size")) or int(value.get("byte_size", 0)) < 1:
		return _failure("SM0_P10_REPRESENTATION_BYTES_INVALID")
	if String(value.get("artifact_hash", "")).length() < 8:
		return _failure("SM0_P10_REPRESENTATION_HASH_INVALID")
	if typeof(value.get("ready")) != TYPE_BOOL or value.get("cacheable") != true or value.get("presentation_only") != true:
		return _failure("SM0_P10_REPRESENTATION_PRESENTATION_CONTRACT_INVALID")
	return _success()

static func distance_m(a: Dictionary, b: Dictionary) -> float:
	var dx := float(a.get("x", 0.0)) - float(b.get("x", 0.0))
	var dy := float(a.get("y", 0.0)) - float(b.get("y", 0.0))
	var dz := float(a.get("z", 0.0)) - float(b.get("z", 0.0))
	return sqrt(dx * dx + dy * dy + dz * dz)

static func _validate_vec3(raw) -> bool:
	if not raw is Dictionary:
		return false
	var value := Dictionary(raw)
	for axis in ["x", "y", "z"]:
		if not value.has(axis) or typeof(value.get(axis)) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var component := float(value.get(axis, 0.0))
		if is_nan(component) or is_inf(component):
			return false
	return true

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}
static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
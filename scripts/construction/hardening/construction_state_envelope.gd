extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const ContractUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const LEGACY_SCHEMA := "planet_simulator.construction_production_state.v1"
const CURRENT_SCHEMA := "planet_simulator.construction_production_state.v2"
const CURRENT_VERSION := 2
const LEGACY_FIELDS: Array[String] = ["schema", "state_version", "payload", "payload_checksum", "checksum"]
const CURRENT_FIELDS: Array[String] = [
	"schema", "state_version", "release_id", "compatible_reader_min",
	"compatible_reader_max", "created_tick", "payload", "payload_checksum", "checksum",
]

static func create(payload: Dictionary, release_id: String, created_tick: int, reader_min: int = 1, reader_max: int = CURRENT_VERSION) -> Dictionary:
	var envelope := {
		"schema": CURRENT_SCHEMA,
		"state_version": CURRENT_VERSION,
		"release_id": release_id,
		"compatible_reader_min": reader_min,
		"compatible_reader_max": reader_max,
		"created_tick": created_tick,
		"payload": payload.duplicate(true),
		"payload_checksum": ContractUtils.payload_hash(payload),
		"checksum": "",
	}
	envelope["checksum"] = H.checksum(envelope)
	return envelope

static func create_legacy(payload: Dictionary) -> Dictionary:
	var envelope := {
		"schema": LEGACY_SCHEMA,
		"state_version": 1,
		"payload": payload.duplicate(true),
		"payload_checksum": ContractUtils.payload_hash(payload),
		"checksum": "",
	}
	envelope["checksum"] = H.checksum(envelope)
	return envelope

static func validate(envelope: Dictionary, reader_version: int = CURRENT_VERSION) -> Dictionary:
	var version := int(envelope.get("state_version", 0))
	if version == 1:
		return _validate_legacy(envelope)
	if version != CURRENT_VERSION:
		return H.failure("UNSUPPORTED_CONSTRUCTION_PRODUCTION_STATE_VERSION")
	var exact := H.exact_fields(envelope, CURRENT_FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_STATE_FIELDS")
	if envelope.get("schema") != CURRENT_SCHEMA:
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_STATE_SCHEMA")
	if not H.is_path_id(envelope.get("release_id"), "release/"):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_STATE_RELEASE")
	if not H.is_positive_integer(envelope.get("compatible_reader_min")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_READER_RANGE")
	if not H.is_positive_integer(envelope.get("compatible_reader_max")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_READER_RANGE")
	var minimum := int(envelope["compatible_reader_min"])
	var maximum := int(envelope["compatible_reader_max"])
	if minimum > maximum or reader_version < minimum or reader_version > maximum:
		return H.failure("INCOMPATIBLE_CONSTRUCTION_PRODUCTION_READER")
	if not H.is_non_negative_integer(envelope.get("created_tick")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_STATE_TICK")
	return _validate_payload_and_checksum(envelope)

static func migrate(envelope: Dictionary, release_id: String, created_tick: int) -> Dictionary:
	var checked := validate(envelope, 1 if int(envelope.get("state_version", 0)) == 1 else CURRENT_VERSION)
	if not bool(checked.get("success", false)):
		return checked
	if int(envelope["state_version"]) == CURRENT_VERSION:
		return H.success({"envelope": envelope.duplicate(true), "migration_trace": []})
	var migrated := create(Dictionary(envelope["payload"]), release_id, created_tick, 1, CURRENT_VERSION)
	return H.success({
		"envelope": migrated,
		"migration_trace": [{"from_version": 1, "to_version": CURRENT_VERSION}],
	})

static func _validate_legacy(envelope: Dictionary) -> Dictionary:
	var exact := H.exact_fields(envelope, LEGACY_FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_LEGACY_CONSTRUCTION_PRODUCTION_STATE_FIELDS")
	if envelope.get("schema") != LEGACY_SCHEMA or not H.is_positive_integer(envelope.get("state_version")) or int(envelope["state_version"]) != 1:
		return H.failure("INVALID_LEGACY_CONSTRUCTION_PRODUCTION_STATE_SCHEMA")
	return _validate_payload_and_checksum(envelope)

static func _validate_payload_and_checksum(envelope: Dictionary) -> Dictionary:
	if typeof(envelope.get("payload")) != TYPE_DICTIONARY:
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_STATE_PAYLOAD")
	var payload_hash := ContractUtils.payload_hash(envelope["payload"])
	if payload_hash.is_empty() or String(envelope.get("payload_checksum", "")) != payload_hash:
		return H.failure("CONSTRUCTION_PRODUCTION_STATE_PAYLOAD_CHECKSUM_MISMATCH")
	return H.validate_checksum(envelope, "CONSTRUCTION_PRODUCTION_STATE_CHECKSUM_MISMATCH")

extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const ContractUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_production_operation.v1"
const VERSION := 1
const FIELDS: Array[String] = [
	"schema", "operation_id", "subject_id", "construct_id", "action",
	"permission_epoch", "release_id", "operation_version", "tick", "payload",
	"payload_checksum", "checksum",
]

static func create(
	operation_id: String,
	subject_id: String,
	construct_id: String,
	action: String,
	permission_epoch: int,
	release_id: String,
	tick: int,
	payload: Dictionary = {}
) -> Dictionary:
	var operation := {
		"schema": SCHEMA,
		"operation_id": operation_id,
		"subject_id": subject_id,
		"construct_id": construct_id,
		"action": action,
		"permission_epoch": permission_epoch,
		"release_id": release_id,
		"operation_version": VERSION,
		"tick": tick,
		"payload": payload.duplicate(true),
		"payload_checksum": ContractUtils.payload_hash(payload),
		"checksum": "",
	}
	operation["checksum"] = H.checksum(operation)
	return operation

static func validate(operation: Dictionary) -> Dictionary:
	var exact := H.exact_fields(operation, FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_OPERATION_FIELDS")
	if operation.get("schema") != SCHEMA:
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_OPERATION_SCHEMA")
	if not H.is_path_id(operation.get("operation_id"), "operation/"):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_OPERATION_ID")
	if not H.is_path_id(operation.get("subject_id"), "subject/"):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_SUBJECT_ID")
	if not H.is_path_id(operation.get("construct_id"), "construct/"):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_CONSTRUCT_ID")
	if not H.is_token(operation.get("action")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_ACTION")
	if not H.is_non_negative_integer(operation.get("permission_epoch")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_PERMISSION_EPOCH")
	if not H.is_path_id(operation.get("release_id"), "release/"):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_RELEASE_ID")
	if int(operation.get("operation_version", 0)) != VERSION:
		return H.failure("UNSUPPORTED_CONSTRUCTION_PRODUCTION_OPERATION_VERSION")
	if not H.is_non_negative_integer(operation.get("tick")):
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_TICK")
	if typeof(operation.get("payload")) != TYPE_DICTIONARY:
		return H.failure("INVALID_CONSTRUCTION_PRODUCTION_PAYLOAD")
	var payload_hash := ContractUtils.payload_hash(operation["payload"])
	if payload_hash.is_empty() or String(operation.get("payload_checksum", "")) != payload_hash:
		return H.failure("CONSTRUCTION_PRODUCTION_PAYLOAD_CHECKSUM_MISMATCH")
	return H.validate_checksum(operation, "CONSTRUCTION_PRODUCTION_OPERATION_CHECKSUM_MISMATCH")

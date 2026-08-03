extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const Stage = preload("res://scripts/simulation/representation/network/contracts/representation_stream_stage.gd")

const SCHEMA := "planet_simulator.representation_stream_plan.v1"
const FIELDS: Array[String] = [
	"schema",
	"stream_id",
	"stream_request_id",
	"interest_request_id",
	"request_revision",
	"source_revision_checksum",
	"stages",
	"final_stage_index",
	"total_transfer_bytes",
	"created_tick",
	"expires_tick",
	"checksum",
]


static func create(
	stream_id: String,
	stream_request_id: String,
	interest_request_id: String,
	request_revision: int,
	source_revision_checksum: String,
	stages: Array,
	created_tick: int,
	expires_tick: int
) -> Dictionary:
	var total_transfer_bytes: int = 0
	for raw_stage in stages:
		if typeof(raw_stage) == TYPE_DICTIONARY:
			total_transfer_bytes += int(raw_stage.get("transfer_bytes", 0))
	var value: Dictionary = {
		"schema": SCHEMA,
		"stream_id": stream_id,
		"stream_request_id": stream_request_id,
		"interest_request_id": interest_request_id,
		"request_revision": request_revision,
		"source_revision_checksum": source_revision_checksum,
		"stages": stages.duplicate(true),
		"final_stage_index": stages.size() - 1,
		"total_transfer_bytes": total_transfer_bytes,
		"created_tick": created_tick,
		"expires_tick": expires_tick,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_PLAN_SCHEMA")
	if not Utils.is_canonical_id(value.get("stream_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_ID")
	if not Utils.is_canonical_id(value.get("stream_request_id"), 2) or not Utils.is_canonical_id(value.get("interest_request_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_PLAN_REQUEST_ID")
	if not Utils.is_json_integer(value.get("request_revision")) or int(value["request_revision"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_PLAN_REVISION")
	if not Utils.is_lower_hex_64(value.get("source_revision_checksum")):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_SOURCE_CHECKSUM")
	if typeof(value.get("stages")) != TYPE_ARRAY or value["stages"].is_empty() or value["stages"].size() > 8:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_STAGES")
	var total_transfer_bytes: int = 0
	var previous_lod: int = 2147483647
	var hashes: Dictionary = {}
	for index in range(value["stages"].size()):
		if typeof(value["stages"][index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_REPRESENTATION_STREAM_STAGE", {"index": index})
		var stage: Dictionary = value["stages"][index]
		checked = Stage.validate(stage)
		if not bool(checked.get("success", false)):
			return checked
		if int(stage["stage_index"]) != index:
			return Utils.failure("REPRESENTATION_STREAM_STAGE_INDEX_GAP", {"index": index})
		var manifest: Dictionary = stage["artifact_manifest"]
		var source_checksum: String = String(manifest["representation_key"]["source_revision"].get("checksum", ""))
		if source_checksum != String(value["source_revision_checksum"]):
			return Utils.failure("REPRESENTATION_STREAM_STAGE_SOURCE_MISMATCH", {"index": index})
		var lod: int = int(manifest["representation_key"]["lod_level"])
		if index > 0 and lod >= previous_lod:
			return Utils.failure("REPRESENTATION_STREAM_STAGES_NOT_COARSE_TO_FINE", {"index": index})
		previous_lod = lod
		var artifact_hash: String = String(manifest["artifact_hash"])
		if hashes.has(artifact_hash):
			return Utils.failure("REPRESENTATION_STREAM_DUPLICATE_ARTIFACT", {"index": index})
		hashes[artifact_hash] = true
		total_transfer_bytes += int(stage["transfer_bytes"])
	if not Utils.is_json_integer(value.get("final_stage_index")) or int(value["final_stage_index"]) != value["stages"].size() - 1:
		return Utils.failure("INVALID_REPRESENTATION_FINAL_STAGE_INDEX")
	if not Utils.is_json_integer(value.get("total_transfer_bytes")) or int(value["total_transfer_bytes"]) != total_transfer_bytes:
		return Utils.failure("REPRESENTATION_STREAM_TOTAL_TRANSFER_MISMATCH")
	if not Utils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CREATED_TICK")
	if not Utils.is_json_integer(value.get("expires_tick")) or int(value["expires_tick"]) <= int(value["created_tick"]):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_EXPIRY")
	return Utils.validate_checksum(value)

extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")

const SCHEMA := "planet_simulator.representation_stream_stage.v1"
const DELIVERY_MODES: Array[String] = ["CACHE_HIT", "TRANSFER"]
const FIELDS: Array[String] = [
	"schema",
	"stage_index",
	"artifact_manifest",
	"delivery_mode",
	"chunk_size_bytes",
	"total_chunks",
	"transfer_bytes",
	"checksum",
]


static func create(
	stage_index: int,
	artifact_manifest: Dictionary,
	delivery_mode: String,
	chunk_size_bytes: int
) -> Dictionary:
	var byte_size: int = int(artifact_manifest.get("byte_size", 0))
	var transfer_bytes: int = 0 if delivery_mode == "CACHE_HIT" else byte_size
	var total_chunks: int = 0
	if delivery_mode == "TRANSFER" and chunk_size_bytes > 0:
		total_chunks = int(ceili(float(byte_size) / float(chunk_size_bytes)))
	var value: Dictionary = {
		"schema": SCHEMA,
		"stage_index": stage_index,
		"artifact_manifest": artifact_manifest.duplicate(true),
		"delivery_mode": delivery_mode,
		"chunk_size_bytes": chunk_size_bytes,
		"total_chunks": total_chunks,
		"transfer_bytes": transfer_bytes,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_STAGE_SCHEMA")
	if not Utils.is_json_integer(value.get("stage_index")) or int(value["stage_index"]) < 0 or int(value["stage_index"]) > 7:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_STAGE_INDEX")
	if typeof(value.get("artifact_manifest")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_STAGE_MANIFEST")
	checked = ArtifactManifest.validate(value["artifact_manifest"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("delivery_mode")) != TYPE_STRING or not DELIVERY_MODES.has(String(value["delivery_mode"])):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_DELIVERY_MODE")
	if not Utils.is_json_integer(value.get("chunk_size_bytes")) or int(value["chunk_size_bytes"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_SIZE")
	if not Utils.is_json_integer(value.get("total_chunks")) or int(value["total_chunks"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_COUNT")
	if not Utils.is_json_integer(value.get("transfer_bytes")) or int(value["transfer_bytes"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_TRANSFER_BYTES")
	var byte_size: int = int(value["artifact_manifest"]["byte_size"])
	if String(value["delivery_mode"]) == "CACHE_HIT":
		if int(value["chunk_size_bytes"]) != 0 or int(value["total_chunks"]) != 0 or int(value["transfer_bytes"]) != 0:
			return Utils.failure("REPRESENTATION_CACHE_HIT_STAGE_HAS_TRANSFER")
	else:
		var chunk_size: int = int(value["chunk_size_bytes"])
		if chunk_size < 32 or chunk_size > 1048576:
			return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_SIZE")
		if int(value["transfer_bytes"]) != byte_size:
			return Utils.failure("REPRESENTATION_STREAM_TRANSFER_SIZE_MISMATCH")
		var expected_chunks: int = int(ceili(float(byte_size) / float(chunk_size)))
		if int(value["total_chunks"]) != expected_chunks:
			return Utils.failure("REPRESENTATION_STREAM_CHUNK_COUNT_MISMATCH")
	return Utils.validate_checksum(value)

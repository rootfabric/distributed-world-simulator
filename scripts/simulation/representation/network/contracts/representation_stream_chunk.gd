extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const BusUtils = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.representation_stream_chunk.v1"
const FIELDS: Array[String] = [
	"schema",
	"stream_id",
	"stream_request_id",
	"request_revision",
	"stage_index",
	"artifact_hash",
	"manifest_checksum",
	"chunk_index",
	"offset_bytes",
	"content_base64",
	"content_hash",
	"chunk_size_bytes",
	"final_chunk",
	"checksum",
]


static func create(
	stream_id: String,
	stream_request_id: String,
	request_revision: int,
	stage_index: int,
	artifact_hash: String,
	manifest_checksum: String,
	chunk_index: int,
	offset_bytes: int,
	content: PackedByteArray,
	final_chunk: bool
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"stream_id": stream_id,
		"stream_request_id": stream_request_id,
		"request_revision": request_revision,
		"stage_index": stage_index,
		"artifact_hash": artifact_hash,
		"manifest_checksum": manifest_checksum,
		"chunk_index": chunk_index,
		"offset_bytes": offset_bytes,
		"content_base64": Marshalls.raw_to_base64(content),
		"content_hash": BusUtils.content_hash_from_bytes(content),
		"chunk_size_bytes": content.size(),
		"final_chunk": final_chunk,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_CHUNK_SCHEMA")
	if not Utils.is_canonical_id(value.get("stream_id"), 2) or not Utils.is_canonical_id(value.get("stream_request_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_ID")
	if not Utils.is_json_integer(value.get("request_revision")) or int(value["request_revision"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_REVISION")
	for field in ["stage_index", "chunk_index", "offset_bytes", "chunk_size_bytes"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_POSITION")
	if int(value["chunk_size_bytes"]) < 1 or int(value["chunk_size_bytes"]) > 1048576:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_SIZE")
	if not Utils.is_lower_hex_64(value.get("artifact_hash")) or not Utils.is_lower_hex_64(value.get("manifest_checksum")) or not Utils.is_lower_hex_64(value.get("content_hash")):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_HASH")
	if typeof(value.get("content_base64")) != TYPE_STRING or typeof(value.get("final_chunk")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CHUNK_CONTENT")
	var bytes: PackedByteArray = Marshalls.base64_to_raw(String(value["content_base64"]))
	if Marshalls.raw_to_base64(bytes) != String(value["content_base64"]):
		return Utils.failure("NON_CANONICAL_REPRESENTATION_CHUNK_BASE64")
	if bytes.size() != int(value["chunk_size_bytes"]):
		return Utils.failure("REPRESENTATION_STREAM_CHUNK_SIZE_MISMATCH")
	if BusUtils.content_hash_from_bytes(bytes) != String(value["content_hash"]):
		return Utils.failure("REPRESENTATION_STREAM_CHUNK_HASH_MISMATCH")
	return Utils.validate_checksum(value)


static func content_bytes(value: Dictionary) -> PackedByteArray:
	if not bool(validate(value).get("success", false)):
		return PackedByteArray()
	return Marshalls.base64_to_raw(String(value["content_base64"]))

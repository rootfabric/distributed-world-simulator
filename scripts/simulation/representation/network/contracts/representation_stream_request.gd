extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const InterestRequest = preload("res://scripts/simulation/representation/contracts/representation_interest_request.gd")
const ScopeBinding = preload("res://scripts/simulation/representation/network/contracts/representation_stream_scope_binding.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")

const SCHEMA := "planet_simulator.representation_stream_request.v1"
const FIELDS: Array[String] = [
	"schema",
	"stream_request_id",
	"interest_request",
	"scope_chain",
	"cached_artifact_hashes",
	"supported_encodings",
	"progressive_loading",
	"maximum_bootstrap_screen_error_px",
	"maximum_stages",
	"maximum_chunk_bytes",
	"maximum_in_flight_bytes",
	"priority",
	"cancellation_generation",
	"checksum",
]


static func create(
	stream_request_id: String,
	interest_request: Dictionary,
	scope_chain: Array,
	cached_artifact_hashes: Array,
	supported_encodings: Array,
	progressive_loading: bool,
	maximum_bootstrap_screen_error_px: float,
	maximum_stages: int,
	maximum_chunk_bytes: int,
	maximum_in_flight_bytes: int,
	priority: int,
	cancellation_generation: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"stream_request_id": stream_request_id,
		"interest_request": interest_request.duplicate(true),
		"scope_chain": scope_chain.duplicate(true),
		"cached_artifact_hashes": cached_artifact_hashes.duplicate(true),
		"supported_encodings": supported_encodings.duplicate(true),
		"progressive_loading": progressive_loading,
		"maximum_bootstrap_screen_error_px": maximum_bootstrap_screen_error_px,
		"maximum_stages": maximum_stages,
		"maximum_chunk_bytes": maximum_chunk_bytes,
		"maximum_in_flight_bytes": maximum_in_flight_bytes,
		"priority": priority,
		"cancellation_generation": cancellation_generation,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_REQUEST_SCHEMA")
	if not Utils.is_canonical_id(value.get("stream_request_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_REQUEST_ID")
	if typeof(value.get("interest_request")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_INTEREST")
	checked = InterestRequest.validate(value["interest_request"])
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_scope_chain(value.get("scope_chain"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_hashes(value.get("cached_artifact_hashes"))
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_encodings(value.get("supported_encodings"))
	if not bool(checked.get("success", false)):
		return checked
	if typeof(value.get("progressive_loading")) != TYPE_BOOL:
		return Utils.failure("INVALID_REPRESENTATION_PROGRESSIVE_FLAG")
	if not Utils.is_positive_number(value.get("maximum_bootstrap_screen_error_px")):
		return Utils.failure("INVALID_REPRESENTATION_BOOTSTRAP_ERROR_BUDGET")
	if float(value["maximum_bootstrap_screen_error_px"]) < float(value["interest_request"]["maximum_screen_error_px"]):
		return Utils.failure("REPRESENTATION_BOOTSTRAP_BUDGET_BELOW_FINAL")
	if not Utils.is_json_integer(value.get("maximum_stages")) or int(value["maximum_stages"]) < 1 or int(value["maximum_stages"]) > 8:
		return Utils.failure("INVALID_REPRESENTATION_MAXIMUM_STAGES")
	if not Utils.is_json_integer(value.get("maximum_chunk_bytes")) or int(value["maximum_chunk_bytes"]) < 32 or int(value["maximum_chunk_bytes"]) > 1048576:
		return Utils.failure("INVALID_REPRESENTATION_CHUNK_BUDGET")
	if not Utils.is_json_integer(value.get("maximum_in_flight_bytes")) or int(value["maximum_in_flight_bytes"]) < int(value["maximum_chunk_bytes"]):
		return Utils.failure("INVALID_REPRESENTATION_IN_FLIGHT_BUDGET")
	if int(value["maximum_in_flight_bytes"]) > 67108864:
		return Utils.failure("INVALID_REPRESENTATION_IN_FLIGHT_BUDGET")
	if not Utils.is_json_integer(value.get("priority")) or int(value["priority"]) < 0 or int(value["priority"]) > 255:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_PRIORITY")
	if not Utils.is_json_integer(value.get("cancellation_generation")) or int(value["cancellation_generation"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_CANCELLATION_GENERATION")
	return Utils.validate_checksum(value)


static func _validate_scope_chain(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.is_empty() or value.size() > 8:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_SCOPE_CHAIN")
	var previous_lod: int = Utils.MAX_LOD_LEVEL + 1
	var scopes: Dictionary = {}
	for index in range(value.size()):
		if typeof(value[index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_REPRESENTATION_STREAM_SCOPE_BINDING", {"index": index})
		var checked: Dictionary = ScopeBinding.validate(value[index])
		if not bool(checked.get("success", false)):
			return checked
		var lod: int = int(value[index]["lod_level"])
		if lod >= previous_lod:
			return Utils.failure("REPRESENTATION_STREAM_SCOPE_CHAIN_NOT_COARSE_TO_FINE", {"index": index})
		previous_lod = lod
		var scope_id: String = String(value[index]["scope_id"])
		if scopes.has(scope_id):
			return Utils.failure("REPRESENTATION_STREAM_SCOPE_CHAIN_DUPLICATE_SCOPE", {"index": index})
		scopes[scope_id] = true
	return Utils.success()


static func _validate_hashes(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return Utils.failure("INVALID_REPRESENTATION_CACHE_HASHES")
	if value.size() > 4096:
		return Utils.failure("REPRESENTATION_CACHE_HASH_LIMIT_EXCEEDED")
	var previous: String = ""
	for index in range(value.size()):
		if not Utils.is_lower_hex_64(value[index]):
			return Utils.failure("INVALID_REPRESENTATION_CACHE_HASH", {"index": index})
		var current: String = String(value[index])
		if index > 0 and current <= previous:
			return Utils.failure("REPRESENTATION_CACHE_HASHES_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	return Utils.success()


static func _validate_encodings(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or value.is_empty():
		return Utils.failure("INVALID_REPRESENTATION_SUPPORTED_ENCODINGS")
	var previous: String = ""
	for index in range(value.size()):
		if typeof(value[index]) != TYPE_STRING or not ArtifactManifest.ENCODINGS.has(String(value[index])):
			return Utils.failure("INVALID_REPRESENTATION_SUPPORTED_ENCODING", {"index": index})
		var current: String = String(value[index])
		if index > 0 and current <= previous:
			return Utils.failure("REPRESENTATION_ENCODINGS_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	return Utils.success()

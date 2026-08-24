extends RefCounted

## P6 R3 read-only outpost projection.
##
## This object is NOT canonical gameplay state. It composes defensive snapshots
## produced by the existing gameplay owners (M4 Item Graph, P4 Construction,
## P5/resource gameplay and player state) for comparison/presentation only.
## Canonical mutations must go back through those owners.

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.p6_outpost_projection.v2"
const VERSION := 2
const REQUIRED_SOURCES: Array[String] = ["gameplay", "item_graph", "construction"]
const OPTIONAL_SOURCES: Array[String] = ["resource_mining"]
const ERR_PRIVATE_MUTATION := "P6_PRIVATE_CANONICAL_MUTATION_FORBIDDEN"

var _sources: Dictionary = {}
var _last_error_code: String = ""
var _projection_revision: int = 0
var _rejected_mutations: int = 0


func configure_from_canonical_sources(sources: Dictionary) -> Dictionary:
	var validation := _validate_sources(sources)
	if not bool(validation.get("success", false)):
		_last_error_code = String(validation.get("error_code", "INVALID_CANONICAL_SOURCES"))
		return validation
	_sources = NetworkUtils.json_round_trip(sources).get("value", {}).duplicate(true)
	_projection_revision += 1
	_last_error_code = ""
	return {
		"success": true,
		"details": {
			"projection_revision": _projection_revision,
			"checksum": compute_checksum(),
			"canonical_mutation_owner": "EXTERNAL",
		},
	}


func serialize() -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"version": VERSION,
		"projection_revision": _projection_revision,
		"sources": _sources.duplicate(true),
		"checksum": "",
	}
	return NetworkUtils.finalize_json_checksum(value)


func deserialize(data: Dictionary) -> bool:
	if String(data.get("schema", "")) != SCHEMA or int(data.get("version", 0)) != VERSION:
		_last_error_code = "PROJECTION_SCHEMA_MISMATCH"
		return false
	if typeof(data.get("sources")) != TYPE_DICTIONARY:
		_last_error_code = "INVALID_PROJECTION_SOURCES"
		return false
	if typeof(data.get("checksum")) != TYPE_STRING or String(data.get("checksum", "")) != _checksum(data):
		_last_error_code = "PROJECTION_CHECKSUM_MISMATCH"
		return false
	var validation := _validate_sources(Dictionary(data.get("sources", {})))
	if not bool(validation.get("success", false)):
		_last_error_code = String(validation.get("error_code", "INVALID_CANONICAL_SOURCES"))
		return false
	var round_trip := NetworkUtils.json_round_trip(data.get("sources", {}))
	if not bool(round_trip.get("success", false)):
		_last_error_code = "PROJECTION_NOT_JSON_SAFE"
		return false
	_sources = Dictionary(round_trip.get("value", {})).duplicate(true)
	_projection_revision = int(data.get("projection_revision", 0))
	_last_error_code = ""
	return true


func compute_checksum() -> String:
	return String(serialize().get("checksum", ""))


func get_source(source_name: String) -> Dictionary:
	var value: Variant = _sources.get(source_name, {})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func get_sources() -> Dictionary:
	return _sources.duplicate(true)


func is_configured() -> bool:
	return not _sources.is_empty()


## Compatibility fail-closed surface. P6 must never apply canonical deltas.
func apply_delta(_delta: Dictionary) -> bool:
	_rejected_mutations += 1
	_last_error_code = ERR_PRIVATE_MUTATION
	return false


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"projection_revision": _projection_revision,
		"source_names": _sources.keys(),
		"checksum": compute_checksum() if is_configured() else "",
		"canonical_mutation_owner": "EXTERNAL",
		"private_canonical_truth": false,
		"rejected_mutations": _rejected_mutations,
		"last_error_code": _last_error_code,
	}


func _validate_sources(sources: Dictionary) -> Dictionary:
	for required in REQUIRED_SOURCES:
		if not sources.has(required) or typeof(sources.get(required)) != TYPE_DICTIONARY:
			return {"success": false, "error_code": "CANONICAL_SOURCE_REQUIRED", "details": {"source": required}}
	for name_value in sources.keys():
		var name := String(name_value)
		if not REQUIRED_SOURCES.has(name) and not OPTIONAL_SOURCES.has(name):
			return {"success": false, "error_code": "UNKNOWN_PROJECTION_SOURCE", "details": {"source": name}}
		if typeof(sources[name_value]) != TYPE_DICTIONARY:
			return {"success": false, "error_code": "INVALID_PROJECTION_SOURCE", "details": {"source": name}}
	var safe := NetworkUtils.canonicalize(sources, "$.p6_outpost_projection")
	if not bool(safe.get("success", false)):
		return {"success": false, "error_code": "PROJECTION_NOT_JSON_SAFE", "details": {"message": String(safe.get("error", ""))}}
	return {"success": true, "details": {}}


static func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return NetworkUtils.payload_hash(payload)

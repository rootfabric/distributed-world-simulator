extends RefCounted

## EG2 world directory (stage stub): the ownership truth for "which authority
## currently serves a world". The gateway consumes it; it never becomes route
## cache truth.
##
## Endpoint discipline: this module returns IDENTIFIERS ONLY — authority_id,
## server_instance_id and catalog_revision. It has no host/port fields, accepts
## only canonical ids, and nothing that leaves it can be used as a connection
## endpoint. Outages are explicit: a marked-unavailable world resolves to
## DIRECTORY_UNAVAILABLE so callers degrade (WARM) instead of guessing.

const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.eg2_world_directory.v1"
const RESOLUTION_FIELDS: Array[String] = [
	"world_id",
	"authority_id",
	"server_instance_id",
	"catalog_revision",
]

var _worlds: Dictionary = {}
var _unavailable: Dictionary = {}
var _registration_counter: int = 0
var _counters := {
	"registrations": 0,
	"registrations_rejected": 0,
	"resolutions_ok": 0,
	"resolutions_unknown_world": 0,
	"resolutions_during_outage": 0,
}


func register_world(
		world_id: String,
		authority_id: String,
		server_instance_id: String,
		catalog_revision: int
) -> Dictionary:
	var id_check := _require_ids(world_id, authority_id, server_instance_id)
	if not bool(id_check.get("success", false)):
		_counters["registrations_rejected"] = int(_counters["registrations_rejected"]) + 1
		return id_check
	if not NetworkUtilsScript.is_json_integer(catalog_revision) or int(catalog_revision) < 1:
		_counters["registrations_rejected"] = int(_counters["registrations_rejected"]) + 1
		return _failure("INVALID_CATALOG_REVISION", {"catalog_revision": catalog_revision})
	var revision := int(catalog_revision)
	if _worlds.has(world_id):
		var existing: Dictionary = _worlds[world_id]
		var existing_revision := int(existing["catalog_revision"])
		if revision < existing_revision:
			_counters["registrations_rejected"] = int(_counters["registrations_rejected"]) + 1
			return _failure("CATALOG_REVISION_REGRESSION", {
				"world_id": world_id,
				"current_revision": existing_revision,
				"offered_revision": revision,
			})
		var same_content := String(existing["authority_id"]) == authority_id \
				and String(existing["server_instance_id"]) == server_instance_id
		if revision == existing_revision and not same_content:
			_counters["registrations_rejected"] = int(_counters["registrations_rejected"]) + 1
			return _failure("CATALOG_REVISION_CONFLICT", {"world_id": world_id})
		if revision == existing_revision and same_content:
			return _success({"changed": false, "catalog_revision": existing_revision})
	_registration_counter += 1
	_worlds[world_id] = {
		"world_id": world_id,
		"authority_id": authority_id,
		"server_instance_id": server_instance_id,
		"catalog_revision": revision,
		"registration_seq": _registration_counter,
	}
	_unavailable.erase(world_id)
	_counters["registrations"] = int(_counters["registrations"]) + 1
	return _success({"changed": true, "catalog_revision": revision})


## Resolve the CURRENT authority for a world. Identifiers only, never endpoints.
func resolve_current_authority(world_id: String) -> Dictionary:
	if not _worlds.has(world_id):
		_counters["resolutions_unknown_world"] = int(_counters["resolutions_unknown_world"]) + 1
		return _failure("UNKNOWN_WORLD", {"world_id": world_id})
	if bool(_unavailable.get(world_id, false)):
		_counters["resolutions_during_outage"] = int(_counters["resolutions_during_outage"]) + 1
		return _failure("DIRECTORY_UNAVAILABLE", {"world_id": world_id})
	var world: Dictionary = _worlds[world_id]
	_counters["resolutions_ok"] = int(_counters["resolutions_ok"]) + 1
	return _success({
		"world_id": String(world["world_id"]),
		"authority_id": String(world["authority_id"]),
		"server_instance_id": String(world["server_instance_id"]),
		"catalog_revision": int(world["catalog_revision"]),
	})


## Simulated directory outage; resolution degrades until set_available.
func set_unavailable(world_id: String) -> Dictionary:
	if not _worlds.has(world_id):
		return _failure("UNKNOWN_WORLD", {"world_id": world_id})
	_unavailable[world_id] = true
	return _success({"world_id": world_id, "unavailable": true})


func set_available(world_id: String) -> Dictionary:
	if not _worlds.has(world_id):
		return _failure("UNKNOWN_WORLD", {"world_id": world_id})
	_unavailable.erase(world_id)
	return _success({"world_id": world_id, "unavailable": false})


func is_available(world_id: String) -> bool:
	return _worlds.has(world_id) and not bool(_unavailable.get(world_id, false))


func get_report() -> Dictionary:
	var worlds: Array = []
	for world_value in _worlds.values():
		var world: Dictionary = world_value
		worlds.append({
			"world_id": String(world["world_id"]),
			"authority_id": String(world["authority_id"]),
			"server_instance_id": String(world["server_instance_id"]),
			"catalog_revision": int(world["catalog_revision"]),
			"available": not bool(_unavailable.get(String(world["world_id"]), false)),
		})
	return {
		"schema": SCHEMA,
		"counters": _counters.duplicate(true),
		"worlds": worlds,
	}


func _require_ids(world_id: String, authority_id: String, server_instance_id: String) -> Dictionary:
	for pair in [
		["world_id", world_id, "world"],
		["authority_id", authority_id, "authority"],
		["server_instance_id", server_instance_id, "server-instance"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(
				{String(pair[0]): pair[1]}, String(pair[0]), String(pair[2]))
		if not bool(check.get("success", false)):
			return _failure("INVALID_ID", {"field": String(pair[0])})
		if _looks_like_host_or_address(String(pair[1])):
			return _failure("ENDPOINT_LIKE_IDENTITY_REJECTED", {"field": String(pair[0])})
	return _success({})


## Endpoint-disclosure fence: identifiers that look like hosts, IP addresses or
## address:port pairs never enter (and therefore never leave) the directory.
func _looks_like_host_or_address(value: String) -> bool:
	if value.contains(":"):
		return true
	for raw_segment in value.split("/", false):
		var segment := String(raw_segment)
		if not segment.contains("."):
			continue
		var host_like := true
		for character in segment:
			if character != "." and (character < "0" or character > "9"):
				host_like = false
				break
		if host_like:
			return true
	return false


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

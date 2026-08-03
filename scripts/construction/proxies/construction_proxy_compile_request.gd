extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const RuntimeRequest = preload("res://scripts/construction/runtime_projection/construction_runtime_projection_request.gd")
const InteriorCell = preload("res://scripts/construction/proxies/construction_proxy_interior_cell.gd")
const Portal = preload("res://scripts/construction/proxies/construction_proxy_portal.gd")

const SCHEMA := "planet_simulator.construction_proxy_compile_request.v1"
const OWNER := "OWNER"
const READ_ONLY := "READ_ONLY"
const MODES: Array[String] = [OWNER, READ_ONLY]
const FIELDS: Array[String] = ["schema", "runtime_projection_request", "authority_epoch", "authority_mode", "compiler_node_id", "section_size_m", "local_distance_m", "section_distance_m", "shell_distance_m", "interior_cells", "portals", "checksum"]

static func create(runtime_projection_request: Dictionary, authority_epoch: int, authority_mode: String, compiler_node_id: String, section_size_m: float = 5.0, local_distance_m: float = 80.0, section_distance_m: float = 250.0, shell_distance_m: float = 1000.0, interior_cells: Array = [], portals: Array = []) -> Dictionary:
	var value := {"schema": SCHEMA, "runtime_projection_request": runtime_projection_request.duplicate(true), "authority_epoch": authority_epoch, "authority_mode": authority_mode, "compiler_node_id": compiler_node_id, "section_size_m": section_size_m, "local_distance_m": local_distance_m, "section_distance_m": section_distance_m, "shell_distance_m": shell_distance_m, "interior_cells": _sorted(interior_cells, "cell_id"), "portals": _sorted(portals, "portal_id"), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return C.failure("UNSUPPORTED_CONSTRUCTION_PROXY_COMPILE_REQUEST_SCHEMA")
	if typeof(value.get("runtime_projection_request")) != TYPE_DICTIONARY: return C.failure("INVALID_CONSTRUCTION_PROXY_RUNTIME_REQUEST")
	var runtime: Dictionary = value["runtime_projection_request"]
	if runtime.get("schema") != RuntimeRequest.SCHEMA or typeof(runtime.get("construct_snapshot")) != TYPE_DICTIONARY: return C.failure("INVALID_CONSTRUCTION_PROXY_RUNTIME_REQUEST")
	var snapshot: Dictionary = runtime["construct_snapshot"]
	if not C.path_id(String(snapshot.get("construct_id", "")), "construct/") or not C.path_id(String(snapshot.get("root_item_instance_id", "")), "item/") or not Utils.is_json_integer(snapshot.get("state_revision")) or int(snapshot["state_revision"]) < 0 or not C.hash64(String(snapshot.get("checksum", ""))): return C.failure("INVALID_CONSTRUCTION_PROXY_PINNED_SNAPSHOT")
	if not C.hash64(String(runtime.get("checksum", ""))) or not C.finite_vector(runtime.get("world_origin_m"), 3) or not C.finite_vector(runtime.get("world_rotation_quaternion"), 4): return C.failure("INVALID_CONSTRUCTION_PROXY_PINNED_RUNTIME_REQUEST")
	var checked: Dictionary = C.success()
	if not Utils.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1: return C.failure("INVALID_CONSTRUCTION_PROXY_AUTHORITY_EPOCH")
	if not MODES.has(String(value.get("authority_mode", ""))) or not C.path_id(String(value.get("compiler_node_id", "")), "server/"): return C.failure("INVALID_CONSTRUCTION_PROXY_COMPILER_AUTHORITY")
	for field in ["section_size_m", "local_distance_m", "section_distance_m", "shell_distance_m"]:
		if not C.finite_number(value.get(field)) or float(value[field]) <= 0.0: return C.failure("INVALID_CONSTRUCTION_PROXY_DISTANCE_POLICY")
	if not (float(value["local_distance_m"]) < float(value["section_distance_m"]) and float(value["section_distance_m"]) < float(value["shell_distance_m"])): return C.failure("NON_MONOTONIC_CONSTRUCTION_PROXY_DISTANCE_POLICY")
	if typeof(value.get("interior_cells")) != TYPE_ARRAY or typeof(value.get("portals")) != TYPE_ARRAY: return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_TOPOLOGY")
	var cell_ids := {}
	var previous := ""
	for cell in value["interior_cells"]:
		if typeof(cell) != TYPE_DICTIONARY: return C.failure("INVALID_CONSTRUCTION_PROXY_INTERIOR_CELL")
		checked = InteriorCell.validate(cell)
		if not bool(checked.get("success", false)): return checked
		var cell_id := String(cell["cell_id"])
		if cell_ids.has(cell_id) or (not previous.is_empty() and cell_id < previous): return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_INTERIOR_CELLS")
		cell_ids[cell_id] = true; previous = cell_id
	previous = ""
	for portal in value["portals"]:
		if typeof(portal) != TYPE_DICTIONARY: return C.failure("INVALID_CONSTRUCTION_PROXY_PORTAL")
		checked = Portal.validate(portal)
		if not bool(checked.get("success", false)): return checked
		if not cell_ids.has(String(portal["cell_a_id"])) or not cell_ids.has(String(portal["cell_b_id"])): return C.failure("CONSTRUCTION_PROXY_PORTAL_REFERENCES_UNKNOWN_CELL")
		var portal_id := String(portal["portal_id"])
		if not previous.is_empty() and portal_id < previous: return C.failure("NON_CANONICAL_CONSTRUCTION_PROXY_PORTALS")
		previous = portal_id
	if String(value.get("checksum", "")) != compute_checksum(value): return C.failure("CONSTRUCTION_PROXY_COMPILE_REQUEST_CHECKSUM_MISMATCH")
	return C.success()

static func compute_checksum(value: Dictionary) -> String:
	var runtime: Dictionary = value.get("runtime_projection_request", {})
	var snapshot: Dictionary = runtime.get("construct_snapshot", {})
	var compact := {
		"schema": value.get("schema"),
		"runtime_request_checksum": runtime.get("checksum", ""),
		"construct_id": snapshot.get("construct_id", ""),
		"root_item_instance_id": snapshot.get("root_item_instance_id", ""),
		"source_revision": snapshot.get("state_revision", -1),
		"source_checksum": snapshot.get("checksum", ""),
		"world_origin_m": runtime.get("world_origin_m", []),
		"world_rotation_quaternion": runtime.get("world_rotation_quaternion", []),
		"authority_epoch": value.get("authority_epoch"),
		"authority_mode": value.get("authority_mode"),
		"compiler_node_id": value.get("compiler_node_id"),
		"section_size_m": value.get("section_size_m"),
		"local_distance_m": value.get("local_distance_m"),
		"section_distance_m": value.get("section_distance_m"),
		"shell_distance_m": value.get("shell_distance_m"),
		"interior_cells": value.get("interior_cells", []),
		"portals": value.get("portals", []),
	}
	return Utils.payload_hash(compact)
static func _sorted(values: Array, field: String) -> Array:
	var result := values.duplicate(true)
	result.sort_custom(func(a, b): return String(a.get(field, "")) < String(b.get(field, "")))
	return result

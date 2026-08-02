extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")

var _artifacts: Dictionary = {}
var _operations: Dictionary = {}
var _generation := 0

func publish(artifact: Dictionary, operation_id: String = "") -> Dictionary:
	var checked := Artifact.validate(artifact)
	if not bool(checked.get("success", false)): return checked
	var op_checksum := String(artifact["content_hash"])
	if not operation_id.is_empty():
		if not C.path_id(operation_id, "operation/"): return C.failure("INVALID_CONSTRUCTION_PROXY_CACHE_OPERATION_ID")
		if _operations.has(operation_id):
			var existing: Dictionary = _operations[operation_id]
			if String(existing["payload_checksum"]) != op_checksum: return C.failure("CONSTRUCTION_PROXY_CACHE_OPERATION_ID_CONFLICT")
			return C.success({"replay": true, "artifact_id": String(existing["artifact_id"]), "generation": _generation})
	var artifact_id := String(artifact["artifact_id"])
	if _artifacts.has(artifact_id):
		if String(_artifacts[artifact_id]["content_hash"]) != String(artifact["content_hash"]): return C.failure("CONSTRUCTION_PROXY_CACHE_CONTENT_ADDRESS_COLLISION")
		if not operation_id.is_empty(): _operations[operation_id] = {"operation_id": operation_id, "payload_checksum": op_checksum, "artifact_id": artifact_id}
		return C.success({"replay": true, "artifact_id": artifact_id, "generation": _generation})
	_artifacts[artifact_id] = artifact.duplicate(true)
	if not operation_id.is_empty(): _operations[operation_id] = {"operation_id": operation_id, "payload_checksum": op_checksum, "artifact_id": artifact_id}
	_generation += 1
	return C.success({"replay": false, "artifact_id": artifact_id, "generation": _generation})

func get_artifact(artifact_id: String) -> Dictionary: return Dictionary(_artifacts.get(artifact_id, {})).duplicate(true)
func has_artifact(artifact_id: String) -> bool: return _artifacts.has(artifact_id)
func get_generation() -> int: return _generation
func get_artifact_count() -> int: return _artifacts.size()
func get_total_bytes() -> int:
	var total := 0
	for artifact in _artifacts.values(): total += int(artifact["estimated_bytes"])
	return total
func export_state() -> Dictionary:
	var artifacts: Array = _artifacts.values(); artifacts.sort_custom(func(a, b): return String(a["artifact_id"]) < String(b["artifact_id"]))
	var operations: Array = _operations.values(); operations.sort_custom(func(a, b): return String(a["operation_id"]) < String(b["operation_id"]))
	return {"schema": "planet_simulator.construction_proxy_cache_state.v1", "generation": _generation, "artifacts": artifacts.duplicate(true), "operations": operations.duplicate(true), "checksum": _state_checksum(_generation, artifacts, operations)}
func load_state(state: Dictionary) -> Dictionary:
	if typeof(state) != TYPE_DICTIONARY or state.get("schema") != "planet_simulator.construction_proxy_cache_state.v1" or not state.has("generation") or not state.has("artifacts") or not state.has("operations") or not state.has("checksum"): return C.failure("INVALID_CONSTRUCTION_PROXY_CACHE_STATE")
	if String(state["checksum"]) != _state_checksum(int(state["generation"]), state["artifacts"], state["operations"]): return C.failure("CONSTRUCTION_PROXY_CACHE_STATE_CHECKSUM_MISMATCH")
	var artifacts := {}; var operations := {}
	for artifact in state["artifacts"]:
		var checked := Artifact.validate(artifact); if not bool(checked.get("success", false)): return checked
		artifacts[String(artifact["artifact_id"])] = artifact.duplicate(true)
	for operation in state["operations"]: operations[String(operation["operation_id"])] = operation.duplicate(true)
	_artifacts = artifacts; _operations = operations; _generation = int(state["generation"])
	return C.success({"artifact_count": _artifacts.size(), "generation": _generation})
static func _state_checksum(generation: int, artifacts: Array, operations: Array) -> String:
	return preload("res://scripts/network/contracts/network_contract_utils.gd").payload_hash({"schema": "planet_simulator.construction_proxy_cache_state.v1", "generation": generation, "artifacts": artifacts, "operations": operations})

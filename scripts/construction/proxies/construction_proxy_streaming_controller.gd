extends Node

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const CompileRequest = preload("res://scripts/construction/proxies/construction_proxy_compile_request.gd")
const Compiler = preload("res://scripts/construction/proxies/construction_proxy_compiler.gd")
const Cache = preload("res://scripts/construction/proxies/construction_proxy_cache.gd")
const Planner = preload("res://scripts/construction/proxies/construction_proxy_streaming_planner.gd")
const Packet = preload("res://scripts/construction/proxies/construction_proxy_network_packet.gd")
const RuntimeNode = preload("res://scripts/construction/proxies/construction_proxy_runtime_node.gd")
const Invalidation = preload("res://scripts/construction/proxies/construction_proxy_invalidation_plan.gd")

var _cache = Cache.new()
var _compiled: Dictionary = {}
var _runtimes: Dictionary = {}
var _generation := 0

func compile_construct(request: Dictionary) -> Dictionary:
	var checked := CompileRequest.validate(request)
	if not bool(checked.get("success", false)): return checked
	var construct_id := String(request["runtime_projection_request"]["construct_snapshot"]["construct_id"])
	if _compiled.has(construct_id):
		var current: Dictionary = _compiled[construct_id]
		if String(current["request_checksum"]) == String(request["checksum"]): return C.success({"replay": true, "manifest": current["manifest"].duplicate(true), "stats": current["stats"].duplicate(true), "generation": _generation})
		var current_manifest: Dictionary = current["manifest"]
		var snapshot: Dictionary = request["runtime_projection_request"]["construct_snapshot"]
		if int(request["authority_epoch"]) < int(current_manifest["authority_epoch"]): return C.failure("STALE_CONSTRUCTION_PROXY_AUTHORITY_EPOCH")
		if int(request["authority_epoch"]) == int(current_manifest["authority_epoch"]) and int(snapshot["state_revision"]) < int(current_manifest["source_revision"]): return C.failure("STALE_CONSTRUCTION_PROXY_SOURCE_REVISION")
		if int(request["authority_epoch"]) == int(current_manifest["authority_epoch"]) and int(snapshot["state_revision"]) == int(current_manifest["source_revision"]) and String(snapshot["checksum"]) != String(current_manifest["source_checksum"]): return C.failure("CONSTRUCTION_PROXY_SOURCE_SAME_REVISION_MUTATION")
	var compiled := Compiler.compile(request, _cache)
	if not bool(compiled.get("success", false)): return compiled
	_compiled[construct_id] = {"request_checksum": String(request["checksum"]), "request": request.duplicate(true), "manifest": compiled["manifest"].duplicate(true), "topology": compiled["topology"].duplicate(true), "descriptor_by_part": compiled["descriptor_by_part"].duplicate(true), "stats": compiled["stats"].duplicate(true)}
	_generation += 1
	return C.success({"replay": false, "manifest": compiled["manifest"], "stats": compiled["stats"], "generation": _generation})

func make_packet(interest: Dictionary) -> Dictionary:
	var construct_id := String(interest.get("construct_id", ""))
	if not _compiled.has(construct_id): return C.failure("CONSTRUCTION_PROXY_CONSTRUCT_NOT_COMPILED")
	var record: Dictionary = _compiled[construct_id]
	if Dictionary(record["topology"]).is_empty() and float(interest.get("distance_m", 0.0)) < float(record["manifest"]["shell_distance_m"]):
		return C.failure("CONSTRUCTION_PROXY_SOURCE_REATTACH_REQUIRED")
	var plan_result := Planner.compile(record["manifest"], record["topology"], interest, _cache)
	if not bool(plan_result.get("success", false)): return plan_result
	var packet_result := Packet.create(record["manifest"], record["request"]["runtime_projection_request"], interest, plan_result["plan"], _cache, record["descriptor_by_part"])
	if not bool(packet_result.get("success", false)): return packet_result
	var checked := Packet.validate(packet_result["packet"])
	return C.success({"plan": plan_result["plan"], "packet": packet_result["packet"]}) if bool(checked.get("success", false)) else checked

func present(client_id: String, interest: Dictionary) -> Dictionary:
	if not C.path_id(client_id, "client/"): return C.failure("INVALID_CONSTRUCTION_PROXY_CLIENT_ID")
	var packet_result := make_packet(interest)
	if not bool(packet_result.get("success", false)): return packet_result
	var key := "%s|%s" % [client_id, String(interest["construct_id"])]
	var runtime = _runtimes.get(key, null)
	if runtime == null or not is_instance_valid(runtime): runtime = RuntimeNode.new(); add_child(runtime); _runtimes[key] = runtime
	var applied: Dictionary = runtime.apply_packet(packet_result["packet"])
	if not bool(applied.get("success", false)): return applied
	return C.success({"runtime": runtime, "packet": packet_result["packet"], "plan": packet_result["plan"], "apply_result": applied})

func recompile_incremental(request: Dictionary, dirty_part_ids: Array) -> Dictionary:
	var construct_id := String(request["runtime_projection_request"]["construct_snapshot"]["construct_id"])
	if not _compiled.has(construct_id): return C.failure("CONSTRUCTION_PROXY_CONSTRUCT_NOT_COMPILED")
	if not C.sorted_unique_strings(C.sorted_strings(dirty_part_ids), "part/"): return C.failure("INVALID_CONSTRUCTION_PROXY_DIRTY_PARTS")
	var previous: Dictionary = _compiled[construct_id]
	var previous_manifest: Dictionary = previous["manifest"]
	var previous_topology: Dictionary = previous["topology"]
	var dirty_sections := {}
	for part_id in dirty_part_ids:
		var section_id := String(previous_topology["part_section_index"].get(part_id, ""))
		if not section_id.is_empty(): dirty_sections[section_id] = true
	var result := compile_construct(request)
	if not bool(result.get("success", false)): return result
	var current: Dictionary = _compiled[construct_id]
	var old_by_section := {}; for ref in previous_manifest["section_artifacts"]: old_by_section[String(ref["section_id"])] = String(ref["artifact_id"])
	var new_by_section := {}; for ref in current["manifest"]["section_artifacts"]: new_by_section[String(ref["section_id"])] = String(ref["artifact_id"])
	var invalidated: Array = []; var reused: Array = []
	for section_id in old_by_section:
		if new_by_section.get(section_id, "") == old_by_section[section_id]: reused.append(String(old_by_section[section_id]))
		else: invalidated.append(String(old_by_section[section_id])); dirty_sections[section_id] = true
	var shell_rebuilt := String(previous_manifest["shell_artifact_id"]) != String(current["manifest"]["shell_artifact_id"])
	if shell_rebuilt: invalidated.append(String(previous_manifest["shell_artifact_id"]))
	else: reused.append(String(previous_manifest["shell_artifact_id"]))
	var plan := Invalidation.create(construct_id, String(previous_manifest["source_checksum"]), String(current["manifest"]["source_checksum"]), C.sorted_strings(dirty_part_ids), C.sorted_strings(dirty_sections.keys()), _unique_sorted(invalidated), _unique_sorted(reused), shell_rebuilt)
	var checked := Invalidation.validate(plan)
	return C.success({"invalidation_plan": plan, "manifest": current["manifest"], "stats": current["stats"]}) if bool(checked.get("success", false)) else checked

func get_manifest(construct_id: String) -> Dictionary: return Dictionary(_compiled.get(construct_id, {})).get("manifest", {}).duplicate(true)
func get_topology(construct_id: String) -> Dictionary: return Dictionary(_compiled.get(construct_id, {})).get("topology", {}).duplicate(true)
func get_cache(): return _cache
func get_generation() -> int: return _generation
func get_runtime(client_id: String, construct_id: String): return _runtimes.get("%s|%s" % [client_id, construct_id], null)
func export_state() -> Dictionary:
	var manifests: Array = []
	var ids: Array = _compiled.keys(); ids.sort()
	for id in ids:
		var record: Dictionary = _compiled[id]
		var runtime_request: Dictionary = record["request"].get("runtime_projection_request", {})
		manifests.append({"construct_id": id, "request_checksum": record["request_checksum"], "manifest": record["manifest"].duplicate(true), "world_origin_m": Array(runtime_request.get("world_origin_m", [0.0, 0.0, 0.0])).duplicate(true), "world_rotation_quaternion": Array(runtime_request.get("world_rotation_quaternion", [0.0, 0.0, 0.0, 1.0])).duplicate(true)})
	var value := {"schema": "planet_simulator.construction_proxy_controller_state.v1", "generation": _generation, "manifests": manifests, "cache_state": _cache.export_state(), "checksum": ""}
	value["checksum"] = preload("res://scripts/network/contracts/network_contract_utils.gd").payload_hash({"schema": value["schema"], "generation": value["generation"], "manifests": value["manifests"], "cache_state": value["cache_state"]})
	return value
func load_state(state: Dictionary) -> Dictionary:
	if typeof(state) != TYPE_DICTIONARY or state.get("schema") != "planet_simulator.construction_proxy_controller_state.v1": return C.failure("INVALID_CONSTRUCTION_PROXY_CONTROLLER_STATE")
	var expected := preload("res://scripts/network/contracts/network_contract_utils.gd").payload_hash({"schema": state.get("schema"), "generation": state.get("generation"), "manifests": state.get("manifests"), "cache_state": state.get("cache_state")})
	if String(state.get("checksum", "")) != expected: return C.failure("CONSTRUCTION_PROXY_CONTROLLER_STATE_CHECKSUM_MISMATCH")
	var loaded := _cache.load_state(state["cache_state"]); if not bool(loaded.get("success", false)): return loaded
	_compiled.clear()
	for row in state["manifests"]:
		_compiled[String(row["construct_id"])] = {"request_checksum": String(row["request_checksum"]), "manifest": row["manifest"].duplicate(true), "request": {"runtime_projection_request": {"world_origin_m": Array(row.get("world_origin_m", [0.0, 0.0, 0.0])).duplicate(true), "world_rotation_quaternion": Array(row.get("world_rotation_quaternion", [0.0, 0.0, 0.0, 1.0])).duplicate(true)}}, "topology": {}, "descriptor_by_part": {}, "stats": {}}
	_generation = int(state["generation"])
	return C.success({"manifest_count": _compiled.size(), "generation": _generation})
func reattach(request: Dictionary) -> Dictionary:
	var construct_id := String(request["runtime_projection_request"]["construct_snapshot"]["construct_id"])
	if not _compiled.has(construct_id): return compile_construct(request)
	var persisted: Dictionary = _compiled[construct_id]
	if String(persisted["manifest"]["source_checksum"]) != String(request["runtime_projection_request"]["construct_snapshot"]["checksum"]) or int(persisted["manifest"]["authority_epoch"]) != int(request["authority_epoch"]): return C.failure("CONSTRUCTION_PROXY_REATTACH_SOURCE_MISMATCH")
	var compiled := Compiler.compile(request, _cache); if not bool(compiled.get("success", false)): return compiled
	_compiled[construct_id] = {"request_checksum": String(request["checksum"]), "request": request.duplicate(true), "manifest": compiled["manifest"].duplicate(true), "topology": compiled["topology"].duplicate(true), "descriptor_by_part": compiled["descriptor_by_part"].duplicate(true), "stats": compiled["stats"].duplicate(true)}
	return C.success({"manifest": compiled["manifest"], "reattached": true})
static func _unique_sorted(values: Array) -> Array:
	var seen := {}; for value in values: seen[String(value)] = true
	var result: Array = seen.keys(); result.sort(); return result

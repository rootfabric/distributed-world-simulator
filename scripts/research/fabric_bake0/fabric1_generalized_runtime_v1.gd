extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const Protocol = preload("res://scripts/research/fabric_bake0/unseen_machine_challenge_protocol_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const BakeRuntime = preload("res://scripts/research/fabric_bake0/exact_boundary_runtime_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")

const CAPSULE_SCHEMA := "planet_simulator.fabric1_generalized_runtime_capsule.v1"
const MODES: Array[String] = ["BAKED", "FULL"]

var _spec: Dictionary = {}
var _context: Dictionary = {}
var _compiled: Dictionary = {}
var _mode := ""
var _event_ledger: Array = []
var _transition_count := 0
var _transition_hash := Utils.canonical_hash({"fabric1": "genesis"})
var _last_tick := -1
var _canonical_mutations_observed := 0

func start_baked(spec: Dictionary, tick: int = 0) -> Dictionary:
	if not _spec.is_empty() or not Utils.is_json_integer(tick) or tick < 0:
		return Utils.failure("FABRIC1_START_INVALID")
	var checked := Graph.validate(spec)
	if not bool(checked.get("success", false)):
		return checked
	var compiled := GenericCompiler.compile(spec)
	if String(compiled.get("status", "")) != "BAKE_READY":
		return Utils.failure("FABRIC1_START_NO_SAFE_BAKE", {"status": compiled.get("status", ""), "reason": compiled.get("reason", "")})
	_spec = spec.duplicate(true)
	_context = compiled["context"].duplicate(true)
	_compiled = compiled.duplicate(true)
	_mode = "BAKED"
	_event_ledger = spec["applied_event_ids"].duplicate()
	_last_tick = tick
	_commit_transition("START_BAKED", tick, {"graph_hash": spec["graph_hash"]})
	return Utils.success(status())

func execute(excitation: Array) -> Dictionary:
	if _spec.is_empty() or not MODES.has(_mode) or excitation.size() != _spec["boundary_node_ids"].size():
		return Utils.failure("FABRIC1_EXECUTION_INVALID")
	if _mode == "BAKED":
		if String(_compiled.get("status", "")) != "BAKE_READY":
			return Utils.failure("FABRIC1_BAKE_NOT_READY")
		var artifact: Dictionary = _compiled["compile_result"]["artifact"]
		var descriptor: Dictionary = _compiled["compile_result"]["diagnostics"]["reduction"]
		var result := BakeRuntime.execute(artifact, descriptor, GenericCompiler.live_context(artifact), excitation)
		if not bool(result.get("success", false)):
			return result
		return Utils.success({
			"mode": _mode,
			"boundary_flow": result["details"]["boundary_flow"],
			"boundary_power": result["details"]["boundary_power"],
			"artifact_hash": artifact["checksum"],
		})
	var full := Reducer.evaluate_full(_context["linear_system"], excitation, GenericCompiler.PIVOT_TOLERANCE)
	if not bool(full.get("success", false)):
		return full
	return Utils.success({
		"mode": _mode,
		"boundary_flow": full["details"]["boundary_flow"],
		"boundary_power": full["details"]["boundary_power"],
		"artifact_hash": "",
	})

func refine_to_full(reason: String, tick: int) -> Dictionary:
	if _mode != "BAKED" or reason.is_empty() or not _next_tick(tick):
		return Utils.failure("FABRIC1_REFINE_INVALID")
	_mode = "FULL"
	_last_tick = tick
	_commit_transition("REFINE_TO_FULL", tick, {"reason": reason, "graph_hash": _spec["graph_hash"]})
	return Utils.success(status())

func apply_canonical_failure(successor: Dictionary, event_id: String, failed_edge_ids: Array, tick: int) -> Dictionary:
	if _mode != "FULL" or _spec.is_empty() or _event_ledger.has(event_id) or not _next_tick(tick):
		return Utils.failure("FABRIC1_CANONICAL_FAILURE_ORDER_INVALID")
	var checked := Protocol.validate_successor(_spec, successor, event_id, failed_edge_ids)
	if not bool(checked.get("success", false)):
		return checked
	var successor_context := GenericCompiler.build_context(successor)
	if not bool(successor_context.get("success", false)):
		return successor_context
	if String(_compiled.get("status", "")) != "BAKE_READY":
		return Utils.failure("FABRIC1_OLD_BAKE_MISSING")
	var old_artifact: Dictionary = _compiled["compile_result"]["artifact"]
	var old_descriptor: Dictionary = _compiled["compile_result"]["diagnostics"]["reduction"]
	var invalidation := BakeInvalidation.create(
		"invalidation/fabric1-%06d" % tick,
		String(old_artifact["artifact_id"]),
		"SOURCE_REVISION",
		String(old_artifact["source_binding"]["frontier_hash"]),
		String(successor_context["details"]["frontier"]["frontier_hash"]),
		tick
	)
	if invalidation.is_empty():
		return Utils.failure("FABRIC1_INVALIDATION_BUILD_FAILED")
	var zero_excitation: Array = []
	zero_excitation.resize(_spec["boundary_node_ids"].size())
	zero_excitation.fill(0.0)
	var stale := BakeRuntime.execute(old_artifact, old_descriptor, GenericCompiler.live_context(old_artifact, [invalidation]), zero_excitation)
	if String(stale.get("error_code", "")) != "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN":
		return Utils.failure("FABRIC1_STALE_BAKE_NOT_FENCED", {"error": stale.get("error_code", "")})
	_spec = successor.duplicate(true)
	_context = successor_context["details"].duplicate(true)
	_event_ledger.append(event_id)
	_event_ledger.sort()
	_compiled = {}
	_last_tick = tick
	_canonical_mutations_observed += 1
	_commit_transition("OBSERVE_CANONICAL_FAILURE", tick, {"event_id": event_id, "failed_edge_ids": Utils.sorted_strings(failed_edge_ids)})
	return Utils.success({"stale_error": String(stale.get("error_code", "")), "status": status()})

func rebake(tick: int) -> Dictionary:
	if _mode != "FULL" or _spec.is_empty() or not _next_tick(tick):
		return Utils.failure("FABRIC1_REBAKE_INVALID")
	var compiled := GenericCompiler.compile(_spec)
	if String(compiled.get("status", "")) != "BAKE_READY":
		return Utils.failure("FABRIC1_REBAKE_NO_SAFE_BAKE", {"status": compiled.get("status", ""), "reason": compiled.get("reason", "")})
	_compiled = compiled.duplicate(true)
	_context = compiled["context"].duplicate(true)
	_mode = "BAKED"
	_last_tick = tick
	_commit_transition("REBAKE", tick, {"artifact_hash": compiled["compile_result"]["artifact"]["checksum"]})
	return Utils.success(status())

func capture_capsule() -> Dictionary:
	if _spec.is_empty() or not MODES.has(_mode):
		return Utils.failure("FABRIC1_CAPSULE_UNAVAILABLE")
	var capsule := {
		"schema": CAPSULE_SCHEMA,
		"canonical": false,
		"derived": true,
		"discardable": true,
		"machine_id": _spec["machine_id"],
		"revision": _spec["revision"],
		"graph_hash": _spec["graph_hash"],
		"spec_checksum": _spec["checksum"],
		"mode": _mode,
		"event_ledger": _event_ledger.duplicate(),
		"transition_count": _transition_count,
		"transition_hash": _transition_hash,
		"last_tick": _last_tick,
		"canonical_mutations_observed": _canonical_mutations_observed,
		"checksum": "",
	}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

func restore(authoritative_spec: Dictionary, capsule: Dictionary) -> Dictionary:
	if not _spec.is_empty():
		return Utils.failure("FABRIC1_RESTORE_REQUIRES_NEW_RUNTIME")
	var checked := Graph.validate(authoritative_spec)
	if not bool(checked.get("success", false)):
		return checked
	if capsule.get("schema") != CAPSULE_SCHEMA or capsule.get("canonical") != false or capsule.get("derived") != true or capsule.get("discardable") != true:
		return Utils.failure("FABRIC1_CAPSULE_INVALID")
	checked = Utils.validate_checksum(capsule)
	if not bool(checked.get("success", false)):
		return Utils.failure("FABRIC1_CAPSULE_CHECKSUM_INVALID")
	if String(capsule.get("machine_id", "")) != String(authoritative_spec["machine_id"]) or int(capsule.get("revision", -1)) != int(authoritative_spec["revision"]) or String(capsule.get("graph_hash", "")) != String(authoritative_spec["graph_hash"]) or String(capsule.get("spec_checksum", "")) != String(authoritative_spec["checksum"]):
		return Utils.failure("FABRIC1_CAPSULE_STALE")
	if capsule.get("event_ledger") != authoritative_spec["applied_event_ids"]:
		return Utils.failure("FABRIC1_CAPSULE_EVENT_LEDGER_MISMATCH")
	if not MODES.has(String(capsule.get("mode", ""))) or not Utils.is_json_integer(capsule.get("transition_count")) or int(capsule["transition_count"]) < 0 or not Utils.is_lower_hex_64(capsule.get("transition_hash")) or not Utils.is_json_integer(capsule.get("last_tick")) or int(capsule["last_tick"]) < 0:
		return Utils.failure("FABRIC1_CAPSULE_STATE_INVALID")
	var context := GenericCompiler.build_context(authoritative_spec)
	if not bool(context.get("success", false)):
		return context
	_spec = authoritative_spec.duplicate(true)
	_context = context["details"].duplicate(true)
	_mode = String(capsule["mode"])
	_event_ledger = capsule["event_ledger"].duplicate()
	_transition_count = int(capsule["transition_count"])
	_transition_hash = String(capsule["transition_hash"])
	_last_tick = int(capsule["last_tick"])
	_canonical_mutations_observed = int(capsule.get("canonical_mutations_observed", 0))
	if _mode == "BAKED":
		var compiled := GenericCompiler.compile(authoritative_spec)
		if String(compiled.get("status", "")) != "BAKE_READY":
			return Utils.failure("FABRIC1_RESTORE_NO_SAFE_BAKE")
		_compiled = compiled.duplicate(true)
	else:
		_compiled = {}
	return Utils.success(status())

func status() -> Dictionary:
	if _spec.is_empty():
		return {"mode": "UNINITIALIZED", "transition_count": 0, "transition_hash": _transition_hash}
	return {
		"machine_id": _spec["machine_id"],
		"revision": _spec["revision"],
		"graph_hash": _spec["graph_hash"],
		"mode": _mode,
		"event_ledger": _event_ledger.duplicate(),
		"transition_count": _transition_count,
		"transition_hash": _transition_hash,
		"last_tick": _last_tick,
		"canonical_mutations_observed": _canonical_mutations_observed,
		"canonical_writes": 0,
	}

func _next_tick(tick: int) -> bool:
	return Utils.is_json_integer(tick) and tick > _last_tick

func _commit_transition(kind: String, tick: int, payload: Dictionary) -> void:
	_transition_count += 1
	_transition_hash = Utils.canonical_hash({
		"previous": _transition_hash,
		"count": _transition_count,
		"kind": kind,
		"tick": tick,
		"payload": payload,
	})

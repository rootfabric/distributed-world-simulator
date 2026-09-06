extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const Protocol = preload("res://scripts/research/fabric_bake0/unseen_machine_challenge_protocol_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const BakeRuntime = preload("res://scripts/research/fabric_bake0/exact_boundary_runtime_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")

# V1 capsules are disposable: discard them and cold-start with current canonical inputs.
const CAPSULE_SCHEMA := "planet_simulator.fabric1_generalized_runtime_capsule.v2"
const MODES: Array[String] = ["BAKED", "FULL"]
const CAPSULE_FIELDS: Array[String] = [
	"schema", "canonical", "derived", "discardable", "machine_id", "revision",
	"graph_hash", "spec_checksum", "mode", "event_ledger", "transition_count",
	"transition_hash", "last_tick", "canonical_mutations_observed",
	"external_source", "source_context_hash", "checksum",
]

var _spec: Dictionary = {}
var _context: Dictionary = {}
var _compiled: Dictionary = {}
var _mode := ""
var _event_ledger: Array = []
var _transition_count := 0
var _transition_hash := Utils.canonical_hash({"fabric1": "genesis"})
var _last_tick := -1
var _canonical_mutations_observed := 0

func start_baked(spec: Dictionary, tick: int = 0, source_context: Dictionary = {}) -> Dictionary:
	return _start(spec, tick, source_context, false)

func start(spec: Dictionary, tick: int = 0, source_context: Dictionary = {}) -> Dictionary:
	return _start(spec, tick, source_context, true)

func _start(spec: Dictionary, tick: int, source_context: Dictionary, allow_full: bool) -> Dictionary:
	if not _spec.is_empty() or not Utils.is_json_integer(tick) or tick < 0:
		return Utils.failure("FABRIC1_START_INVALID")
	var compiled := GenericCompiler.compile(spec, source_context)
	var compile_status: String = compiled.get("status", "")
	if not compiled.get("success", false):
		return compiled
	if compile_status != "BAKE_READY":
		if not allow_full or compile_status != "NO_SAFE_BAKE":
			return Utils.failure("FABRIC1_START_NO_SAFE_BAKE", {"reason": compiled.get("reason", "")})
		var full := _validate_full(compiled["context"])
		if not full.success:
			return full
	# Commit only after compilation / fallback has succeeded.
	_spec = spec.duplicate(true)
	_context = compiled["context"].duplicate(true)
	_mode = "BAKED" if compile_status == "BAKE_READY" else "FULL"
	_compiled = compiled.duplicate(true) if _mode == "BAKED" else {}
	_event_ledger = spec["applied_event_ids"].duplicate()
	_last_tick = tick
	_commit_transition("START_" + _mode, tick, {"graph_hash": spec["graph_hash"]})
	return Utils.success(status())

func execute(excitation: Array, source_context: Dictionary = {}) -> Dictionary:
	if _spec.is_empty() or not MODES.has(_mode) or excitation.size() != _spec["boundary_node_ids"].size():
		return Utils.failure("FABRIC1_EXECUTION_INVALID")
	for value in excitation:
		if not Utils.is_finite_number(value):
			return Utils.failure("FABRIC1_EXCITATION_INVALID")
	var current := _check_live(source_context)
	if not current.success:
		return current
	var result: Dictionary
	var artifact_hash := ""
	if _mode == "BAKED":
		if _compiled.get("status") != "BAKE_READY":
			return Utils.failure("FABRIC1_BAKE_NOT_READY")
		var artifact: Dictionary = _compiled["compile_result"]["artifact"]
		var descriptor: Dictionary = _compiled["compile_result"]["diagnostics"]["reduction"]
		result = BakeRuntime.execute(artifact, descriptor, GenericCompiler.live_context(_context), excitation)
		artifact_hash = artifact["checksum"]
	else:
		result = Reducer.evaluate_full(_context["linear_system"], excitation, GenericCompiler.PIVOT_TOLERANCE)
	if not result.get("success", false):
		return result
	for flow in result["details"]["boundary_flow"]:
		if not Utils.is_finite_number(flow):
			return Utils.failure("FABRIC1_NONFINITE_RESPONSE")
	if not Utils.is_finite_number(result["details"]["boundary_power"]):
		return Utils.failure("FABRIC1_NONFINITE_RESPONSE")
	return Utils.success({"mode": _mode, "boundary_flow": result["details"]["boundary_flow"],
		"boundary_power": result["details"]["boundary_power"], "artifact_hash": artifact_hash})

func refine_to_full(reason: String, tick: int, source_context: Dictionary = {}) -> Dictionary:
	if not MODES.has(_mode) or reason.is_empty() or not _next_tick(tick):
		return Utils.failure("FABRIC1_REFINE_INVALID")
	var current := _check_live(source_context)
	if not current.success:
		return current
	if _mode == "FULL":
		return Utils.success(status())
	_mode = "FULL"
	_last_tick = tick
	_commit_transition("REFINE_TO_FULL", tick, {"reason": reason, "graph_hash": _spec["graph_hash"]})
	return Utils.success(status())

func apply_canonical_failure(successor: Dictionary, event_id: String, failed_edge_ids: Array, tick: int, source_context: Dictionary = {}) -> Dictionary:
	if _mode != "FULL" or _event_ledger.has(event_id) or not _next_tick(tick):
		return Utils.failure("FABRIC1_CANONICAL_FAILURE_ORDER_INVALID")
	var checked := Protocol.validate_successor(_spec, successor, event_id, failed_edge_ids)
	if not checked.success:
		return checked
	if bool(_context["external_source"]) == source_context.is_empty():
		return Utils.failure("FABRIC1_SOURCE_CONTEXT_REQUIRED")
	var next_context := GenericCompiler.build_context(successor, source_context)
	if not next_context.success:
		return next_context
	checked = _check_source_successor(next_context.details)
	if not checked.success:
		return checked
	checked = _validate_full(next_context.details)
	if not checked.success:
		return checked
	# A FULL region may have no bake at all (cold restore or consecutive failures).
	# Retire a retained artifact when present; its absence is not a physical failure.
	var stale_error := ""
	if not _compiled.is_empty():
		var old_artifact: Dictionary = _compiled["compile_result"]["artifact"]
		var descriptor: Dictionary = _compiled["compile_result"]["diagnostics"]["reduction"]
		var invalidation := BakeInvalidation.create("invalidation/fabric1-%06d" % tick,
			old_artifact["artifact_id"], "SOURCE_REVISION", old_artifact["source_binding"]["frontier_hash"],
			next_context.details.frontier.frontier_hash, tick)
		if invalidation.is_empty():
			return Utils.failure("FABRIC1_INVALIDATION_BUILD_FAILED")
		var zero := _zero_excitation(successor)
		var stale := BakeRuntime.execute(old_artifact, descriptor,
			GenericCompiler.live_context(next_context.details, [invalidation]), zero)
		stale_error = stale.get("error_code", "")
		if stale_error != "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN":
			return Utils.failure("FABRIC1_STALE_BAKE_NOT_FENCED")
	_spec = successor.duplicate(true)
	_context = next_context.details.duplicate(true)
	_event_ledger = successor["applied_event_ids"].duplicate()
	_compiled = {}
	_last_tick = tick
	_canonical_mutations_observed += 1
	_commit_transition("OBSERVE_CANONICAL_FAILURE", tick, {"event_id": event_id, "failed_edge_ids": Utils.sorted_strings(failed_edge_ids)})
	return Utils.success({"stale_error": stale_error, "retired_bake": not stale_error.is_empty(), "status": status()})

func rebake(tick: int, source_context: Dictionary = {}) -> Dictionary:
	if _mode != "FULL" or not _next_tick(tick):
		return Utils.failure("FABRIC1_REBAKE_INVALID")
	var current := _check_live(source_context)
	if not current.success:
		return current
	var compiled := GenericCompiler.compile(_spec, source_context)
	if compiled.get("status", "") != "BAKE_READY":
		return Utils.failure("FABRIC1_REBAKE_NO_SAFE_BAKE", {"reason": compiled.get("reason", "")})
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
		"schema": CAPSULE_SCHEMA, "canonical": false, "derived": true, "discardable": true,
		"machine_id": _spec["machine_id"], "revision": _spec["revision"],
		"graph_hash": _spec["graph_hash"], "spec_checksum": _spec["checksum"], "mode": _mode,
		"event_ledger": _event_ledger.duplicate(), "transition_count": _transition_count,
		"transition_hash": _transition_hash, "last_tick": _last_tick,
		"canonical_mutations_observed": _canonical_mutations_observed,
		"external_source": _context["external_source"],
		"source_context_hash": Utils.canonical_hash(_context["source_context"]), "checksum": "",
	}
	capsule["checksum"] = Utils.compute_checksum(capsule)
	return Utils.success({"capsule": capsule})

func restore(authoritative_spec: Dictionary, capsule: Dictionary, source_context: Dictionary = {}) -> Dictionary:
	if not _spec.is_empty():
		return Utils.failure("FABRIC1_RESTORE_REQUIRES_NEW_RUNTIME")
	var checked := Graph.validate(authoritative_spec)
	if not checked.success:
		return checked
	checked = _validate_capsule(capsule, authoritative_spec)
	if not checked.success:
		return checked
	if bool(capsule["external_source"]) == source_context.is_empty():
		return Utils.failure("FABRIC1_SOURCE_CONTEXT_REQUIRED")
	var context := GenericCompiler.build_context(authoritative_spec, source_context)
	if not context.success:
		return context
	if capsule["source_context_hash"] != Utils.canonical_hash(context.details.source_context):
		return Utils.failure("FABRIC1_CAPSULE_SOURCE_STALE")
	var compiled: Dictionary = {}
	if capsule["mode"] == "BAKED":
		compiled = GenericCompiler.compile(authoritative_spec, source_context)
		if compiled.get("status", "") != "BAKE_READY":
			return Utils.failure("FABRIC1_RESTORE_NO_SAFE_BAKE")
	else:
		checked = _validate_full(context.details)
		if not checked.success:
			return checked
	# Nothing above this line changes this instance. Failed restore remains retryable.
	_spec = authoritative_spec.duplicate(true)
	_context = context.details.duplicate(true)
	_compiled = compiled.duplicate(true)
	_mode = capsule["mode"]
	_event_ledger = authoritative_spec["applied_event_ids"].duplicate()
	_transition_count = int(capsule["transition_count"])
	_transition_hash = capsule["transition_hash"]
	_last_tick = int(capsule["last_tick"])
	_canonical_mutations_observed = int(capsule["canonical_mutations_observed"])
	return Utils.success(status())

func status() -> Dictionary:
	if _spec.is_empty():
		return {"mode": "UNINITIALIZED", "transition_count": 0, "transition_hash": _transition_hash}
	return {
		"machine_id": _spec["machine_id"], "revision": _spec["revision"], "graph_hash": _spec["graph_hash"],
		"mode": _mode, "event_ledger": _event_ledger.duplicate(), "transition_count": _transition_count,
		"transition_hash": _transition_hash, "last_tick": _last_tick,
		"canonical_mutations_observed": _canonical_mutations_observed, "canonical_writes": 0,
		"external_source": _context["external_source"], "source_context": _context["source_context"].duplicate(true),
		"artifact_source_binding": _compiled["compile_result"]["artifact"]["source_binding"].duplicate(true) if _mode == "BAKED" and not _compiled.is_empty() else {},
	}

func _check_live(source_context: Dictionary) -> Dictionary:
	if _context.is_empty():
		return Utils.failure("FABRIC1_NOT_STARTED")
	if not bool(_context["external_source"]):
		return Utils.success() if source_context.is_empty() else Utils.failure("FABRIC1_BINDING_MODE_MISMATCH")
	if source_context.is_empty():
		return Utils.failure("FABRIC1_SOURCE_CONTEXT_REQUIRED")
	var checked := GenericCompiler.validate_source_context(_spec, source_context)
	if not checked.success:
		return checked
	if Utils.canonical_hash(source_context) != Utils.canonical_hash(_context["source_context"]):
		return Utils.failure("FABRIC1_CANONICAL_SOURCE_STALE")
	return Utils.success()

func _check_source_successor(next_context: Dictionary) -> Dictionary:
	if _context["authority"]["checksum"] != next_context["authority"]["checksum"]:
		return Utils.failure("FABRIC1_AUTHORITY_CHANGED_RESTART_REQUIRED")
	if not bool(_context["external_source"]):
		return Utils.success()
	var next_sources := {}
	for source in next_context.frontier.sources:
		next_sources[Utils.source_key(source.source_domain, source.source_id)] = source
	var advanced := false
	for before in _context.frontier.sources:
		var key := Utils.source_key(before.source_domain, before.source_id)
		if not next_sources.has(key):
			return Utils.failure("FABRIC1_SOURCE_SET_CHANGED")
		var after: Dictionary = next_sources[key]
		if _context.authority.readonly_source_ids.has(key):
			if Utils.canonical_hash(before) != Utils.canonical_hash(after):
				return Utils.failure("FABRIC1_READONLY_SOURCE_CHANGED")
		else:
			var delta := int(after.source_revision) - int(before.source_revision)
			if delta < 0 or delta > 1:
				return Utils.failure("FABRIC1_SOURCE_REVISION_INVALID")
			if delta == 0 and Utils.canonical_hash(before) != Utils.canonical_hash(after):
				return Utils.failure("FABRIC1_SOURCE_REVISION_NOT_ADVANCED")
			advanced = advanced or delta == 1
	return Utils.success() if advanced else Utils.failure("FABRIC1_SOURCE_REVISION_NOT_ADVANCED")

static func _validate_capsule(capsule: Dictionary, spec: Dictionary) -> Dictionary:
	if not Utils.validate_exact_fields(capsule, CAPSULE_FIELDS).success:
		return Utils.failure("FABRIC1_CAPSULE_FIELDS_INVALID")
	for field in ["schema", "machine_id", "graph_hash", "spec_checksum", "mode", "transition_hash", "source_context_hash", "checksum"]:
		if typeof(capsule[field]) != TYPE_STRING:
			return Utils.failure("FABRIC1_CAPSULE_STATE_INVALID")
	for field in ["canonical", "derived", "discardable", "external_source"]:
		if typeof(capsule[field]) != TYPE_BOOL:
			return Utils.failure("FABRIC1_CAPSULE_STATE_INVALID")
	for field in ["revision", "transition_count", "last_tick", "canonical_mutations_observed"]:
		if not Utils.is_json_integer(capsule[field]) or int(capsule[field]) < 0:
			return Utils.failure("FABRIC1_CAPSULE_STATE_INVALID")
	if capsule.schema != CAPSULE_SCHEMA or capsule.canonical or not capsule.derived or not capsule.discardable:
		return Utils.failure("FABRIC1_CAPSULE_INVALID")
	if not Utils.validate_checksum(capsule).success:
		return Utils.failure("FABRIC1_CAPSULE_CHECKSUM_INVALID")
	if capsule.machine_id != spec.machine_id or int(capsule.revision) != int(spec.revision) or capsule.graph_hash != spec.graph_hash or capsule.spec_checksum != spec.checksum:
		return Utils.failure("FABRIC1_CAPSULE_STALE")
	if typeof(capsule.event_ledger) != TYPE_ARRAY or capsule.event_ledger != spec.applied_event_ids:
		return Utils.failure("FABRIC1_CAPSULE_EVENT_LEDGER_MISMATCH")
	if not MODES.has(capsule.mode) or not Utils.is_lower_hex_64(capsule.transition_hash) or not Utils.is_lower_hex_64(capsule.source_context_hash):
		return Utils.failure("FABRIC1_CAPSULE_STATE_INVALID")
	if int(capsule.transition_count) < int(capsule.canonical_mutations_observed) + 1 or int(capsule.canonical_mutations_observed) > capsule.event_ledger.size():
		return Utils.failure("FABRIC1_CAPSULE_STATE_INVALID")
	return Utils.success()

static func _zero_excitation(spec: Dictionary) -> Array:
	var result: Array = []
	result.resize(spec["boundary_node_ids"].size())
	result.fill(0.0)
	return result

static func _validate_full(context: Dictionary) -> Dictionary:
	return Reducer.evaluate_full(context["linear_system"], _zero_excitation(context["spec"]), GenericCompiler.PIVOT_TOLERANCE)

func _next_tick(tick: int) -> bool:
	return Utils.is_json_integer(tick) and tick > _last_tick

func _commit_transition(kind: String, tick: int, payload: Dictionary) -> void:
	_transition_count += 1
	_transition_hash = Utils.canonical_hash({"previous": _transition_hash, "count": _transition_count,
		"kind": kind, "tick": tick, "payload": payload})

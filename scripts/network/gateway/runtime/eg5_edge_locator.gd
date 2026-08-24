extends RefCounted

## EG5 edge locator: deterministic gateway selection by client-network
## health score. "Nearest" = lowest healthy score over the bounded candidate
## set; NOT geographic distance. Routine authority handoff must NOT cause
## Gateway rehome, and the persisted world location must NOT influence selection.

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const EG5_SCHEMA := "planet_simulator.eg5_edge_locator.v1"
const HEALTH_DEGRADED_THRESHOLD := 70.0
const HEALTH_DRAINING_THRESHOLD := 85.0
const HEALTH_UNHEALTHY_THRESHOLD := 1000.0
const WEIGHT_RTT := 0.4
const WEIGHT_LOSS := 0.3
const WEIGHT_JITTER := 0.15
const WEIGHT_HEALTH := 0.1
const WEIGHT_CAPACITY := 0.05
const HYSTERESIS_MARGIN := 0.05

var _probe_simulator = null
var _last_selected_gateway: String = ""
var _last_primary_score: float = -1.0
var _last_health_state: String = ""
var _fallback_chain: Array = []
var _counters := {
	"selections": 0,
	"healthy_selections": 0,
	"degraded_selections": 0,
	"fallback_uses": 0,
	"hysteresis_holds": 0,
	"probe_failures": 0,
	"independent_of_world_location": 0,
}


func configure(p_probe_simulator) -> Dictionary:
	if p_probe_simulator == null or not p_probe_simulator.has_method("probe"):
		return _failure("INVALID_PROBE_SIMULATOR", "probe simulator with probe() required")
	_probe_simulator = p_probe_simulator
	return _success({})


## Select the lowest-healthy-score gateway for a given client. Independent of
## the persisted world location: a `world_id_hint` is accepted only to enforce
## the documented invariant, NOT to influence selection.
func select_for_client(client_id: String, candidates: Array, world_id_hint: String = "") -> Dictionary:
	_counters["selections"] = int(_counters["selections"]) + 1
	var ids: Array = _validate_candidates(candidates)
	if ids.is_empty():
		return _failure("NO_CANDIDATES", {})
	var scored: Array = []
	var probe_failures: int = 0
	for candidate_value in candidates:
		var candidate: Dictionary = Dictionary(candidate_value)
		var gateway_id: String = String(candidate.get("gateway_instance_id", ""))
		var probe_result: Variant = _probe_simulator.probe(client_id, candidate)
		if typeof(probe_result) != TYPE_DICTIONARY or not bool(Dictionary(probe_result).get("success", false)):
			probe_failures += 1
			continue
		var probe: Dictionary = Dictionary(probe_result["details"])
		var score: Dictionary = _score(probe)
		scored.append({"gateway_instance_id": gateway_id, "candidate": candidate, "probe": probe, "score": score})
	if probe_failures > 0:
		_counters["probe_failures"] = int(_counters["probe_failures"]) + probe_failures
	if scored.is_empty():
		return _failure("ALL_PROBES_FAILED", {"probe_failures": probe_failures})
	scored.sort_custom(func(a, b) -> bool:
		var a_value: float = float(a["score"]["healthy_score"])
		var b_value: float = float(b["score"]["healthy_score"])
		if not is_equal_approx(a_value, b_value):
			return a_value < b_value
		return String(a["gateway_instance_id"]) < String(b["gateway_instance_id"])
	)
	var primary: Dictionary = scored[0]
	var primary_score: float = float(primary["score"]["healthy_score"])
	if not _last_selected_gateway.is_empty() and _last_selected_gateway != String(primary["gateway_instance_id"]):
		var current_entry: Dictionary = _find_scored_entry(scored, _last_selected_gateway)
		if not current_entry.is_empty():
			var current_score: float = float(current_entry["score"]["healthy_score"])
			if primary_score >= current_score * (1.0 - HYSTERESIS_MARGIN):
				_counters["hysteresis_holds"] = int(_counters["hysteresis_holds"]) + 1
				_last_primary_score = current_score
				_last_health_state = String(current_entry["probe"]["health_state"])
				_set_fallback_chain(scored, _last_selected_gateway)
				_counters["independent_of_world_location"] = int(_counters["independent_of_world_location"]) + 1
				return _selection_outcome(_last_selected_gateway, current_entry["score"], world_id_hint, current_entry, false)
	var chosen: String = String(primary["gateway_instance_id"])
	var healthy_state: String = String(primary["probe"]["health_state"])
	var selection_changed_bool: bool = chosen != _last_selected_gateway
	if healthy_state == "HEALTHY":
		_counters["healthy_selections"] = int(_counters["healthy_selections"]) + 1
	elif healthy_state == "DEGRADED" or healthy_state == "DRAINING":
		_counters["degraded_selections"] = int(_counters["degraded_selections"]) + 1
	_set_fallback_chain(scored, chosen)
	_last_selected_gateway = chosen
	_last_primary_score = primary_score
	_last_health_state = healthy_state
	_counters["independent_of_world_location"] = int(_counters["independent_of_world_location"]) + 1
	return _selection_outcome(chosen, primary["score"], world_id_hint, primary, selection_changed_bool)


## Assert that two world-location hints for the same client produce the same
## gateway selection. Carries the invariant used in test #4.
func assert_independent_of_world_location(client_id: String, candidates: Array, world_a: String, world_b: String) -> Dictionary:
	var pick_a: Dictionary = select_for_client(client_id, candidates, world_a)
	var pick_b: Dictionary = select_for_client(client_id, candidates, world_b)
	if not bool(pick_a.get("success", false)) or not bool(pick_b.get("success", false)):
		return _failure("PROBE_FAILED", {"a": pick_a, "b": pick_b})
	if String(pick_a["details"]["gateway_instance_id"]) != String(pick_b["details"]["gateway_instance_id"]):
		return _failure("WORLD_HINT_INFLUENCED_SELECTION", {"a": pick_a["details"], "b": pick_b["details"]})
	return _success({"gateway_instance_id": String(pick_a["details"]["gateway_instance_id"])})


## Apply a routine authority handoff (A -> B) WITHOUT re-evaluating selection.
## Demonstrates test #5: authority change does NOT trigger Gateway rehome.
func mark_authority_handoff(p_authority_id: String) -> Dictionary:
	if p_authority_id.is_empty():
		return _failure("INVALID_AUTHORITY", {})
	return _success({"selected_gateway_unchanged": _last_selected_gateway})


## Reset persisted selection state — used by tests to isolate independent
## scenarios; not part of any public locator contract.
func reset_state() -> Dictionary:
	_last_selected_gateway = ""
	_last_primary_score = -1.0
	_last_health_state = ""
	_fallback_chain = []
	return _success({})


func get_report() -> Dictionary:
	return {
		"schema": EG5_SCHEMA,
		"counters": _counters.duplicate(true),
		"last_selected_gateway": _last_selected_gateway,
		"fallback_chain_size": _fallback_chain.size(),
	}


func _score(probe: Dictionary) -> Dictionary:
	var rtt: float = float(probe.get("rtt_ms", 0.0))
	var loss: float = float(probe.get("loss_pct", 0.0)) * 100.0
	var jitter: float = float(probe.get("jitter_ms", 0.0))
	var health_state: String = String(probe.get("health_state", "HEALTHY"))
	var capacity: float = float(probe.get("capacity_hint", 100.0))
	var health_penalty: float = 0.0
	if health_state == "DEGRADED":
		health_penalty = HEALTH_DEGRADED_THRESHOLD
	elif health_state == "DRAINING":
		health_penalty = HEALTH_DRAINING_THRESHOLD
	elif health_state == "UNHEALTHY":
		health_penalty = HEALTH_UNHEALTHY_THRESHOLD
	var capacity_score: float = max(0.0, 100.0 - capacity)
	var healthy_score: float = WEIGHT_RTT * rtt + WEIGHT_LOSS * loss + WEIGHT_JITTER * jitter + WEIGHT_HEALTH * health_penalty + WEIGHT_CAPACITY * capacity_score
	return {
		"rtt_ms": rtt,
		"loss_pct": loss,
		"jitter_ms": jitter,
		"health_state": health_state,
		"capacity_hint": capacity,
		"healthy_score": healthy_score,
	}


func _validate_candidates(candidates: Array) -> Array:
	var ids: Array = []
	for candidate_value in candidates:
		if typeof(candidate_value) != TYPE_DICTIONARY:
			return []
		var gateway_id: String = String(Dictionary(candidate_value).get("gateway_instance_id", ""))
		if gateway_id.is_empty():
			return []
		ids.append(gateway_id)
	return ids


func _find_scored_entry(scored: Array, gateway_id: String) -> Dictionary:
	for entry_value in scored:
		var entry: Dictionary = Dictionary(entry_value)
		if String(entry.get("gateway_instance_id", "")) == gateway_id:
			return entry
	return {}


func _set_fallback_chain(scored: Array, selected_gateway: String) -> void:
	_fallback_chain = []
	for entry_value in scored:
		var entry: Dictionary = Dictionary(entry_value)
		var gateway_id: String = String(entry.get("gateway_instance_id", ""))
		if gateway_id != selected_gateway:
			_fallback_chain.append(gateway_id)


func _selection_outcome(gateway_id: String, score: Dictionary, world_id_hint: String, selected_entry: Dictionary, changed: bool) -> Dictionary:
	return _success({
		"gateway_instance_id": gateway_id,
		"healthy_score": score,
		"world_id_hint": world_id_hint,
		"selection_changed": changed,
		"health_state": String(selected_entry["probe"]["health_state"]),
	})


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details_or_message = null) -> Dictionary:
	if typeof(details_or_message) == TYPE_STRING:
		return {"success": false, "error_code": error_code, "details": {"message": details_or_message}}
	return {"success": false, "error_code": error_code, "details": details_or_message if details_or_message != null else {}}

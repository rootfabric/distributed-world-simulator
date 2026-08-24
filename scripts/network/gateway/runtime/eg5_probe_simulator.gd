extends RefCounted

## EG5 deterministic client-network-probe simulator.
## One simulator per locator run; given a fixed (candidates, client_id) pair
## produces a deterministic set of measurements (RTT, loss, jitter, sample
## timestamp) for each candidate — no live network required, fully reproducible.

const EG5_GATEWAY_HEALTH_STATES := ["HEALTHY", "DEGRADED", "DRAINING", "UNHEALTHY"]

var _seed: int = 0
var _salt_by_candidate: Dictionary = {}
var _forced_failure_by_candidate: Dictionary = {}
var _forced_latency_by_candidate: Dictionary = {}


func configure(seed: int, candidates: Array) -> Dictionary:
	if typeof(seed) != TYPE_INT:
		return _failure("INVALID_SEED", {})
	_seed = int(seed)
	_salt_by_candidate = {}
	for candidate_value in candidates:
		var candidate: Dictionary = Dictionary(candidate_value)
		var gateway_id: String = String(candidate.get("gateway_instance_id", ""))
		if gateway_id.is_empty():
			return _failure("INVALID_CANDIDATE", {"candidate": candidate})
		_salt_by_candidate[gateway_id] = int(candidate.get("hint_seed", _seed))
	_forced_failure_by_candidate = {}
	_forced_latency_by_candidate = {}
	return _success({})


func force_failure(gateway_instance_id: String) -> void:
	_forced_failure_by_candidate[gateway_instance_id] = true


func force_latency(gateway_instance_id: String, latency_ms: int) -> void:
	_forced_latency_by_candidate[gateway_instance_id] = int(latency_ms)


func probe(client_id: String, candidate: Dictionary) -> Dictionary:
	var gateway_id: String = String(candidate.get("gateway_instance_id", ""))
	if gateway_id.is_empty():
		return _failure("INVALID_CANDIDATE", {"candidate": candidate})
	if bool(_forced_failure_by_candidate.get(gateway_id, false)):
		return _failure("LEG_UNAVAILABLE", {"gateway_instance_id": gateway_id})
	var seed_value: int = int(_salt_by_candidate.get(gateway_id, _seed))
	var key_value: int = (int(_hash_str(client_id)) ^ int(_hash_str(gateway_id)) ^ seed_value) & 0x7fffffff
	var base_rtt: int = int(candidate.get("base_rtt_ms", 20 + (key_value % 60)))
	var base_loss: float = float(candidate.get("loss_pct", (key_value % 50) / 1000.0))
	var base_jitter: float = float(candidate.get("jitter_ms", 2.0 + (key_value % 12)))
	var forced_latency: int = int(_forced_latency_by_candidate.get(gateway_id, 0))
	if forced_latency > 0:
		base_rtt += forced_latency
	return _success({
		"gateway_instance_id": gateway_id,
		"rtt_ms": base_rtt,
		"loss_pct": base_loss,
		"jitter_ms": base_jitter,
		"health_state": String(candidate.get("health_state", "HEALTHY")),
		"capacity_hint": int(candidate.get("capacity_hint", 80)),
		"probed_at_ms": (key_value % 100000) + 1,
	})


func _hash_str(value: String) -> int:
	var result: int = 2166136261
	for character in value:
		result = ((result ^ int(character)) * 16777619) & 0xffffffff
	return result


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

extends SceneTree

## EG5 post-P6 correctness repair regression.
## Proves exact probe failure accounting, fresh-vs-fresh hysteresis, selected
## gateway metadata coherence, and fail-open-to-fresh-selection when the
## previously selected gateway can no longer be probed.

const LocatorScript = preload("res://scripts/network/gateway/runtime/eg5_edge_locator.gd")
const ProbeScript = preload("res://scripts/network/gateway/runtime/eg5_probe_simulator.gd")

var assertions: int = 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg5-repair][FAIL] %s" % message)


func _candidate(gateway_id: String, rtt: int, health: String = "HEALTHY") -> Dictionary:
	return {
		"gateway_instance_id": gateway_id,
		"base_rtt_ms": rtt,
		"loss_pct": 0.0,
		"jitter_ms": 0.0,
		"health_state": health,
		"capacity_hint": 100,
	}


func _init() -> void:
	_test_exact_probe_failure_count()
	_test_hysteresis_uses_fresh_current_score_and_metadata()
	_test_failed_current_gateway_cannot_be_held()

	if failures.is_empty():
		print("[eg5-repair] all %d assertions passed" % assertions)
		print("[eg5-repair][exit] EG5_TELEMETRY_HYSTERESIS_REPAIR_PASS")
		quit(0)
	else:
		print("[eg5-repair] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


func _test_exact_probe_failure_count() -> void:
	var simulator := ProbeScript.new()
	var candidates: Array = [
		_candidate("gateway/fail-a", 20),
		_candidate("gateway/fail-b", 21),
	]
	_assert(bool(simulator.configure(101, candidates).get("success", false)), "failure-count simulator configure")
	simulator.force_failure("gateway/fail-a")
	simulator.force_failure("gateway/fail-b")
	var locator := LocatorScript.new()
	_assert(bool(locator.configure(simulator).get("success", false)), "failure-count locator configure")
	var result: Dictionary = locator.select_for_client("client/failure-count", candidates)
	_assert(not bool(result.get("success", false)), "all failed probes must reject selection")
	_assert(String(result.get("error_code", "")) == "ALL_PROBES_FAILED", "all failed probes use ALL_PROBES_FAILED")
	_assert(int(result["details"]["probe_failures"]) == 2, "two failed probes are reported as exactly two")
	var report: Dictionary = locator.get_report()
	_assert(int(report["counters"]["probe_failures"]) == 2, "global probe_failures increments once per failed probe")


func _test_hysteresis_uses_fresh_current_score_and_metadata() -> void:
	var simulator := ProbeScript.new()
	var initial: Array = [
		_candidate("gateway/current", 20),
		_candidate("gateway/challenger", 50),
	]
	_assert(bool(simulator.configure(202, initial).get("success", false)), "fresh-hysteresis simulator configure")
	var locator := LocatorScript.new()
	_assert(bool(locator.configure(simulator).get("success", false)), "fresh-hysteresis locator configure")
	var first: Dictionary = locator.select_for_client("client/hysteresis", initial)
	_assert(String(first["details"]["gateway_instance_id"]) == "gateway/current", "initial current gateway selected")

	# Fresh scores: current = 0.4*100 + 7 DEGRADED penalty = 47.0;
	# challenger = 0.4*112 = 44.8. Challenger is only ~4.7% better, so the
	# 5% hysteresis margin must retain current based on THIS call's measurements.
	var fresh: Array = [
		_candidate("gateway/current", 100, "DEGRADED"),
		_candidate("gateway/challenger", 112, "HEALTHY"),
	]
	var held: Dictionary = locator.select_for_client("client/hysteresis", fresh)
	_assert(bool(held.get("success", false)), "fresh-hysteresis selection succeeds")
	_assert(String(held["details"]["gateway_instance_id"]) == "gateway/current", "fresh-vs-fresh hysteresis retains current gateway")
	_assert(not bool(held["details"]["selection_changed"]), "hysteresis hold does not report a gateway change")
	_assert(String(held["details"]["health_state"]) == "DEGRADED", "outcome health metadata describes retained gateway")
	_assert(String(held["details"]["healthy_score"]["health_state"]) == "DEGRADED", "score metadata describes retained gateway")
	_assert(is_equal_approx(float(held["details"]["healthy_score"]["healthy_score"]), 47.0), "retained gateway exposes its fresh score, not historical/challenger score")
	var report: Dictionary = locator.get_report()
	_assert(int(report["counters"]["hysteresis_holds"]) == 1, "hysteresis hold counter increments exactly once")


func _test_failed_current_gateway_cannot_be_held() -> void:
	var simulator := ProbeScript.new()
	var initial: Array = [
		_candidate("gateway/current", 20),
		_candidate("gateway/fallback", 30),
	]
	_assert(bool(simulator.configure(303, initial).get("success", false)), "failed-current simulator configure")
	var locator := LocatorScript.new()
	_assert(bool(locator.configure(simulator).get("success", false)), "failed-current locator configure")
	var first: Dictionary = locator.select_for_client("client/failover", initial)
	_assert(String(first["details"]["gateway_instance_id"]) == "gateway/current", "failed-current initial selection")

	# 21ms is within 5% of the old 20ms score. Historical-score hysteresis would
	# incorrectly retain current even though its fresh probe failed.
	simulator.force_failure("gateway/current")
	var next_candidates: Array = [
		_candidate("gateway/current", 20),
		_candidate("gateway/fallback", 21),
	]
	var switched: Dictionary = locator.select_for_client("client/failover", next_candidates)
	_assert(bool(switched.get("success", false)), "fallback selection succeeds when current probe fails")
	_assert(String(switched["details"]["gateway_instance_id"]) == "gateway/fallback", "unprobeable current gateway cannot be retained by hysteresis")
	_assert(bool(switched["details"]["selection_changed"]), "fallback takeover reports selection change")
	_assert(String(switched["details"]["health_state"]) == "HEALTHY", "fallback metadata describes actual selected gateway")
	var report: Dictionary = locator.get_report()
	_assert(int(report["counters"]["probe_failures"]) == 1, "failed current probe counted exactly once")

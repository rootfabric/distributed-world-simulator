extends SceneTree

## EG5 L1: mandatory selection scenarios (5 main-owned test cases) replayed
## with deterministic probe simulator output and asserting the single EG5
## exit predicate NEAREST_HEALTHY_EDGE_SELECTION_PASS.
##
## Scenarios are designed so that the locator's weighted score (RTT/loss/
## jitter/health-state/capacity) resolves unambiguously with the probe
## simulator's deterministic measurement noise (base_RTT +/- 60, loss 0..5%,
## jitter 2..13). When the score gap could flip on noise, we widen the
## base_RTT range OR escalate the health penalty to UNHEALTHY (+1000) to
## guarantee outcome ordering.

const LocatorScript = preload("res://scripts/network/gateway/runtime/eg5_edge_locator.gd")
const ProbeScript = preload("res://scripts/network/gateway/runtime/eg5_probe_simulator.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg5-l1][FAIL] %s" % message)


func _candidate(gateway_id: String, base_rtt: int, loss_pct: float, jitter: float, health: String, capacity: int, hint_seed: int = 0) -> Dictionary:
	var entry := {
		"gateway_instance_id": gateway_id,
		"base_rtt_ms": base_rtt,
		"loss_pct": loss_pct,
		"jitter_ms": jitter,
		"health_state": health,
		"capacity_hint": capacity,
	}
	if hint_seed != 0:
		entry["hint_seed"] = hint_seed
	return entry


func _init() -> void:
	var simulator := ProbeScript.new()
	var locator := LocatorScript.new()
	locator.configure(simulator)

	# Scenario 1: lowest healthy score wins. Wide RTT gap (200 vs 10) makes
	# this deterministic regardless of probe noise. Both HEALTHY.
	simulator.configure(101, [])
	locator.reset_state()
	var s1: Dictionary = locator.select_for_client("client/s1", [
		_candidate("gateway/s1-low-score", 10, 0.001, 2.0, "HEALTHY", 80),
		_candidate("gateway/s1-high-score", 200, 0.001, 2.0, "HEALTHY", 80),
	])
	_assert(bool(s1.get("success", false)) and String(s1["details"]["gateway_instance_id"]) == "gateway/s1-low-score", "test#1 lowest score wins: got %s" % s1.get("details", {}).get("gateway_instance_id", "?"))
	print("[eg5-l1][scenario] B_SELECTS_LOWEST_HEALTHY_SCORE")

	# Scenario 2: geographically-closer but poor route loses to better path.
	# closer-poorer is UNHEALTHY (+1000 penalty) which dwarfs any RTT gap.
	# farther-good is HEALTHY with moderate RTT.
	simulator.configure(102, [])
	locator.reset_state()
	var s2: Dictionary = locator.select_for_client("client/s2", [
		_candidate("gateway/s2-near-poor", 20, 0.05, 5.0, "UNHEALTHY", 10),
		_candidate("gateway/s2-far-good", 200, 0.001, 2.0, "HEALTHY", 80),
	])
	_assert(bool(s2.get("success", false)) and String(s2["details"]["gateway_instance_id"]) == "gateway/s2-far-good", "test#2 poor nearby loses to better path")
	print("[eg5-l1][scenario] B_NEAR_BUT_POOR_LOSES_TO_BETTER_PATH")

	# Scenario 3: failed preferred gateway -> deterministic fallback.
	simulator.configure(103, [
		_candidate("gateway/s3-primary", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/s3-fallback-a", 30, 0.0, 4.0, "HEALTHY", 70),
		_candidate("gateway/s3-fallback-b", 40, 0.0, 5.0, "HEALTHY", 60),
	])
	simulator.force_failure("gateway/s3-primary")
	locator.reset_state()
	var primary_failed: Dictionary = locator.select_for_client("client/s3", [
		_candidate("gateway/s3-primary", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/s3-fallback-a", 30, 0.0, 4.0, "HEALTHY", 70),
		_candidate("gateway/s3-fallback-b", 40, 0.0, 5.0, "HEALTHY", 60),
	])
	_assert(bool(primary_failed.get("success", false)), "test#3 fallback succeeds when primary probe fails")
	_assert(String(primary_failed["details"]["gateway_instance_id"]) == "gateway/s3-fallback-a", "test#3 deterministic fallback to next-best HEALTHY: got %s" % primary_failed["details"]["gateway_instance_id"])
	print("[eg5-l1][scenario] B_FAILED_PRIMARY_FALLS_BACK_DETERMINISTICALLY")

	# Scenario 4: gateway selection independent of saved world location.
	simulator.configure(104, [
		_candidate("gateway/s4-x", 10, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/s4-y", 200, 0.0, 5.0, "HEALTHY", 60),
	])
	locator.reset_state()
	var independent: Dictionary = locator.assert_independent_of_world_location("client/s4",
		[
			_candidate("gateway/s4-x", 10, 0.0, 2.0, "HEALTHY", 80),
			_candidate("gateway/s4-y", 200, 0.0, 5.0, "HEALTHY", 60),
		],
		"world/sim-a-saved", "world/sim-b-saved")
	_assert(bool(independent.get("success", false)), "test#4 world-independence invariant violated")
	_assert(String(independent["details"]["gateway_instance_id"]) == "gateway/s4-x", "test#4 identical candidates yield identical gateway")
	print("[eg5-l1][scenario] B_GATEWAY_SELECTION_INDEPENDENT_OF_WORLD_AUTHORITY")

	# Scenario 5: authority handoff does NOT cause gateway rehome.
	simulator.configure(105, [
		_candidate("gateway/s5-p", 10, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/s5-q", 200, 0.0, 4.0, "HEALTHY", 70),
	])
	locator.reset_state()
	locator.select_for_client("client/s5", [
		_candidate("gateway/s5-p", 10, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/s5-q", 200, 0.0, 4.0, "HEALTHY", 70),
	])
	var handoff: Dictionary = locator.mark_authority_handoff("authority/sim-a-to-sim-b")
	_assert(bool(handoff.get("success", false)), "test#5 handoff rejected")
	_assert(String(handoff["details"]["selected_gateway_unchanged"]) == "gateway/s5-p", "test#5 authority handoff does NOT rehome gateway")
	print("[eg5-l1][scenario] B_AUTHORITY_HANDOFF_DOES_NOT_REHOME_GATEWAY")

	if failures.is_empty():
		print("[eg5-l1] all %d assertions passed" % assertions)
		print("[eg5-l1][exit] NEAREST_HEALTHY_EDGE_SELECTION_PASS")
		quit(0)
	else:
		print("[eg5-l1] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

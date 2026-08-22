extends SceneTree

## EG5 L0: locator + probe simulator unit contracts. Deterministic scores,
## hysteresis, fallback chain, tie-break by gateway_id, world-independence,
## authority-handoff non-rehome, unhealthy exclusion, probe failure handling.

const LocatorScript = preload("res://scripts/network/gateway/runtime/eg5_edge_locator.gd")
const ProbeScript = preload("res://scripts/network/gateway/runtime/eg5_probe_simulator.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg5-l0][FAIL] %s" % message)


func _candidate(gateway_id: String, base_rtt: int, loss_pct: float, jitter: float, health: String, capacity: int) -> Dictionary:
	return {
		"gateway_instance_id": gateway_id,
		"base_rtt_ms": base_rtt,
		"loss_pct": loss_pct,
		"jitter_ms": jitter,
		"health_state": health,
		"capacity_hint": capacity,
	}


func _init() -> void:
	var simulator := ProbeScript.new()
	var config: Dictionary = simulator.configure(42, [
		_candidate("gateway/g-a", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-b", 30, 0.0, 5.0, "HEALTHY", 60),
		_candidate("gateway/g-c", 40, 0.0, 4.0, "DEGRADED", 50),
	])
	_assert(bool(config.get("success", false)), "simulator configure failed: %s" % config.get("error_code", ""))

	var locator := LocatorScript.new()
	_assert(bool(locator.configure(simulator).get("success", false)), "locator configure failed")

	var r1: Dictionary = locator.select_for_client("client/alpha", [
		_candidate("gateway/g-a", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-b", 30, 0.0, 5.0, "HEALTHY", 60),
		_candidate("gateway/g-c", 40, 0.0, 4.0, "DEGRADED", 50),
	])
	_assert(bool(r1.get("success", false)), "first selection failed")
	_assert(String(r1["details"]["gateway_instance_id"]) == "gateway/g-a", "lowest-score gateway selected on first call (got %s)" % str(r1["details"]))
	_assert(bool(r1["details"]["selection_changed"]) == true, "first selection must be flagged as changed")

	var r2: Dictionary = locator.select_for_client("client/alpha", [
		_candidate("gateway/g-a", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-b", 25, 0.0, 3.0, "HEALTHY", 70),
	])
	_assert(bool(r2.get("success", false)), "second selection failed")
	_assert(String(r2["details"]["gateway_instance_id"]) == "gateway/g-a", "re-selection: same primary wins (got %s)" % str(r2["details"]))
	_assert(bool(r2["details"]["selection_changed"]) == false, "selection_changed flag is false on unchanged re-selection")

	var tie: Dictionary = simulator.configure(7, [
		_candidate("gateway/g-z", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-a", 20, 0.0, 2.0, "HEALTHY", 80),
	])
	locator.reset_state()
	locator.configure(simulator)
	var tie_pick: Dictionary = locator.select_for_client("client/alpha", [
		_candidate("gateway/g-z", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-a", 20, 0.0, 2.0, "HEALTHY", 80),
	])
	_assert(bool(tie_pick.get("success", false)), "tie-break selection failed")
	_assert(String(tie_pick["details"]["gateway_instance_id"]) == "gateway/g-a", "tie-break by gateway_id picks alphabetically smallest: got %s" % tie_pick["details"]["gateway_instance_id"])

	simulator.configure(11, [
		_candidate("gateway/g-1", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-2", 100, 0.0, 50.0, "HEALTHY", 80),
		_candidate("gateway/g-3", 200, 0.0, 5.0, "UNHEALTHY", 0),
	])
	locator.reset_state()
	locator.configure(simulator)
	var healthy_pick: Dictionary = locator.select_for_client("client/beta", [
		_candidate("gateway/g-1", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-2", 100, 0.0, 50.0, "HEALTHY", 80),
		_candidate("gateway/g-3", 200, 0.0, 5.0, "UNHEALTHY", 0),
	])
	_assert(bool(healthy_pick.get("success", false)), "healthy pick failed")
	_assert(String(healthy_pick["details"]["gateway_instance_id"]) == "gateway/g-1", "lowest-RTT/lowest-loss HEALTHY selected over DEGRADED/UNHEALTHY: got %s" % healthy_pick["details"]["gateway_instance_id"])
	_assert(String(healthy_pick["details"]["health_state"]) == "HEALTHY", "selection reports HEALTHY")

	locator.reset_state()
	var worlds: Dictionary = locator.assert_independent_of_world_location("client/gamma",
		[
			_candidate("gateway/g-a", 20, 0.0, 2.0, "HEALTHY", 80),
			_candidate("gateway/g-b", 30, 0.0, 5.0, "HEALTHY", 60),
		],
		"world/sim-a", "world/sim-b")
	_assert(bool(worlds.get("success", false)), "world-independence invariant violated: %s" % worlds.get("error_code", ""))
	_assert(String(worlds["details"]["gateway_instance_id"]) == "gateway/g-a", "identical candidates across worlds must select the same gateway")

	simulator.configure(13, [
		_candidate("gateway/g-x", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-y", 30, 0.0, 5.0, "HEALTHY", 60),
	])
	locator.reset_state()
	locator.configure(simulator)
	locator.select_for_client("client/delta", [
		_candidate("gateway/g-x", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-y", 30, 0.0, 5.0, "HEALTHY", 60),
	])
	var handoff: Dictionary = locator.mark_authority_handoff("authority/sim-a-to-sim-b")
	_assert(bool(handoff.get("success", false)), "authority handoff call rejected")
	_assert(String(handoff["details"]["selected_gateway_unchanged"]) == "gateway/g-x", "authority handoff must NOT rehome gateway")

	simulator.configure(17, [
		_candidate("gateway/g-p", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-q", 25, 0.0, 3.0, "HEALTHY", 70),
	])
	locator.reset_state()
	locator.configure(simulator)
	var f1: Dictionary = locator.select_for_client("client/echo", [
		_candidate("gateway/g-p", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-q", 25, 0.0, 3.0, "HEALTHY", 70),
	])
	var f2: Dictionary = locator.select_for_client("client/echo", [
		_candidate("gateway/g-p", 20, 0.0, 2.0, "HEALTHY", 80),
		_candidate("gateway/g-q", 25, 0.0, 3.0, "HEALTHY", 70),
	])
	_assert(bool(f1.get("success", false)) and bool(f2.get("success", false)), "fallback repeated selections must succeed")
	_assert(String(f1["details"]["gateway_instance_id"]) == String(f2["details"]["gateway_instance_id"]), "fallback selection deterministic")

	var empty_pick: Dictionary = locator.select_for_client("client/empty", [])
	_assert(not bool(empty_pick.get("success", false)), "empty candidate list rejected")
	_assert(String(empty_pick.get("error_code", "")) == "NO_CANDIDATES", "NO_CANDIDATES error code")

	locator.reset_state()
	simulator.configure(19, [
		_candidate("gateway/g-allfail", 100, 0.5, 50.0, "HEALTHY", 80),
	])
	simulator.force_failure("gateway/g-allfail")
	locator.configure(simulator)
	var failed_pick: Dictionary = locator.select_for_client("client/foxtrot", [
		_candidate("gateway/g-allfail", 100, 0.5, 50.0, "HEALTHY", 80),
	])
	_assert(not bool(failed_pick.get("success", false)), "all-probes-failed rejected")
	_assert(String(failed_pick.get("error_code", "")) == "ALL_PROBES_FAILED", "ALL_PROBES_FAILED reported")

	var report: Dictionary = locator.get_report()
	_assert(int(report["counters"]["selections"]) >= 6, "selection counter incremented through runs")
	_assert(int(report["counters"]["healthy_selections"]) >= 3, "healthy_selections counter accumulated")

	if failures.is_empty():
		print("[eg5-l0] all %d assertions passed" % assertions)
		print("[eg5-l0][exit] NEAREST_HEALTHY_EDGE_SELECTION_PASS")
		quit(0)
	else:
		print("[eg5-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

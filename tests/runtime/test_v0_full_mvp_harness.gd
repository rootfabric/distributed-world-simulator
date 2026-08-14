extends SceneTree

const Acceptance = preload("res://tests/runtime/v0/v0_full_mvp_acceptance.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_phase_spec()
	_test_state_aggregation()
	_test_spawn_spacing()
	_test_player_convergence()
	_test_item_graph_convergence()
	_test_world_and_container_convergence()
	_test_construction_convergence()
	_test_reconnect_bundle()
	_test_soak_guard()
	_finish()


func _test_phase_spec() -> void:
	var phases := Acceptance.phases()
	_assert(phases.size() == 37, "scenario contains exactly 37 required phases")
	var names: Dictionary = {}
	for index in range(phases.size()):
		var phase: Dictionary = phases[index]
		_assert(int(phase.get("id", 0)) == index + 1, "phase %02d id is deterministic" % (index + 1))
		_assert(String(phase.get("code", "")) == "%02d" % (index + 1), "phase %02d code is deterministic" % (index + 1))
		names[String(phase.get("name", ""))] = true
	_assert(names.size() == 37, "phase names are unique")
	_assert(String(phases[4].get("name", "")) == "players spawn approximately 10 metres apart", "spawn-spacing phase is preserved")
	_assert(String(phases[33].get("name", "")) == "B converges to Construction state", "construction reconnect phase is preserved")


func _test_state_aggregation() -> void:
	var phase := Acceptance.phases()[0]
	var all_pass: Array = [Acceptance.phase_result(phase, Acceptance.STATE_PASS)]
	_assert(Acceptance.aggregate_state(all_pass) == Acceptance.STATE_PASS, "all PASS aggregates to PASS")
	var pending := all_pass.duplicate(true)
	pending.append(Acceptance.phase_result(phase, Acceptance.STATE_DEPENDENCY_PENDING, "dependency"))
	_assert(Acceptance.aggregate_state(pending) == Acceptance.STATE_DEPENDENCY_PENDING, "dependency pending prevents green aggregate")
	var not_implemented := all_pass.duplicate(true)
	not_implemented.append(Acceptance.phase_result(phase, Acceptance.STATE_NOT_IMPLEMENTED, "not implemented"))
	_assert(Acceptance.aggregate_state(not_implemented) == Acceptance.STATE_NOT_IMPLEMENTED, "not implemented prevents green aggregate")
	var failed := pending.duplicate(true)
	failed.append(Acceptance.phase_result(phase, Acceptance.STATE_FAIL, "failure"))
	_assert(Acceptance.aggregate_state(failed) == Acceptance.STATE_FAIL, "failure state has aggregate precedence")
	var summary := Acceptance.build_summary(all_pass, "integration/base/sha", 30, "unit")
	_assert(String(summary.get("integration_base", "")) == "integration/base/sha", "machine evidence records integration base separately")
	_assert(not summary.has("integration_head"), "machine evidence does not mislabel worker HEAD as integration base")
	var invalid := Acceptance.phase_result(phase, "SKIP")
	_assert(String(invalid.get("state", "")) == Acceptance.STATE_FAIL, "unsupported SKIP cannot silently enter evidence")


func _test_spawn_spacing() -> void:
	var a := {"position": {"x": 0.0, "y": 0.0, "z": 0.0}}
	var b := {"position": {"x": 10.0, "y": 0.0, "z": 0.0}}
	_assert(bool(Acceptance.validate_spawn_spacing(a, b).get("success", false)), "10 metre spawn spacing is accepted")
	b["position"] = {"x": 3.0, "y": 0.0, "z": 0.0}
	_assert(not bool(Acceptance.validate_spawn_spacing(a, b).get("success", true)), "too-close spawn spacing is rejected")


func _test_player_convergence() -> void:
	var authority := _player_record()
	var replica := authority.duplicate(true)
	_assert(bool(Acceptance.compare_player_identity(authority, replica).get("success", false)), "current player identity converges")
	_assert(bool(Acceptance.compare_player_state(authority, replica).get("success", false)), "current authoritative player state converges")
	var wrong_identity := replica.duplicate(true)
	wrong_identity["player_entity_id"] = "player/stale"
	_assert(not bool(Acceptance.compare_player_identity(authority, wrong_identity).get("success", true)), "stale player identity is rejected")
	var stale_state := replica.duplicate(true)
	stale_state["state_revision"] = 6
	stale_state["position"] = {"x": 2.0, "y": 0.0, "z": 0.0}
	_assert(not bool(Acceptance.compare_player_state(authority, stale_state).get("success", true)), "stale player state is rejected")


func _test_item_graph_convergence() -> void:
	var graph := _item_graph()
	_assert(bool(Acceptance.compare_item_graph(graph, graph.duplicate(true)).get("success", false)), "matching canonical Item Graph checksum converges")
	var stale := graph.duplicate(true)
	stale["checksum"] = "b".repeat(64)
	_assert(not bool(Acceptance.compare_item_graph(graph, stale).get("success", true)), "stale Item Graph checksum is rejected")


func _test_world_and_container_convergence() -> void:
	var authority := _item_graph()
	var reordered := authority.duplicate(true)
	var items: Array = Array(reordered["items"])
	items.reverse()
	reordered["items"] = items
	_assert(bool(Acceptance.compare_world_items(authority, reordered).get("success", false)), "WORLD item projection is order-insensitive")
	_assert(bool(Acceptance.compare_containers(authority, reordered).get("success", false)), "container projection is order-insensitive")
	var missing_world := reordered.duplicate(true)
	missing_world["items"] = [Dictionary(Array(reordered["items"])[0])]
	_assert(not bool(Acceptance.compare_world_items(authority, missing_world).get("success", true)), "missing WORLD item is detected")
	var changed_container := authority.duplicate(true)
	changed_container["containers"] = {"container/shared/crate/1": {"revision": 8}}
	_assert(not bool(Acceptance.compare_containers(authority, changed_container).get("success", true)), "container revision divergence is detected")


func _test_construction_convergence() -> void:
	var authority := {"server_generation": 4, "last_event_index": 8, "checksum": "construction/checksum/4"}
	_assert(bool(Acceptance.compare_construction(authority, authority.duplicate(true)).get("success", false)), "matching Construction state converges")
	var stale := authority.duplicate(true)
	stale["server_generation"] = 3
	_assert(not bool(Acceptance.compare_construction(authority, stale).get("success", true)), "stale Construction generation is detected")


func _test_reconnect_bundle() -> void:
	var player := _player_record()
	var graph := _item_graph()
	var construction := {"server_generation": 4, "last_event_index": 8, "checksum": "construction/checksum/4"}
	var converged := Acceptance.reconnect_convergence(player, player.duplicate(true), graph, graph.duplicate(true), construction, construction.duplicate(true))
	_assert(bool(converged.get("success", false)), "all canonical reconnect domains converge together")
	var stale_graph := graph.duplicate(true)
	stale_graph["checksum"] = "c".repeat(64)
	var divergent := Acceptance.reconnect_convergence(player, player.duplicate(true), graph, stale_graph, construction, construction.duplicate(true))
	_assert(not bool(divergent.get("success", true)), "combined reconnect assertion fails closed")
	_assert("item_graph" in Array(divergent.get("details", {}).get("failed_domains", [])), "combined reconnect evidence names divergent domain")


func _test_soak_guard() -> void:
	var short_tracker := Acceptance.SoakTracker.new()
	short_tracker.observe(_healthy_sample(0, 0))
	short_tracker.observe(_healthy_sample(0, 0))
	var short_result: Dictionary = short_tracker.finish(30)
	_assert(String(short_result.get("state", "")) == Acceptance.STATE_DEPENDENCY_PENDING, "short development soak cannot claim final PASS")
	var override_tracker := Acceptance.SoakTracker.new()
	override_tracker.observe(_healthy_sample(0, 0))
	var override_result: Dictionary = override_tracker.finish(30, 30)
	_assert(String(override_result.get("state", "")) == Acceptance.STATE_DEPENDENCY_PENDING, "caller cannot lower the final 30-minute soak minimum")
	var final_tracker := Acceptance.SoakTracker.new()
	final_tracker.observe(_healthy_sample(2, 3))
	final_tracker.observe(_healthy_sample(1, 2))
	var final_result: Dictionary = final_tracker.finish(Acceptance.FINAL_SOAK_SECONDS)
	_assert(String(final_result.get("state", "")) == Acceptance.STATE_PASS, "healthy 30-minute evidence can satisfy soak contract")
	var growth_tracker := Acceptance.SoakTracker.new()
	growth_tracker.observe(_healthy_sample(0, 0))
	growth_tracker.observe(_healthy_sample(50, 55))
	growth_tracker.observe(_healthy_sample(49, 54))
	var growth_result: Dictionary = growth_tracker.finish(Acceptance.FINAL_SOAK_SECONDS)
	_assert(String(growth_result.get("state", "")) == Acceptance.STATE_FAIL, "persistent net pending/queue growth fails soak despite a small dip")
	var burst_tracker := Acceptance.SoakTracker.new()
	burst_tracker.observe(_healthy_sample(0, 0))
	burst_tracker.observe(_healthy_sample(50, 55))
	burst_tracker.observe(_healthy_sample(0, 0))
	var burst_result: Dictionary = burst_tracker.finish(Acceptance.FINAL_SOAK_SECONDS)
	_assert(String(burst_result.get("state", "")) == Acceptance.STATE_PASS, "bounded queue burst that returns to baseline is allowed")
	var crash_tracker := Acceptance.SoakTracker.new()
	var crash := _healthy_sample(0, 0)
	crash["process_alive"] = false
	crash_tracker.observe(crash)
	_assert(String(crash_tracker.finish(Acceptance.FINAL_SOAK_SECONDS).get("state", "")) == Acceptance.STATE_FAIL, "process exit fails soak")


func _player_record() -> Dictionary:
	return {
		"logical_player_id": "b",
		"player_entity_id": "player/b",
		"transport_session_id": "transport-session/v0/b/2",
		"ownership_epoch": 2,
		"connected": true,
		"position": {"x": 10.0, "y": 0.0, "z": 2.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"last_input_sequence": 42,
		"state_revision": 7,
		"orientation_yaw": 0.25,
		"flashlight_enabled": false,
	}


func _item_graph() -> Dictionary:
	return {
		"checksum": "a".repeat(64),
		"containers": {"container/shared/crate/1": {"revision": 7}},
		"items": [
			{
				"item_id": "item/world/ore/1",
				"definition_id": "item/ore",
				"quantity": 3,
				"location": {"kind": "WORLD", "region_id": "earth"},
				"transform": {"origin": {"x": 1.0, "y": 0.0, "z": 2.0}},
			},
			{
				"item_id": "item/container/ore/2",
				"definition_id": "item/ore",
				"quantity": 2,
				"location": {"kind": "CONTAINER", "container_id": "container/shared/crate/1", "slot_index": 0},
			},
		],
	}


func _healthy_sample(pending: int, reliable_queue: int) -> Dictionary:
	return {
		"process_alive": true,
		"assertion_failures": 0,
		"disconnect_reconnect_failures": 0,
		"serious_error_count": 0,
		"state_divergence": false,
		"pending_operations": pending,
		"reliable_queue_depth": reliable_queue,
	}


func _assert(value: bool, message: String) -> void:
	assertions += 1
	if value:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("V0 full MVP harness contracts: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

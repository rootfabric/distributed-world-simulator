extends SceneTree

const Acceptance = preload("res://tests/runtime/v0/v0_full_mvp_acceptance.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_phase_spec()
	_test_state_aggregation()
	_test_result_set_integrity()
	_test_pass_evidence_contract()
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
	var all_pass := _valid_pass_results()
	_assert(Acceptance.aggregate_state(all_pass) == Acceptance.STATE_PASS, "37 evidence-valid PASS phases aggregate to PASS")
	var pending := all_pass.duplicate(true)
	pending[0] = Acceptance.phase_result(Acceptance.phases()[0], Acceptance.STATE_DEPENDENCY_PENDING, "dependency")
	_assert(Acceptance.aggregate_state(pending) == Acceptance.STATE_DEPENDENCY_PENDING, "dependency pending prevents green aggregate")
	var not_implemented := all_pass.duplicate(true)
	not_implemented[0] = Acceptance.phase_result(Acceptance.phases()[0], Acceptance.STATE_NOT_IMPLEMENTED, "not implemented")
	_assert(Acceptance.aggregate_state(not_implemented) == Acceptance.STATE_NOT_IMPLEMENTED, "not implemented prevents green aggregate")
	var failed := all_pass.duplicate(true)
	failed[0] = Acceptance.phase_result(Acceptance.phases()[0], Acceptance.STATE_FAIL, "failure")
	_assert(Acceptance.aggregate_state(failed) == Acceptance.STATE_FAIL, "failure state has aggregate precedence")
	var summary := Acceptance.build_summary(all_pass, "integration/base/sha", 30, "unit")
	_assert(String(summary.get("integration_base", "")) == "integration/base/sha", "machine evidence records integration base separately")
	_assert(bool(summary.get("result_set_integrity", {}).get("success", false)), "summary records result-set integrity")
	_assert(bool(summary.get("final_soak_duration_satisfied", false)), "summary derives final soak satisfaction from trusted evidence, not requested duration")
	var invalid := Acceptance.phase_result(Acceptance.phases()[0], "SKIP")
	_assert(String(invalid.get("state", "")) == Acceptance.STATE_FAIL, "unsupported SKIP cannot silently enter evidence")


func _test_result_set_integrity() -> void:
	var valid := _valid_pass_results()
	var missing := valid.duplicate(true)
	missing.remove_at(10)
	_assert(Acceptance.aggregate_state(missing) == Acceptance.STATE_FAIL, "missing required phase makes aggregate FAIL")
	_assert(not bool(Acceptance.validate_result_set(missing).get("success", true)), "missing phase fails result-set integrity")
	var duplicate := valid.duplicate(true)
	duplicate[10] = duplicate[9].duplicate(true)
	_assert(Acceptance.aggregate_state(duplicate) == Acceptance.STATE_FAIL, "duplicate phase makes aggregate FAIL")
	_assert(not bool(Acceptance.validate_result_set(duplicate).get("success", true)), "duplicate phase fails result-set integrity")
	var unexpected := valid.duplicate(true)
	unexpected[-1]["id"] = 99
	unexpected[-1]["code"] = "99"
	_assert(Acceptance.aggregate_state(unexpected) == Acceptance.STATE_FAIL, "unexpected phase cannot be credited")


func _test_pass_evidence_contract() -> void:
	var empty := Acceptance.phase_result(Acceptance.phases()[0], Acceptance.STATE_PASS, "", {})
	_assert(String(empty.get("state", "")) == Acceptance.STATE_FAIL, "PASS with evidence={} becomes FAIL")
	var raw_false_green: Array = []
	for phase in Acceptance.phases():
		raw_false_green.append({
			"id": phase["id"],
			"code": phase["code"],
			"name": phase["name"],
			"dependency": phase["dependency"],
			"state": Acceptance.STATE_PASS,
			"reason": "",
			"evidence": {},
		})
	_assert(Acceptance.aggregate_state(raw_false_green) == Acceptance.STATE_FAIL, "raw 37-phase PASS with empty evidence cannot manufacture green")
	var graph_evidence := _valid_evidence_for_phase(10)
	graph_evidence["item_graph"].erase("checksum")
	var invalid_graph := Acceptance.phase_result(Acceptance.phases()[9], Acceptance.STATE_PASS, "", graph_evidence)
	_assert(String(invalid_graph.get("state", "")) == Acceptance.STATE_FAIL, "canonical Item Graph PASS requires checksum")
	var final_evidence := _valid_evidence_for_phase(37)
	final_evidence["assertion_failures"] = 1
	var invalid_final := Acceptance.phase_result(Acceptance.phases()[36], Acceptance.STATE_PASS, "", final_evidence)
	_assert(String(invalid_final.get("state", "")) == Acceptance.STATE_FAIL, "nonzero final assertion counter rejects PASS")


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
	var short_result: Dictionary = short_tracker.finish(30.0)
	_assert(String(short_result.get("state", "")) == Acceptance.STATE_DEPENDENCY_PENDING, "short development soak cannot claim final PASS")
	var override_tracker := Acceptance.SoakTracker.new()
	override_tracker.observe(_healthy_sample(0, 0))
	override_tracker.observe(_healthy_sample(0, 0))
	var override_result: Dictionary = override_tracker.finish(30.0, 30)
	_assert(String(override_result.get("state", "")) == Acceptance.STATE_DEPENDENCY_PENDING, "caller cannot lower the final 30-minute soak minimum")
	var final_tracker := Acceptance.SoakTracker.new()
	final_tracker.observe(_healthy_sample(2, 3))
	final_tracker.observe(_healthy_sample(1, 2))
	var final_result: Dictionary = final_tracker.finish(float(Acceptance.FINAL_SOAK_SECONDS))
	_assert(String(final_result.get("state", "")) == Acceptance.STATE_PASS, "healthy trusted 30-minute elapsed value can satisfy soak contract")
	var growth_tracker := Acceptance.SoakTracker.new()
	growth_tracker.observe(_healthy_sample(0, 0))
	growth_tracker.observe(_healthy_sample(50, 55))
	growth_tracker.observe(_healthy_sample(49, 54))
	var growth_result: Dictionary = growth_tracker.finish(float(Acceptance.FINAL_SOAK_SECONDS))
	_assert(String(growth_result.get("state", "")) == Acceptance.STATE_FAIL, "persistent net pending/queue growth fails soak despite a small dip")
	var burst_tracker := Acceptance.SoakTracker.new()
	burst_tracker.observe(_healthy_sample(0, 0))
	burst_tracker.observe(_healthy_sample(50, 55))
	burst_tracker.observe(_healthy_sample(0, 0))
	var burst_result: Dictionary = burst_tracker.finish(float(Acceptance.FINAL_SOAK_SECONDS))
	_assert(String(burst_result.get("state", "")) == Acceptance.STATE_PASS, "bounded queue burst that returns to baseline is allowed")
	var crash_tracker := Acceptance.SoakTracker.new()
	var crash := _healthy_sample(0, 0)
	crash["process_alive"] = false
	crash_tracker.observe(crash)
	crash_tracker.observe(_healthy_sample(0, 0))
	_assert(String(crash_tracker.finish(float(Acceptance.FINAL_SOAK_SECONDS)).get("state", "")) == Acceptance.STATE_FAIL, "process exit fails soak")


func _valid_pass_results() -> Array:
	var results: Array = []
	for phase in Acceptance.phases():
		results.append(Acceptance.phase_result(phase, Acceptance.STATE_PASS, "", _valid_evidence_for_phase(int(phase["id"]))))
	return results


func _valid_evidence_for_phase(id: int) -> Dictionary:
	var graph := _evidence_item_graph()
	var world_item := {"item_id": "item/world/ore/1", "state": "WORLD"}
	var player_a := _player_record()
	player_a["logical_player_id"] = "a"
	player_a["player_entity_id"] = "player/a"
	var player_b := _player_record()
	var container := {"container_id": "container/shared/crate/1", "state": "OPEN", "revision": 7}
	var construction := {"server_generation": 4, "checksum": "construction/checksum/4"}
	var before := {"position": {"x": 0.0, "y": 0.0, "z": 0.0}}
	var after := {"position": {"x": 1.0, "y": 0.0, "z": 0.0}}
	match id:
		1:
			return {"server": {"process_id": 101, "alive": true}}
		2:
			return {"client_a": {"process_id": 102, "alive": true, "session_id": "session/a/1"}}
		3:
			return {"client_b": {"process_id": 103, "alive": true, "session_id": "session/b/1"}}
		4, 5:
			return {"player_a": player_a, "player_b": player_b}
		6, 7, 8, 9:
			return {"player_entity_id": "player/a" if id in [6, 9] else "player/b", "authoritative_before": before, "authoritative_after": after, "rendered_before": before, "rendered_after": after}
		10:
			return {"item_graph": graph, "world_item": world_item}
		11, 12, 13, 14, 15:
			return {"item_graph": graph, "world_item": world_item, "player_inventory": {"container_id": "player/a", "revision": 5}, "convergence": true}
		16, 17, 18, 19:
			return {"item_graph": graph, "container": container, "convergence": true}
		20:
			return {"item_graph": graph, "player_inventory": {"container_id": "player/a", "revision": 6}}
		21, 22, 23, 24, 25:
			return {"construction": construction, "convergence": true}
		26:
			return {"client_b_session": {"session_id": "session/b/1", "connected": false}, "ownership_epoch": 2}
		27:
			return {"player_a": player_a, "continuation_check": true}
		28:
			return {"item_graph": graph, "world_item": world_item}
		29:
			return {"session_before": {"session_id": "session/b/1", "connected": false}, "session_after": {"session_id": "session/b/2", "connected": true}, "ownership_epoch_before": 2, "ownership_epoch_after": 3}
		30:
			return {"player_a": player_a, "player_b": player_b, "convergence": true}
		31:
			return {"item_graph_authority": graph, "item_graph_client_b": graph.duplicate(true), "convergence": true}
		32:
			return {"world_item_authority": world_item, "world_item_client_b": world_item.duplicate(true), "convergence": true}
		33:
			return {"container_authority": container, "container_client_b": container.duplicate(true), "convergence": true}
		34:
			return {"construction_authority": construction, "construction_client_b": construction.duplicate(true), "convergence": true}
		35:
			return {"observation_samples": [_healthy_sample(0, 0), _healthy_sample(0, 0)], "checks": {"convergence": true, "reconnect": true}, "trusted_start_ticks_msec": 100, "trusted_end_ticks_msec": 1800100, "trusted_elapsed_seconds": 1800.0, "trusted_sample_count": 2}
		36:
			return {"processes": [{"process_id": 101}, {"process_id": 102}, {"process_id": 103}], "shutdown_clean": true}
		37:
			return {"error_count": 0, "assertion_failures": 0, "process_exit_failures": 0, "leak_count": 0}
	return {}


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


func _evidence_item_graph() -> Dictionary:
	return {"graph_id": "item-graph/canonical", "revision": 12, "checksum": "a".repeat(64)}


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

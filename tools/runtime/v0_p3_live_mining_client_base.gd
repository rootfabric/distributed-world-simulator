extends "res://tools/runtime/v0_p2_live_reconnect_client.gd"

const EarthResourceSpatialResolver = preload(
	"res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd"
)

const RESOURCE_NODE_ID := "resource/earth/ore-demo/1"
const RESOURCE_READY_TIMEOUT_MS := 20000
const MINED_ITEM_PREFIX := "item/server-output/"

var expected_resource_checksum := ""
var expected_resource_generation := -1
var expected_output_item_id := ""


func _run() -> void:
	await _wait_frames(3)
	var resource_ready := await _wait_resource_state(
		func(snapshot: Dictionary) -> bool:
			return (
				String(snapshot.get("checksum", "")).length() == 64
				and int(snapshot.get("generation", -1)) >= 1
				and int(_resource_node(snapshot, RESOURCE_NODE_ID).get("remaining_units", -1)) >= 0
			),
		RESOURCE_READY_TIMEOUT_MS
	)
	_assert(resource_ready, "%s receives canonical ResourceMining snapshot" % mode)
	if not resource_ready:
		_fail("V0_P3_RESOURCE_SNAPSHOT_TIMEOUT")
		return
	match mode:
		"actor": await _run_actor_p3()
		"before": await _run_before_p3()
		"after": await _run_after_p3()


func _run_actor_p3() -> void:
	var initial_resource: Dictionary = client.get_resource_mining_snapshot()
	var initial_item: Dictionary = client.get_item_graph_snapshot()
	_assert(int(_resource_node(initial_resource, RESOURCE_NODE_ID).get("remaining_units", -1)) == 8, "actor sees eight initial ore units")
	_assert(_mined_output_ids(initial_item).is_empty(), "actor starts without P3 mined server-output items")
	_assert_runtime_healthy(client.get_report(), "P3 actor initial")
	_assert_p3_runtime_healthy(client.get_report(), "P3 actor initial")
	_write("ACTOR_READY", failures.is_empty(), {
		"resource_checksum": String(initial_resource.get("checksum", "")),
		"resource_generation": int(initial_resource.get("generation", -1)),
		"remaining_units": int(_resource_node(initial_resource, RESOURCE_NODE_ID).get("remaining_units", -1)),
		"item_graph_checksum": String(initial_item.get("checksum", "")),
		"actor_player": client.get_local_player_record(),
		"runtime_report": client.get_report(),
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var mutate_requested := await _wait_control_phase("MUTATE", CONTROL_TIMEOUT_MS)
	_assert(mutate_requested, "P3 actor receives MUTATE phase")
	if not mutate_requested:
		_fail("V0_P3_MUTATE_PHASE_TIMEOUT")
		return
	var b_disconnected := await _wait_player_connected("b", false, 15000)
	_assert(b_disconnected, "P3 actor observes B disconnected before mining")
	if not b_disconnected:
		_fail("V0_P3_B_DISCONNECT_NOT_OBSERVED")
		return

	var target_result := _resource_target_position(initial_resource)
	_assert(bool(target_result.get("success", false)), "P3 actor resolves Earth-fixed ore target into M3 plane")
	if not bool(target_result.get("success", false)):
		_fail(String(target_result.get("error_code", "V0_P3_RESOURCE_TARGET_RESOLUTION_FAILED")), target_result)
		return
	var target: Vector3 = target_result.get("details", {}).get("position", Vector3.ZERO)
	var moved: Dictionary = await _move_toward(target, 4)
	_assert(bool(moved.get("success", false)), "P3 actor approaches canonical ore node while B absent")
	if not bool(moved.get("success", false)):
		_fail(String(moved.get("error_code", "V0_P3_RESOURCE_APPROACH_FAILED")), moved)
		return

	var before_mine_resource: Dictionary = client.get_resource_mining_snapshot()
	var before_mine_item: Dictionary = client.get_item_graph_snapshot()
	var mine_operation := "operation/v0-p3/live/mine/%d" % Time.get_ticks_msec()
	var mined: Dictionary = client.execute_resource_mine_blocking(
		RESOURCE_NODE_ID,
		1,
		mine_operation
	)
	_assert(bool(mined.get("success", false)), "P3 actor mines one ore unit through RESOURCE_COMMAND")
	if not bool(mined.get("success", false)):
		_fail(String(mined.get("error_code", "V0_P3_RESOURCE_MINE_FAILED")), mined)
		return

	var resource_mutation_visible := await _wait_resource_state(
		func(snapshot: Dictionary) -> bool:
			return int(_resource_node(snapshot, RESOURCE_NODE_ID).get("remaining_units", -1)) == 7,
		10000
	)
	_assert(resource_mutation_visible, "P3 actor receives authoritative resource depletion to seven units")
	var item_mutation_visible := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return _mined_output_ids(snapshot).size() == 1,
		10000
	)
	_assert(item_mutation_visible, "P3 actor receives exactly one canonical mined output item")
	if not resource_mutation_visible or not item_mutation_visible:
		_fail("V0_P3_MINING_CONVERGENCE_TIMEOUT")
		return

	var mutated_resource: Dictionary = client.get_resource_mining_snapshot()
	var mutated_item: Dictionary = client.get_item_graph_snapshot()
	var output_ids: Array = _mined_output_ids(mutated_item)
	var output_item_id := String(output_ids[0]) if output_ids.size() == 1 else ""
	var output_item := _item_record(mutated_item, output_item_id)
	var output_location: Dictionary = Dictionary(output_item.get("location", {}))
	_assert(String(mutated_resource.get("checksum", "")) != String(before_mine_resource.get("checksum", "")), "P3 mining changes resource checksum")
	_assert(int(mutated_resource.get("generation", 0)) == int(before_mine_resource.get("generation", 0)) + 1, "P3 mining advances resource generation exactly once")
	_assert(String(mutated_item.get("checksum", "")) != String(before_mine_item.get("checksum", "")), "P3 mining changes Item Graph checksum")
	_assert(String(output_item.get("definition_id", "")) == "item/ore" and int(output_item.get("quantity", 0)) == 1, "P3 mined output is exactly one item/ore")
	_assert(String(output_location.get("kind", "")) == "INVENTORY" and String(output_location.get("player_id", "")) == "a", "P3 mined output belongs to canonical A inventory")
	_assert_runtime_healthy(client.get_report(), "P3 actor post-mine")
	_assert_p3_runtime_healthy(client.get_report(), "P3 actor post-mine")
	_write("ACTOR_MUTATED", failures.is_empty(), {
		"resource_checksum": String(mutated_resource.get("checksum", "")),
		"resource_generation": int(mutated_resource.get("generation", -1)),
		"remaining_units": int(_resource_node(mutated_resource, RESOURCE_NODE_ID).get("remaining_units", -1)),
		"item_graph_checksum": String(mutated_item.get("checksum", "")),
		"output_item_id": output_item_id,
		"actor_player": client.get_local_player_record(),
		"runtime_report": client.get_report(),
	})
	if not failures.is_empty():
		_shutdown(1)
		return

	var b_reconnected := await _wait_player_connected("b", true, CONTROL_TIMEOUT_MS)
	_assert(b_reconnected, "P3 actor remains live and observes B reconnect")
	if not b_reconnected:
		_fail("V0_P3_B_RETURN_NOT_OBSERVED")
		return
	await _wait_frames(5)
	var reconnect_resource: Dictionary = client.get_resource_mining_snapshot()
	var reconnect_item: Dictionary = client.get_item_graph_snapshot()
	var reconnect_outputs: Array = _mined_output_ids(reconnect_item)
	_assert(String(reconnect_resource.get("checksum", "")) == String(mutated_resource.get("checksum", "")), "B reconnect itself does not mutate ResourceMining state")
	_assert(String(reconnect_item.get("checksum", "")) == String(mutated_item.get("checksum", "")), "B reconnect itself does not mutate Item Graph")
	_assert(reconnect_outputs.size() == 1 and String(reconnect_outputs[0]) == output_item_id, "B reconnect itself does not duplicate mined ore")
	_assert_runtime_healthy(client.get_report(), "P3 actor reconnect-observed")
	_assert_p3_runtime_healthy(client.get_report(), "P3 actor reconnect-observed")
	_write("ACTOR_RECONNECT_SEEN", failures.is_empty(), {
		"resource_checksum": String(reconnect_resource.get("checksum", "")),
		"resource_generation": int(reconnect_resource.get("generation", -1)),
		"remaining_units": int(_resource_node(reconnect_resource, RESOURCE_NODE_ID).get("remaining_units", -1)),
		"item_graph_checksum": String(reconnect_item.get("checksum", "")),
		"output_item_id": output_item_id,
		"actor_player": client.get_local_player_record(),
		"b_player": client.get_player("b"),
		"runtime_report": client.get_report(),
	})

	var finish_requested := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish_requested, "P3 actor receives FINISH phase")
	if not finish_requested:
		_fail("V0_P3_FINISH_PHASE_TIMEOUT")
		return
	_complete("ACTOR_COMPLETE", {
		"resource_checksum": String(client.get_resource_mining_snapshot().get("checksum", "")),
		"item_graph_checksum": String(client.get_item_graph_snapshot().get("checksum", "")),
		"runtime_report": client.get_report(),
	})


func _run_before_p3() -> void:
	var resource: Dictionary = client.get_resource_mining_snapshot()
	var item: Dictionary = client.get_item_graph_snapshot()
	_assert(int(_resource_node(resource, RESOURCE_NODE_ID).get("remaining_units", -1)) == 8, "B initial session sees eight ore units")
	_assert(_mined_output_ids(item).is_empty(), "B initial session sees no mined server-output ore")
	_assert(bool(client.get_player("a").get("connected", false)), "B initial session observes A connected")
	var report: Dictionary = client.get_report()
	_assert_runtime_healthy(report, "P3 B initial")
	_assert_p3_runtime_healthy(report, "P3 B initial")
	var leave: Dictionary = client.request_graceful_leave(3000)
	_assert(bool(leave.get("success", false)), "P3 B initial session leaves through canonical LEAVE")
	_write("BEFORE_COMPLETE", failures.is_empty(), {
		"resource_checksum": String(resource.get("checksum", "")),
		"resource_generation": int(resource.get("generation", -1)),
		"remaining_units": int(_resource_node(resource, RESOURCE_NODE_ID).get("remaining_units", -1)),
		"item_graph_checksum": String(item.get("checksum", "")),
		"transport_session_id": String(report.get("transport_session_id", "")),
		"player_entity_id": String(report.get("player_entity_id", "")),
		"ownership_epoch": int(report.get("ownership_epoch", 0)),
		"runtime_report": report,
	})
	_shutdown(0 if failures.is_empty() else 1)


func _run_after_p3() -> void:
	var resource_converged := await _wait_resource_state(
		func(snapshot: Dictionary) -> bool:
			return (
				String(snapshot.get("checksum", "")).length() == 64
				and int(snapshot.get("generation", -1)) == expected_resource_generation
				and String(snapshot.get("checksum", "")) == expected_resource_checksum
				and int(_resource_node(snapshot, RESOURCE_NODE_ID).get("remaining_units", -1)) == 7
			),
		15000
	)
	_assert(resource_converged, "reconnected B converges to absent-peer resource depletion")
	var item_converged := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return (
				String(snapshot.get("checksum", "")) == expected_item_checksum
				and expected_output_item_id in _mined_output_ids(snapshot)
			),
		15000
	)
	_assert(item_converged, "reconnected B converges to absent-peer mined Item Graph output")
	var report: Dictionary = client.get_report()
	_assert_runtime_healthy(report, "P3 B reconnected")
	_assert_p3_runtime_healthy(report, "P3 B reconnected")
	_assert(String(report.get("transport_session_id", "")) != previous_session_id, "P3 reconnected B receives a new transport session")
	_assert(String(report.get("player_entity_id", "")) == previous_player_entity_id, "P3 reconnected B preserves canonical player entity")
	_assert(int(report.get("ownership_epoch", 0)) > previous_ownership_epoch, "P3 reconnected B advances ownership epoch")
	_assert(bool(client.get_player("a").get("connected", false)), "P3 reconnected B observes A still connected")
	await _wait_frames(5)
	var resource: Dictionary = client.get_resource_mining_snapshot()
	var item: Dictionary = client.get_item_graph_snapshot()
	var output_ids: Array = _mined_output_ids(item)
	_assert(output_ids.size() == 1 and String(output_ids[0]) == expected_output_item_id, "P3 reconnected B sees exactly one deterministic mined output")
	_write("RECONNECT_READY", failures.is_empty(), {
		"resource_checksum": String(resource.get("checksum", "")),
		"resource_generation": int(resource.get("generation", -1)),
		"remaining_units": int(_resource_node(resource, RESOURCE_NODE_ID).get("remaining_units", -1)),
		"item_graph_checksum": String(item.get("checksum", "")),
		"output_item_id": expected_output_item_id,
		"transport_session_id": String(report.get("transport_session_id", "")),
		"player_entity_id": String(report.get("player_entity_id", "")),
		"ownership_epoch": int(report.get("ownership_epoch", 0)),
		"actor_player": client.get_player("a"),
		"runtime_report": report,
	})
	if not failures.is_empty():
		_shutdown(1)
		return
	var finish_requested := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish_requested, "P3 reconnected B receives FINISH phase")
	if not finish_requested:
		_fail("V0_P3_RECONNECT_FINISH_PHASE_TIMEOUT")
		return
	var leave: Dictionary = client.request_graceful_leave(3000)
	_assert(bool(leave.get("success", false)), "P3 reconnected B leaves cleanly")
	_complete("RECONNECT_COMPLETE", {
		"resource_checksum": String(resource.get("checksum", "")),
		"item_graph_checksum": String(item.get("checksum", "")),
		"leave": leave,
		"runtime_report": client.get_report(),
	})


func _wait_resource_state(predicate: Callable, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		if bool(predicate.call(client.get_resource_mining_snapshot())):
			return true
		await create_timer(0.05).timeout
	return false


func _resource_target_position(snapshot: Dictionary) -> Dictionary:
	var node := _resource_node(snapshot, RESOURCE_NODE_ID)
	if node.is_empty():
		return {"success": false, "error_code": "RESOURCE_NOT_FOUND", "details": {}}
	var resolver = EarthResourceSpatialResolver.new()
	var setup_result: Dictionary = resolver.setup()
	if not bool(setup_result.get("success", false)):
		return setup_result
	var resolved: Dictionary = resolver.resolve_planar(Dictionary(node.get("spatial", {})))
	if not bool(resolved.get("success", false)):
		return resolved
	var planar: Dictionary = Dictionary(resolved.get("details", {}).get("planar_position", {}))
	return {
		"success": true,
		"error_code": "",
		"details": {
			"position": Vector3(
				float(planar.get("x", 0.0)),
				0.0,
				float(planar.get("z", 0.0))
			),
		},
	}


func _resource_node(snapshot: Dictionary, node_id: String) -> Dictionary:
	for node_value in snapshot.get("nodes", []):
		if node_value is Dictionary and String(node_value.get("resource_node_id", "")) == node_id:
			return Dictionary(node_value).duplicate(true)
	return {}


func _mined_output_ids(snapshot: Dictionary) -> Array:
	var result: Array = []
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", ""))
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			item_id.begins_with(MINED_ITEM_PREFIX)
			and String(item.get("definition_id", "")) == "item/ore"
			and int(item.get("quantity", 0)) == 1
			and String(location.get("kind", "")) == "INVENTORY"
			and String(location.get("player_id", "")) == "a"
		):
			result.append(item_id)
	result.sort()
	return result


func _assert_p3_runtime_healthy(report: Dictionary, label: String) -> void:
	var resource_report: Dictionary = Dictionary(report.get("v0_p3_resource_mining", {}))
	_assert(int(resource_report.get("rejections", 0)) == 0, "%s has zero resource replica rejections" % label)
	_assert(not bool(resource_report.get("resync_pending", false)), "%s has no pending resource resync" % label)


func _parse_args() -> void:
	super._parse_args()
	for value in OS.get_cmdline_user_args():
		var argument := String(value)
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		var key := argument.substr(2, separator - 2)
		var raw := argument.substr(separator + 1)
		match key:
			"expected-resource-checksum": expected_resource_checksum = raw
			"expected-resource-generation": expected_resource_generation = int(raw)
			"expected-output-item-id": expected_output_item_id = raw

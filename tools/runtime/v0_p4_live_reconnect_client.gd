extends "res://tools/runtime/v0_p3_live_mining_client.gd"

const OutpostAdapterScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_mvp_outpost_client_adapter.gd"
)

const STAGE_COSTS: Array[int] = [2, 4, 2]
const STAGE_REMAINING: Array[int] = [6, 2, 0]
const STATE_TIMEOUT_MS := 20000

var outpost


func _run() -> void:
	await _wait_frames(3)
	var resource_ready := await _wait_resource_state(
		func(snapshot: Dictionary) -> bool:
			return (
				String(snapshot.get("checksum", "")).length() == 64
				and int(snapshot.get("generation", -1)) >= 1
				and int(_resource_node(snapshot, RESOURCE_NODE_ID).get("remaining_units", -1)) >= 0
			),
		STATE_TIMEOUT_MS
	)
	_assert(resource_ready, "%s receives canonical ResourceMining snapshot" % mode)
	var construction_ready := await _wait_construction_state(
		func(bundle: Dictionary) -> bool:
			return (
				String(bundle.get("checksum", "")).length() == 64
				and int(bundle.get("server_generation", -1)) >= 0
			),
		STATE_TIMEOUT_MS
	)
	_assert(construction_ready, "%s receives canonical Construction bundle" % mode)
	if not resource_ready or not construction_ready:
		_fail("V0_P4_LIVE_RECONNECT_INITIAL_STATE_TIMEOUT")
		return
	outpost = OutpostAdapterScript.new()
	var configured: Dictionary = outpost.setup(client)
	_assert(bool(configured.get("success", false)), "%s configures canonical outpost client adapter" % mode)
	if not bool(configured.get("success", false)):
		_fail(String(configured.get("error_code", "V0_P4_OUTPOST_ADAPTER_SETUP_FAILED")), configured)
		return
	match mode:
		"actor": await _run_actor_p4()
		"before": await _run_before_p4()
		"after": await _run_after_p4()


func _run_actor_p4() -> void:
	_assert(int(_resource_node(client.get_resource_mining_snapshot(), RESOURCE_NODE_ID).get("remaining_units", -1)) == 8, "actor starts with eight canonical ore units")
	_assert(_ore_quantity(client.get_item_graph_snapshot(), "a") == 0, "actor starts with zero mined ore")
	_assert(int(outpost.get_status().get("completed_stage_count", -1)) == 0, "actor starts before foundation")
	_assert_runtime_healthy(client.get_report(), "P4.6 actor initial")
	_assert_p3_runtime_healthy(client.get_report(), "P4.6 actor initial")
	_write("ACTOR_READY", failures.is_empty(), _state_details())
	if not failures.is_empty():
		_shutdown(1)
		return

	var target_result := _resource_target_position(client.get_resource_mining_snapshot())
	_assert(bool(target_result.get("success", false)), "P4.6 actor resolves canonical ore target")
	if not bool(target_result.get("success", false)):
		_fail(String(target_result.get("error_code", "V0_P4_RESOURCE_TARGET_FAILED")), target_result)
		return
	var approached := false
	for stage_index in range(STAGE_COSTS.size()):
		var phase := "STAGE_%d" % stage_index
		var requested := await _wait_control_phase(phase, CONTROL_TIMEOUT_MS)
		_assert(requested, "actor receives %s phase" % phase)
		if not requested:
			_fail("V0_P4_STAGE_PHASE_TIMEOUT", {"stage_index": stage_index})
			return
		if not approached:
			var target: Vector3 = target_result.get("details", {}).get("position", Vector3.ZERO)
			var moved: Dictionary = await _move_toward(target, 4)
			_assert(bool(moved.get("success", false)), "actor approaches canonical ore node")
			if not bool(moved.get("success", false)):
				_fail(String(moved.get("error_code", "V0_P4_RESOURCE_APPROACH_FAILED")), moved)
				return
			approached = true

		var mine_op := "operation/v0-p4/e2e/a/mine-stage-%d" % stage_index
		var mined: Dictionary = client.execute_resource_mine_blocking(
			RESOURCE_NODE_ID,
			STAGE_COSTS[stage_index],
			mine_op
		)
		_assert(bool(mined.get("success", false)), "actor mines exact stage-%d ore cost" % stage_index)
		if not bool(mined.get("success", false)):
			_fail(String(mined.get("error_code", "V0_P4_E2E_MINE_FAILED")), mined)
			return
		var mined_visible := await _wait_resource_state(
			func(snapshot: Dictionary) -> bool:
				return int(_resource_node(snapshot, RESOURCE_NODE_ID).get("remaining_units", -1)) == STAGE_REMAINING[stage_index],
			STATE_TIMEOUT_MS
		)
		_assert(mined_visible, "actor receives stage-%d resource depletion" % stage_index)
		var ore_visible := await _wait_item_state(
			func(snapshot: Dictionary) -> bool:
				return _ore_quantity(snapshot, "a") == STAGE_COSTS[stage_index],
			STATE_TIMEOUT_MS
		)
		_assert(ore_visible, "actor receives stage-%d canonical mined ore" % stage_index)
		if not mined_visible or not ore_visible:
			_fail("V0_P4_E2E_MINE_CONVERGENCE_TIMEOUT", {"stage_index": stage_index})
			return

		var built: Dictionary = outpost.build_next_stage_blocking()
		_assert(bool(built.get("success", false)), "actor builds stage-%d from canonical mined ore" % stage_index)
		if not bool(built.get("success", false)):
			_fail(String(built.get("error_code", "V0_P4_E2E_BUILD_FAILED")), built)
			return
		var item_consumed := await _wait_item_state(
			func(snapshot: Dictionary) -> bool:
				return _ore_quantity(snapshot, "a") == 0,
			STATE_TIMEOUT_MS
		)
		var construction_visible := await _wait_construction_state(
			func(_bundle: Dictionary) -> bool:
				return int(outpost.get_status().get("completed_stage_count", -1)) == stage_index + 1,
			STATE_TIMEOUT_MS
		)
		_assert(item_consumed, "stage-%d build consumes all allocated ore" % stage_index)
		_assert(construction_visible, "stage-%d Construction publication reaches actor" % stage_index)
		if not item_consumed or not construction_visible:
			_fail("V0_P4_E2E_BUILD_CONVERGENCE_TIMEOUT", {"stage_index": stage_index})
			return
		_assert_runtime_healthy(client.get_report(), "P4.6 actor stage %d" % stage_index)
		_assert_p3_runtime_healthy(client.get_report(), "P4.6 actor stage %d" % stage_index)
		_write("ACTOR_STAGE_%d" % stage_index, failures.is_empty(), _state_details())
		if not failures.is_empty():
			_shutdown(1)
			return

	var final_status: Dictionary = outpost.get_status()
	_assert(bool(final_status.get("complete", false)), "actor completes Earth outpost")
	_assert(int(_resource_node(client.get_resource_mining_snapshot(), RESOURCE_NODE_ID).get("remaining_units", -1)) == 0, "actor exhausts canonical ore node exactly")
	_assert(_ore_quantity(client.get_item_graph_snapshot(), "a") == 0, "actor ends with zero ore after complete build")

	var leave_phase := await _wait_control_phase("LEAVE_B", CONTROL_TIMEOUT_MS)
	_assert(leave_phase, "actor receives LEAVE_B phase")
	if not leave_phase:
		_fail("V0_P4_LEAVE_B_PHASE_TIMEOUT")
		return
	var b_left := await _wait_player_connected("b", false, STATE_TIMEOUT_MS)
	_assert(b_left, "actor observes B canonical disconnect")
	if not b_left:
		_fail("V0_P4_B_DISCONNECT_NOT_OBSERVED")
		return
	var final_before_reconnect := _state_details()
	_write("ACTOR_B_LEFT", failures.is_empty(), final_before_reconnect)

	var b_returned := await _wait_player_connected("b", true, CONTROL_TIMEOUT_MS)
	_assert(b_returned, "actor observes B reconnect")
	if not b_returned:
		_fail("V0_P4_B_RECONNECT_NOT_OBSERVED")
		return
	await _wait_frames(5)
	var final_after_reconnect := _state_details()
	_assert(_same_canonical_state(final_before_reconnect, final_after_reconnect), "B reconnect itself mutates no Resource/Item/Construction state")
	_write("ACTOR_RECONNECT_SEEN", failures.is_empty(), final_after_reconnect)
	if not failures.is_empty():
		_shutdown(1)
		return

	var finish := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish, "actor receives FINISH phase")
	if not finish:
		_fail("V0_P4_ACTOR_FINISH_TIMEOUT")
		return
	_complete("ACTOR_COMPLETE", _state_details())


func _run_before_p4() -> void:
	_assert(bool(client.get_player("a").get("connected", false)), "B initial session observes A connected")
	_assert_runtime_healthy(client.get_report(), "P4.6 B initial")
	_assert_p3_runtime_healthy(client.get_report(), "P4.6 B initial")
	_write("B_READY", failures.is_empty(), _state_details())
	if not failures.is_empty():
		_shutdown(1)
		return
	for stage_index in range(STAGE_COSTS.size()):
		var phase := "STAGE_%d" % stage_index
		var requested := await _wait_control_phase(phase, CONTROL_TIMEOUT_MS)
		_assert(requested, "B receives %s phase" % phase)
		if not requested:
			_fail("V0_P4_B_STAGE_PHASE_TIMEOUT", {"stage_index": stage_index})
			return
		var converged := await _wait_stage_state(stage_index)
		_assert(converged, "B converges after stage-%d mine/build publication" % stage_index)
		if not converged:
			_fail("V0_P4_B_STAGE_CONVERGENCE_TIMEOUT", {"stage_index": stage_index})
			return
		_assert_runtime_healthy(client.get_report(), "P4.6 B stage %d" % stage_index)
		_assert_p3_runtime_healthy(client.get_report(), "P4.6 B stage %d" % stage_index)
		_write("B_STAGE_%d" % stage_index, failures.is_empty(), _state_details())
		if not failures.is_empty():
			_shutdown(1)
			return

	var leave_phase := await _wait_control_phase("LEAVE_B", CONTROL_TIMEOUT_MS)
	_assert(leave_phase, "B receives LEAVE_B phase")
	if not leave_phase:
		_fail("V0_P4_B_LEAVE_PHASE_TIMEOUT")
		return
	var report: Dictionary = client.get_report()
	var details := _state_details()
	details["transport_session_id"] = String(report.get("transport_session_id", ""))
	details["player_entity_id"] = String(report.get("player_entity_id", ""))
	details["ownership_epoch"] = int(report.get("ownership_epoch", 0))
	var leave: Dictionary = client.request_graceful_leave(3000)
	_assert(bool(leave.get("success", false)), "B initial session leaves through canonical LEAVE")
	_write("BEFORE_COMPLETE", failures.is_empty(), details)
	_shutdown(0 if failures.is_empty() else 1)


func _run_after_p4() -> void:
	var resource_converged := await _wait_resource_state(
		func(snapshot: Dictionary) -> bool:
			return (
				String(snapshot.get("checksum", "")) == expected_resource_checksum
				and int(snapshot.get("generation", -1)) == expected_resource_generation
				and int(_resource_node(snapshot, RESOURCE_NODE_ID).get("remaining_units", -1)) == 0
			),
		STATE_TIMEOUT_MS
	)
	var item_converged := await _wait_item_state(
		func(snapshot: Dictionary) -> bool:
			return (
				String(snapshot.get("checksum", "")) == expected_item_checksum
				and _ore_quantity(snapshot, "a") == 0
			),
		STATE_TIMEOUT_MS
	)
	var construction_converged := await _wait_construction_state(
		func(bundle: Dictionary) -> bool:
			return (
				String(bundle.get("checksum", "")) == expected_construction_checksum
				and int(bundle.get("server_generation", -1)) == expected_construction_generation
				and bool(outpost.get_status().get("complete", false))
			),
		STATE_TIMEOUT_MS
	)
	_assert(resource_converged, "reconnected B reconstructs exact final ResourceMining state")
	_assert(item_converged, "reconnected B reconstructs exact final Item Graph state")
	_assert(construction_converged, "reconnected B reconstructs exact final Construction state")
	var report: Dictionary = client.get_report()
	_assert(String(report.get("transport_session_id", "")) != previous_session_id, "reconnected B gets new transport session")
	_assert(String(report.get("player_entity_id", "")) == previous_player_entity_id, "reconnected B preserves canonical player entity")
	_assert(int(report.get("ownership_epoch", 0)) > previous_ownership_epoch, "reconnected B advances ownership epoch")
	_assert(bool(client.get_player("a").get("connected", false)), "reconnected B observes A still connected")
	_assert_runtime_healthy(report, "P4.6 B reconnected")
	_assert_p3_runtime_healthy(report, "P4.6 B reconnected")
	_write("RECONNECT_READY", failures.is_empty(), _state_details().merged({
		"transport_session_id": String(report.get("transport_session_id", "")),
		"player_entity_id": String(report.get("player_entity_id", "")),
		"ownership_epoch": int(report.get("ownership_epoch", 0)),
	}, true))
	if not failures.is_empty():
		_shutdown(1)
		return
	var finish := await _wait_control_phase("FINISH", CONTROL_TIMEOUT_MS)
	_assert(finish, "reconnected B receives FINISH phase")
	if not finish:
		_fail("V0_P4_RECONNECT_FINISH_TIMEOUT")
		return
	var leave: Dictionary = client.request_graceful_leave(3000)
	_assert(bool(leave.get("success", false)), "reconnected B leaves cleanly")
	_complete("RECONNECT_COMPLETE", _state_details())


func _wait_stage_state(stage_index: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < STATE_TIMEOUT_MS:
		var resource: Dictionary = client.get_resource_mining_snapshot()
		var item: Dictionary = client.get_item_graph_snapshot()
		var status: Dictionary = outpost.get_status()
		if (
			int(_resource_node(resource, RESOURCE_NODE_ID).get("remaining_units", -1)) == STAGE_REMAINING[stage_index]
			and _ore_quantity(item, "a") == 0
			and int(status.get("completed_stage_count", -1)) == stage_index + 1
		):
			return true
		await create_timer(0.05).timeout
	return false


func _state_details() -> Dictionary:
	var resource: Dictionary = client.get_resource_mining_snapshot()
	var item: Dictionary = client.get_item_graph_snapshot()
	var construction: Dictionary = client.get_construction_bundle()
	var status: Dictionary = outpost.get_status() if outpost != null else {}
	return {
		"resource_checksum": String(resource.get("checksum", "")),
		"resource_generation": int(resource.get("generation", -1)),
		"remaining_units": int(_resource_node(resource, RESOURCE_NODE_ID).get("remaining_units", -1)),
		"item_graph_checksum": String(item.get("checksum", "")),
		"item_graph_revision": int(item.get("revision", -1)),
		"ore_quantity_a": _ore_quantity(item, "a"),
		"construction_checksum": String(construction.get("checksum", "")),
		"construction_generation": int(construction.get("server_generation", -1)),
		"completed_stage_count": int(status.get("completed_stage_count", -1)),
		"construction_complete": bool(status.get("complete", false)),
		"construct_checksum": String(status.get("construct_checksum", "")),
		"runtime_report": client.get_report(),
	}


func _ore_quantity(snapshot: Dictionary, player_id: String) -> int:
	var total := 0
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			String(item.get("definition_id", "")) == "item/ore"
			and String(location.get("kind", "")) == "INVENTORY"
			and String(location.get("player_id", "")) == player_id
		):
			total += int(item.get("quantity", 0))
	return total


func _same_canonical_state(a: Dictionary, b: Dictionary) -> bool:
	for key in [
		"resource_checksum", "resource_generation", "remaining_units",
		"item_graph_checksum", "item_graph_revision", "ore_quantity_a",
		"construction_checksum", "construction_generation",
		"completed_stage_count", "construction_complete", "construct_checksum",
	]:
		if a.get(key) != b.get(key):
			return false
	return true

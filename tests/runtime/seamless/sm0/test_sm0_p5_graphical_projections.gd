extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_contract.gd")
const ViewContract = preload("res://scripts/runtime/seamless/sm0/sm0_p5_projection_view_contract.gd")
const GraphicalHost = preload("res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_host.gd")
const Observer = preload("res://scripts/runtime/seamless/sm0/sm0_p5_graphical_projection_observer.gd")

const CONTROL_A := 25980
const CONTROL_B := 25981
const VIEW_A := 25990
const VIEW_B := 25991
const EXPECTED_ASSERTIONS := 29

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	_test_view_contract()
	await _test_two_authority_graphical_views()
	_finish()


func _test_view_contract() -> void:
	var player_a := _player("a", -1.0, 4)
	var player_b := _player("b", 1.0, 5)
	var projection_b := ProjectionContract.create_from_player(player_b, Contracts.AUTHORITY_B, Contracts.ZONE_B, 1)
	var view := ViewContract.create(Contracts.AUTHORITY_A, Contracts.ZONE_A, 1, player_a, projection_b, 1)
	_assert(bool(ViewContract.validate(view).get("success", false)), "view contract accepts local+remote derived presentation")
	_assert(not Dictionary(view.get("local_player", {})).has("transport_session_id"), "local presentation omits transport session")
	_assert(not Dictionary(view.get("remote_projection", {})).has("inventory"), "remote presentation omits inventory truth")
	_assert(not bool(view.get("command_channel", true)), "view contract explicitly has no command channel")
	_assert(bool(Dictionary(view.get("remote_projection", {})).get("read_only", false)), "remote presentation remains explicitly read-only")

	var bad_command := view.duplicate(true)
	bad_command["command_channel"] = true
	bad_command["checksum"] = ""
	bad_command = Utils.finalize_json_checksum(bad_command)
	_assert(String(ViewContract.validate(bad_command).get("error_code", "")) == "SM0_P5_VIEW_COMMAND_CHANNEL_FORBIDDEN", "view contract rejects command channel")


func _test_two_authority_graphical_views() -> void:
	var observer_a = Observer.new()
	var observer_b = Observer.new()
	root.add_child(observer_a)
	root.add_child(observer_b)
	var observer_setup_a: Dictionary = observer_a.setup({"viewer_authority_id": Contracts.AUTHORITY_A, "listen_port": VIEW_A})
	var observer_setup_b: Dictionary = observer_b.setup({"viewer_authority_id": Contracts.AUTHORITY_B, "listen_port": VIEW_B})
	_assert(bool(observer_setup_a.get("success", false)), "graphical observer A starts")
	_assert(bool(observer_setup_b.get("success", false)), "graphical observer B starts")
	if not bool(observer_setup_a.get("success", false)) or not bool(observer_setup_b.get("success", false)):
		_finish_nodes(observer_a, observer_b, null, null)
		return

	var server_a = GraphicalHost.new()
	var server_b = GraphicalHost.new()
	root.add_child(server_a)
	root.add_child(server_b)
	var setup_a: Dictionary = server_a.setup({
		"authority_id": Contracts.AUTHORITY_A,
		"zone_id": Contracts.ZONE_A,
		"local_player_id": "a",
		"control_port": CONTROL_A,
		"peer_control_port": CONTROL_B,
		"view_port": VIEW_A,
	})
	var setup_b: Dictionary = server_b.setup({
		"authority_id": Contracts.AUTHORITY_B,
		"zone_id": Contracts.ZONE_B,
		"local_player_id": "b",
		"control_port": CONTROL_B,
		"peer_control_port": CONTROL_A,
		"view_port": VIEW_B,
	})
	_assert(bool(setup_a.get("success", false)), "P5 server A starts with observer feed")
	_assert(bool(setup_b.get("success", false)), "P5 server B starts with observer feed")
	if not bool(setup_a.get("success", false)) or not bool(setup_b.get("success", false)):
		_finish_nodes(observer_a, observer_b, server_a, server_b)
		return

	await _wait_for_remote_pair(observer_a, observer_b, 2500)
	var status_a: Dictionary = observer_a.status_for_tests()
	var status_b: Dictionary = observer_b.status_for_tests()
	_assert(bool(status_a.get("local_visible", false)), "observer A renders local player a")
	_assert(bool(status_b.get("local_visible", false)), "observer B renders local player b")
	_assert(bool(status_a.get("remote_visible", false)), "observer A renders remote projection b")
	_assert(bool(status_b.get("remote_visible", false)), "observer B renders remote projection a")
	_assert(String(status_a.get("local_player_id", "")) == "a", "observer A local identity is a")
	_assert(String(status_a.get("remote_player_id", "")) == "b", "observer A remote identity is b")
	_assert(String(status_b.get("local_player_id", "")) == "b", "observer B local identity is b")
	_assert(String(status_b.get("remote_player_id", "")) == "a", "observer B remote identity is a")
	_assert(bool(status_a.get("remote_read_only", false)), "observer A remote presentation is read-only")
	_assert(bool(status_b.get("remote_read_only", false)), "observer B remote presentation is read-only")
	_assert(not bool(status_a.get("command_channel", true)), "observer A has no command channel")
	_assert(not bool(status_b.get("command_channel", true)), "observer B has no command channel")
	_assert(int(server_a.status_for_tests().get("writer_count", 0)) == 1, "server A remains exactly one canonical writer")
	_assert(int(server_b.status_for_tests().get("writer_count", 0)) == 1, "server B remains exactly one canonical writer")

	var remote_before := Dictionary(status_b.get("remote_position", {}))
	var canonical_a := Dictionary(server_a.status_for_tests().get("canonical_player", {}))
	var move_a: Dictionary = server_a.apply_move_for_tests({
		"logical_player_id": "a",
		"input_sequence": int(canonical_a.get("last_input_sequence", 0)) + 1,
		"delta_x": 0.35,
		"delta_z": 0.0,
	})
	_assert(bool(move_a.get("success", false)), "canonical A move succeeds")
	await _wait_for_remote_change(observer_b, remote_before, 2000)
	var status_b_after := observer_b.status_for_tests()
	_assert(Dictionary(status_b_after.get("remote_position", {})) != remote_before, "observer B updates remote a presentation from newer canonical state")
	_assert(int(server_a.status_for_tests().get("writer_count", 0)) == 1, "graphical observer does not create second writer on A")

	var current_view := ViewContract.create(
		Contracts.AUTHORITY_A,
		Contracts.ZONE_A,
		100,
		Dictionary(server_a.status_for_tests().get("canonical_player", {})),
		Dictionary(server_a.status_for_tests().get("peer_projection", {})),
		1
	)
	var direct_accept := observer_a.accept_view_for_tests(current_view)
	_assert(bool(direct_accept.get("success", false)), "observer accepts a valid newer direct view")
	var divergent := current_view.duplicate(true)
	divergent["local_player"] = Dictionary(divergent.get("local_player", {})).duplicate(true)
	divergent["local_player"]["position"] = {"x": -99.0, "y": 0.0, "z": 0.0}
	divergent["local_player"]["checksum"] = ""
	divergent["local_player"] = Utils.finalize_json_checksum(Dictionary(divergent["local_player"]))
	divergent["checksum"] = ""
	divergent = Utils.finalize_json_checksum(divergent)
	_assert(String(observer_a.accept_view_for_tests(divergent).get("error_code", "")) == "SM0_P5_GRAPHICAL_SAME_SEQUENCE_MUTATION", "same-sequence divergent graphical view fails closed")

	_finish_nodes(observer_a, observer_b, server_a, server_b)
	await process_frame


func _player(logical_id: String, x: float, revision: int) -> Dictionary:
	return {
		"logical_player_id": logical_id,
		"player_entity_id": "player/%s" % logical_id,
		"ownership_epoch": 1,
		"state_revision": revision,
		"last_input_sequence": revision,
		"connected": true,
		"position": {"x": x, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"orientation_yaw": 0.0,
	}


func _wait_for_remote_pair(observer_a, observer_b, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var a: Dictionary = observer_a.status_for_tests()
		var b: Dictionary = observer_b.status_for_tests()
		if bool(a.get("remote_visible", false)) and bool(b.get("remote_visible", false)):
			return
		await process_frame
	_assert(false, "both graphical observers receive remote projections before timeout")


func _wait_for_remote_change(observer, before: Dictionary, timeout_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if Dictionary(observer.status_for_tests().get("remote_position", {})) != before:
			return
		await process_frame
	_assert(false, "graphical remote presentation updates before timeout")


func _finish_nodes(observer_a, observer_b, server_a, server_b) -> void:
	if server_a != null:
		server_a.shutdown(0, "test-complete")
		server_a.queue_free()
	if server_b != null:
		server_b.shutdown(0, "test-complete")
		server_b.queue_free()
	if observer_a != null:
		observer_a.shutdown(0, "test-complete")
		observer_a.queue_free()
	if observer_b != null:
		observer_b.shutdown(0, "test-complete")
		observer_b.queue_free()


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _assertions != EXPECTED_ASSERTIONS:
		_failures.append("assertion count mismatch: expected %d, got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failures.is_empty():
		print("SM0 P5.1 graphical cross-authority projections: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SM0 P5.1 graphical cross-authority projections: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
	quit(1)

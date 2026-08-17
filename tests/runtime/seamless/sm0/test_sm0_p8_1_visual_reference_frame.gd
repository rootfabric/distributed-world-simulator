extends SceneTree

const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const Observer = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd")

const EXPECTED_ASSERTIONS := 33
const EPS := 0.00001

var _assertions := 0
var _failed := false
var _observer: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_observer = Observer.new()
	_observer.name = "P81Observer"
	root.add_child(_observer)
	_check_success(_observer.setup({"listen_port": 26434, "visual_response_hz": 10.0}), "observer setup")

	var initial: Dictionary = _observer.status_for_tests()
	_check(bool(initial.get("reference_frame_parented", false)), "ship and player share ShipRoot")
	_check(int(initial.get("ship_root_instance_id", 0)) > 0, "ShipRoot created")
	_check(int(initial.get("ship_parent_instance_id", 0)) == int(initial.get("ship_root_instance_id", 0)), "ship parent is ShipRoot")
	_check(int(initial.get("player_parent_instance_id", 0)) == int(initial.get("ship_root_instance_id", 0)), "player parent is ShipRoot")
	_check(int(initial.get("ship_visual_instance_id", 0)) > 0, "ship visual created")
	_check(int(initial.get("player_visual_instance_id", 0)) > 0, "player visual created")
	_check(absf(float(initial.get("visual_response_hz", 0.0)) - 10.0) <= EPS, "visual response configured")

	var ship_id := int(initial.get("ship_visual_instance_id", 0))
	var player_id := int(initial.get("player_visual_instance_id", 0))
	var root_id := int(initial.get("ship_root_instance_id", 0))

	var player1 := _player(-5.0, 0.0, 0.5, 1)
	var anchor1 := Contract.create_anchor(Topology.AUTHORITY_A, 1, 10, {"x": 1.0, "y": 0.0, "z": 2.0}, 0.35, {"x": 0.8, "y": 0.0, "z": 0.1}, 0.2)
	var view1 := Contract.create_view(1, anchor1, 1, player1)
	_check_success(_observer.accept_view_for_tests(view1), "first view accepted")
	var state1: Dictionary = _observer.status_for_tests()
	_check(bool(state1.get("visual_initialized", false)), "first view initializes visual frame")
	_check(_vec_close(Dictionary(state1.get("rendered_ship_world_position", {})), Dictionary(anchor1.get("world_position", {}))), "first ship frame snaps to anchor")
	_check(_vec_close(Dictionary(state1.get("rendered_player_local_position", {})), Dictionary(player1.get("position", {}))), "player rendered in ship-local coordinates")
	var expected_world1 := Contract.compose_world_position(anchor1, Dictionary(player1.get("position", {})))
	var rendered_world1 := Dictionary(state1.get("rendered_player_world_position", {}))
	_check(absf(float(rendered_world1.get("x", 0.0)) - float(expected_world1.get("x", 0.0))) <= EPS, "parented player world x matches composed frame")
	_check(absf(float(rendered_world1.get("z", 0.0)) - float(expected_world1.get("z", 0.0))) <= EPS, "parented player world z matches composed frame")
	_check(absf(float(rendered_world1.get("y", 0.0)) - (float(expected_world1.get("y", 0.0)) + 0.75)) <= EPS, "visual deck offset is local-only")

	var player2 := _player(-5.0, 0.0, 0.5, 1)
	var anchor2 := Contract.create_anchor(Topology.AUTHORITY_C, 2, 20, {"x": 9.0, "y": 0.0, "z": -3.0}, 1.10, {"x": 0.8, "y": 0.0, "z": 0.1}, 0.2)
	var view2 := Contract.create_view(2, anchor2, 1, player2)
	_check_success(_observer.accept_view_for_tests(view2), "owner-pivot view accepted")
	var before_step := Dictionary(_observer.status_for_tests().get("rendered_ship_world_position", {}))
	_observer.advance_visual_for_tests(0.05)
	var mid: Dictionary = _observer.status_for_tests()
	var mid_ship := Dictionary(mid.get("rendered_ship_world_position", {}))
	_check(float(mid_ship.get("x", 0.0)) > float(before_step.get("x", 0.0)), "ShipRoot interpolates toward new anchor")
	_check(float(mid_ship.get("x", 0.0)) < float(Dictionary(anchor2.get("world_position", {})).get("x", 0.0)), "ShipRoot does not snap after initialization")
	_check(_vec_close(Dictionary(mid.get("rendered_player_local_position", {})), Dictionary(player2.get("position", {}))), "rigid passenger local position stays fixed during outer interpolation")
	_check(int(mid.get("owner_change_count", 0)) == 1, "owner pivot observed once")

	_observer.snap_visual_to_target_for_tests()
	var state2: Dictionary = _observer.status_for_tests()
	_check(_vec_close(Dictionary(state2.get("rendered_ship_world_position", {})), Dictionary(anchor2.get("world_position", {}))), "ShipRoot reaches target anchor")
	var expected_world2 := Contract.compose_world_position(anchor2, Dictionary(player2.get("position", {})))
	var rendered_world2 := Dictionary(state2.get("rendered_player_world_position", {}))
	_check(absf(float(rendered_world2.get("x", 0.0)) - float(expected_world2.get("x", 0.0))) <= EPS, "rigid passenger world x follows ShipRoot")
	_check(absf(float(rendered_world2.get("z", 0.0)) - float(expected_world2.get("z", 0.0))) <= EPS, "rigid passenger world z follows ShipRoot")

	var player3 := _player(-4.2, 0.0, 0.9, 2)
	var view3 := Contract.create_view(3, anchor2, 1, player3)
	_check_success(_observer.accept_view_for_tests(view3), "local-walk view accepted")
	_observer.advance_visual_for_tests(0.05)
	var walk_mid := Dictionary(_observer.status_for_tests().get("rendered_player_local_position", {}))
	_check(float(walk_mid.get("x", 0.0)) > -5.0 and float(walk_mid.get("x", 0.0)) < -4.2, "player local walk interpolates inside ShipRoot")
	_observer.snap_visual_to_target_for_tests()
	var state3: Dictionary = _observer.status_for_tests()
	_check(_vec_close(Dictionary(state3.get("rendered_player_local_position", {})), Dictionary(player3.get("position", {}))), "player local walk reaches target")
	_check(int(state3.get("ship_root_instance_id", 0)) == root_id, "ShipRoot persists across owner pivot")
	_check(int(state3.get("ship_visual_instance_id", 0)) == ship_id, "ship visual persists across owner pivot")
	_check(int(state3.get("player_visual_instance_id", 0)) == player_id, "player visual persists across owner pivot")

	var mutation := view3.duplicate(true)
	mutation["checksum"] = "same-sequence-mutation"
	var mutation_result: Dictionary = _observer.accept_view_for_tests(mutation)
	_check(not bool(mutation_result.get("success", true)), "same-sequence mutation still rejected")
	_check(String(mutation_result.get("error_code", "")) == "SM0_P8_VIEW_SAME_SEQUENCE_MUTATION", "same-sequence mutation error preserved")

	var stale := Contract.create_view(2, anchor2, 1, player3)
	var stale_result: Dictionary = _observer.accept_view_for_tests(stale)
	_check(not bool(stale_result.get("success", true)), "stale view still rejected")
	_check(String(stale_result.get("error_code", "")) == "SM0_P8_VIEW_STALE", "stale view error preserved")

	_finish()

func _player(x: float, y: float, z: float, sequence: int) -> Dictionary:
	return {
		"logical_player_id": Contract.LOGICAL_PLAYER_ID,
		"player_entity_id": Contract.PLAYER_ENTITY_ID,
		"position": {"x": x, "y": y, "z": z},
		"last_input_sequence": sequence,
		"state_revision": sequence,
	}

func _vec_close(a: Dictionary, b: Dictionary) -> bool:
	return absf(float(a.get("x", 0.0)) - float(b.get("x", 0.0))) <= EPS \
		and absf(float(a.get("y", 0.0)) - float(b.get("y", 0.0))) <= EPS \
		and absf(float(a.get("z", 0.0)) - float(b.get("z", 0.0))) <= EPS

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s: %s" % [label, result])

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("P8.1 assertion failed: %s" % label)

func _finish() -> void:
	if _observer != null:
		_observer.shutdown(0, "test-complete")
		_observer.queue_free()
	if _assertions != EXPECTED_ASSERTIONS:
		_failed = true
		push_error("P8.1 assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failed:
		print("SM0 P8.1 visual reference-frame repair: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 P8.1 visual reference-frame repair: PASS (%d assertions)" % _assertions)
	quit(0)

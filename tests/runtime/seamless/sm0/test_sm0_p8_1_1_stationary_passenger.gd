extends SceneTree

const NestedNode = preload("res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_node.gd")
const Contract = preload("res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_contract.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")

const EXPECTED_ASSERTIONS := 14
const EPS := 0.0000001

var _assertions := 0
var _failed := false
var _nested: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_nested = NestedNode.new()
	_nested.name = "P811StationaryNested"
	root.add_child(_nested)

	var setup: Dictionary = _nested.setup({
		"anchor_port": 26633,
		"view_port": 0,
		"auto_local_motion": false,
	})
	_check_success(setup, "stationary nested setup")

	var initial: Dictionary = _nested.status_for_tests()
	var player_before := Dictionary(initial.get("player", {}))
	_check(String(player_before.get("player_entity_id", "")) == Contract.PLAYER_ENTITY_ID, "player/a exists before proof")
	var sequence_before := int(player_before.get("last_input_sequence", -1))
	var position_before := Dictionary(player_before.get("position", {}))

	var anchor := Contract.create_anchor(
		Topology.AUTHORITY_A,
		1,
		10,
		{"x": 2.0, "y": 0.0, "z": -1.0},
		0.35,
		{"x": 0.8, "y": 0.0, "z": 0.1},
		0.2
	)
	_check_success(_nested.accept_anchor_for_tests(anchor), "stationary anchor accepted")
	_check(String(Dictionary(_nested.status_for_tests().get("anchor", {})).get("outer_owner_authority_id", "")) == Topology.AUTHORITY_A, "outer owner A accepted")

	await create_timer(0.30).timeout

	var after: Dictionary = _nested.status_for_tests()
	var player_after := Dictionary(after.get("player", {}))
	var position_after := Dictionary(player_after.get("position", {}))

	_check(String(player_after.get("player_entity_id", "")) == Contract.PLAYER_ENTITY_ID, "player/a identity preserved")
	_check(int(player_after.get("last_input_sequence", -2)) == sequence_before, "input sequence unchanged while stationary")
	_check(absf(float(position_after.get("x", 0.0)) - float(position_before.get("x", 0.0))) <= EPS, "local x unchanged")
	_check(absf(float(position_after.get("y", 0.0)) - float(position_before.get("y", 0.0))) <= EPS, "local y unchanged")
	_check(absf(float(position_after.get("z", 0.0)) - float(position_before.get("z", 0.0))) <= EPS, "local z unchanged")
	_check(int(after.get("view_sequence", 0)) >= 3, "views continue while passenger is stationary")
	_check(int(after.get("inner_authority_epoch", 0)) == 1, "inner authority epoch remains one")
	_check(int(after.get("writer_count", 0)) == 1, "nested authority remains writer")
	_check(String(Dictionary(after.get("anchor", {})).get("outer_owner_authority_id", "")) == Topology.AUTHORITY_A, "anchor owner remains A")
	_check(int(after.get("owner_change_count", -1)) == 0, "no synthetic owner pivot")
	_check(int(after.get("anchor_accept_count", 0)) == 1, "exactly one anchor accepted")

	_finish()

func _check_success(result: Dictionary, label: String) -> void:
	_check(bool(result.get("success", false)), "%s: %s" % [label, result])

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failed = true
	push_error("P8.1.1 assertion failed: %s" % label)

func _finish() -> void:
	if _nested != null:
		_nested.shutdown(0, "test-complete")
		_nested.queue_free()
	if _assertions != EXPECTED_ASSERTIONS:
		_failed = true
		push_error("P8.1.1 assertion count mismatch: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failed:
		print("SM0 P8.1.1 stationary passenger: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 P8.1.1 stationary passenger: PASS (%d assertions)" % _assertions)
	quit(0)

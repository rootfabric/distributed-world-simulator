extends SceneTree

const Contracts = preload("res://scripts/runtime/seamless/sm0/sm0_contracts.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ViewContract = preload("res://scripts/runtime/seamless/sm0/sm0_p6_pivot_view_contract.gd")
const Observer = preload("res://scripts/runtime/seamless/sm0/sm0_p6_projection_pivot_observer.gd")

const VIEW_PORT := 26110
const EXPECTED_ASSERTIONS := 30

var _assertions := 0
var _failures: Array[String] = []


func _init() -> void:
	_run()


func _run() -> void:
	_test_contract_roles()
	await _test_persistent_visual_pivot()
	_finish()


func _test_contract_roles() -> void:
	var state := _player_state(-0.5, 5, 8)
	var directory_a := Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1)
	var projection_view := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 1, directory_a, ViewContract.ROLE_PROJECTION, state)
	_assert(bool(ViewContract.validate(projection_view).get("success", false)), "projection role validates")
	_assert(bool(projection_view.get("read_only", false)), "projection is read-only")
	_assert(not bool(projection_view.get("canonical_writer", true)), "projection is not writer")
	_assert(String(projection_view.get("visual_entity_key", "")) == "earth/player/a", "visual key is stable player/a")

	var directory_b := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
	var canonical_view := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 2, directory_b, ViewContract.ROLE_CANONICAL, state)
	_assert(bool(ViewContract.validate(canonical_view).get("success", false)), "canonical role validates")
	_assert(bool(canonical_view.get("canonical_writer", false)), "canonical role is writer")
	_assert(not bool(canonical_view.get("read_only", true)), "canonical role is not read-only")
	_assert(not bool(canonical_view.get("command_channel", true)), "view never exposes command channel")

	var bad_command := canonical_view.duplicate(true)
	bad_command["command_channel"] = true
	bad_command["checksum"] = ""
	bad_command = Utils.finalize_json_checksum(bad_command)
	_assert(String(ViewContract.validate(bad_command).get("error_code", "")) == "SM0_P6_VIEW_COMMAND_CHANNEL_FORBIDDEN", "command channel is rejected")

	var hold_view := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 3, directory_b, ViewContract.ROLE_HANDOFF_HOLD, state)
	_assert(bool(ViewContract.validate(hold_view).get("success", false)), "handoff hold validates")
	_assert(bool(hold_view.get("held", false)) and bool(hold_view.get("read_only", false)), "handoff hold is read-only and held")


func _test_persistent_visual_pivot() -> void:
	var observer = Observer.new()
	root.add_child(observer)
	var setup_result: Dictionary = observer.setup({
		"viewer_authority_id": Contracts.AUTHORITY_B,
		"listen_port": VIEW_PORT,
	})
	_assert(bool(setup_result.get("success", false)), "observer starts")
	if not bool(setup_result.get("success", false)):
		observer.queue_free()
		return
	var initial_instance := int(observer.status_for_tests().get("visual_instance_id", 0))
	_assert(initial_instance > 0, "observer creates one persistent visual instance")

	var state_a := _player_state(-0.5, 5, 8)
	var directory_a := Contracts.create_directory(Contracts.AUTHORITY_A, 1, 1)
	var projection := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 1, directory_a, ViewContract.ROLE_PROJECTION, state_a)
	_assert(bool(observer.accept_view_for_tests(projection).get("success", false)), "observer accepts initial remote projection")
	var after_projection: Dictionary = observer.status_for_tests()
	_assert(String(after_projection.get("presentation_role", "")) == ViewContract.ROLE_PROJECTION, "initial role is projection")
	_assert(int(after_projection.get("pivot_count", -1)) == 0, "initial role does not count as pivot")

	var directory_b := Contracts.create_directory(Contracts.AUTHORITY_B, 2, 2)
	var hold_to_b := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 2, directory_b, ViewContract.ROLE_HANDOFF_HOLD, state_a)
	_assert(bool(observer.accept_view_for_tests(hold_to_b).get("success", false)), "observer accepts projection-to-canonical hold")
	_assert(int(observer.status_for_tests().get("visual_instance_id", 0)) == initial_instance, "hold keeps same visual instance")

	var state_b := _player_state(0.05, 6, 8)
	var canonical := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 3, directory_b, ViewContract.ROLE_CANONICAL, state_b)
	_assert(bool(observer.accept_view_for_tests(canonical).get("success", false)), "observer accepts target canonical view")
	var after_canonical: Dictionary = observer.status_for_tests()
	_assert(String(after_canonical.get("presentation_role", "")) == ViewContract.ROLE_CANONICAL, "projection pivots to canonical")
	_assert(int(after_canonical.get("pivot_count", 0)) == 1, "projection-to-canonical counts one pivot")
	_assert(int(after_canonical.get("visual_instance_id", 0)) == initial_instance, "projection-to-canonical keeps same visual instance")
	_assert(bool(after_canonical.get("canonical_writer", false)) and not bool(after_canonical.get("read_only", true)), "canonical role flags are correct")

	var divergent := canonical.duplicate(true)
	divergent["position"] = {"x": 99.0, "y": 0.0, "z": 0.0}
	divergent["checksum"] = ""
	divergent = Utils.finalize_json_checksum(divergent)
	_assert(String(observer.accept_view_for_tests(divergent).get("error_code", "")) == "SM0_P6_SAME_SEQUENCE_MUTATION", "same-sequence divergent view fails closed")

	var directory_a2 := Contracts.create_directory(Contracts.AUTHORITY_A, 3, 3)
	var hold_to_a := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 4, directory_a2, ViewContract.ROLE_HANDOFF_HOLD, state_b)
	_assert(bool(observer.accept_view_for_tests(hold_to_a).get("success", false)), "observer accepts canonical-to-projection hold")
	var state_a2 := _player_state(-0.05, 7, 9)
	var projection_again := ViewContract.create(Contracts.AUTHORITY_B, Contracts.ZONE_B, 5, directory_a2, ViewContract.ROLE_PROJECTION, state_a2)
	_assert(bool(observer.accept_view_for_tests(projection_again).get("success", false)), "observer accepts new owner projection")
	var final_status: Dictionary = observer.status_for_tests()
	_assert(String(final_status.get("presentation_role", "")) == ViewContract.ROLE_PROJECTION, "canonical pivots back to projection")
	_assert(int(final_status.get("pivot_count", 0)) == 2, "round trip counts two pivots")
	_assert(int(final_status.get("visual_instance_id", 0)) == initial_instance, "round-trip pivot never respawns visual")
	_assert(String(final_status.get("player_entity_id", "")) == "player/a" and not bool(final_status.get("command_channel", true)), "identity stays player/a and observer remains command-free")

	observer.shutdown(0, "test-complete")
	observer.queue_free()
	await process_frame


func _player_state(x: float, revision: int, input_sequence: int) -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"state_revision": revision,
		"last_input_sequence": input_sequence,
		"position": {"x": x, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.25, "y": 0.0, "z": 0.0},
		"orientation_yaw": 0.0,
	}


func _assert(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _assertions != EXPECTED_ASSERTIONS:
		_failures.append("assertion count mismatch: expected %d, got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failures.is_empty():
		print("SM0 P6 projection/canonical pivot: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SM0 P6 projection/canonical pivot: FAIL (%d assertions, %d failures)" % [_assertions, _failures.size()])
	quit(1)
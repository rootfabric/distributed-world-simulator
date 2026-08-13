extends SceneTree

const MovementAuthorityProfile = preload(
	"res://scripts/network/authority/movement_authority_profile.gd"
)

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_owner_client_is_not_a_body_writer()
	_test_snapshot_path_cannot_rewind_local_owner()
	_test_server_relay_has_no_presentation_writer()
	_finish()


func _test_owner_client_is_not_a_body_writer() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
	)
	_assert(source.begins_with("extends \"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd\""), "owner client is a leaf over canonical M3 runtime")
	_assert(source.contains("LOCAL_TRANSFORM_SINGLE_WRITER_STATE_POSTFACTUM_TO_SERVER_V1"), "single-writer policy explicit")
	for forbidden in ["CharacterBody3D", "move_and_slide", "global_position =", "global_transform =", "set_global_position", "set_global_transform"]:
		_assert(not source.contains(forbidden), "owner network leaf does not write physics body via %s" % forbidden)
	_assert(not source.contains("fix7") and not source.contains("fix8") and not source.contains("fix9") and not source.contains("fix10"), "legacy FIX render chain not imported")
	_assert(source.contains("advance_local_prediction"), "local prediction remains locomotion author")
	_assert(source.contains("submit_player_state_nonblocking"), "network path submits already-authored state")


func _test_snapshot_path_cannot_rewind_local_owner() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
	)
	var start := source.find("func _reconcile_prediction_from_snapshot")
	var finish := source.find("func _owner_playable_state", start)
	_assert(start >= 0 and finish > start, "snapshot reconciliation override bounded")
	if start >= 0 and finish > start:
		var body := source.substr(start, finish - start)
		_assert(not body.contains("super._reconcile_prediction_from_snapshot"), "routine snapshot does not invoke local rewind")
		_assert(not body.contains("prediction_updated.emit"), "routine snapshot does not emit local presentation rewrite")
		_assert(body.contains("_owner_snapshot_reconciliations_skipped"), "suppressed local rewind remains observable")


func _test_server_relay_has_no_presentation_writer() -> void:
	var server_source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd"
	)
	var service_source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd"
	)
	_assert(server_source.contains("_movement_snapshot_dirty = true"), "accepted owner state uses existing canonical snapshot relay")
	_assert(service_source.contains("_movement.apply_authoritative_state"), "server validates through canonical movement service")
	_assert(service_source.contains(MovementAuthorityProfile.OWNER_AUTHORITATIVE_VALIDATED), "service advertises bounded owner mode")
	for source in [server_source, service_source]:
		_assert(not source.contains("CharacterBody3D"), "server/service has no CharacterBody presentation authority")
		_assert(not source.contains("global_transform ="), "server/service has no render transform writer")


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("NX.C1 render/physics separation: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("NX.C1 render/physics single-writer separation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("NX.C1 render/physics single-writer separation: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

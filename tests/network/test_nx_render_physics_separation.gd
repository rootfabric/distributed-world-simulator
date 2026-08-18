extends SceneTree

const MovementAuthorityProfile = preload(
	"res://scripts/network/authority/movement_authority_profile.gd"
)

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_owner_client_is_not_a_body_writer()
	_test_snapshot_path_reconciles_only_after_rejection()
	_test_server_relay_has_no_presentation_writer()
	_test_server_ready_and_persistence_rebind_are_fail_closed()
	_finish()


func _test_owner_client_is_not_a_body_writer() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
	)
	_assert(source.begins_with("extends \"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd\""), "owner client is a leaf over canonical M3 runtime")
	_assert(source.contains("LOCAL_TRANSFORM_SINGLE_WRITER_RECONCILE_ON_REJECTION_V1"), "single-writer correction policy explicit")
	for forbidden in ["CharacterBody3D", "move_and_slide", "global_position =", "global_transform =", "set_global_position", "set_global_transform"]:
		_assert(not source.contains(forbidden), "owner network leaf does not write physics body via %s" % forbidden)
	_assert(not source.contains("fix7") and not source.contains("fix8") and not source.contains("fix9") and not source.contains("fix10"), "legacy FIX render chain not imported")
	_assert(source.contains("advance_local_prediction"), "local prediction remains locomotion author")
	_assert(source.contains("submit_player_state_nonblocking"), "network path submits already-authored state")


func _test_snapshot_path_reconciles_only_after_rejection() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_owner_movement.gd"
	)
	var start := source.find("func _reconcile_prediction_from_snapshot")
	var finish := source.find("func _is_owner_state_operation", start)
	_assert(start >= 0 and finish > start, "snapshot reconciliation override bounded")
	if start >= 0 and finish > start:
		var body := source.substr(start, finish - start)
		_assert(body.contains("if _owner_reconciliation_required"), "authoritative correction requires explicit rejection arm")
		_assert(body.contains("super._reconcile_prediction_from_snapshot(snapshot)"), "rejected state can reconcile to server snapshot")
		_assert(body.contains("_owner_reconciliation_required = false"), "rejection arm is one-shot")
		_assert(body.contains("_owner_snapshot_reconciliations_skipped"), "routine local rewind remains suppressed and observable")
	_assert(source.contains("command_type\", \"\")) == \"PLAYER_STATE\""), "only PLAYER_STATE rejection arms owner correction")
	_assert(source.contains("_is_owner_state_operation"), "rejection is fenced to NX.C1 owner operation identity")


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


func _test_server_ready_and_persistence_rebind_are_fail_closed() -> void:
	var source := FileAccess.get_file_as_string(
		"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_owner_movement.gd"
	)
	_assert(source.contains("set_block_signals(true)"), "base READY signal blocked during service swap")
	_assert(source.contains("set_block_signals(false)"), "signals restored after base setup")
	var replacement_index := source.find("_service = replacement")
	var ready_emit_index := source.find("ready_for_clients.emit(get_report())")
	_assert(replacement_index >= 0 and ready_emit_index > replacement_index, "READY signal emitted only after owner service replacement")
	_assert(source.contains("if _persistence_enabled:"), "persistence branch explicit")
	_assert(source.contains("var recovery_rebind := _setup_recovery()"), "persistence/replay adapters rebound to replacement service")
	_assert(source.find("OWNER_MOVEMENT_REQUIRES_PLAYABLE_SANDBOX") < source.find("super.setup(base_config)"), "invalid non-playable config rejected before socket startup")


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

extends SceneTree

const WRAPPER_PATH := "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
const NX6_BASE_PATH := "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"
const REPLICA_STORE_PATH := "res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var wrapper := _read(WRAPPER_PATH)
	var nx6_base := _read(NX6_BASE_PATH)
	var replica_store := _read(REPLICA_STORE_PATH)

	_assert(
		wrapper.contains('extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"'),
		"INT0 client runtime inherits the accepted NX6 implementation"
	)
	_assert(
		wrapper.contains('error_code == "MULTIPLAYER_DELTA_BASE_MISMATCH"'),
		"INT0 client handles only the bounded delta-base mismatch"
	)
	_assert(
		wrapper.contains("_pending_replica_resync = true"),
		"delta mismatch enters pending resync"
	)
	_assert(
		wrapper.contains("_pending_replica_resync = false"),
		"authoritative snapshot clears pending resync"
	)
	_assert(
		wrapper.contains('report["delta_base_mismatches"]'),
		"bounded mismatch telemetry is reported"
	)
	_assert(
		wrapper.contains('report["snapshot_resyncs"]'),
		"successful snapshot resync telemetry is reported"
	)
	_assert(
		not wrapper.contains("NetworkedGameplayService.new"),
		"composition adapter does not construct gameplay authority"
	)
	_assert(
		nx6_base.contains("ClientPredictionReconciler"),
		"accepted NX6 prediction runtime remains in the inherited base"
	)
	_assert(
		nx6_base.contains("CanonicalItemGraphDelta"),
		"accepted NX6 item replication path remains in the inherited base"
	)
	_assert(
		nx6_base.contains("_item_resync_pending"),
		"accepted NX6 item resync state remains in the inherited base"
	)
	_assert(
		replica_store.contains('return _failure("MULTIPLAYER_DELTA_BASE_MISMATCH"'),
		"replica store preserves the exact mismatch fence"
	)
	_assert(
		not wrapper.contains("<<<<<<<") and not nx6_base.contains("<<<<<<<") and not replica_store.contains("<<<<<<<"),
		"composition sources contain no merge markers"
	)

	_finish()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		failures.append("Missing source: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _assert(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("INT0 RL3/MW10 M3 composition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("INT0 RL3/MW10 M3 composition: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

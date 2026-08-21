extends SceneTree

const WRAPPER_PATH := "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd"
const NX6_BASE_PATH := "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"
const REPLICA_STORE_PATH := "res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var wrapper := _read(WRAPPER_PATH)
	var effective_client := _load_script_source_chain(WRAPPER_PATH, {})
	var nx6_base := _read(NX6_BASE_PATH)
	var replica_store := _read(REPLICA_STORE_PATH)

	_assert(
		effective_client.contains('extends "res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"'),
		"INT0 client runtime inheritance chain includes the accepted NX6 implementation"
	)
	_assert(
		effective_client.contains('Support.transport_bound_operation_id(_logical_player_id, "join", _transport_session_id)'),
		"INT0 production adapter preserves the M5 transport-bound JOIN source contract"
	)
	_assert(
		effective_client.contains("super._process(delta)"),
		"INT0 adapter delegates JOIN transmission to the accepted NX6 process"
	)
	_assert(
		not wrapper.contains("operation/m3/%s/join/%d"),
		"INT0 adapter does not restore process-local JOIN identity"
	)
	_assert(
		effective_client.contains('error_code == "MULTIPLAYER_DELTA_BASE_MISMATCH"'),
		"INT0 client handles only the bounded delta-base mismatch"
	)
	_assert(
		effective_client.contains("_pending_replica_resync = true"),
		"delta mismatch enters pending resync"
	)
	_assert(
		effective_client.contains("_pending_replica_resync = false"),
		"authoritative snapshot clears pending resync"
	)
	_assert(
		effective_client.contains('report["delta_base_mismatches"]'),
		"bounded mismatch telemetry is reported"
	)
	_assert(
		effective_client.contains('report["snapshot_resyncs"]'),
		"successful snapshot resync telemetry is reported"
	)
	_assert(
		not effective_client.contains("NetworkedGameplayService.new"),
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
		not effective_client.contains("<<<<<<<") and not nx6_base.contains("<<<<<<<") and not replica_store.contains("<<<<<<<"),
		"composition sources contain no merge markers"
	)

	_finish()


func _load_script_source_chain(path: String, visited: Dictionary) -> String:
	if path.is_empty() or visited.has(path):
		return ""
	visited[path] = true
	var source := _read(path)
	if source.is_empty():
		return source
	var line_end := source.find("\n")
	var first_line := source.substr(0, line_end if line_end >= 0 else source.length()).strip_edges()
	if first_line.begins_with("extends \"") and first_line.ends_with("\""):
		var base_path := first_line.substr(9, first_line.length() - 10)
		return source + "\n" + _load_script_source_chain(base_path, visited)
	return source


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

extends SceneTree

const Reconciler = preload("res://scripts/network/prediction/client_prediction_reconciler.gd")
const Movement = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const Sequence = preload("res://scripts/network/simulation/input_sequence.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")

var assertions: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_immediate_prediction()
	_test_replay_matches_shared_kernel()
	_test_visual_correction_policy()
	_test_future_clock_only_snapshot()
	_test_clock_only_snapshot_preserves_active_smoothing()
	_test_rejection_and_hard_correction()
	_test_bounded_history()
	_test_history_miss_authoritative_reset()
	_test_frame_rate_independence()
	_test_delayed_lossy_snapshot_reconciliation()
	_test_authoritative_sequence_adoption()
	_test_sequence_wrap()
	_test_source_contracts()
	_finish()

func _test_immediate_prediction() -> void:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 100).get("success", false)), "prediction configured")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "prediction input accepted")
	var advanced: Dictionary = reconciler.advance_frame(1.0 / 60.0)
	_assert(bool(advanced.get("success", false)), "prediction advances in same render frame")
	var predicted: Dictionary = reconciler.get_predicted_state()
	_assert(_position(predicted).z < -0.09, "same-frame prediction moves local player")
	_assert(int(predicted.get("last_input_sequence", 0)) == 1, "prediction records input sequence")
	_assert(int(reconciler.get_report().get("history_size", 0)) == 1, "prediction stores first tick")

func _test_replay_matches_shared_kernel() -> void:
	var reconciler = Reconciler.new()
	var initial: Dictionary = _player()
	_assert(bool(reconciler.configure(initial, 0).get("success", false)), "replay reconciler configured")
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "replay input accepted")
	for _index in range(6):
		_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "prediction tick advanced")
	var before: Vector3 = _position(reconciler.get_predicted_state())
	var movement = Movement.new()
	var authoritative: Dictionary = initial.duplicate(true)
	for _index in range(3):
		var moved: Dictionary = movement.apply_fixed_tick(authoritative, 1, _intent(0.0, 1.0), 1.0 / 60.0)
		_assert(bool(moved.get("success", false)), "authoritative shared kernel tick succeeds")
		authoritative = Dictionary(moved.get("details", {}).get("player", {}))
	var reconciled: Dictionary = reconciler.reconcile(authoritative, 3)
	_assert(bool(reconciled.get("success", false)), "authoritative snapshot reconciled")
	_assert(int(reconciled.get("details", {}).get("replayed_ticks", -1)) == 3, "unacknowledged ticks replayed")
	_assert(int(reconciler.get_report().get("ticks_replayed", -1)) == 3, "replay telemetry counts ticks exactly once")
	_assert(_position(reconciler.get_predicted_state()).distance_to(before) < 0.000001, "shared kernel replay preserves prediction")
	_assert(float(reconciled.get("details", {}).get("prediction_error_m", -1.0)) < 0.000001, "matching prediction has no correction error")

func _test_visual_correction_policy() -> void:
	var reconciler = Reconciler.new()
	_assert(bool(reconciler.configure(_player(), 0).get("success", false)), "smoothing reconciler configured")
	_assert(bool(reconciler.set_input(1, _intent(1.0, 0.0)).get("success", false)), "smoothing input accepted")
	for _index in range(6):
		reconciler.advance_frame(1.0 / 60.0)
	var old_presentation: Vector3 = _position(reconciler.sample_presentation(0.0))
	var authoritative: Dictionary = reconciler.get_predicted_state()
	var position: Dictionary = Dictionary(authoritative.get("position", {}))
	position["x"] = float(position.get("x", 0.0)) - 0.10
	authoritative["position"] = position
	var reconciled: Dictionary = reconciler.reconcile(authoritative, reconciler.get_prediction_tick())
	_assert(String(reconciled.get("details", {}).get("correction_mode", "")) == "SMOOTH", "ten-centimeter correction is smoothed")
	var preserved: Vector3 = _position(reconciler.sample_presentation(0.0))
	_assert(preserved.distance_to(old_presentation) < 0.000001, "visual position is preserved at correction start")
	for _index in range(20):
		reconciler.sample_presentation(1.0 / 60.0)
	_assert(float(reconciler.get_report().get("visual_offset_m", 1.0)) < 0.001, "visual correction decays to authoritative state")

func _test_future_clock_only_snapshot() -> void:
	var reconciler = Reconciler.new()
	var initial: Dictionary = _player()
	initial["position"] = {"x": 10.0, "y": 2.0, "z": -3.5}
	_assert(bool(reconciler.configure(initial, 101).get("success", false)), "future clock-only reconciler configured away from origin")
	var before_state: Dictionary = reconciler.get_predicted_state()
	var before_report: Dictionary = reconciler.get_report()
	var result: Dictionary = reconciler.reconcile(before_state.duplicate(true), 103)
	_assert(bool(result.get("success", false)), "identical future clock-only snapshot reconciles")
	var details: Dictionary = Dictionary(result.get("details", {}))
	_assert(float(details.get("prediction_error_m", -1.0)) < 0.000001, "future clock-only snapshot has zero prediction error away from origin")
	_assert(String(details.get("correction_mode", "")) == "NONE", "future clock-only snapshot does not create a correction")
	_assert(not bool(details.get("hard_correction", true)), "future clock-only snapshot does not hard-correct")
	_assert(int(details.get("prediction_tick", -1)) == 103, "future clock-only snapshot advances prediction clock")
	_assert(reconciler.get_predicted_state() == before_state, "future clock-only snapshot preserves gameplay state")
	var after_report: Dictionary = reconciler.get_report()
	_assert(int(after_report.get("corrections", -1)) == int(before_report.get("corrections", -2)), "future clock-only snapshot does not increment correction telemetry")
	_assert(int(after_report.get("hard_corrections", -1)) == int(before_report.get("hard_corrections", -2)), "future clock-only snapshot does not increment hard-correction telemetry")
	_assert(float(after_report.get("last_error_m", -1.0)) < 0.000001, "future clock-only telemetry records zero error")


func _test_clock_only_snapshot_preserves_active_smoothing() -> void:
	var reconciler = Reconciler.new()
	var initial: Dictionary = _player()
	initial["position"] = {"x": 10.0, "y": 0.0, "z": -4.0}
	_assert(bool(reconciler.configure(initial, 100).get("success", false)), "smoothing-preservation reconciler configured")
	_assert(bool(reconciler.set_input(1, _intent(1.0, 0.0)).get("success", false)), "smoothing-preservation input accepted")
	for _index in range(6):
		_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "smoothing-preservation prediction advances")
	var authority: Dictionary = reconciler.get_predicted_state()
	var authority_position: Dictionary = Dictionary(authority.get("position", {}))
	authority_position["x"] = float(authority_position.get("x", 0.0)) - 0.10
	authority["position"] = authority_position
	var correction: Dictionary = reconciler.reconcile(authority, reconciler.get_prediction_tick())
	_assert(String(correction.get("details", {}).get("correction_mode", "")) == "SMOOTH", "precondition creates active smoothing")
	var report_before_clock: Dictionary = reconciler.get_report()
	var offset_before: float = float(report_before_clock.get("visual_offset_m", 0.0))
	var corrections_before: int = int(report_before_clock.get("corrections", 0))
	var hard_before: int = int(report_before_clock.get("hard_corrections", 0))
	_assert(offset_before > 0.09, "precondition retains a visible smoothing offset")
	var clock_state: Dictionary = reconciler.get_predicted_state()
	var future: Dictionary = reconciler.reconcile(clock_state.duplicate(true), 108)
	_assert(bool(future.get("success", false)), "future clock-only snapshot accepted during smoothing")
	_assert(float(future.get("details", {}).get("prediction_error_m", -1.0)) < 0.000001, "future clock-only snapshot remains exact during smoothing")
	_assert(int(future.get("details", {}).get("prediction_tick", -1)) == 108, "future clock-only snapshot advances clock during smoothing")
	var report_after_future: Dictionary = reconciler.get_report()
	_assert(absf(float(report_after_future.get("visual_offset_m", 0.0)) - offset_before) < 0.000001, "future clock-only snapshot preserves active smoothing offset")
	_assert(int(report_after_future.get("corrections", -1)) == corrections_before, "future clock-only snapshot does not add correction telemetry during smoothing")
	_assert(int(report_after_future.get("hard_corrections", -1)) == hard_before, "future clock-only snapshot does not add hard-correction telemetry during smoothing")
	_assert(reconciler.get_predicted_state() == clock_state, "future clock-only snapshot preserves corrected gameplay state")
	var duplicate: Dictionary = reconciler.reconcile(clock_state.duplicate(true), 108)
	_assert(bool(duplicate.get("success", false)), "duplicate matching snapshot accepted during smoothing")
	var report_after_duplicate: Dictionary = reconciler.get_report()
	_assert(absf(float(report_after_duplicate.get("visual_offset_m", 0.0)) - offset_before) < 0.000001, "duplicate snapshot does not cancel active smoothing")
	_assert(int(report_after_duplicate.get("corrections", -1)) == corrections_before, "duplicate snapshot does not add correction telemetry")
	_assert(int(report_after_duplicate.get("hard_corrections", -1)) == hard_before, "duplicate snapshot does not add hard-correction telemetry")


func _test_rejection_and_hard_correction() -> void:
	var reconciler = Reconciler.new()
	var initial: Dictionary = _player()
	reconciler.configure(initial, 0)
	reconciler.set_input(1, _intent(0.0, 1.0, true))
	for _index in range(30):
		reconciler.advance_frame(1.0 / 60.0)
	var rejected: Dictionary = initial.duplicate(true)
	rejected["last_input_sequence"] = 0
	var result: Dictionary = reconciler.reconcile(rejected, 30)
	_assert(bool(result.get("success", false)), "server rejection rolls prediction back")
	_assert(String(result.get("details", {}).get("correction_mode", "")) == "HARD", "large rejected prediction hard-corrects")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(initial)) < 0.000001, "rejected state returns to authority")
	_assert(int(reconciler.get_report().get("hard_corrections", 0)) == 1, "hard correction counted")

func _test_bounded_history() -> void:
	var reconciler = Reconciler.new()
	reconciler.configure(_player(), 0)
	reconciler.set_input(1, _intent(0.0, 1.0))
	for _index in range(400):
		reconciler.advance_frame(1.0 / 60.0)
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("history_size", 0)) == Reconciler.MAX_HISTORY_TICKS, "prediction history is bounded")
	_assert(int(report.get("history_overflows", 0)) == 400 - Reconciler.MAX_HISTORY_TICKS, "history overflow is observable")


func _test_history_miss_authoritative_reset() -> void:
	var reconciler = Reconciler.new()
	var initial: Dictionary = _player()
	reconciler.configure(initial, 0)
	reconciler.set_input(1, _intent(0.0, 1.0))
	for _index in range(Reconciler.MAX_HISTORY_TICKS + 40):
		reconciler.advance_frame(1.0 / 60.0)
	var movement = Movement.new()
	var moved: Dictionary = movement.apply_fixed_tick(initial, 1, _intent(0.0, 1.0), 1.0 / 60.0)
	_assert(bool(moved.get("success", false)), "history-miss authority tick succeeds")
	var authority: Dictionary = Dictionary(moved.get("details", {}).get("player", {}))
	var result: Dictionary = reconciler.reconcile(authority, 1)
	_assert(bool(result.get("success", false)), "snapshot outside prediction ring resets safely")
	_assert(bool(result.get("details", {}).get("history_miss_reset", false)), "history miss is explicit")
	_assert(int(result.get("details", {}).get("replayed_ticks", -1)) == 0, "history miss never performs partial replay")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(authority)) < 0.000001, "history miss adopts authority exactly")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("history_miss_resets", 0)) == 1, "history miss reset is observable")
	_assert(int(report.get("prediction_tick", -1)) == 1, "history miss resets prediction clock to authority")
	_assert(int(report.get("history_size", -1)) == 0, "history miss discards incomplete history")

func _test_frame_rate_independence() -> void:
	var positions: Array[Vector3] = []
	for fps in [30, 60, 144]:
		var reconciler = Reconciler.new()
		reconciler.configure(_player(), 0)
		reconciler.set_input(1, _intent(0.0, 1.0))
		for _frame in range(fps):
			reconciler.advance_frame(1.0 / float(fps))
		positions.append(_position(reconciler.get_predicted_state()))
		_assert(int(reconciler.get_report().get("ticks_predicted", 0)) == 60, "prediction emits 60 ticks at %d FPS" % fps)
	_assert(positions[0].distance_to(positions[1]) < 0.000001, "30 and 60 FPS prediction converge")
	_assert(positions[1].distance_to(positions[2]) < 0.000001, "60 and 144 FPS prediction converge")

func _test_delayed_lossy_snapshot_reconciliation() -> void:
	var reconciler = Reconciler.new()
	var authoritative: Dictionary = _player()
	var movement = Movement.new()
	_assert(bool(reconciler.configure(authoritative, 0).get("success", false)), "conditioned prediction configured")
	var delayed_snapshots: Array[Dictionary] = []
	var maximum_error: float = 0.0
	var delivered: int = 0
	var dropped: int = 0
	for tick in range(1, 181):
		var sequence: int = tick
		var intent: Dictionary = _intent(0.0, 1.0 if tick <= 120 else 0.0)
		_assert(bool(reconciler.set_input(sequence, intent).get("success", false)), "conditioned prediction input accepted")
		_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "conditioned prediction advances")
		var moved: Dictionary = movement.apply_fixed_tick(authoritative, sequence, intent, 1.0 / 60.0)
		_assert(bool(moved.get("success", false)), "conditioned authoritative tick succeeds")
		authoritative = Dictionary(moved.get("details", {}).get("player", {}))
		if tick % 3 == 0:
			# Deterministic 100 ms base latency with 0/1/2 tick jitter. Every tenth snapshot is lost.
			var jitter_ticks: int = (tick / 3) % 3
			delayed_snapshots.append({
				"deliver_tick": tick + 6 + jitter_ticks,
				"server_tick": tick,
				"player": authoritative.duplicate(true),
			})
		var pending: Array[Dictionary] = []
		for snapshot_value in delayed_snapshots:
			var snapshot: Dictionary = snapshot_value
			if int(snapshot.get("deliver_tick", 0)) > tick:
				pending.append(snapshot)
				continue
			if int(snapshot.get("server_tick", 0)) % 30 == 0:
				dropped += 1
				continue
			var result: Dictionary = reconciler.reconcile(
				Dictionary(snapshot.get("player", {})),
				int(snapshot.get("server_tick", 0))
			)
			_assert(bool(result.get("success", false)), "delayed snapshot reconciles")
			maximum_error = maxf(maximum_error, float(result.get("details", {}).get("prediction_error_m", 0.0)))
			delivered += 1
		delayed_snapshots = pending
	# Deliver the final authority after the simulated link drains.
	var final_result: Dictionary = reconciler.reconcile(authoritative, 180)
	_assert(bool(final_result.get("success", false)), "final conditioned authority reconciles")
	_assert(delivered > 40, "conditioned stream delivers many snapshots")
	_assert(dropped > 0, "conditioned stream deterministically loses snapshots")
	_assert(maximum_error < 0.000001, "shared kernel remains exact under 100 ms latency, jitter, and loss")
	_assert(_position(reconciler.get_predicted_state()).distance_to(_position(authoritative)) < 0.000001, "conditioned prediction converges to final authority")
	var report: Dictionary = reconciler.get_report()
	_assert(int(report.get("history_size", 0)) <= Reconciler.MAX_HISTORY_TICKS, "conditioned prediction history remains bounded")
	_assert(int(report.get("replay_failures", 0)) == 0, "conditioned prediction has no replay failures")
	_assert(int(report.get("hard_corrections", 0)) == 0, "matching conditioned simulation needs no hard corrections")

func _test_authoritative_sequence_adoption() -> void:
	var reconciler = Reconciler.new()
	var player: Dictionary = _player()
	reconciler.configure(player, 0)
	reconciler.set_input(1, _intent(0.0, 1.0))
	reconciler.advance_frame(1.0 / 60.0)
	var authority: Dictionary = reconciler.get_predicted_state()
	authority["last_input_sequence"] = 5
	var result: Dictionary = reconciler.reconcile(authority, 1)
	_assert(bool(result.get("success", false)), "newer authoritative sequence is accepted")
	_assert(int(reconciler.get_report().get("current_input_sequence", 0)) == 5, "authoritative sequence advances local cursor")
	_assert(bool(reconciler.set_input(6, _intent(1.0, 0.0)).get("success", false)), "next local input continues after authoritative cursor")

func _test_sequence_wrap() -> void:
	var player: Dictionary = _player()
	player["last_input_sequence"] = Sequence.MAX_SEQUENCE
	var reconciler = Reconciler.new()
	reconciler.configure(player, 10)
	_assert(bool(reconciler.set_input(1, _intent(0.0, 1.0)).get("success", false)), "prediction accepts wrapped sequence")
	_assert(bool(reconciler.advance_frame(1.0 / 60.0).get("success", false)), "wrapped prediction tick succeeds")
	_assert(int(reconciler.get_predicted_state().get("last_input_sequence", 0)) == 1, "wrapped sequence committed")

func _test_source_contracts() -> void:
	_assert(RuntimeIdentity.CHECKPOINT == "v16.14.0-network-nx4-client-prediction-reconciliation", "runtime checkpoint advanced to NX4")
	_assert(RuntimeIdentity.BUILD_ID == "nx4-client-prediction-reconciliation", "runtime build ID advanced to NX4")
	var contracts: Dictionary = ProtocolManifest.create().get("contract_versions", {})
	var prediction_contract: Dictionary = Dictionary(contracts.get("client_prediction_reconciler", {}))
	_assert(String(prediction_contract.get("schema", "")) == Reconciler.SCHEMA, "protocol manifest includes prediction reconciler")
	_assert(int(prediction_contract.get("max_history_ticks", 0)) == Reconciler.MAX_HISTORY_TICKS, "protocol manifest fingerprints prediction history bound")
	_assert(String(prediction_contract.get("replay_policy", "")) == Reconciler.REPLAY_POLICY, "protocol manifest fingerprints replay policy")
	_assert(String(prediction_contract.get("clock_only_snapshot_policy", "")) == Reconciler.CLOCK_ONLY_SNAPSHOT_POLICY, "protocol manifest fingerprints clock-only snapshot policy")
	_assert(String(prediction_contract.get("history_miss_policy", "")) == Reconciler.HISTORY_MISS_POLICY, "protocol manifest fingerprints history-miss reset policy")
	var roadmap = JSON.parse_string(FileAccess.get_file_as_string("res://config/network/network-experience-roadmap.v1.json"))
	_assert(roadmap is Dictionary, "network roadmap is valid JSON")
	if roadmap is Dictionary:
		_assert(String(roadmap.get("current_stage", "")) == "NX4", "network roadmap current stage is NX4")
	var config = JSON.parse_string(FileAccess.get_file_as_string("res://config/network/nx4-client-prediction-reconciliation.v1.json"))
	_assert(config is Dictionary, "NX4 config is valid JSON")
	if config is Dictionary:
		_assert(String(config.get("checkpoint", "")) == RuntimeIdentity.CHECKPOINT, "NX4 config checkpoint matches runtime")
		_assert(int(config.get("prediction", {}).get("tick_rate_hz", 0)) == Reconciler.TICK_RATE_HZ, "NX4 config tick rate matches reconciler")
		_assert(int(config.get("prediction", {}).get("max_history_ticks", 0)) == Reconciler.MAX_HISTORY_TICKS, "NX4 config history bound matches reconciler")
		_assert(String(config.get("reconciliation", {}).get("policy", "")) == Reconciler.REPLAY_POLICY, "NX4 config replay policy matches reconciler")
	var client_source: String = _load_script_source_chain(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd", {}
	)
	var playground_source: String = FileAccess.get_file_as_string("res://scripts/world/testing/playground_runtime.gd")
	var player_source: String = FileAccess.get_file_as_string("res://scripts/actors/player/lunar_player.gd")
	_assert(client_source.contains("advance_local_prediction"), "client runtime exposes prediction frame API")
	_assert(client_source.contains("prediction_updated.emit"), "client runtime publishes predicted presentation")
	_assert(client_source.contains("_reconcile_prediction_from_snapshot"), "authoritative snapshots trigger reconciliation")
	_assert(client_source.contains("_same_snapshot_state_except_clock"), "same-revision clock-only snapshots advance prediction without mutating replica state")
	_assert(playground_source.contains("player.set_network_prediction_mode(true)"), "playground enables local prediction")
	_assert(playground_source.contains("CLIENT_PREDICTION_RECONCILIATION"), "playground reports NX4 presentation mode")
	_assert(player_source.contains("not network_replica_mode"), "CharacterBody physics cannot double-simulate network prediction")
	var recovery_source: String = FileAccess.get_file_as_string("res://tools/runtime/m7_playable_recovery_client.gd")
	_assert(recovery_source.contains("distance_to(before_position) > 0.05"), "recovery smoke accepts one canonical 0.1 m fixed tick")


func _load_script_source_chain(path: String, visited: Dictionary) -> String:
	if path.is_empty() or visited.has(path):
		return ""
	visited[path] = true
	var source: String = FileAccess.get_file_as_string(path)
	if source.is_empty():
		return source
	var line_end: int = source.find("\n")
	var first_line: String = source.substr(
		0, line_end if line_end >= 0 else source.length()
	).strip_edges()
	if first_line.begins_with("extends \"") and first_line.ends_with("\""):
		var base_path: String = first_line.substr(9, first_line.length() - 10)
		return source + "\n" + _load_script_source_chain(base_path, visited)
	return source


func _player() -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/nx4/a",
		"ownership_epoch": 1,
		"connected": true,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.0, "y": 0.0, "z": 0.0},
		"inventory": [],
		"last_input_sequence": 0,
		"state_revision": 1,
		"orientation_yaw": 0.0,
		"flashlight_enabled": false,
	}

func _intent(move_x: float, move_z: float, sprint: bool = false) -> Dictionary:
	return {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": sprint,
		"delta_seconds": 1.0 / 60.0,
	}

func _position(state: Dictionary) -> Vector3:
	var value: Dictionary = Dictionary(state.get("position", {}))
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("NX4 assertion failed: %s" % message)

func _finish() -> void:
	if failures.is_empty():
		print("NX4 client prediction and reconciliation: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("NX4 client prediction and reconciliation: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

extends SceneTree

const Scheduler = preload("res://scripts/network/simulation/fixed_tick_scheduler.gd")
const InputBuffer = preload("res://scripts/network/simulation/fixed_tick_input_buffer.gd")
const Sequence = preload("res://scripts/network/simulation/input_sequence.gd")
const Movement = preload("res://scripts/runtime/networked_gameplay/services/player_movement_service.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const InputBatch = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_batch.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")
const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var assertions: int = 0
var failures: Array[String] = []

func _init() -> void:
	_test_scheduler_is_frame_rate_independent()
	_test_scheduler_catch_up_is_bounded()
	_test_sequence_wrap_and_window()
	_test_wrap_is_end_to_end()
	_test_input_buffer_ordering_staleness_and_hold()
	_test_jump_is_edge_triggered()
	_test_fixed_movement_ignores_client_delta()
	_test_fixed_service_distance_is_deterministic()
	_test_batching_does_not_change_tick_result()
	_test_transition_history_survives_latest_wins_coalescing()
	_test_jittered_input_arrival_keeps_fixed_speed()
	_test_protocol_and_runtime_wiring()
	_finish()

func _test_scheduler_is_frame_rate_independent() -> void:
	for fps in [30, 60, 144]:
		var scheduler = Scheduler.new()
		_assert(_ok(scheduler.configure()), "Scheduler setup failed at %d FPS" % fps)
		var emitted: int = 0
		for _frame in range(fps * 10):
			var result: Dictionary = scheduler.advance(1.0 / float(fps))
			_assert(_ok(result), "Scheduler advance failed at %d FPS" % fps)
			emitted += int(result.get("details", {}).get("tick_count", 0))
		_assert(emitted == 600, "Ten seconds did not emit 600 fixed ticks at %d FPS: %d" % [fps, emitted])
		_assert(scheduler.get_server_tick() == 600, "Server tick drifted at %d FPS" % fps)
		_assert(is_equal_approx(scheduler.get_tick_delta_seconds(), 1.0 / 60.0), "Fixed delta changed at %d FPS" % fps)

func _test_scheduler_catch_up_is_bounded() -> void:
	var scheduler = Scheduler.new()
	_assert(_ok(scheduler.configure(60, 4)), "Catch-up scheduler setup failed")
	var result: Dictionary = scheduler.advance(0.25)
	_assert(_ok(result), "Catch-up scheduler advance failed")
	_assert(int(result.get("details", {}).get("tick_count", 0)) == 4, "Catch-up limit was not enforced")
	var report: Dictionary = scheduler.get_report()
	_assert(int(report.get("catch_up_limit_hits", 0)) == 1, "Catch-up limit hit was not observable")
	_assert(float(report.get("dropped_time_seconds", 0.0)) > 0.0, "Dropped catch-up time was not observable")
	_assert(_error(scheduler.advance(-0.1)) == "INVALID_FRAME_DELTA", "Negative frame delta was accepted")

func _test_sequence_wrap_and_window() -> void:
	_assert(Sequence.next(0) == 1, "Initial input sequence is not one")
	_assert(Sequence.next(Sequence.MAX_SEQUENCE) == 1, "Input sequence did not wrap")
	_assert(Sequence.is_newer(1, Sequence.MAX_SEQUENCE), "Wrapped sequence was not newer")
	_assert(not Sequence.is_newer(Sequence.MAX_SEQUENCE, 1), "Pre-wrap sequence was treated as newer")
	_assert(Sequence.forward_distance(Sequence.MAX_SEQUENCE, 1) == 1, "Wrapped forward distance is wrong")
	_assert(not Sequence.is_valid(0), "Zero input sequence was accepted")


func _test_wrap_is_end_to_end() -> void:
	var entries: Array[Dictionary] = [
		_entry(Sequence.MAX_SEQUENCE, _intent(0.0, 1.0)),
		_entry(1, _intent(0.0, 1.0)),
	]
	var batch: Dictionary = InputBatch.create(
		"input-batch/nx3/wrap", "a", 1, entries, "operation/nx3/wrap"
	)
	_assert(_ok(InputBatch.validate(batch)), "Wrap-spanning input batch was rejected")
	var expanded: Dictionary = InputBatch.expand_inputs(batch)
	_assert(_ok(expanded), "Wrap-spanning input batch did not expand")
	var expanded_inputs: Array = expanded.get("details", {}).get("inputs", [])
	_assert(expanded_inputs.size() == 2, "Wrap-spanning input batch changed entry count")
	_assert(int(expanded_inputs[0].get("input_sequence", 0)) == Sequence.MAX_SEQUENCE, "Pre-wrap input order changed")
	_assert(int(expanded_inputs[1].get("input_sequence", 0)) == 1, "Wrapped input order changed")

	var invalid_batch: Dictionary = InputBatch.create(
		"input-batch/nx3/reverse-wrap",
		"a",
		1,
		[_entry(1, _intent(0.0, 1.0)), _entry(Sequence.MAX_SEQUENCE, _intent(0.0, 1.0))],
		"operation/nx3/reverse-wrap"
	)
	_assert(_error(InputBatch.validate(invalid_batch)) == "INVALID_PLAYER_INPUT_SEQUENCE_ORDER", "Reverse wrap order was accepted")

	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure(Sequence.MAX_SEQUENCE - 1)), "Wrap buffer setup failed")
	for input_value in expanded_inputs:
		_assert(_ok(buffer.enqueue(Dictionary(input_value), 1)), "Wrap input enqueue failed")
	var movement = Movement.new()
	var record: Dictionary = _record()
	record["last_input_sequence"] = Sequence.MAX_SEQUENCE - 1
	for tick in range(1, 3):
		var consumed: Dictionary = buffer.consume_for_tick(tick)
		_assert(_ok(consumed), "Wrap input consume failed")
		var result: Dictionary = movement.apply_fixed_tick(
			record,
			int(consumed.get("details", {}).get("input_sequence", 0)),
			Dictionary(consumed.get("details", {}).get("intent", {})),
			1.0 / 60.0
		)
		_assert(_ok(result), "Wrap-aware fixed movement failed")
		record = Dictionary(result.get("details", {}).get("player", record)).duplicate(true)
	_assert(int(record.get("last_input_sequence", 0)) == 1, "Fixed movement did not commit wrapped sequence")
	_assert(is_equal_approx(absf(float(record.get("position", {}).get("z", 0.0))), 0.2), "Wrapped inputs changed fixed movement distance")

	var client = ClientRuntime.new()
	_assert(bool(client.call("_sequence_acknowledges", 1, Sequence.MAX_SEQUENCE)), "Client did not acknowledge pre-wrap target with wrapped sequence")
	_assert(not bool(client.call("_sequence_acknowledges", Sequence.MAX_SEQUENCE, 1)), "Client accepted stale pre-wrap acknowledgement")
	client.set("_input_sequence", Sequence.MAX_SEQUENCE)
	client.call("_adopt_authoritative_input_sequence", 1)
	_assert(int(client.get("_input_sequence")) == 1, "Client did not adopt wrapped authoritative sequence")
	client.queue_free()

func _test_input_buffer_ordering_staleness_and_hold() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "Input buffer setup failed")
	_assert(_ok(buffer.enqueue(_entry(2, _intent(1.0, 0.0)), 10)), "Reordered sequence 2 enqueue failed")
	_assert(_ok(buffer.enqueue(_entry(1, _intent(0.0, 1.0)), 10)), "Reordered sequence 1 enqueue failed")
	var tick_one: Dictionary = buffer.consume_for_tick(11)
	var tick_two: Dictionary = buffer.consume_for_tick(12)
	_assert(int(tick_one.get("details", {}).get("input_sequence", 0)) == 1, "Input queue did not restore sequence order")
	_assert(int(tick_two.get("details", {}).get("input_sequence", 0)) == 2, "Second ordered input was not consumed")
	_assert(bool(tick_one.get("details", {}).get("consumed_new_input", false)), "Fresh input was not marked consumed")
	_assert(not bool(buffer.consume_for_tick(13).get("details", {}).get("consumed_new_input", true)), "Held input was marked fresh")
	_assert(_ok(buffer.enqueue(_entry(2, _intent(1.0, 0.0)), 13)), "Redundant enqueue returned a transport failure")
	_assert(int(buffer.get_report(13).get("redundant", 0)) == 1, "Redundant input was not counted")

	var stale = InputBuffer.new()
	_assert(_ok(stale.configure()), "Stale buffer setup failed")
	_assert(_ok(stale.enqueue(_entry(1, _intent(1.0, 0.0)), 1)), "Stale candidate enqueue failed")
	var stale_result: Dictionary = stale.consume_for_tick(InputBuffer.MAX_QUEUE_AGE_TICKS + 2)
	_assert(int(stale_result.get("details", {}).get("input_sequence", 0)) == 0, "Stale queued input was applied")
	_assert(int(stale.get_report().get("stale_dropped", 0)) == 1, "Stale drop was not counted")

	var held = InputBuffer.new()
	_assert(_ok(held.configure()), "Hold buffer setup failed")
	_assert(_ok(held.enqueue(_entry(1, _intent(1.0, 0.0)), 1)), "Hold input enqueue failed")
	held.consume_for_tick(1)
	var before_expiry: Dictionary = held.consume_for_tick(InputBuffer.MAX_INPUT_HOLD_TICKS)
	var after_expiry: Dictionary = held.consume_for_tick(InputBuffer.MAX_INPUT_HOLD_TICKS + 1)
	_assert(absf(float(before_expiry.get("details", {}).get("intent", {}).get("move_x", 0.0))) > 0.5, "Input stopped before hold deadline")
	_assert(is_zero_approx(float(after_expiry.get("details", {}).get("intent", {}).get("move_x", 1.0))), "Expired input did not fail safe to idle")
	_assert(int(held.get_report().get("hold_expirations", 0)) == 1, "Hold expiration was not counted")

	var windowed = InputBuffer.new()
	_assert(_ok(windowed.configure()), "Window buffer setup failed")
	var too_far: int = InputBuffer.MAX_SEQUENCE_AHEAD + 1
	_assert(_error(windowed.enqueue(_entry(too_far, _intent(1.0, 0.0)), 1)) == "INPUT_SEQUENCE_WINDOW_EXCEEDED", "Far-future input escaped sequence window")

func _test_jump_is_edge_triggered() -> void:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "Jump buffer setup failed")
	var jump_intent: Dictionary = _intent(0.0, 0.0)
	jump_intent["jump_pressed"] = true
	_assert(_ok(buffer.enqueue(_entry(1, jump_intent), 1)), "Jump enqueue failed")
	var first: Dictionary = buffer.consume_for_tick(1)
	var second: Dictionary = buffer.consume_for_tick(2)
	_assert(bool(first.get("details", {}).get("intent", {}).get("jump_pressed", false)), "Jump edge was not emitted")
	_assert(not bool(second.get("details", {}).get("intent", {}).get("jump_pressed", true)), "Jump edge repeated on held input")
	_assert(int(buffer.get_report().get("jump_edges", 0)) == 1, "Jump edge counter is wrong")

func _test_fixed_movement_ignores_client_delta() -> void:
	var movement = Movement.new()
	var record: Dictionary = _record()
	var small_delta_intent: Dictionary = _intent(0.0, 1.0)
	small_delta_intent["delta_seconds"] = 0.001
	var large_delta_intent: Dictionary = _intent(0.0, 1.0)
	large_delta_intent["delta_seconds"] = 0.25
	var first: Dictionary = movement.apply_fixed_tick(record, 1, small_delta_intent, 1.0 / 60.0)
	var second: Dictionary = movement.apply_fixed_tick(record, 1, large_delta_intent, 1.0 / 60.0)
	_assert(_ok(first) and _ok(second), "Fixed movement rejected valid intent")
	var first_position: Dictionary = first.get("details", {}).get("player", {}).get("position", {})
	var second_position: Dictionary = second.get("details", {}).get("player", {}).get("position", {})
	_assert(is_equal_approx(float(first_position.get("z", 0.0)), float(second_position.get("z", 1.0))), "Client delta changed fixed-tick displacement")
	_assert(_error(movement.apply_fixed_tick(record, 1, small_delta_intent, 1.0 / 30.0)) == "INVALID_FIXED_TICK_DELTA", "Non-60Hz authoritative delta was accepted")
func _test_fixed_service_distance_is_deterministic() -> void:
	var distances: Array[float] = []
	for fps in [30, 60, 144]:
		var service = _service()
		var scheduler = Scheduler.new()
		_assert(_ok(scheduler.configure()), "Service scheduler setup failed")
		var frames: int = fps * 2
		for _frame in range(frames):
			var scheduled: Dictionary = scheduler.advance(1.0 / float(fps))
			var first_tick: int = int(scheduled.get("details", {}).get("first_tick", 0))
			for offset in range(int(scheduled.get("details", {}).get("tick_count", 0))):
				var tick: int = first_tick + offset
				_assert(_ok(service.advance_fixed_server_tick(tick)), "Service tick advance failed")
				_assert(_ok(service.simulate_fixed_movement_tick("a", "transport-session/nx3/a", 1, 1, _intent(0.0, 1.0), 1.0 / 60.0)), "Fixed service movement failed")
		var position: Dictionary = service.get_player("a").get("position", {})
		distances.append(absf(float(position.get("z", 0.0))))
		_assert(int(service.get_report().get("server_tick", 0)) == 120, "Service server_tick is not fixed-tick count")
	_assert(is_equal_approx(distances[0], distances[1]) and is_equal_approx(distances[1], distances[2]), "Client frame rate changed authoritative distance: %s" % [distances])
	_assert(is_equal_approx(distances[0], 12.0), "Two seconds of walking did not travel 12 metres: %s" % [distances[0]])

func _test_batching_does_not_change_tick_result() -> void:
	var individual = InputBuffer.new()
	var batched = InputBuffer.new()
	_assert(_ok(individual.configure()) and _ok(batched.configure()), "Batch comparison buffer setup failed")
	var entries: Array[Dictionary] = [
		_entry(1, _intent(0.0, 1.0)),
		_entry(2, _intent(1.0, 0.0)),
		_entry(3, _intent(0.0, 0.0)),
	]
	for index in range(entries.size()):
		_assert(_ok(individual.enqueue(entries[index], index + 1)), "Individual input enqueue failed")
	for entry in entries:
		_assert(_ok(batched.enqueue(entry, 1)), "Batched input enqueue failed")
	for tick in range(1, 4):
		var left: Dictionary = individual.consume_for_tick(tick).get("details", {})
		var right: Dictionary = batched.consume_for_tick(tick).get("details", {})
		_assert(int(left.get("input_sequence", 0)) == int(right.get("input_sequence", -1)), "Batching changed consumed sequence")
		_assert(Dictionary(left.get("intent", {})) == Dictionary(right.get("intent", {})), "Batching changed fixed-tick intent")


func _test_transition_history_survives_latest_wins_coalescing() -> void:
	var history: Array = []
	for sample in [
		{"sequence": 1, "move_z": 0.0},
		{"sequence": 2, "move_z": 1.0},
		{"sequence": 3, "move_z": 1.0},
		{"sequence": 4, "move_z": 0.0},
	]:
		history = InputBatch.append_to_history(history, _entry(int(sample["sequence"]), _intent(0.0, float(sample["move_z"]))))
	_assert(history.size() == 3, "Latest-wins history did not preserve idle-movement-idle transitions")
	_assert(int(history[1].get("input_sequence", 0)) == 3, "Repeated movement state did not refresh its sequence")
	_assert(is_equal_approx(float(history[1].get("intent", {}).get("move_z", 0.0)), 1.0), "Movement transition was lost before final idle")
	_assert(int(history.back().get("input_sequence", 0)) == 4, "Final idle transition was not retained")

func _test_jittered_input_arrival_keeps_fixed_speed() -> void:
	var baseline: Dictionary = _simulate_continuous_input([0])
	var jittered: Dictionary = _simulate_continuous_input([0, 1, 0, 2, 1, 0, 3, 0])
	_assert(is_equal_approx(float(baseline.get("distance", 0.0)), 60.0), "Ten seconds baseline movement did not travel 60 metres")
	_assert(is_equal_approx(float(jittered.get("distance", 0.0)), float(baseline.get("distance", -1.0))), "Packet arrival jitter changed fixed-tick movement distance")
	_assert(int(jittered.get("hold_expirations", -1)) == 0, "Ordinary jitter exhausted the input hold window")
	_assert(int(jittered.get("last_sequence", 0)) > 250, "Jitter simulation did not process the continuous input stream")

func _simulate_continuous_input(jitter_pattern: Array) -> Dictionary:
	var buffer = InputBuffer.new()
	_assert(_ok(buffer.configure()), "Jitter buffer setup failed")
	var arrivals: Dictionary = {}
	for sample_index in range(300):
		var sequence: int = sample_index + 1
		var base_tick: int = 1 + sample_index * 2
		var jitter: int = int(jitter_pattern[sample_index % jitter_pattern.size()])
		var arrival_tick: int = mini(base_tick + jitter, 600)
		if not arrivals.has(arrival_tick):
			arrivals[arrival_tick] = []
		arrivals[arrival_tick].append(_entry(sequence, _intent(0.0, 1.0)))
	var movement = Movement.new()
	var record: Dictionary = _record()
	for tick in range(1, 601):
		for input_value in arrivals.get(tick, []):
			_assert(_ok(buffer.enqueue(Dictionary(input_value), tick)), "Jittered input enqueue failed")
		var consumed: Dictionary = buffer.consume_for_tick(tick)
		_assert(_ok(consumed), "Jittered input consume failed")
		var sequence: int = int(consumed.get("details", {}).get("input_sequence", 0))
		if sequence < 1:
			continue
		var applied: Dictionary = movement.apply_fixed_tick(record, sequence, Dictionary(consumed.get("details", {}).get("intent", {})), 1.0 / 60.0)
		_assert(_ok(applied), "Jittered fixed movement failed")
		record = Dictionary(applied.get("details", {}).get("player", record)).duplicate(true)
	return {
		"distance": absf(float(record.get("position", {}).get("z", 0.0))),
		"hold_expirations": int(buffer.get_report(600).get("hold_expirations", 0)),
		"last_sequence": int(record.get("last_input_sequence", 0)),
	}

func _test_protocol_and_runtime_wiring() -> void:
	var manifest: Dictionary = ProtocolManifest.create()
	_assert(RuntimeIdentity.CHECKPOINT in ["v16.13.0-network-nx3-fixed-tick-authoritative-simulation", "v16.14.0-network-nx4-client-prediction-reconciliation"], "Runtime identity no longer includes accepted NX3 capability")
	_assert(RuntimeIdentity.BUILD_ID in ["nx3-fixed-tick-authoritative-simulation", "nx4-client-prediction-reconciliation"], "Runtime build ID no longer includes accepted NX3 capability")
	var contracts: Dictionary = manifest.get("contract_versions", {})
	_assert(String(contracts.get("fixed_tick_scheduler", {}).get("schema", "")) == Scheduler.SCHEMA, "Protocol manifest omitted fixed scheduler")
	_assert(String(contracts.get("fixed_tick_input_buffer", {}).get("schema", "")) == InputBuffer.SCHEMA, "Protocol manifest omitted input buffer")
	_assert(String(contracts.get("input_sequence", {}).get("schema", "")) == Sequence.SCHEMA, "Protocol manifest omitted sequence wrap")
	_assert(String(contracts.get("player_input_batch", {}).get("server_delta_policy", "")) == "IGNORED_SERVER_FIXED_TICK_V1", "Protocol manifest still trusts packet arrival/client delta")
	_assert(String(contracts.get("player_input_batch", {}).get("sequence_order_policy", "")) == InputBatch.SEQUENCE_ORDER_POLICY, "Protocol manifest omitted wrap-aware batch ordering")
	var server_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	_assert(server_source.contains("FixedTickScheduler"), "M3 server does not use fixed scheduler")
	_assert(server_source.contains("simulate_fixed_movement_tick"), "M3 server does not execute fixed movement ticks")
	_assert(server_source.contains("NX3_FIXED_TICK_DELTA_SECONDS"), "M3 server has no canonical fixed delta")
	_assert(not server_source.contains("server_delta_budget"), "M3 server still derives movement from packet arrival")
	_assert(server_source.contains("INPUT_QUEUE"), "M3 server does not expose input queue rejection stage")
	var client_source: String = _load_script_source_chain(
		"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd", {}
	)
	_assert(client_source.contains("InputSequence.next"), "Client input sequence does not wrap safely")
	_assert(client_source.contains("_sequence_acknowledges"), "Client acknowledgement path is not wrap-aware")
	_assert(not client_source.contains("acknowledged_sequence >= latest_sequence"), "Client still compares acknowledgement sequences numerically")
	var config_text: String = FileAccess.get_file_as_string("res://config/network/nx3-fixed-tick-authoritative-simulation.v1.json")
	var config = JSON.parse_string(config_text)
	_assert(config is Dictionary, "NX3 config is not valid JSON")
	if config is Dictionary:
		_assert(String(config.get("checkpoint", "")) == "v16.13.0-network-nx3-fixed-tick-authoritative-simulation", "NX3 config checkpoint drifted")
		_assert(int(config.get("simulation", {}).get("tick_rate_hz", 0)) == 60, "NX3 config tick rate mismatch")
		_assert(String(config.get("input", {}).get("selection_policy", "")) == InputBuffer.INPUT_SELECTION_POLICY, "NX3 config input policy mismatch")
		_assert(String(config.get("input", {}).get("sequence_order_policy", "")) == InputBatch.SEQUENCE_ORDER_POLICY, "NX3 config sequence policy mismatch")
		_assert(not bool(config.get("simulation", {}).get("packet_arrival_delta", true)), "NX3 config still allows packet-arrival delta")

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

func _service():
	var service = Service.new()
	_assert(_ok(service.setup("simulation/nx3/test", 1, 0, {
		"profile": Service.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "TEST",
		"region_id": "region/nx3/test",
		"playable_sandbox": true,
		"fixed_tick_authority": true,
	})), "Fixed service setup failed")
	var joined: Dictionary = service.join("a", "transport-session/nx3/a", "operation/nx3/join/a")
	_assert(_ok(joined), "Fixed service join failed")
	return service

func _entry(sequence: int, intent: Dictionary) -> Dictionary:
	return {
		"input_sequence": sequence,
		"operation_id": "operation/nx3/input/%d" % sequence,
		"client_tick": sequence,
		"client_sent_at_ms": sequence,
		"intent": intent.duplicate(true),
	}

func _intent(move_x: float, move_z: float) -> Dictionary:
	return {
		"move_x": move_x,
		"move_z": move_z,
		"look_yaw": 0.0,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 0.25,
	}

func _record() -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"transport_session_id": "transport-session/nx3/a",
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

func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))

func _error(result: Dictionary) -> String:
	return String(result.get("error_code", ""))

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("NX3 fixed-tick authoritative simulation: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

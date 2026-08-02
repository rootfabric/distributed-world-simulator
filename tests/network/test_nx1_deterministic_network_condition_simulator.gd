extends SceneTree

const Rng = preload("res://scripts/network/conditions/deterministic_network_rng.gd")
const Profile = preload("res://scripts/network/conditions/network_condition_profile.gd")
const ProfileStore = preload("res://scripts/network/conditions/network_condition_profile_store.gd")
const SimulatorPort = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const ProtocolFrame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const RuntimeIdentity = preload("res://scripts/network/observability/network_runtime_identity.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const TelemetryCollector = preload("res://scripts/network/observability/network_telemetry_collector.gd")
const LaunchOptions = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptor = preload("res://scripts/runtime/runtime_descriptor.gd")

const PEER_ID := "peer/nx1/test"
const SESSION_ID := "transport-session/nx1/test"
const ROUTE_ID := "route/nx1/test"
const PAYLOAD_SCHEMA := "planet_simulator.nx1.test_payload.v1"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_rng_and_profile_store()
	_test_deterministic_schedule()
	_test_reliable_loss_preserves_delivery()
	_test_unreliable_loss_and_duplicate_semantics()
	_test_incoming_latency_and_bandwidth_queue()
	_test_burst_reorder_queue_and_presets()
	_test_runtime_switch_spike_and_blackout()
	_test_manual_conditions_hold_queued_frames()
	_test_ready_events_respect_incoming_manual_conditions()
	_test_boundary_unreliable_gap_policy()
	_test_telemetry_and_runtime_wiring()
	print("NX1 deterministic network condition simulator: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_rng_and_profile_store() -> void:
	var first = Rng.new()
	var second = Rng.new()
	_assert(_ok(first.configure(12345)), "First deterministic RNG configures")
	_assert(_ok(second.configure(12345)), "Second deterministic RNG configures")
	var values_a: Array = []
	var values_b: Array = []
	for _index in range(12):
		values_a.append(first.next_int(-1000, 1000))
		values_b.append(second.next_int(-1000, 1000))
	_assert(values_a == values_b, "Equal seeds produce equal random sequence")
	_assert(int(first.snapshot().get("draw_count", 0)) == 12, "RNG draw count is observable")
	_assert(Rng.derive_seed(1004, "OUTGOING|COMMAND") == Rng.derive_seed(1004, "OUTGOING|COMMAND"), "Stream seed derivation is stable")
	_assert(Rng.derive_seed(1004, "OUTGOING|COMMAND") != Rng.derive_seed(1004, "INCOMING|COMMAND"), "Direction has an independent random stream")
	var document_result: Dictionary = ProfileStore.load_document()
	_assert(_ok(document_result), "Preset document loads")
	var ids_result: Dictionary = ProfileStore.list_profile_ids()
	_assert(_ok(ids_result), "Preset IDs load")
	var ids: Array = ids_result.get("details", {}).get("profile_ids", [])
	_assert(ids.size() == 8, "Eight standard presets are available")
	_assert(ids.has("LOCAL") and ids.has("EXTREME") and ids.has("ASYMMETRIC"), "Required presets are present")
	var mobile: Dictionary = ProfileStore.load_profile("mobile").get("details", {}).get("profile", {})
	_assert(_ok(Profile.validate(mobile)), "Named preset returns a valid profile")
	_assert(String(mobile.get("profile_id", "")) == "MOBILE", "Preset lookup canonicalizes profile ID")
	_assert(Profile.is_passthrough(ProfileStore.load_profile("LOCAL").get("details", {}).get("profile", {})), "LOCAL is a true passthrough profile")
	_assert(not Profile.is_passthrough(mobile), "MOBILE is not a passthrough profile")


func _test_deterministic_schedule() -> void:
	var profile: Dictionary = _profile("DETERMINISTIC", {
		"outgoing_latency_min_ms": 20,
		"outgoing_latency_max_ms": 80,
		"jitter_ms": 15,
		"packet_loss_percent": 7.0,
		"reorder_percent": 25.0,
		"random_seed": 777,
	})
	var setup_a: Dictionary = _simulator(profile, 5000)
	var setup_b: Dictionary = _simulator(profile, 5000)
	var simulator_a = setup_a["simulator"]
	var simulator_b = setup_b["simulator"]
	var plans_a: Array = []
	var plans_b: Array = []
	for sequence in range(1, 13):
		var frame: Dictionary = _frame(sequence, "RELIABLE_ORDERED", "COMMAND")
		plans_a.append(simulator_a.send_to_peer(PEER_ID, frame).get("details", {}))
		plans_b.append(simulator_b.send_to_peer(PEER_ID, frame).get("details", {}))
	_assert(plans_a == plans_b, "Same seed and traffic produce byte-identical scheduling decisions")
	_assert(simulator_a.get_runtime_snapshot().get("counters", {}) == simulator_b.get_runtime_snapshot().get("counters", {}), "Deterministic runs produce equal counters")
	_assert(_ok(simulator_a.stop()) and _ok(simulator_b.stop()), "Deterministic simulators stop")


func _test_reliable_loss_preserves_delivery() -> void:
	var profile: Dictionary = _profile("RELIABLE_LOSS", {
		"outgoing_latency_min_ms": 10,
		"outgoing_latency_max_ms": 10,
		"packet_loss_percent": 100.0,
		"random_seed": 31,
	})
	var setup: Dictionary = _simulator(profile, 1000)
	var simulator = setup["simulator"]
	var delegate = setup["delegate"]
	var result: Dictionary = simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))
	_assert(_ok(result) and not bool(result.get("details", {}).get("dropped", true)), "Reliable packet is never application-dropped")
	_assert(delegate.get_messages_for_peer(PEER_ID).is_empty(), "Reliable packet waits for simulated retransmission")
	simulator.poll_events(16)
	_assert(delegate.get_messages_for_peer(PEER_ID).is_empty(), "Reliable packet is not delivered before due time")
	_assert(_ok(simulator.advance_time_ms(70)), "Manual clock advances through retransmission delay")
	simulator.poll_events(16)
	_assert(delegate.get_messages_for_peer(PEER_ID).size() == 1, "Reliable packet is delivered exactly once after simulated retransmission")
	var counters: Dictionary = simulator.get_runtime_snapshot().get("counters", {})
	_assert(int(counters.get("network_simulator_reliable_retransmissions_simulated", 0)) == 1, "Reliable loss is recorded as one retransmission")
	_assert(int(counters.get("network_simulator_unreliable_packets_dropped", 0)) == 0, "Reliable loss does not increment unreliable drops")
	_assert(_ok(simulator.stop()), "Reliable-loss simulator stops")


func _test_unreliable_loss_and_duplicate_semantics() -> void:
	var loss_profile: Dictionary = _profile("UNRELIABLE_LOSS", {
		"packet_loss_percent": 100.0,
		"random_seed": 41,
	})
	var loss_setup: Dictionary = _simulator(loss_profile, 0)
	var loss_simulator = loss_setup["simulator"]
	var loss_delegate = loss_setup["delegate"]
	var dropped: Dictionary = loss_simulator.send_to_peer(PEER_ID, _frame(1, "UNRELIABLE_SEQUENCED", "STATE"))
	_assert(_ok(dropped) and bool(dropped.get("details", {}).get("dropped", false)), "Unreliable packet is dropped by 100 percent loss")
	loss_simulator.poll_events(16)
	_assert(loss_delegate.get_messages_for_peer(PEER_ID).is_empty(), "Dropped unreliable packet never reaches delegate")
	_assert(_ok(loss_simulator.stop()), "Unreliable-loss simulator stops")

	var duplicate_profile: Dictionary = _profile("UNRELIABLE_DUPLICATE", {
		"duplicate_percent": 100.0,
		"random_seed": 42,
	})
	var duplicate_setup: Dictionary = _simulator(duplicate_profile, 0)
	var duplicate_simulator = duplicate_setup["simulator"]
	var duplicate_delegate = duplicate_setup["delegate"]
	_assert(_ok(duplicate_simulator.send_to_peer(PEER_ID, _frame(1, "UNRELIABLE_SEQUENCED", "STATE"))), "Unreliable duplicate packet queues")
	duplicate_simulator.poll_events(16)
	_assert(duplicate_delegate.get_messages_for_peer(PEER_ID).size() == 1, "Original unreliable datagram is delivered first")
	duplicate_simulator.advance_time_ms(1)
	duplicate_simulator.poll_events(16)
	_assert(duplicate_delegate.get_messages_for_peer(PEER_ID).size() == 2, "Duplicate unreliable datagram is emitted separately")
	_assert(int(duplicate_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_datagrams_duplicated", 0)) == 1, "Duplicate datagram is counted")
	_assert(_ok(duplicate_simulator.stop()), "Duplicate simulator stops")


func _test_incoming_latency_and_bandwidth_queue() -> void:
	var incoming_profile: Dictionary = _profile("INCOMING_LATENCY", {
		"incoming_latency_min_ms": 40,
		"incoming_latency_max_ms": 40,
		"random_seed": 51,
	})
	var setup: Dictionary = _simulator(incoming_profile, 200)
	var simulator = setup["simulator"]
	var delegate = setup["delegate"]
	_assert(_ok(delegate.inject_received_frame(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "Delegate accepts incoming frame")
	var before: Array = simulator.poll_events(16)
	_assert(_message_event_count(before) == 0, "Incoming message is hidden before latency expires")
	simulator.advance_time_ms(39)
	_assert(_message_event_count(simulator.poll_events(16)) == 0, "Incoming message remains queued one millisecond before deadline")
	simulator.advance_time_ms(1)
	_assert(_message_event_count(simulator.poll_events(16)) == 1, "Incoming message is released exactly at deadline")
	_assert(_ok(simulator.stop()), "Incoming-latency simulator stops")

	var bandwidth_profile: Dictionary = _profile("BANDWIDTH", {
		"bandwidth_limit_kbps": 8,
		"random_seed": 52,
	})
	var bandwidth_setup: Dictionary = _simulator(bandwidth_profile, 0)
	var bandwidth_simulator = bandwidth_setup["simulator"]
	var bandwidth_delegate = bandwidth_setup["delegate"]
	var first: Dictionary = bandwidth_simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "COMMAND", {"blob": "x".repeat(256)}))
	var second: Dictionary = bandwidth_simulator.send_to_peer(PEER_ID, _frame(2, "RELIABLE_ORDERED", "COMMAND", {"blob": "y".repeat(256)}))
	_assert(_ok(first) and _ok(second), "Bandwidth-limited reliable frames queue")
	_assert(int(second.get("details", {}).get("scheduled_at_ms", 0)) > int(first.get("details", {}).get("scheduled_at_ms", 0)), "Bandwidth cap serializes packets")
	bandwidth_simulator.poll_events(16)
	_assert(bandwidth_delegate.get_messages_for_peer(PEER_ID).size() == 1, "Only first bandwidth-limited packet is immediately deliverable")
	bandwidth_simulator.advance_time_ms(1000)
	bandwidth_simulator.poll_events(16)
	_assert(bandwidth_delegate.get_messages_for_peer(PEER_ID).size() == 2, "Second packet is delivered after bandwidth queue drains")
	_assert(_ok(bandwidth_simulator.stop()), "Bandwidth simulator stops")


func _test_burst_reorder_queue_and_presets() -> void:
	var preset_ids: Array = ProfileStore.list_profile_ids().get("details", {}).get("profile_ids", [])
	for profile_id_value in preset_ids:
		var profile_id: String = String(profile_id_value)
		var profile: Dictionary = ProfileStore.load_profile(profile_id).get("details", {}).get("profile", {})
		var setup: Dictionary = _simulator(profile, 0)
		var simulator = setup["simulator"]
		var delegate = setup["delegate"]
		var sent: Dictionary = simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))
		_assert(_ok(sent), "%s accepts reliable packet" % profile_id)
		simulator.advance_time_ms(10000)
		simulator.poll_events(64)
		_assert(delegate.get_messages_for_peer(PEER_ID).size() == 1, "%s preserves reliable delivery" % profile_id)
		_assert(_ok(simulator.stop()), "%s simulator stops" % profile_id)

	var burst_profile: Dictionary = _profile("BURST", {
		"burst_loss_probability_percent": 100.0,
		"burst_loss_duration_ms": 100,
		"random_seed": 81,
	})
	var burst_setup: Dictionary = _simulator(burst_profile, 0)
	var burst_simulator = burst_setup["simulator"]
	var burst_delegate = burst_setup["delegate"]
	var burst_drop: Dictionary = burst_simulator.send_to_peer(PEER_ID, _frame(1, "UNRELIABLE_SEQUENCED", "STATE"))
	_assert(bool(burst_drop.get("details", {}).get("dropped", false)), "Burst window drops triggering unreliable packet")
	var burst_drop_two: Dictionary = burst_simulator.send_to_peer(PEER_ID, _frame(2, "UNRELIABLE_SEQUENCED", "STATE"))
	_assert(bool(burst_drop_two.get("details", {}).get("dropped", false)), "Active burst window drops following unreliable packet")
	_assert(burst_delegate.get_messages_for_peer(PEER_ID).is_empty(), "Burst loss delivers no dropped datagrams")
	_assert(int(burst_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_burst_loss_windows", 0)) == 1, "Burst window starts once")
	_assert(_ok(burst_simulator.stop()), "Burst simulator stops")

	var reorder_profile: Dictionary = _profile("REORDER", {
		"reorder_percent": 100.0,
		"outgoing_latency_min_ms": 0,
		"outgoing_latency_max_ms": 10,
		"random_seed": 82,
	})
	var reorder_setup: Dictionary = _simulator(reorder_profile, 0)
	var reorder_simulator = reorder_setup["simulator"]
	var reorder_delegate = reorder_setup["delegate"]
	var reorder_one: Dictionary = reorder_simulator.send_to_peer(PEER_ID, _frame(1, "UNRELIABLE_SEQUENCED", "STATE"))
	var reorder_two: Dictionary = reorder_simulator.send_to_peer(PEER_ID, _frame(2, "UNRELIABLE_SEQUENCED", "STATE"))
	var first_due: int = int(reorder_one.get("details", {}).get("scheduled_at_ms", 0))
	var second_due: int = int(reorder_two.get("details", {}).get("scheduled_at_ms", 0))
	_assert(first_due > second_due, "Reorder holds the first datagram behind the second")
	reorder_simulator.set_manual_time_ms(second_due)
	reorder_simulator.poll_events(16)
	var reordered_messages: Array = reorder_delegate.get_messages_for_peer(PEER_ID)
	_assert(reordered_messages.size() == 1 and int(reordered_messages[0].get("sequence", 0)) == 2, "Newer unreliable datagram arrives first")
	reorder_simulator.set_manual_time_ms(first_due)
	reorder_simulator.poll_events(16)
	reordered_messages = reorder_delegate.get_messages_for_peer(PEER_ID)
	_assert(reordered_messages.size() == 2 and int(reordered_messages[1].get("sequence", 0)) == 1, "Held stale datagram arrives later")
	_assert(int(reorder_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_reorder_events", 0)) == 1, "Reorder event is counted")
	_assert(_ok(reorder_simulator.stop()), "Reorder simulator stops")

	var queue_profile: Dictionary = _profile("QUEUE_LIMIT", {
		"outgoing_latency_min_ms": 100,
		"outgoing_latency_max_ms": 100,
		"queue_limit_bytes": 1024,
		"random_seed": 83,
	})
	var queue_setup: Dictionary = _simulator(queue_profile, 0)
	var queue_simulator = queue_setup["simulator"]
	var large_payload: Dictionary = {"blob": "q".repeat(400)}
	var queued_reliable: Dictionary = queue_simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "COMMAND", large_payload))
	var blocked_reliable: Dictionary = queue_simulator.send_to_peer(PEER_ID, _frame(2, "RELIABLE_ORDERED", "COMMAND", large_payload))
	_assert(_ok(queued_reliable), "Queue accepts first reliable packet")
	_assert(String(blocked_reliable.get("error_code", "")) == "NETWORK_SIMULATOR_QUEUE_LIMIT", "Queue applies reliable backpressure")
	var dropped_unreliable: Dictionary = queue_simulator.send_to_peer(PEER_ID, _frame(3, "UNRELIABLE_SEQUENCED", "STATE", large_payload))
	_assert(_ok(dropped_unreliable) and bool(dropped_unreliable.get("details", {}).get("dropped", false)), "Queue overflow drops unreliable packet without breaking sender")
	_assert(_ok(queue_simulator.stop()), "Queue-limit simulator stops")

	var spike_profile: Dictionary = _profile("PERIODIC_SPIKE", {
		"lag_spike_ms": 1000,
		"random_seed": 84,
	})
	var spike_setup: Dictionary = _simulator(spike_profile, 0)
	var spike_simulator = spike_setup["simulator"]
	var sixteenth_due: int = 0
	for sequence in range(1, 17):
		var result: Dictionary = spike_simulator.send_to_peer(PEER_ID, _frame(sequence, "RELIABLE_ORDERED", "CONTROL"))
		if sequence == 16:
			sixteenth_due = int(result.get("details", {}).get("scheduled_at_ms", 0))
	_assert(sixteenth_due >= 1000, "LAG_SPIKE preset injects deterministic periodic spike")
	_assert(int(spike_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_periodic_lag_spikes", 0)) == 1, "Periodic lag spike is counted once")
	_assert(_ok(spike_simulator.stop()), "Periodic-spike simulator stops")

	var blackout_profile: Dictionary = _profile("PERIODIC_BLACKOUT", {
		"disconnect_duration_ms": 40,
		"random_seed": 53,
	})
	var blackout_setup: Dictionary = _simulator(blackout_profile, 0)
	var blackout_simulator = blackout_setup["simulator"]
	var blackout_delegate = blackout_setup["delegate"]
	var sixty_fourth_due: int = 0
	for sequence in range(1, 65):
		var result: Dictionary = blackout_simulator.send_to_peer(PEER_ID, _frame(sequence, "RELIABLE_ORDERED", "CONTROL"))
		if sequence == 64:
			sixty_fourth_due = int(result.get("details", {}).get("scheduled_at_ms", 0))
	_assert(sixty_fourth_due >= 40, "Periodic transport blackout delays the sixty-fourth reliable packet")
	blackout_simulator.set_manual_time_ms(sixty_fourth_due)
	blackout_simulator.poll_events(128)
	_assert(blackout_delegate.get_messages_for_peer(PEER_ID).size() == 64, "Periodic blackout preserves all reliable application frames")
	_assert(int(blackout_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_periodic_disconnect_blackouts", 0)) == 1, "Periodic transport blackout is counted once")
	_assert(_ok(blackout_simulator.stop()), "Periodic-blackout simulator stops")


func _test_runtime_switch_spike_and_blackout() -> void:
	var local: Dictionary = ProfileStore.load_profile("LOCAL").get("details", {}).get("profile", {})
	var setup: Dictionary = _simulator(local, 100)
	var simulator = setup["simulator"]
	var delegate = setup["delegate"]
	_assert(bool(simulator.get_runtime_snapshot().get("passthrough", false)), "LOCAL begins in passthrough mode")
	_assert(_ok(simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "LOCAL packet sends")
	_assert(delegate.get_messages_for_peer(PEER_ID).size() == 1, "LOCAL packet reaches delegate synchronously")
	var delayed: Dictionary = _profile("SWITCHED", {
		"outgoing_latency_min_ms": 25,
		"outgoing_latency_max_ms": 25,
		"random_seed": 61,
	})
	var switched: Dictionary = simulator.set_profile(delayed)
	_assert(_ok(switched) and int(switched.get("details", {}).get("profile_generation", 0)) == 2, "Profile switches at runtime")
	_assert(_ok(simulator.send_to_peer(PEER_ID, _frame(2, "RELIABLE_ORDERED", "CONTROL"))), "Post-switch packet queues")
	_assert(delegate.get_messages_for_peer(PEER_ID).size() == 1, "Runtime switch affects new packets")
	simulator.advance_time_ms(25)
	simulator.poll_events(16)
	_assert(delegate.get_messages_for_peer(PEER_ID).size() == 2, "Post-switch packet uses new latency")
	_assert(_ok(simulator.trigger_lag_spike("OUTGOING", 100)), "Manual lag spike starts")
	var spike: Dictionary = simulator.send_to_peer(PEER_ID, _frame(3, "RELIABLE_ORDERED", "CONTROL"))
	_assert(int(spike.get("details", {}).get("scheduled_at_ms", 0)) >= 250, "Manual lag spike extends outgoing deadline")
	_assert(_ok(simulator.trigger_disconnect_blackout("OUTGOING", 80)), "Manual disconnect blackout starts")
	var unreliable: Dictionary = simulator.send_to_peer(PEER_ID, _frame(4, "UNRELIABLE_SEQUENCED", "STATE"))
	_assert(bool(unreliable.get("details", {}).get("dropped", false)), "Blackout drops unreliable datagram")
	var reliable: Dictionary = simulator.send_to_peer(PEER_ID, _frame(5, "RELIABLE_ORDERED", "CONTROL"))
	_assert(_ok(reliable) and not bool(reliable.get("details", {}).get("dropped", true)), "Blackout retains reliable datagram")
	_assert(int(reliable.get("details", {}).get("scheduled_at_ms", 0)) >= 205, "Reliable datagram waits until blackout ends")
	_assert(_ok(simulator.stop()), "Runtime-switch simulator stops")


func _test_manual_conditions_hold_queued_frames() -> void:
	var blackout_profile: Dictionary = _profile("QUEUED_BLACKOUT", {
		"outgoing_latency_min_ms": 50,
		"outgoing_latency_max_ms": 50,
		"random_seed": 62,
	})
	var blackout_setup: Dictionary = _simulator(blackout_profile, 0)
	var blackout_simulator = blackout_setup["simulator"]
	var blackout_delegate = blackout_setup["delegate"]
	_assert(_ok(blackout_simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "Reliable frame queues before manual blackout")
	_assert(_ok(blackout_simulator.send_to_peer(PEER_ID, _frame(2, "UNRELIABLE_SEQUENCED", "STATE"))), "Unreliable frame queues before manual blackout")
	_assert(_ok(blackout_simulator.advance_time_ms(10)), "Blackout clock advances before trigger")
	_assert(_ok(blackout_simulator.trigger_disconnect_blackout("OUTGOING", 100)), "Outgoing blackout starts after frames are queued")
	_assert(_ok(blackout_simulator.advance_time_ms(40)), "Blackout clock reaches original frame deadline")
	blackout_simulator.poll_events(16)
	_assert(blackout_delegate.get_messages_for_peer(PEER_ID).is_empty(), "Queued frames are not delivered during active blackout")
	_assert(_ok(blackout_simulator.advance_time_ms(59)), "Blackout clock reaches final blocked millisecond")
	blackout_simulator.poll_events(16)
	_assert(blackout_delegate.get_messages_for_peer(PEER_ID).is_empty(), "Queued frames remain blocked until blackout deadline")
	_assert(_ok(blackout_simulator.advance_time_ms(1)), "Blackout clock reaches release deadline")
	blackout_simulator.poll_events(16)
	_assert(blackout_delegate.get_messages_for_peer(PEER_ID).size() == 2, "Queued reliable and pre-blackout unreliable frames release after blackout")
	_assert(int(blackout_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_queued_packets_deferred_by_blackout", 0)) == 2, "Blackout records both deferred queued frames")
	_assert(_ok(blackout_simulator.stop()), "Queued-blackout simulator stops")

	var spike_profile: Dictionary = _profile("QUEUED_LAG_SPIKE", {
		"outgoing_latency_min_ms": 50,
		"outgoing_latency_max_ms": 50,
		"random_seed": 63,
	})
	var spike_setup: Dictionary = _simulator(spike_profile, 0)
	var spike_simulator = spike_setup["simulator"]
	var spike_delegate = spike_setup["delegate"]
	_assert(_ok(spike_simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "Reliable frame queues before manual lag spike")
	spike_simulator.advance_time_ms(10)
	_assert(_ok(spike_simulator.trigger_lag_spike("OUTGOING", 100)), "Outgoing lag spike starts after frame is queued")
	spike_simulator.advance_time_ms(40)
	spike_simulator.poll_events(16)
	_assert(spike_delegate.get_messages_for_peer(PEER_ID).is_empty(), "Queued frame is not delivered during active lag spike")
	spike_simulator.advance_time_ms(60)
	spike_simulator.poll_events(16)
	_assert(spike_delegate.get_messages_for_peer(PEER_ID).size() == 1, "Queued frame releases after lag spike deadline")
	_assert(int(spike_simulator.get_runtime_snapshot().get("counters", {}).get("network_simulator_queued_packets_deferred_by_lag_spike", 0)) == 1, "Lag spike records deferred queued frame")
	_assert(_ok(spike_simulator.stop()), "Queued-lag-spike simulator stops")

	var incoming_profile: Dictionary = _profile("QUEUED_INCOMING_BLACKOUT", {
		"incoming_latency_min_ms": 50,
		"incoming_latency_max_ms": 50,
		"random_seed": 64,
	})
	var incoming_setup: Dictionary = _simulator(incoming_profile, 0)
	var incoming_simulator = incoming_setup["simulator"]
	var incoming_delegate = incoming_setup["delegate"]
	_assert(_ok(incoming_delegate.inject_received_frame(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "Incoming reliable frame enters delegate before blackout")
	_assert(_message_event_count(incoming_simulator.poll_events(16)) == 0, "Incoming reliable frame is queued by simulator")
	incoming_simulator.advance_time_ms(10)
	_assert(_ok(incoming_simulator.trigger_disconnect_blackout("INCOMING", 100)), "Incoming blackout starts after frame is queued")
	incoming_simulator.advance_time_ms(40)
	_assert(_message_event_count(incoming_simulator.poll_events(16)) == 0, "Queued incoming frame is hidden during active blackout")
	incoming_simulator.advance_time_ms(60)
	_assert(_message_event_count(incoming_simulator.poll_events(16)) == 1, "Queued incoming frame releases after blackout deadline")
	_assert(_ok(incoming_simulator.stop()), "Queued-incoming-blackout simulator stops")


func _test_ready_events_respect_incoming_manual_conditions() -> void:
	var blackout_setup: Dictionary = _simulator(_profile("READY_EVENT_BLACKOUT", {"random_seed": 65}), 0)
	var blackout_simulator = blackout_setup["simulator"]
	var blackout_delegate = blackout_setup["delegate"]
	_assert(_ok(blackout_delegate.inject_received_frame(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "First incoming frame prepares for ready-event blackout regression")
	_assert(_ok(blackout_delegate.inject_received_frame(PEER_ID, _frame(2, "RELIABLE_ORDERED", "CONTROL"))), "Second incoming frame prepares for ready-event blackout regression")
	var first_events: Array = blackout_simulator.poll_events(1)
	_assert(_message_sequences(first_events) == [1], "poll_events(1) returns only the first prepared message")
	var ready_before: Dictionary = blackout_simulator.get_runtime_snapshot()
	_assert(int(ready_before.get("ready_message_events", 0)) == 1, "Second prepared message remains in ready events")
	_assert(_ok(blackout_simulator.trigger_disconnect_blackout("INCOMING", 100)), "Incoming blackout starts while one message is already ready")
	_assert(_ok(blackout_delegate.drain()), "Lifecycle event is queued during incoming blackout")
	var lifecycle_events: Array = blackout_simulator.poll_events(1)
	_assert(lifecycle_events.size() == 1 and String(lifecycle_events[0].get("event_type", "")) == "LISTENER_DRAINING", "Lifecycle event bypasses incoming blackout")
	_assert(_message_event_count(lifecycle_events) == 0, "Lifecycle bypass does not leak the held application message")
	var blocked_events: Array = blackout_simulator.poll_events(1)
	_assert(blocked_events.is_empty(), "Ready MESSAGE_RECEIVED stays blocked during incoming blackout")
	var ready_during: Dictionary = blackout_simulator.get_runtime_snapshot()
	_assert(int(ready_during.get("ready_message_events", 0)) == 1, "Held ready message remains queued during blackout")
	_assert(int(ready_during.get("ready_message_events_blocked", 0)) == 1, "Runtime snapshot reports blocked ready message")
	blackout_simulator.advance_time_ms(99)
	_assert(blackout_simulator.poll_events(1).is_empty(), "Ready message remains blocked until final blackout millisecond")
	blackout_simulator.advance_time_ms(1)
	_assert(_message_sequences(blackout_simulator.poll_events(1)) == [2], "Held ready message releases after blackout in original order")
	_assert(_ok(blackout_simulator.stop()), "Ready-event blackout simulator stops")

	var spike_setup: Dictionary = _simulator(_profile("READY_EVENT_LAG_SPIKE", {"random_seed": 66}), 0)
	var spike_simulator = spike_setup["simulator"]
	var spike_delegate = spike_setup["delegate"]
	_assert(_ok(spike_delegate.inject_received_frame(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "First incoming frame prepares for ready-event lag-spike regression")
	_assert(_ok(spike_delegate.inject_received_frame(PEER_ID, _frame(2, "RELIABLE_ORDERED", "CONTROL"))), "Second incoming frame prepares for ready-event lag-spike regression")
	_assert(_message_sequences(spike_simulator.poll_events(1)) == [1], "Lag-spike regression leaves one prepared message in ready events")
	_assert(int(spike_simulator.get_runtime_snapshot().get("ready_message_events", 0)) == 1, "Lag-spike regression confirms one ready message before trigger")
	_assert(_ok(spike_simulator.trigger_lag_spike("INCOMING", 80)), "Incoming lag spike starts while one message is already ready")
	_assert(spike_simulator.poll_events(1).is_empty(), "Ready MESSAGE_RECEIVED stays blocked during incoming lag spike")
	spike_simulator.advance_time_ms(79)
	_assert(spike_simulator.poll_events(1).is_empty(), "Ready message remains blocked until final lag-spike millisecond")
	spike_simulator.advance_time_ms(1)
	_assert(_message_sequences(spike_simulator.poll_events(1)) == [2], "Held ready message releases after lag spike")
	_assert(_ok(spike_simulator.stop()), "Ready-event lag-spike simulator stops")

	var order_setup: Dictionary = _simulator(_profile("READY_EVENT_ORDER", {"random_seed": 67}), 0)
	var order_simulator = order_setup["simulator"]
	var order_delegate = order_setup["delegate"]
	for sequence in range(1, 4):
		_assert(_ok(order_delegate.inject_received_frame(PEER_ID, _frame(sequence, "RELIABLE_ORDERED", "CONTROL"))), "Incoming frame %d prepares ready-event order regression" % sequence)
	_assert(_message_sequences(order_simulator.poll_events(1)) == [1], "Order regression consumes only first ready message")
	_assert(int(order_simulator.get_runtime_snapshot().get("ready_message_events", 0)) == 2, "Two ready messages remain before order blackout")
	_assert(_ok(order_simulator.trigger_disconnect_blackout("INCOMING", 50)), "Order blackout starts with two held ready messages")
	_assert(order_simulator.poll_events(2).is_empty(), "Both ready messages remain held during order blackout")
	order_simulator.advance_time_ms(50)
	_assert(_message_sequences(order_simulator.poll_events(2)) == [2, 3], "Held ready messages preserve FIFO order after blackout")
	_assert(_ok(order_simulator.stop()), "Ready-event order simulator stops")


func _test_boundary_unreliable_gap_policy() -> void:
	var delegate = LoopbackPort.new()
	var boundary = Boundary.new()
	_assert(_ok(boundary.configure(delegate, 8192, 16, 65536)), "Boundary configures for unreliable sequence policy")
	_assert(_ok(boundary.start_server({"transport": "LOOPBACK", "name": "nx1-gap"})), "Boundary loopback server starts")
	_assert(_ok(delegate.attach_peer(PEER_ID, SESSION_ID, ROUTE_ID, 1)), "Boundary peer attaches")
	_assert(_ok(boundary.poll_events(16)), "Boundary consumes peer connection")
	_assert(_ok(boundary.mark_peer_ready(PEER_ID)), "Boundary peer becomes ready")
	_assert(_ok(delegate.inject_received_frame(PEER_ID, _frame(2, "UNRELIABLE_SEQUENCED", "STATE"))), "Unreliable frame with sequence gap injects")
	var gap_poll: Dictionary = boundary.poll_events(16)
	_assert(_ok(gap_poll), "Unreliable sequence gap does not fail boundary")
	_assert(_message_event_count(gap_poll.get("details", {}).get("events", [])) == 1, "Newest unreliable frame is delivered across gap")
	_assert(int(boundary.get_peer_snapshot(PEER_ID).get("incoming_sequence", 0)) == 2, "Unreliable gap advances latest sequence")
	_assert(_ok(delegate.inject_received_frame(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "Earlier reliable frame injects after newer unreliable frame")
	var reliable_poll: Dictionary = boundary.poll_events(16)
	_assert(_ok(reliable_poll), "Earlier reliable frame does not fail boundary")
	_assert(_message_event_count(reliable_poll.get("details", {}).get("events", [])) == 1, "Valid reliable frame survives cross-stream reordering")
	_assert(_ok(delegate.inject_received_frame(PEER_ID, _frame(1, "UNRELIABLE_SEQUENCED", "STATE"))), "Stale reordered unreliable frame injects")
	var stale_poll: Dictionary = boundary.poll_events(16)
	_assert(_ok(stale_poll), "Stale unreliable frame does not fail boundary")
	_assert(_message_event_count(stale_poll.get("details", {}).get("events", [])) == 0, "Stale unreliable frame is suppressed within its own stream")
	_assert(_ok(delegate.inject_received_frame(PEER_ID, _frame(3, "RELIABLE_ORDERED", "CONTROL"))), "Later reliable frame injects across global sequence interleave")
	_assert(_message_event_count(boundary.poll_events(16).get("details", {}).get("events", [])) == 1, "Reliable stream accepts global gaps owned by other transport streams")
	var sequence_streams: Dictionary = boundary.get_peer_snapshot(PEER_ID).get("incoming_sequences", {})
	_assert(int(sequence_streams.get("UNRELIABLE_SEQUENCED|ENET_CHANNEL_2", 0)) == 2, "Unreliable STATE stream retains latest-wins cursor")
	_assert(int(sequence_streams.get("RELIABLE|ENET_CHANNEL_0", 0)) == 3, "Reliable CONTROL stream has an independent cursor")
	var peer_contract: Dictionary = ProtocolManifest.contract_versions().get("peer_session", {})
	_assert(String(peer_contract.get("incoming_sequence_stream_policy", "")) == "DELIVERY_CLASS_ENET_CHANNEL_V1", "Protocol manifest fingerprints incoming sequence stream policy")
	_assert(String(peer_contract.get("reliable_sequence_policy", "")) == "MONOTONIC_PER_STREAM_GLOBAL_GAPS_V1", "Protocol manifest fingerprints reliable per-stream gap policy")
	_assert(_ok(boundary.stop()), "Boundary unreliable sequence test stops")


func _test_telemetry_and_runtime_wiring() -> void:
	var fingerprint: Dictionary = RuntimeIdentity.create_fingerprint({
		"world_id": "moon",
		"network_session_token": "session-id/nx1/unit",
	})
	var telemetry = TelemetryCollector.new()
	_assert(_ok(telemetry.configure("test", fingerprint, 64)), "NX1 telemetry collector configures")
	var profile: Dictionary = _profile("TELEMETRY", {
		"outgoing_latency_min_ms": 5,
		"outgoing_latency_max_ms": 5,
		"random_seed": 71,
	})
	var delegate = LoopbackPort.new()
	var simulator = SimulatorPort.new()
	_assert(_ok(simulator.setup(delegate, profile, telemetry, true, 0)), "Simulator attaches telemetry")
	_assert(_ok(simulator.start_server({"transport": "LOOPBACK", "name": "nx1-telemetry"})), "Telemetry simulator starts")
	_assert(_ok(delegate.attach_peer(PEER_ID, SESSION_ID, ROUTE_ID, 1)), "Telemetry peer attaches")
	simulator.poll_events(16)
	_assert(_ok(simulator.send_to_peer(PEER_ID, _frame(1, "RELIABLE_ORDERED", "CONTROL"))), "Telemetry packet queues")
	simulator.advance_time_ms(5)
	simulator.poll_events(16)
	var sample_result: Dictionary = telemetry.create_sample(10)
	_assert(_ok(sample_result), "NX1 telemetry sample creates")
	var sample: Dictionary = sample_result.get("details", {}).get("sample", {})
	_assert(int(sample.get("counters", {}).get("network_simulator_outgoing_packets_queued", 0)) == 1, "Telemetry counts simulator queue")
	_assert(int(sample.get("counters", {}).get("network_simulator_outgoing_packets_delivered", 0)) == 1, "Telemetry counts simulator delivery")
	_assert(Dictionary(sample.get("distributions", {})).has("network_simulator_outgoing_scheduled_delay_ms"), "Telemetry includes scheduled delay distribution")
	_assert(is_equal_approx(float(sample.get("gauges", {}).get("network_simulator_outgoing_queue_messages", -1.0)), 0.0), "Telemetry queue gauge returns to zero")
	var parsed: Dictionary = LaunchOptions.parse(PackedStringArray([
		"--role=dedicated-server", "--world=moon", "--network-profile=bad_mobile",
		"--network-presets-file=res://config/network/network-condition-presets.v1.json",
	]))
	_assert(bool(parsed.get("success", false)), "CLI accepts canonicalized network profile")
	_assert(String(parsed.get("options", {}).get("network_condition_profile", "")) == "BAD_MOBILE", "CLI normalizes network profile")
	var descriptor: Dictionary = RuntimeDescriptor.create(parsed.get("options", {}), {
		"checkpoint": RuntimeIdentity.CHECKPOINT,
		"build_id": RuntimeIdentity.BUILD_ID,
	})
	_assert(_ok(RuntimeDescriptor.validate(descriptor)), "Runtime descriptor validates NX1 network condition fields")
	_assert(String(descriptor.get("network_condition_profile", "")) == "BAD_MOBILE", "Runtime descriptor publishes active network profile")
	_assert(String(descriptor.get("network_condition_presets_file", "")) == "res://config/network/network-condition-presets.v1.json", "Runtime descriptor publishes preset source")
	var invalid: Dictionary = LaunchOptions.parse(PackedStringArray([
		"--role=dedicated-server", "--world=moon", "--network-profile=bad mobile",
	]))
	_assert(not bool(invalid.get("success", true)), "CLI rejects invalid network profile ID")
	var server_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	var client_source: String = FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
	var app_source: String = FileAccess.get_file_as_string("res://scripts/app/simulator_app.gd")
	_assert(server_source.contains("ConditionSimulatorPort.new()") and client_source.contains("ConditionSimulatorPort.new()"), "M3 server and client wrap production ENet in NX1 simulator")
	_assert(server_source.contains("set_network_condition_profile") and client_source.contains("set_network_condition_profile"), "Runtime profile switching is exposed on both endpoints")
	_assert(app_source.count("network_condition_profile") >= 2, "SimulatorApp forwards network profile to server and client")
	_assert(RuntimeIdentity.CHECKPOINT in ["v16.11.0-network-nx1-deterministic-condition-simulator", "v16.12.0-network-nx2-realtime-traffic-separation", "v16.13.0-network-nx3-fixed-tick-authoritative-simulation"], "Runtime identity no longer includes accepted NX1 capability")
	_assert(_ok(simulator.stop()), "Telemetry simulator stops")


func _simulator(profile: Dictionary, initial_time_ms: int) -> Dictionary:
	var delegate = LoopbackPort.new()
	var simulator = SimulatorPort.new()
	_assert(_ok(simulator.setup(delegate, profile, null, true, initial_time_ms)), "Simulator setup for %s" % String(profile.get("profile_id", "")))
	_assert(_ok(simulator.start_server({"transport": "LOOPBACK", "name": String(profile.get("profile_id", "")).to_lower()})), "Simulator server starts for %s" % String(profile.get("profile_id", "")))
	_assert(_ok(delegate.attach_peer(PEER_ID, SESSION_ID, ROUTE_ID, 1)), "Simulator peer attaches for %s" % String(profile.get("profile_id", "")))
	simulator.poll_events(16)
	return {"delegate": delegate, "simulator": simulator}


func _profile(profile_id: String, overrides: Dictionary) -> Dictionary:
	var values: Dictionary = {
		"outgoing_latency_min_ms": 0,
		"outgoing_latency_max_ms": 0,
		"incoming_latency_min_ms": 0,
		"incoming_latency_max_ms": 0,
		"jitter_ms": 0,
		"packet_loss_percent": 0.0,
		"burst_loss_probability_percent": 0.0,
		"burst_loss_duration_ms": 0,
		"duplicate_percent": 0.0,
		"reorder_percent": 0.0,
		"bandwidth_limit_kbps": 0,
		"queue_limit_bytes": 1048576,
		"lag_spike_ms": 0,
		"disconnect_duration_ms": 0,
		"random_seed": 1,
	}
	for key in overrides.keys():
		values[key] = overrides[key]
	return Profile.create(profile_id, values)


func _frame(sequence: int, delivery_mode: String, channel: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"sequence": sequence}
	for key in extra.keys():
		payload[key] = extra[key]
	return ProtocolFrame.create(
		"frame/nx1/test/%d" % sequence,
		SESSION_ID,
		sequence,
		channel,
		delivery_mode,
		PAYLOAD_SCHEMA,
		payload
	)


func _message_sequences(events) -> Array[int]:
	var sequences: Array[int] = []
	if events is Array:
		for event_value in events:
			if event_value is Dictionary and String(event_value.get("event_type", "")) == "MESSAGE_RECEIVED":
				sequences.append(int(event_value.get("sequence", 0)))
	return sequences


func _message_event_count(events) -> int:
	var count: int = 0
	if events is Array:
		for event_value in events:
			if event_value is Dictionary and String(event_value.get("event_type", "")) == "MESSAGE_RECEIVED":
				count += 1
	return count


func _ok(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)

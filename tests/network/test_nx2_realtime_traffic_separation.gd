extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ChannelPolicy = preload("res://scripts/network/realtime/realtime_channel_policy.gd")
const Frame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const Boundary = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const Loopback = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const InputBatch = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_batch.gd")
const ItemDelta = preload("res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd")
const CompactSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const ProtocolManifest = preload("res://scripts/network/observability/network_protocol_manifest.gd")
const ENetPort = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

const PEER := "peer/nx2/a"
const SESSION := "transport-session/nx2/a"
const ROUTE := "route/nx2/a"
const SCHEMA := "planet_simulator.nx2.test.v1"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_architecture_config()
	_test_channel_policy()
	_test_boundary_stream_partition_and_coalescing()
	_test_realtime_coalescing_is_transactional()
	_test_input_batch()
	_test_compact_realtime_wire_budget()
	_test_item_graph_delta()
	_test_runtime_wiring()
	_finish()



func _test_architecture_config() -> void:
	var text: String = FileAccess.get_file_as_string("res://config/network/nx2-realtime-traffic-separation.v1.json")
	var parsed = JSON.parse_string(text)
	_assert(parsed is Dictionary, "NX2 architecture config is not valid JSON")
	if not parsed is Dictionary:
		return
	var config: Dictionary = Dictionary(parsed)
	_assert(String(config.get("schema", "")) == "planet_simulator.nx2_realtime_traffic_separation.v1", "NX2 architecture config schema mismatch")
	_assert(String(config.get("checkpoint", "")) == "v16.12.0-network-nx2-realtime-traffic-separation", "NX2 architecture config checkpoint mismatch")
	_assert(String(config.get("base_checkpoint", "")) == "v16.11.0-network-nx1-deterministic-condition-simulator", "NX2 architecture config base mismatch")
	_assert(int(config.get("movement", {}).get("input_batch_max_entries", 0)) == InputBatch.MAX_INPUTS, "NX2 architecture config input redundancy mismatch")
	_assert(int(config.get("movement", {}).get("snapshot_interval_ms", 0)) == 50, "NX2 architecture config snapshot cadence mismatch")
	_assert(not bool(config.get("movement", {}).get("successful_command_result", true)), "NX2 architecture config still enables movement success results")
	_assert(not bool(config.get("movement", {}).get("per_input_full_snapshot", true)), "NX2 architecture config still enables per-input full snapshots")
	_assert(String(config.get("items", {}).get("full_snapshot_channel", "")) == "RESYNC", "NX2 architecture config does not isolate full Item Graph resync")
	_assert(String(config.get("items", {}).get("delta_validation", "")) == ItemDelta.VALIDATION_POLICY, "NX2 architecture config omits strict Item Graph delta validation")
	_assert(String(config.get("items", {}).get("committed_mutation_delta_failure", "")) == "FULL_RESYNC_WITH_SUCCESS_RESULT", "NX2 architecture config permits false rejection after committed mutation")
	_assert(not bool(config.get("movement", {}).get("fixed_tick_authority", true)), "NX2 architecture config incorrectly claims NX3 fixed tick")
	_assert(String(config.get("physical_binding", {}).get("validation", "")) == ENetPort.PHYSICAL_FRAME_BINDING_POLICY, "NX2 architecture config physical binding policy mismatch")
	_assert(String(config.get("physical_binding", {}).get("violation_scope", "")) == ENetPort.PHYSICAL_MISMATCH_HANDLING_POLICY, "NX2 architecture config does not keep mismatch peer-local")
	_assert(not bool(config.get("physical_binding", {}).get("listener_failure", true)), "NX2 architecture config permits peer mismatch to fail listener")
	_assert(bool(config.get("physical_binding", {}).get("healthy_peers_preserved", false)), "NX2 architecture config does not preserve healthy peers")
	_assert(int(config.get("acceptance", {}).get("focused_steps", 0)) == 9, "NX2 focused step count does not include physical regression")

func _test_channel_policy() -> void:
	_assert(ChannelPolicy.ENET_CHANNEL_COUNT == 6, "NX2 must expose six ENet channels")
	_assert(ChannelPolicy.CANONICAL_CHANNELS == ["CONTROL", "INPUT", "SNAPSHOT", "ITEM", "RESYNC", "TELEMETRY"], "Canonical channel order changed")
	_assert(ChannelPolicy.UNRELIABLE_TRANSPORT_MAPPING == "RAW_ENET_UNRELIABLE_APPLICATION_SEQUENCED_V1", "Unreliable transport mapping is not protocol-versioned")
	_assert(ChannelPolicy.REALTIME_COALESCING_POLICY == "LATEST_PENDING_TRANSACTIONAL_REPLACEMENT_PER_STREAM_V1", "Realtime coalescing replacement is not protocol-versioned")
	var manifest: Dictionary = ProtocolManifest.create()
	_assert(String(manifest.get("channel_policy", {}).get("queue_policy", {}).get("unreliable_transport_mapping", "")) == ChannelPolicy.UNRELIABLE_TRANSPORT_MAPPING, "Protocol manifest omitted raw-unreliable mapping")
	_assert(String(manifest.get("channel_policy", {}).get("queue_policy", {}).get("realtime_coalescing", "")) == ChannelPolicy.REALTIME_COALESCING_POLICY, "Protocol manifest omitted transactional realtime replacement")
	_assert(String(manifest.get("contract_versions", {}).get("canonical_item_graph_delta", {}).get("validation_policy", "")) == ItemDelta.VALIDATION_POLICY, "Protocol manifest omitted Item Graph delta validation policy")
	_assert(String(manifest.get("contract_versions", {}).get("player_input_batch", {}).get("history_policy", "")) == InputBatch.HISTORY_POLICY, "Protocol manifest omitted input transition-history policy")
	_assert(String(manifest.get("contract_versions", {}).get("player_input_batch", {}).get("server_delta_policy", "")) == InputBatch.SERVER_DELTA_POLICY, "Protocol manifest omitted server movement budget policy")
	_assert(String(manifest.get("contract_versions", {}).get("enet_transport", {}).get("physical_frame_binding_policy", "")) == ENetPort.PHYSICAL_FRAME_BINDING_POLICY, "Protocol manifest omitted physical frame binding policy")
	_assert(String(manifest.get("contract_versions", {}).get("enet_transport", {}).get("physical_mismatch_handling_policy", "")) == ENetPort.PHYSICAL_MISMATCH_HANDLING_POLICY, "Protocol manifest omitted peer-local mismatch policy")
	for channel in ChannelPolicy.CANONICAL_CHANNELS:
		_assert(ChannelPolicy.channel_index(channel) >= 0, "Canonical channel has no ENet index: %s" % channel)
		_assert(_ok(ChannelPolicy.validate_delivery(channel, ChannelPolicy.default_delivery(channel))), "Canonical delivery was rejected: %s" % channel)
	_assert(_error(ChannelPolicy.validate_delivery("INPUT", "RELIABLE_ORDERED")) == "CHANNEL_DELIVERY_MISMATCH", "Reliable input channel was accepted")
	_assert(_error(ChannelPolicy.validate_delivery("SNAPSHOT", "RELIABLE_ORDERED")) == "CHANNEL_DELIVERY_MISMATCH", "Reliable snapshot channel was accepted")
	var valid := Frame.create("frame/nx2/input/1", SESSION, 1, "INPUT", "UNRELIABLE_SEQUENCED", SCHEMA, {"value": 1})
	_assert(_ok(Frame.validate(valid)), "Valid NX2 input frame was rejected")
	var invalid := valid.duplicate(true)
	invalid["delivery_mode"] = "RELIABLE_ORDERED"
	_assert(_error(Frame.validate(invalid)) == "CHANNEL_DELIVERY_MISMATCH", "Mismatched input delivery was accepted")


func _test_boundary_stream_partition_and_coalescing() -> void:
	var port = Loopback.new()
	var boundary = Boundary.new()
	_assert(_ok(boundary.configure(port, 4096, 16, 65536)), "NX2 boundary config failed")
	_assert(_ok(boundary.start_server({"transport": "LOOPBACK", "name": "nx2"})), "NX2 loopback server failed")
	_assert(_ok(port.attach_peer(PEER, SESSION, ROUTE, 1)), "NX2 peer attach failed")
	_assert(_ok(boundary.poll_events(8)), "NX2 connect polling failed")
	for method in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		_assert(_ok(boundary.call(method, PEER)), "NX2 peer state failed: %s" % method)

	var input_one := boundary.create_frame_for_peer(PEER, "INPUT", SCHEMA, {"ordinal": 1}, "UNRELIABLE_SEQUENCED")
	_assert(_ok(input_one) and _ok(boundary.send_to_peer(PEER, input_one.get("details", {}).get("frame", {}))), "First realtime input queue failed")
	var input_two := boundary.create_frame_for_peer(PEER, "INPUT", SCHEMA, {"ordinal": 2}, "UNRELIABLE_SEQUENCED")
	var coalesced: Dictionary = boundary.send_to_peer(PEER, input_two.get("details", {}).get("frame", {}))
	_assert(_ok(coalesced), "Second realtime input queue failed")
	_assert(int(coalesced.get("details", {}).get("coalesced_messages", 0)) == 1, "Realtime input was not latest-wins coalesced")
	_assert(int(boundary.get_peer_snapshot(PEER).get("queued_messages", 0)) == 1, "Coalesced input retained two queue reservations")

	for ordinal in [1, 2]:
		var item_frame := boundary.create_frame_for_peer(PEER, "ITEM", SCHEMA, {"ordinal": ordinal}, "RELIABLE_ORDERED")
		_assert(_ok(item_frame) and _ok(boundary.send_to_peer(PEER, item_frame.get("details", {}).get("frame", {}))), "Reliable item FIFO queue failed")
	_assert(int(boundary.get_peer_snapshot(PEER).get("queued_messages", 0)) == 3, "Independent item/input streams were not retained")
	var streams: Dictionary = boundary.get_snapshot().get("outbound_streams", {})
	_assert(streams.has(PEER) and Dictionary(streams[PEER]).size() == 2, "Boundary did not partition outbound streams")
	var flushed: Dictionary = boundary.flush_outbound(16, PEER)
	_assert(_ok(flushed) and int(flushed.get("details", {}).get("dispatched", 0)) == 3, "Partitioned streams did not flush")
	var delivered: Array = port.get_messages_for_peer(PEER)
	_assert(delivered.size() == 3, "Unexpected delivered frame count")
	var item_ordinals: Array[int] = []
	var input_ordinals: Array[int] = []
	for delivered_frame in delivered:
		if String(delivered_frame.get("channel", "")) == "ITEM":
			item_ordinals.append(int(delivered_frame.get("payload", {}).get("ordinal", 0)))
		elif String(delivered_frame.get("channel", "")) == "INPUT":
			input_ordinals.append(int(delivered_frame.get("payload", {}).get("ordinal", 0)))
	_assert(item_ordinals == [1, 2], "Reliable item FIFO lost order")
	_assert(input_ordinals == [2], "Stale coalesced input was delivered")
	boundary.stop()


func _test_realtime_coalescing_is_transactional() -> void:
	var port = Loopback.new()
	var boundary = Boundary.new()
	_assert(_ok(boundary.configure(port, 4096, 8, 700)), "Transactional coalescing boundary config failed")
	_assert(_ok(boundary.start_server({"transport": "LOOPBACK", "name": "nx2-coalescing"})), "Transactional coalescing server failed")
	_assert(_ok(port.attach_peer(PEER, SESSION, ROUTE, 1)), "Transactional coalescing peer attach failed")
	_assert(_ok(boundary.poll_events(8)), "Transactional coalescing connect polling failed")
	for method in ["mark_peer_handshaking", "mark_peer_synchronizing", "mark_peer_ready"]:
		_assert(_ok(boundary.call(method, PEER)), "Transactional coalescing peer state failed: %s" % method)

	var original := boundary.create_frame_for_peer(
		PEER, "INPUT", SCHEMA, {"ordinal": 1, "body": "small"}, "UNRELIABLE_SEQUENCED"
	)
	_assert(_ok(original) and _ok(boundary.send_to_peer(PEER, original.get("details", {}).get("frame", {}))), "Transactional coalescing original queue failed")
	var oversized := boundary.create_frame_for_peer(
		PEER, "INPUT", SCHEMA, {"ordinal": 2, "body": "x".repeat(900)}, "UNRELIABLE_SEQUENCED"
	)
	_assert(_ok(oversized), "Transactional coalescing oversized frame creation failed")
	_assert(_error(boundary.send_to_peer(PEER, oversized.get("details", {}).get("frame", {}))) == "PEER_QUEUE_BYTE_LIMIT", "Failed replacement did not preserve queue limit error")
	var queued: Dictionary = boundary.get_peer_snapshot(PEER)
	_assert(int(queued.get("queued_messages", 0)) == 1, "Failed replacement lost original queue reservation")
	_assert(int(queued.get("outgoing_sequence", 0)) == 1, "Failed replacement committed outgoing sequence")
	var flushed: Dictionary = boundary.flush_outbound(8, PEER)
	_assert(_ok(flushed) and int(flushed.get("details", {}).get("dispatched", 0)) == 1, "Original realtime frame was not retained after failed replacement")
	var delivered: Array = port.get_messages_for_peer(PEER)
	_assert(delivered.size() == 1 and int(delivered[0].get("payload", {}).get("ordinal", 0)) == 1, "Failed replacement discarded the original realtime frame")
	boundary.stop()


func _test_input_batch() -> void:
	var inputs: Array = []
	for sequence in [8, 9, 10]:
		inputs.append({
			"input_sequence": sequence,
			"operation_id": "operation/nx2/input/%d" % sequence,
			"client_tick": sequence,
			"client_sent_at_ms": 1000 + sequence,
			"intent": {
				"move_x": 1.0, "move_z": 0.0, "look_yaw": 0.1,
				"look_pitch": 0.0, "jump_pressed": false, "sprint": true,
				"delta_seconds": 1.0 / 60.0,
			},
		})
	var batch: Dictionary = InputBatch.create(
		"input-batch/nx2/a/10", "a", 2, inputs, "operation/nx2/input/10"
	)
	_assert(_ok(InputBatch.validate(batch)), "Valid three-input redundancy batch was rejected")
	_assert(int(batch.get("latest_sequence", 0)) == 10, "Batch latest sequence is incorrect")
	_assert(Dictionary(batch.get("inputs", [])[0]).has("s") and not Dictionary(batch.get("inputs", [])[0]).has("input_sequence"), "Input batch is not compact on wire")
	var expanded: Dictionary = InputBatch.expand_inputs(batch)
	_assert(_ok(expanded), "Compact input batch did not expand")
	var expanded_inputs: Array = expanded.get("details", {}).get("inputs", [])
	_assert(expanded_inputs.size() == 3 and int(expanded_inputs.back().get("input_sequence", 0)) == 10, "Expanded input batch lost entries")
	_assert(String(expanded_inputs.back().get("operation_id", "")) == "operation/nx2/input/10", "Latest operation ID was not preserved")
	_assert(String(expanded_inputs.front().get("operation_id", "")).begins_with("operation/nx2/redundant/a/"), "Redundant input operation ID is not deterministic")
	var history: Array = []
	for sample in [
		{"sequence": 1, "move_z": 0.0, "delta": 0.03},
		{"sequence": 2, "move_z": 1.0, "delta": 0.04},
		{"sequence": 3, "move_z": 1.0, "delta": 0.05},
		{"sequence": 4, "move_z": 0.0, "delta": 0.03},
	]:
		history = InputBatch.append_to_history(history, {
			"input_sequence": int(sample["sequence"]),
			"operation_id": "operation/nx2/history/%d" % int(sample["sequence"]),
			"client_tick": int(sample["sequence"]),
			"client_sent_at_ms": 2000 + int(sample["sequence"]),
			"intent": {
				"move_x": 0.0, "move_z": float(sample["move_z"]),
				"look_yaw": 0.0, "look_pitch": 0.0,
				"jump_pressed": false, "sprint": false,
				"delta_seconds": float(sample["delta"]),
			},
		})
	_assert(history.size() == 3, "Input history did not retain idle-movement-idle transitions")
	_assert(int(history.front().get("input_sequence", 0)) == 1 and int(history.back().get("input_sequence", 0)) == 4, "Transition redundancy window has wrong sequence range")
	_assert(int(history[1].get("input_sequence", 0)) == 3, "Repeated movement state did not refresh the transition sequence")
	_assert(float(history[1].get("intent", {}).get("move_z", 0.0)) == 1.0, "Movement transition was lost from redundancy history")
	_assert(is_equal_approx(float(history[1].get("intent", {}).get("delta_seconds", 0.0)), 0.05), "Client input duration was unexpectedly accumulated")
	var stable_history: Array = history.duplicate(true)
	for sequence in range(5, 25):
		stable_history = InputBatch.append_to_history(stable_history, {
			"input_sequence": sequence,
			"operation_id": "operation/nx2/history/%d" % sequence,
			"client_tick": sequence,
			"client_sent_at_ms": 2000 + sequence,
			"intent": {"move_x": 0.0, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 0.03},
		})
	_assert(stable_history.size() == 3, "Transition redundancy history exceeded three states")
	_assert(int(stable_history.front().get("input_sequence", 0)) == 1, "Earlier idle transition was unexpectedly discarded without a fourth state transition")
	_assert(int(stable_history.back().get("input_sequence", 0)) == 24, "Latest repeated idle sequence was not retained")
	var reordered := batch.duplicate(true)
	reordered["inputs"][1]["s"] = 8
	reordered["checksum"] = Utils.payload_hash(_without_checksum(reordered))
	_assert(_error(InputBatch.validate(reordered)) == "INVALID_PLAYER_INPUT_SEQUENCE_ORDER", "Duplicate input sequence was accepted")
	var oversized_inputs: Array = inputs.duplicate(true)
	oversized_inputs.append(inputs.back().duplicate(true))
	oversized_inputs.back()["input_sequence"] = 11
	oversized_inputs.back()["operation_id"] = "operation/nx2/input/11"
	var oversized := InputBatch.create(
		"input-batch/nx2/a/11", "a", 2, oversized_inputs, "operation/nx2/input/11"
	)
	_assert(_error(InputBatch.validate(oversized)) == "INVALID_PLAYER_INPUT_BATCH_SIZE", "Oversized redundancy batch was accepted")
	var input_frame := Frame.create(
		"frame/nx2/input-budget/1", SESSION, 1, "INPUT", "UNRELIABLE_SEQUENCED", SCHEMA,
		{"type": "PLAYER_INPUT_BATCH", "batch": batch, "client_sent_at_ms": 1010, "client_message_sequence": 10}
	)
	var encoded_input: Dictionary = Frame.encode(input_frame)
	_assert(_ok(encoded_input), "Compact input frame failed to encode")
	_assert(int(encoded_input.get("details", {}).get("packet_bytes", 9999)) < 1200, "Three-input batch exceeds realtime MTU budget")
	var decoded_input: Dictionary = Frame.decode(encoded_input.get("details", {}).get("packet", PackedByteArray()))
	_assert(_ok(decoded_input), "Compact input frame failed JSON wire round-trip")
	var decoded_batch: Dictionary = decoded_input.get("details", {}).get("frame", {}).get("payload", {}).get("batch", {})
	_assert(_ok(InputBatch.validate(decoded_batch)), "Input batch checksum changed after protocol-frame JSON round-trip")


func _test_compact_realtime_wire_budget() -> void:
	var snapshot: Dictionary = _gameplay_snapshot()
	var compact_result: Dictionary = CompactSnapshot.encode(snapshot)
	_assert(_ok(compact_result), "Gameplay snapshot compaction failed")
	var compact: Dictionary = compact_result.get("details", {}).get("snapshot", {})
	_assert(_ok(CompactSnapshot.validate(compact)), "Compact gameplay snapshot validation failed")
	var decoded: Dictionary = CompactSnapshot.decode(compact)
	_assert(_ok(decoded), "Compact gameplay snapshot decode failed")
	_assert(
		Utils.canonical_json(decoded.get("details", {}).get("snapshot", {})) == Utils.canonical_json(snapshot),
		"Compact gameplay snapshot did not round-trip byte-canonically"
	)
	var frame := Frame.create(
		"frame/nx2/snapshot-budget/1", SESSION, 2, "SNAPSHOT", "UNRELIABLE_SEQUENCED", SCHEMA,
		{"type": "COMPACT_GAMEPLAY_SNAPSHOT", "reason": "MOVEMENT_NETWORK_TICK", "snapshot": compact, "server_sent_at_ms": 2000}
	)
	var encoded: Dictionary = Frame.encode(frame)
	_assert(_ok(encoded), "Compact gameplay snapshot frame failed to encode")
	_assert(int(encoded.get("details", {}).get("packet_bytes", 9999)) < 1200, "Compact gameplay snapshot exceeds realtime MTU budget")


func _test_item_graph_delta() -> void:
	var base := _item_snapshot(4, 10, [{"item_id": "item/a", "definition_id": "definition/a"}], {"inventory/a": ["item/a"]})
	var target := _item_snapshot(5, 11, [
		{"item_id": "item/a", "definition_id": "definition/a"},
		{"item_id": "item/b", "definition_id": "definition/b"},
	], {"inventory/a": ["item/a", "item/b"]})
	var created: Dictionary = ItemDelta.create(base, target)
	_assert(_ok(created), "Item Graph delta creation failed")
	var delta: Dictionary = created.get("details", {}).get("delta", {})
	_assert(_ok(ItemDelta.validate(delta)), "Created Item Graph delta is invalid")
	var applied: Dictionary = ItemDelta.apply(base, delta)
	_assert(_ok(applied), "Item Graph delta application failed")
	_assert(Utils.canonical_json(applied.get("details", {}).get("snapshot", {})) == Utils.canonical_json(target), "Item Graph delta did not reproduce target")
	var stale_base := base.duplicate(true)
	stale_base["revision"] = 3
	stale_base.erase("checksum")
	stale_base["checksum"] = Utils.payload_hash(stale_base)
	_assert(_error(ItemDelta.apply(stale_base, delta)) == "ITEM_GRAPH_DELTA_BASE_REVISION_MISMATCH", "Stale Item Graph base was accepted")
	var malformed_revision := delta.duplicate(true)
	malformed_revision["base_revision"] = "1"
	_assert(_error(ItemDelta.validate(malformed_revision)) == "INVALID_ITEM_GRAPH_DELTA_REVISION", "String Item Graph revision was accepted")
	var malformed_checksum := delta.duplicate(true)
	malformed_checksum["base_checksum"] = "G".repeat(64)
	_assert(_error(ItemDelta.validate(malformed_checksum)) == "INVALID_ITEM_GRAPH_DELTA_CHECKSUM", "Non-hex Item Graph checksum was accepted")


func _test_runtime_wiring() -> void:
	var powershell_runner: String = FileAccess.get_file_as_string("res://RUN_NX2_REALTIME_TRAFFIC_SEPARATION_TESTS.ps1")
	_assert(powershell_runner.contains("res://tests/network/test_nx2_physical_channel_processes.gd"), "PowerShell focused runner omits physical channel regression")
	_assert(powershell_runner.contains("PASS (9/9)"), "PowerShell focused runner step count is not 9/9")
	var server := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	var client := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
	var controller := FileAccess.get_file_as_string("res://scripts/items/presentation/item_gameplay_controller.gd")
	var m7_bridge := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m7/m7_network_item_command_bridge.gd")
	var enet := FileAccess.get_file_as_string("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")
	_assert(server.contains("func _handle_player_input_batch"), "Server input batching is not wired")
	_assert(server.contains("_movement_results_suppressed += 1"), "Movement success result suppression is absent")
	_assert(not server.contains("_broadcast_snapshot(\"PLAYER_INPUT_SIMULATED\")"), "Per-input movement snapshot remains")
	_assert(server.contains("COMPACT_GAMEPLAY_SNAPSHOT") and server.contains("MOVEMENT_NETWORK_TICK"), "Compact network-tick movement snapshot is absent")
	_assert(client.contains("PLAYER_INPUT_BATCH") and client.contains("expect_result\": false"), "Client input batching/nonblocking contract is absent")
	_assert(client.contains("RealtimeChannelPolicy.INPUT") and client.contains("RealtimeChannelPolicy.ITEM"), "Client channels are not separated")
	_assert(client.contains("ITEM_GRAPH_RESYNC_REQUEST") and server.contains("_handle_item_graph_resync_request"), "Item Graph explicit resync is not wired")
	_assert(server.contains("ITEM_GRAPH_DELTA_BUILD_FALLBACK") and server.contains("_broadcast_item_snapshot"), "Committed Item Graph mutation has no full-resync fallback")
	_assert(not server.contains('result = _failure("ITEM_GRAPH_DELTA_BUILD_FAILED"'), "Committed Item Graph mutation is incorrectly converted into rejection")
	_assert(controller.contains("uses_server_authoritative_persistence") and controller.contains("SERVER_AUTHORITATIVE_PERSISTENCE"), "Server-authoritative persistence capability is not consulted")
	_assert(m7_bridge.contains("func uses_server_authoritative_persistence() -> bool") and m7_bridge.contains("return true"), "M7 network bridge does not suppress client item.save")
	_assert(enet.contains("ChannelPolicyScript.ENET_CHANNEL_COUNT"), "ENet did not adopt six-channel policy")
	_assert(enet.contains("MultiplayerPeer.TRANSFER_MODE_UNRELIABLE if delivery_mode == \"UNRELIABLE_SEQUENCED\""), "NX2 realtime delivery still relies on ENet ordered packet-size-sensitive sequencing")

	_assert(server.contains("_movement_snapshot_retransmit_requests += 1"), "Redundant movement batches do not request authoritative snapshot retransmission")
	_assert(server.contains("_movement_snapshot_dirty = target_count > 0 and not all_enqueued"), "Movement snapshot dirty state is cleared before all target queues accept the acknowledgement")
	_assert(enet.contains("PHYSICAL_CHANNEL_MISMATCH"), "Physical ENet channel mismatch is not rejected")
	_assert(enet.contains("PHYSICAL_DELIVERY_MODE_MISMATCH"), "Physical ENet transfer mode mismatch is not rejected")


func _gameplay_snapshot() -> Dictionary:
	var players: Array = []
	for logical_id in ["a", "b"]:
		var inventory: Array = []
		for index in range(5):
			inventory.append("item/%s/%d" % [logical_id, index])
		players.append({
			"logical_player_id": logical_id,
			"player_entity_id": "player/%s" % logical_id,
			"transport_session_id": "transport-session/nx2/%s" % logical_id,
			"ownership_epoch": 2,
			"connected": true,
			"position": {"x": 10.0, "y": 2.0, "z": -4.0},
			"velocity": {"x": 1.0, "y": 0.0, "z": 0.0},
			"inventory": inventory,
			"last_input_sequence": 100,
			"state_revision": 12,
			"orientation_yaw": 0.25,
			"flashlight_enabled": false,
		})
	var snapshot: Dictionary = {
		"schema": "planet_simulator.player_state_snapshot.v1",
		"authority_owner_id": "simulation/nx2/test",
		"authority_epoch": 1,
		"revision": 20,
		"server_tick": 200,
		"region_id": "region/nx2/test",
		"players": players,
		"shared_item": {
			"item_id": "item/shared/beacon/1",
			"available": true,
			"owner_player_entity_id": "",
			"revision": 3,
		},
	}
	snapshot["checksum"] = Utils.payload_hash(snapshot)
	return snapshot


func _item_snapshot(revision: int, tick: int, items: Array, inventories: Dictionary) -> Dictionary:
	var snapshot: Dictionary = {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "simulation/nx2/test",
		"authority_epoch": 1,
		"revision": revision,
		"tick": tick,
		"items": items.duplicate(true),
		"inventories": inventories.duplicate(true),
		"containers": [],
		"mounts": [],
		"open_containers": {},
	}
	snapshot["checksum"] = Utils.payload_hash(snapshot)
	return snapshot


func _without_checksum(value: Dictionary) -> Dictionary:
	var copy := value.duplicate(true)
	copy.erase("checksum")
	return copy


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
	print("NX2 realtime traffic separation: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

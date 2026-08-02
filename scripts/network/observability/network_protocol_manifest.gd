extends RefCounted

const FingerprintScript = preload("res://scripts/network/observability/network_build_fingerprint.gd")
const ProtocolFrameScript = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const TransportEventScript = preload("res://scripts/network/transports/v2/network_transport_event.gd")
const PeerSessionScript = preload("res://scripts/network/transports/v2/network_peer_session.gd")
const TransportBoundaryScript = preload("res://scripts/network/transports/v2/network_transport_boundary_v2.gd")
const TransportPortScript = preload("res://scripts/network/transports/v2/network_transport_port_v2.gd")
const PlayerInputScript = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const PlayerSnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const PlayerDeltaScript = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")
const CommandResultScript = preload("res://scripts/runtime/networked_gameplay/contracts/command_result.gd")
const ItemGraphSnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_snapshot.gd")
const ItemGraphDeltaScript = preload("res://scripts/runtime/networked_gameplay/contracts/item_graph_delta.gd")
const CompatibilityHandshakeScript = preload("res://scripts/network/observability/network_compatibility_handshake.gd")
const ObservabilitySampleScript = preload("res://scripts/network/observability/network_observability_sample.gd")
const NetworkConditionProfileScript = preload("res://scripts/network/conditions/network_condition_profile.gd")
const NetworkConditionSimulatorPortScript = preload("res://scripts/network/conditions/network_condition_simulator_port.gd")
const RealtimeChannelPolicyScript = preload("res://scripts/network/realtime/realtime_channel_policy.gd")
const PlayerInputBatchScript = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_batch.gd")
const CanonicalItemGraphDeltaScript = preload("res://scripts/runtime/networked_gameplay/contracts/canonical_item_graph_delta.gd")
const CompactGameplaySnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/compact_gameplay_snapshot.gd")
const ENetPortScript = preload("res://scripts/network/transports/v2/enet_multi_peer_transport_port.gd")

const SCHEMA: String = "planet_simulator.network_protocol_manifest.v1"
const MANIFEST_VERSION: int = 1
const M3_MESSAGE_SCHEMA: String = "planet_simulator.m3.graphical_multiplayer_message.v1"
const FIELDS: Array[String] = [
	"schema", "manifest_version", "contract_versions", "channel_policy", "protocol_hash",
]


static func create() -> Dictionary:
	var contracts: Dictionary = contract_versions()
	var channels: Dictionary = channel_policy()
	return {
		"schema": SCHEMA,
		"manifest_version": MANIFEST_VERSION,
		"contract_versions": contracts,
		"channel_policy": channels,
		"protocol_hash": FingerprintScript.compute_protocol_hash(contracts, channels),
	}


static func current_protocol_hash() -> String:
	return String(create().get("protocol_hash", ""))


static func contract_versions() -> Dictionary:
	return {
		"protocol_frame": {
			"schema": ProtocolFrameScript.SCHEMA,
			"protocol_version": ProtocolFrameScript.PROTOCOL_VERSION,
		},
		"transport_event": {"schema": TransportEventScript.SCHEMA},
		"peer_session": {
			"schema": PeerSessionScript.SCHEMA,
			"incoming_sequence_stream_policy": PeerSessionScript.INCOMING_SEQUENCE_STREAM_POLICY,
			"reliable_sequence_policy": PeerSessionScript.RELIABLE_SEQUENCE_POLICY,
			"unreliable_sequence_policy": PeerSessionScript.UNRELIABLE_SEQUENCE_POLICY,
		},
		"transport_boundary": {"schema": TransportBoundaryScript.SCHEMA},
		"transport_port": {"schema": TransportPortScript.SCHEMA},
		"enet_transport": {
			"physical_frame_binding_policy": ENetPortScript.PHYSICAL_FRAME_BINDING_POLICY,
			"physical_mismatch_handling_policy": ENetPortScript.PHYSICAL_MISMATCH_HANDLING_POLICY,
		},
		"m3_message": {"schema": M3_MESSAGE_SCHEMA},
		"player_input": {"schema": PlayerInputScript.SCHEMA},
		"player_input_batch": {
			"schema": PlayerInputBatchScript.SCHEMA,
			"max_inputs": PlayerInputBatchScript.MAX_INPUTS,
			"history_policy": PlayerInputBatchScript.HISTORY_POLICY,
			"server_delta_policy": PlayerInputBatchScript.SERVER_DELTA_POLICY,
		},
		"player_snapshot": {"schema": PlayerSnapshotScript.SCHEMA},
		"player_delta": {"schema": PlayerDeltaScript.SCHEMA},
		"command_result": {"schema": CommandResultScript.SCHEMA},
		"item_graph_snapshot": {"schema": ItemGraphSnapshotScript.SCHEMA},
		"item_graph_delta": {"schema": ItemGraphDeltaScript.SCHEMA},
		"canonical_item_graph_delta": {
			"schema": CanonicalItemGraphDeltaScript.SCHEMA,
			"validation_policy": CanonicalItemGraphDeltaScript.VALIDATION_POLICY,
		},
		"compact_gameplay_snapshot": {"schema": CompactGameplaySnapshotScript.SCHEMA},
		"compatibility_hello": {"schema": CompatibilityHandshakeScript.HELLO_SCHEMA},
		"compatibility_ack": {"schema": CompatibilityHandshakeScript.ACK_SCHEMA},
		"compatibility_rejection": {"schema": CompatibilityHandshakeScript.REJECTION_SCHEMA},
		"observability_sample": {"schema": ObservabilitySampleScript.SCHEMA},
		"network_condition_profile": {"schema": NetworkConditionProfileScript.SCHEMA},
		"network_condition_simulator_port": {"schema": NetworkConditionSimulatorPortScript.SIMULATOR_SCHEMA},
	}


static func channel_policy() -> Dictionary:
	var policy: Dictionary = RealtimeChannelPolicyScript.canonical_policy()
	policy["frame_channels"] = ProtocolFrameScript.CHANNELS.duplicate()
	policy["delivery_modes"] = ProtocolFrameScript.DELIVERY_MODES.duplicate()
	policy["queue_policy"] = {
		"partition": "PEER_DELIVERY_CHANNEL_STREAM_V1",
		"realtime_coalescing": RealtimeChannelPolicyScript.REALTIME_COALESCING_POLICY,
		"reliable_ordering": "FIFO_PER_STREAM_V1",
		"flush_fairness": "PRIORITY_ROUND_ROBIN_V1",
		"unreliable_transport_mapping": RealtimeChannelPolicyScript.UNRELIABLE_TRANSPORT_MAPPING,
	}
	return policy


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = _validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("UNSUPPORTED_SCHEMA")
	if int(value.get("manifest_version", 0)) != MANIFEST_VERSION:
		return _failure("UNSUPPORTED_MANIFEST_VERSION")
	if not value.get("contract_versions") is Dictionary or not value.get("channel_policy") is Dictionary:
		return _failure("INVALID_PROTOCOL_COMPONENTS")
	var expected: Dictionary = create()
	if Dictionary(value.get("contract_versions", {})) != Dictionary(expected["contract_versions"]):
		return _failure("CONTRACT_VERSION_DRIFT")
	if Dictionary(value.get("channel_policy", {})) != Dictionary(expected["channel_policy"]):
		return _failure("CHANNEL_POLICY_DRIFT")
	if String(value.get("protocol_hash", "")) != String(expected["protocol_hash"]):
		return _failure("PROTOCOL_HASH_MISMATCH")
	return _success()


static func _validate_exact_fields(value: Dictionary, expected: Array[String]) -> Dictionary:
	var actual: Array[String] = []
	for key_value in value.keys():
		actual.append(String(key_value))
	actual.sort()
	var sorted_expected: Array[String] = expected.duplicate()
	sorted_expected.sort()
	return _success() if actual == sorted_expected else _failure("FIELD_SET_MISMATCH", {
		"expected": sorted_expected,
		"actual": actual,
	})


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const IngressScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const SessionBindingScript = preload("res://scripts/network/gateway/gateway_session_binding.gd")
const RouteBindingScript = preload("res://scripts/network/gateway/gateway_route_binding.gd")
const ProjectionSubscriptionScript = preload("res://scripts/network/gateway/projection_subscription.gd")
const GatewayDescriptorScript = preload("res://scripts/network/gateway/gateway_descriptor.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_client_world_frames()
	_test_gateway_ingress()
	_test_gateway_egress_projection_fencing()
	_test_session_identity_separation()
	_test_route_revision_independence()
	_test_projection_subscription()
	_test_gateway_descriptor()
	_finish()


func _test_client_world_frames() -> void:
	var operation_frame: Dictionary = _operation_frame()
	_assert_ok(FrameScript.validate(operation_frame), "Valid WORLD_OPERATION frame rejected")
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(operation_frame)
	_assert(bool(round_trip.get("success", false)), "WORLD_OPERATION frame is not JSON round-trip safe")
	if bool(round_trip.get("success", false)):
		_assert(
			NetworkUtilsScript.canonical_json(round_trip.get("value")) == NetworkUtilsScript.canonical_json(operation_frame),
			"WORLD_OPERATION frame changed across JSON round-trip",
		)
	var missing_operation: Dictionary = operation_frame.duplicate(true)
	missing_operation["payload"].erase("operation_id")
	_assert_error(FrameScript.validate(missing_operation), "INVALID_OPERATION_ID", "Operation without operation_id accepted")

	var input_frame: Dictionary = FrameScript.create(
		"frame/test/input-1",
		"gateway-session/test/a",
		"CLIENT_TO_WORLD",
		"INPUT_MOVEMENT",
		8,
		"planet_simulator.test_input.v1",
		{"input_seq": 42, "axis_x": 1},
	)
	_assert_ok(FrameScript.validate(input_frame), "Valid INPUT_MOVEMENT frame rejected")
	input_frame["payload"]["input_seq"] = 0
	_assert_error(FrameScript.validate(input_frame), "INVALID_INPUT_SEQUENCE", "Zero input sequence accepted")

	var runtime_payload: Dictionary = _operation_frame()
	var runtime_node := Node.new()
	runtime_payload["payload"]["runtime_object"] = runtime_node
	_assert_error(FrameScript.validate(runtime_payload), "NON_CANONICAL_PAYLOAD", "Godot runtime object accepted in frame payload")
	runtime_node.free()


func _test_gateway_ingress() -> void:
	var frame: Dictionary = _operation_frame()
	var ingress: Dictionary = IngressScript.create(
		"gateway-envelope/test/ingress-1",
		"gateway/test/g1",
		"backend-link/test/g1-a",
		"gateway-session/test/a",
		14,
		92,
		52,
		"authority/test/a",
		"server-instance/test/a-1",
		"ACTIVE",
		frame,
	)
	_assert_ok(IngressScript.validate(ingress), "Valid ACTIVE ingress rejected")
	_assert(
		String(ingress["frame"]["payload"]["operation_id"]) == String(frame["payload"]["operation_id"]),
		"Gateway ingress changed OperationId",
	)
	var warm: Dictionary = ingress.duplicate(true)
	warm["route_role"] = "WARM"
	_assert_error(IngressScript.validate(warm), "NON_ACTIVE_MUTATION_ROUTE", "WARM route accepted mutating command")
	var session_mismatch: Dictionary = ingress.duplicate(true)
	session_mismatch["gateway_session_id"] = "gateway-session/test/other"
	_assert_error(IngressScript.validate(session_mismatch), "SESSION_MISMATCH", "Ingress accepted mismatched session")


func _test_gateway_egress_projection_fencing() -> void:
	var projection_frame: Dictionary = _projection_frame()
	var egress: Dictionary = EgressScript.create(
		"gateway-envelope/test/egress-1",
		"gateway/test/g1",
		"backend-link/test/g1-b",
		"gateway-session/test/a",
		14,
		93,
		53,
		"authority/test/b",
		"server-instance/test/b-1",
		"PROJECTION",
		projection_frame,
	)
	_assert_ok(EgressScript.validate(egress), "Valid projection egress rejected")
	var forged_active: Dictionary = egress.duplicate(true)
	forged_active["source_role"] = "ACTIVE"
	_assert_error(EgressScript.validate(forged_active), "PROJECTION_SOURCE_REQUIRED", "ACTIVE role accepted WORLD_PROJECTION frame")
	var wrong_projection_channel: Dictionary = egress.duplicate(true)
	wrong_projection_channel["frame"] = FrameScript.create(
		"frame/test/snapshot-from-projection",
		"gateway-session/test/a",
		"WORLD_TO_CLIENT",
		"AUTHORITATIVE_SNAPSHOT",
		9,
		"planet_simulator.test_snapshot.v1",
		{"revision": 1},
	)
	_assert_error(EgressScript.validate(wrong_projection_channel), "PROJECTION_CHANNEL_REQUIRED", "Projection source emitted authoritative snapshot")


func _test_session_identity_separation() -> void:
	var binding: Dictionary = SessionBindingScript.create(
		"gateway-session/test/a",
		"client-session/test/a",
		"player/test/alice",
		"entity/test/player-alice",
		"world/test/earth",
		3,
		"ATTACHED",
	)
	_assert_ok(SessionBindingScript.validate(binding), "Valid gateway session binding rejected")
	var peer_leak: Dictionary = binding.duplicate(true)
	peer_leak["peer_id"] = "player/test/alice"
	_assert_error(SessionBindingScript.validate(peer_leak), "UNEXPECTED_FIELD", "peer_id leaked into session binding")
	var player_as_entity: Dictionary = binding.duplicate(true)
	player_as_entity["player_entity_id"] = "player/test/alice"
	_assert_error(SessionBindingScript.validate(player_as_entity), "INVALID_ID", "PlayerId accepted as PlayerEntityId")


func _test_route_revision_independence() -> void:
	var route: Dictionary = RouteBindingScript.create(
		"gateway-route/test/a",
		"gateway-session/test/a",
		"entity/test/player-alice",
		"authority/test/a",
		"server-instance/test/a-1",
		52,
		92,
		"ACTIVE",
	)
	_assert_ok(RouteBindingScript.validate(route), "Valid route binding rejected")
	var same_numeric_value: Dictionary = route.duplicate(true)
	same_numeric_value["route_revision"] = 52
	_assert_ok(
		RouteBindingScript.validate(same_numeric_value),
		"RouteRevision was incorrectly coupled to AuthorityEpoch numeric value",
	)


func _test_projection_subscription() -> void:
	var subscription: Dictionary = ProjectionSubscriptionScript.create(
		"projection-subscription/test/b",
		"gateway-session/test/a",
		"authority/test/b",
		"server-instance/test/b-1",
		"projection-stream/test/b-neighbor",
		2,
		4,
		"projection-grant/test/a-b",
		"interest/test/neighbor-b",
		true,
	)
	_assert_ok(ProjectionSubscriptionScript.validate(subscription), "Valid read-only projection subscription rejected")
	subscription["read_only"] = false
	_assert_error(
		ProjectionSubscriptionScript.validate(subscription),
		"PROJECTION_NOT_READ_ONLY",
		"Writable projection subscription accepted",
	)


func _test_gateway_descriptor() -> void:
	var descriptor: Dictionary = GatewayDescriptorScript.create(
		"gateway-descriptor/test/g1",
		"gateway/test/g1",
		"gateway-pop/test/us-central",
		"us/central",
		"endpoint/test/g1-public",
		7,
		"HEALTHY",
		73,
	)
	_assert_ok(GatewayDescriptorScript.validate(descriptor), "Valid GatewayDescriptor rejected")
	var server_endpoint: Dictionary = descriptor.duplicate(true)
	server_endpoint["simulation_server_endpoint"] = "127.0.0.1:7777"
	_assert_error(
		GatewayDescriptorScript.validate(server_endpoint),
		"UNEXPECTED_FIELD",
		"Simulation-server endpoint leaked into GatewayDescriptor",
	)
	var over_capacity: Dictionary = descriptor.duplicate(true)
	over_capacity["capacity_hint"] = 101
	_assert_error(
		GatewayDescriptorScript.validate(over_capacity),
		"INVALID_CAPACITY_HINT",
		"Out-of-range capacity hint accepted",
	)


func _operation_frame() -> Dictionary:
	return FrameScript.create(
		"frame/test/operation-1",
		"gateway-session/test/a",
		"CLIENT_TO_WORLD",
		"WORLD_OPERATION",
		7,
		"planet_simulator.test_world_operation.v1",
		{
			"operation_id": "operation/test/pickup-1",
			"command": "pickup",
			"target_id": "entity/test/item-1",
		},
	)


func _projection_frame() -> Dictionary:
	return FrameScript.create(
		"frame/test/projection-1",
		"gateway-session/test/a",
		"WORLD_TO_CLIENT",
		"WORLD_PROJECTION",
		8,
		"planet_simulator.test_world_projection.v1",
		{
			"read_only": true,
			"source_revision": 4,
			"entities": ["entity/test/tree-1"],
		},
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code,
		"%s: %s" % [message, result],
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EG0 Edge Gateway contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("EG0 Edge Gateway contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

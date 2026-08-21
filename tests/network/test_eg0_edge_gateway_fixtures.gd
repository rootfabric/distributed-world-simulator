extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")
const IngressScript = preload("res://scripts/network/gateway/gateway_ingress_envelope.gd")
const EgressScript = preload("res://scripts/network/gateway/gateway_egress_envelope.gd")
const SessionBindingScript = preload("res://scripts/network/gateway/gateway_session_binding.gd")
const RouteBindingScript = preload("res://scripts/network/gateway/gateway_route_binding.gd")
const ProjectionSubscriptionScript = preload("res://scripts/network/gateway/projection_subscription.gd")
const GatewayDescriptorScript = preload("res://scripts/network/gateway/gateway_descriptor.gd")

const FIXTURE_PATH := "res://tests/network/fixtures/edge_gateway/eg0_contract_fixtures.v1.json"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	var text: String = FileAccess.get_file_as_string(FIXTURE_PATH)
	_assert(not text.is_empty(), "EG0 fixture file is missing or empty")
	var parsed = JSON.parse_string(text)
	_assert(parsed is Dictionary, "EG0 fixture root is not a Dictionary")
	if not parsed is Dictionary:
		_finish()
		return
	var fixture: Dictionary = Dictionary(parsed)
	_assert(String(fixture.get("schema")) == "planet_simulator.edge_gateway_eg0_fixture_set.v1", "Fixture schema mismatch")
	_assert(int(fixture.get("protocol_version", 0)) == 1, "Fixture protocol_version mismatch")

	var validators: Array = [
		["client_world_frame_operation", FrameScript],
		["client_world_frame_projection", FrameScript],
		["gateway_ingress_envelope", IngressScript],
		["gateway_egress_envelope_projection", EgressScript],
		["gateway_session_binding", SessionBindingScript],
		["gateway_route_binding", RouteBindingScript],
		["projection_subscription", ProjectionSubscriptionScript],
		["gateway_descriptor", GatewayDescriptorScript],
	]
	for entry in validators:
		var key: String = String(entry[0])
		var value = fixture.get(key)
		_assert(value is Dictionary, "%s fixture is not an Object" % key)
		if value is Dictionary:
			var check: Dictionary = entry[1].validate(Dictionary(value))
			_assert(bool(check.get("success", false)), "%s fixture validation failed: %s" % [key, check])
			var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
			_assert(bool(round_trip.get("success", false)), "%s fixture is not JSON-roundtrip safe" % key)
			if bool(round_trip.get("success", false)):
				_assert(
					NetworkUtilsScript.canonical_json(round_trip.get("value")) == NetworkUtilsScript.canonical_json(value),
					"%s changed across canonical JSON round-trip" % key,
				)

	var frame: Dictionary = Dictionary(fixture["client_world_frame_operation"])
	var ingress: Dictionary = Dictionary(fixture["gateway_ingress_envelope"])
	_assert(
		String(frame["payload"]["operation_id"]) == String(ingress["frame"]["payload"]["operation_id"]),
		"OperationId changed between client frame and ingress fixture",
	)
	var route: Dictionary = Dictionary(fixture["gateway_route_binding"])
	_assert(
		int(route["route_revision"]) != int(route["observed_authority_epoch"]),
		"Golden fixture accidentally aliases route revision and authority epoch",
	)
	var subscription: Dictionary = Dictionary(fixture["projection_subscription"])
	_assert(bool(subscription["read_only"]), "Golden projection subscription is not read-only")
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EG0 Edge Gateway fixtures: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("EG0 Edge Gateway fixtures: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

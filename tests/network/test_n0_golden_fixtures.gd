extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Command = preload("res://scripts/network/contracts/network_command_envelope.gd")
const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const Delta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const Lease = preload("res://scripts/network/contracts/authority_lease.gd")
const Route = preload("res://scripts/network/contracts/authority_route.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")
const Space = preload("res://scripts/network/contracts/simulation_space_descriptor.gd")
const Ghost = preload("res://scripts/network/contracts/ghost_replica_state.gd")
const ClientRoute = preload("res://scripts/network/contracts/client_route.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Result = preload("res://scripts/network/contracts/handoff_result.gd")
const NodeDescriptor = preload("res://scripts/network/contracts/simulation_node_descriptor.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Gateway = preload("res://scripts/network/loopback/network_command_gateway.gd")
const Transport = preload("res://scripts/network/loopback/loopback_command_transport.gd")

const FIXTURE_IDS: Array[String] = [
	"valid_command", "stale_authority_command", "unsupported_protocol_command",
	"valid_entity_snapshot", "valid_entity_delta", "valid_authority_lease",
	"valid_handoff_ticket", "aborted_handoff_result", "committed_handoff_result",
	"valid_network_endpoint", "valid_simulation_space", "valid_authority_route",
	"valid_simulation_node", "valid_authority_region", "valid_ghost_replica",
	"valid_client_route",
]

var failures: Array[String] = []
var assertions: int = 0
var handler_calls: int = 0


func _init() -> void:
	var directory := DirAccess.open("res://config/network/fixtures")
	_assert(directory != null, "Golden fixture directory missing")
	var discovered: Array[String] = []
	if directory != null:
		directory.list_dir_begin()
		var name: String = directory.get_next()
		while not name.is_empty():
			if not directory.current_is_dir() and name.ends_with(".json"):
				discovered.append(name.trim_suffix(".json"))
			name = directory.get_next()
		directory.list_dir_end()
	discovered.sort()
	var expected_discovered: Array[String] = FIXTURE_IDS.duplicate()
	expected_discovered.sort()
	_assert(discovered == expected_discovered, "Fixture manifest mismatch: %s" % [discovered])

	for fixture_id in FIXTURE_IDS:
		var fixture: Dictionary = _read_fixture(fixture_id)
		_assert(not fixture.is_empty(), "Fixture could not be read: %s" % fixture_id)
		if fixture.is_empty():
			continue
		_assert(String(fixture.get("schema", "")) == "planet_simulator.network_golden_fixture.v1", "Fixture schema mismatch: %s" % fixture_id)
		_assert(String(fixture.get("fixture_id", "")) == fixture_id, "Fixture ID mismatch: %s" % fixture_id)
		_assert(typeof(fixture.get("value")) == TYPE_DICTIONARY, "Fixture value is not Dictionary: %s" % fixture_id)
		var evaluation: Dictionary = _evaluate_fixture(fixture)
		_assert(bool(evaluation.get("valid", false)) == bool(fixture.get("expected_valid", false)), "Fixture validity mismatch: %s result=%s" % [fixture_id, evaluation])
		_assert(String(evaluation.get("error_code", "")) == String(fixture.get("expected_error_code", "")), "Fixture error mismatch: %s result=%s" % [fixture_id, evaluation])
		if bool(fixture.get("expected_valid", false)):
			var expected_hash: String = String(fixture.get("expected_hash", ""))
			_assert(not expected_hash.is_empty(), "Valid fixture lacks expected hash: %s" % fixture_id)
			_assert(String(evaluation.get("hash", "")) == expected_hash, "Golden hash changed: %s expected=%s actual=%s" % [fixture_id, expected_hash, evaluation.get("hash", "")])
			var canonical_value = evaluation.get("canonical", {})
			_assert(typeof(canonical_value) == TYPE_DICTIONARY and not canonical_value.is_empty(), "Valid fixture lacks canonical value: %s" % fixture_id)
			var round_trip: Dictionary = Utils.json_round_trip(canonical_value)
			_assert(bool(round_trip.get("success", false)), "Fixture JSON round-trip failed: %s" % fixture_id)

	_assert(handler_calls == 0, "Stale fixture unexpectedly invoked gateway handler")
	_finish()


func _evaluate_fixture(fixture: Dictionary) -> Dictionary:
	var contract: String = String(fixture.get("contract", ""))
	var value: Dictionary = fixture.get("value", {})
	match contract:
		"network_command":
			var validation: Dictionary = Command.validate(value)
			return _standard(validation, Command.normalize(value), Command.command_fingerprint(value))
		"entity_snapshot":
			var validation: Dictionary = Snapshot.validate(value)
			return _standard(validation, Snapshot.normalize(value), Snapshot.snapshot_hash(value))
		"entity_delta":
			var validation: Dictionary = Delta.validate(value)
			return _standard(validation, Delta.normalize(value), String(value.get("checksum", "")))
		"authority_lease":
			var validation: Dictionary = Lease.validate(value)
			return _standard(validation, Lease.normalize(value), Utils.payload_hash(Lease.normalize(value)))
		"network_endpoint":
			var validation: Dictionary = Endpoint.validate(value)
			return _standard(validation, Endpoint.normalize(value), Utils.payload_hash(Endpoint.normalize(value)))
		"simulation_space":
			var validation: Dictionary = Space.validate(value)
			return _standard(validation, Space.normalize(value), Utils.payload_hash(Space.normalize(value)))
		"authority_route":
			var validation: Dictionary = Route.validate(value)
			return _standard(validation, Route.normalize(value), Utils.payload_hash(Route.normalize(value)))
		"handoff_ticket":
			var validation: Dictionary = Ticket.validate(value)
			return _standard(validation, Ticket.normalize(value), Ticket.ticket_hash(value))
		"handoff_result":
			var validation: Dictionary = Result.validate(value)
			return _standard(validation, Result.normalize(value), Utils.payload_hash(Result.normalize(value)))
		"simulation_node":
			var validation: Dictionary = NodeDescriptor.validate(value)
			return _standard(validation, NodeDescriptor.normalize(value), NodeDescriptor.descriptor_hash(value))
		"authority_region":
			var validation: Dictionary = Region.validate(value)
			return _standard(validation, Region.normalize(value), Utils.payload_hash(Region.normalize(value)))
		"ghost_replica":
			var validation: Dictionary = Ghost.validate(value)
			return _standard(validation, Ghost.normalize(value), Utils.payload_hash(Ghost.normalize(value)))
		"client_route":
			var validation: Dictionary = ClientRoute.validate(value)
			return _standard(validation, ClientRoute.normalize(value), Utils.payload_hash(ClientRoute.normalize(value)))
		"gateway_command":
			var gateway = Gateway.new()
			gateway.setup(int(fixture.get("context", {}).get("actual_authority_epoch", 1)))
			gateway.register_handler("item.move", Callable(self, "_handler"))
			var transport = Transport.new()
			transport.setup(gateway)
			var transport_result: Dictionary = transport.send(value)
			var result: Dictionary = transport_result.get("result", {})
			return {
				"valid": bool(transport_result.get("success", false)),
				"error_code": String(result.get("error_code", transport_result.get("error_code", ""))),
				"hash": Command.command_fingerprint(value),
				"canonical": Command.normalize(value),
			}
	return {"valid": false, "error_code": "UNKNOWN_FIXTURE_CONTRACT", "hash": "", "canonical": {}}


func _standard(validation: Dictionary, canonical: Dictionary, hash_value: String) -> Dictionary:
	return {
		"valid": bool(validation.get("success", false)),
		"error_code": "" if bool(validation.get("success", false)) else String(validation.get("error_code", "")),
		"hash": hash_value,
		"canonical": canonical,
	}


func _handler(_envelope: Dictionary) -> Dictionary:
	handler_calls += 1
	return {"success": true, "retryable": false, "error_code": "", "result_revision": 1, "payload": {}}


func _read_fixture(fixture_id: String) -> Dictionary:
	var path: String = "res://config/network/fixtures/%s.json" % fixture_id
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 golden fixtures: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 golden fixtures: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

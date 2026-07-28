extends SceneTree

const Command = preload("res://scripts/network/contracts/network_command_envelope.gd")
const Result = preload("res://scripts/network/contracts/network_command_result_envelope.gd")
const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const Delta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const Lease = preload("res://scripts/network/contracts/authority_lease.gd")
const Route = preload("res://scripts/network/contracts/authority_route.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")
const Space = preload("res://scripts/network/contracts/simulation_space_descriptor.gd")
const NodeDescriptor = preload("res://scripts/network/contracts/simulation_node_descriptor.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const Ghost = preload("res://scripts/network/contracts/ghost_replica_state.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const HandoffResult = preload("res://scripts/network/contracts/handoff_result.gd")
const ClientRoute = preload("res://scripts/network/contracts/client_route.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var endpoint: Dictionary = Endpoint.create("ENET", "127.0.0.1", 19001, "simulation")
	var secondary: Dictionary = Endpoint.create("ENET", "127.0.0.1", 19002, "simulation")
	var spatial: Dictionary = SpatialRef.create("body/moon/fixed", Vector3(1, 2, 3))
	var command: Dictionary = Command.create("message/1", "operation/1", "entity/1", "item.move", {"quantity": 1}, 1, 2, 3, 4)
	var result: Dictionary = Result.create("message/1", "operation/1", "SUCCEEDED", "", 2, 2, {"moved": true})
	var snapshot: Dictionary = Snapshot.create("snapshot/1", "entity/1", "world_item", 2, "sim-a", 2, 3, spatial, {}, {}, {})
	var delta: Dictionary = Delta.create("delta/1", "entity/1", "world_item", 2, 3, "sim-a", 2, 4, {"physics_state": {}}, [])
	var lease: Dictionary = Lease.create("lease/1", "ENTITY", "entity/1", "sim-a", 2, 10, 20, 30, 2, "token".sha256_text())
	var route: Dictionary = Route.create("route/1", "ENTITY", "entity/1", "sim-a", 2, "lease/1", "region/a", endpoint, 1, 10, 30)
	var space: Dictionary = Space.create("moon", "persistent", "main", "body/moon/fixed", "cube_sphere", 1, ["region/a"], 1)
	var node: Dictionary = NodeDescriptor.create("sim-a", "simulation-server", "build", "checkpoint", "persistent", [space], endpoint, ["command"], "READY", 10, 20, 1)
	var region: Dictionary = Region.create("region/a", "main", "persistent", "moon", "cube_sphere", 1, {"kind": "GLOBAL_SPACE", "partition_prefix": "", "chunk_ids": []}, "sim-a", 2, "ACTIVE", 1)
	var ghost: Dictionary = Ghost.create("replica/1", "entity/1", "sim-a", 2, 2, "snapshot".sha256_text(), "interest/a", 10, 20)
	var ticket: Dictionary = Ticket.create("handoff/1", "entity/1", "sim-a", "sim-b", 2, 3, 2, "region/b", 10, 30)
	var handoff_result: Dictionary = HandoffResult.create("handoff/1", "entity/1", "COMMITTED", "", "sim-a", "sim-b", "sim-b", 3, 3, 25, {})
	var client_route: Dictionary = ClientRoute.create("client-route/1", "client/1", "entity/1", "sim-a", "sim-b", 2, 10, 30, "overlap", 1, endpoint, secondary)

	_exercise("endpoint", endpoint, Endpoint.FIELDS, Callable(Endpoint, "validate"))
	_exercise("command", command, Command.FIELDS, Callable(Command, "validate"))
	_exercise("result", result, Result.FIELDS, Callable(Result, "validate"))
	_exercise("snapshot", snapshot, Snapshot.FIELDS, Callable(Snapshot, "validate"))
	_exercise("delta", delta, Delta.FIELDS, Callable(Delta, "validate"))
	_exercise("lease", lease, Lease.FIELDS, Callable(Lease, "validate"))
	_exercise("route", route, Route.FIELDS, Callable(Route, "validate"))
	_exercise("space", space, Space.FIELDS, Callable(Space, "validate"))
	_exercise("node", node, NodeDescriptor.FIELDS, Callable(NodeDescriptor, "validate"))
	_exercise("region", region, Region.FIELDS, Callable(Region, "validate"))
	_exercise("ghost", ghost, Ghost.FIELDS, Callable(Ghost, "validate"))
	_exercise("ticket", ticket, Ticket.FIELDS, Callable(Ticket, "validate"))
	_exercise("handoff_result", handoff_result, HandoffResult.FIELDS, Callable(HandoffResult, "validate"))
	_exercise("client_route", client_route, ClientRoute.FIELDS, Callable(ClientRoute, "validate"))

	_finish()


func _exercise(name: String, value: Dictionary, fields: Array[String], validator: Callable) -> void:
	_assert(bool(validator.call(value).get("success", false)), "%s baseline invalid" % name)
	for field in fields:
		var missing: Dictionary = value.duplicate(true)
		missing.erase(field)
		_assert(not bool(validator.call(missing).get("success", false)), "%s accepted missing field %s" % [name, field])
		var wrong_type: Dictionary = value.duplicate(true)
		wrong_type[field] = _wrong_type_for(value[field])
		_assert(not bool(validator.call(wrong_type).get("success", false)), "%s accepted wrong type for %s" % [name, field])
	var extra: Dictionary = value.duplicate(true)
	extra["unexpected_contract_field"] = true
	_assert(not bool(validator.call(extra).get("success", false)), "%s accepted extra field" % name)


func _wrong_type_for(value):
	match typeof(value):
		TYPE_STRING:
			return 42
		TYPE_INT, TYPE_FLOAT:
			return "42"
		TYPE_BOOL:
			return "true"
		TYPE_ARRAY:
			return {}
		TYPE_DICTIONARY:
			return []
	return Node.new()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("N0 contract mutation matrix: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("N0 contract mutation matrix: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

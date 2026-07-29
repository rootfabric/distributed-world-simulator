extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Command = preload("res://scripts/network/contracts/network_command_envelope.gd")
const Snapshot = preload("res://scripts/network/contracts/entity_snapshot_envelope.gd")
const Delta = preload("res://scripts/network/contracts/entity_delta_envelope.gd")
const Lease = preload("res://scripts/network/contracts/authority_lease.gd")
const Route = preload("res://scripts/network/contracts/authority_route.gd")
const Ghost = preload("res://scripts/network/contracts/ghost_replica_state.gd")
const ClientRoute = preload("res://scripts/network/contracts/client_route.gd")
const Ticket = preload("res://scripts/network/contracts/handoff_ticket.gd")
const Result = preload("res://scripts/network/contracts/handoff_result.gd")
const Endpoint = preload("res://scripts/network/contracts/network_endpoint.gd")
const Space = preload("res://scripts/network/contracts/simulation_space_descriptor.gd")
const NodeDescriptor = preload("res://scripts/network/contracts/simulation_node_descriptor.gd")
const Region = preload("res://scripts/network/contracts/authority_region_descriptor.gd")
const SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")


func _init() -> void:
	var command: Dictionary = Command.create(
		"message/golden/1", "operation/golden/1", "entity/item/golden",
		"item.move", {"target_container_id": "container/golden", "quantity": 2},
		7, 4, 100, 12345
	)
	_write("valid_command", "network_command", true, "", Command.command_fingerprint(command), command, {})
	var stale_command: Dictionary = command.duplicate(true)
	stale_command["message_id"] = "message/golden/stale"
	stale_command["operation_id"] = "operation/golden/stale"
	stale_command["authority_epoch"] = 3
	_write("stale_authority_command", "gateway_command", true, "STALE_AUTHORITY_EPOCH", Command.command_fingerprint(stale_command), stale_command, {"actual_authority_epoch": 4})
	var unsupported: Dictionary = command.duplicate(true)
	unsupported["message_id"] = "message/golden/unsupported"
	unsupported["operation_id"] = "operation/golden/unsupported"
	unsupported["protocol_version"] = 99
	_write("unsupported_protocol_command", "network_command", false, "UNSUPPORTED_PROTOCOL", "", unsupported, {})

	var spatial: Dictionary = SpatialRef.create(
		"body/moon/fixed", Vector3(10.0, 20.0, 30.0), Basis.IDENTITY,
		Vector3(1.0, 2.0, 3.0), Vector3(0.1, 0.2, 0.3), 42.0,
		"main", "sol", "persistent"
	)
	var snapshot: Dictionary = Snapshot.create(
		"snapshot/golden/1", "entity/item/golden", "world_item", 8, "sim-a", 4, 101,
		spatial, {}, {"mass_kg": 5.0}, {"item": {"definition_id": "survey_beacon"}}
	)
	_write("valid_entity_snapshot", "entity_snapshot", true, "", Snapshot.snapshot_hash(snapshot), snapshot, {})

	var delta: Dictionary = Delta.create(
		"delta/golden/1", "entity/item/golden", "world_item", 8, 9,
		"sim-a", 4, 102, {"physics_state.sleeping": false}, ["domain_components.legacy"]
	)
	_write("valid_entity_delta", "entity_delta", true, "", String(delta["checksum"]), delta, {})

	var lease: Dictionary = Lease.create(
		"lease/golden/1", "ENTITY", "entity/item/golden", "sim-a", 4,
		100, 140, 200, 8, "golden-lease-token".sha256_text()
	)
	_write("valid_authority_lease", "authority_lease", true, "", Utils.payload_hash(Lease.normalize(lease)), lease, {})

	var ticket: Dictionary = Ticket.create(
		"handoff/golden/1", "entity/item/golden", "sim-a", "sim-b",
		4, 5, 8, "region/moon/b", 100, 200
	)
	_write("valid_handoff_ticket", "handoff_ticket", true, "", Ticket.ticket_hash(ticket), ticket, {})
	var aborted: Dictionary = Result.create(
		"handoff/golden/1", "entity/item/golden", "ABORTED", "target_unavailable",
		"sim-a", "sim-b", "sim-a", 4, 8, 120, {"transition_revision": 2}
	)
	_write("aborted_handoff_result", "handoff_result", true, "", Utils.payload_hash(Result.normalize(aborted)), aborted, {})
	var committed: Dictionary = Result.create(
		"handoff/golden/1", "entity/item/golden", "COMMITTED", "",
		"sim-a", "sim-b", "sim-b", 5, 9, 130, {"transition_revision": 5}
	)
	_write("committed_handoff_result", "handoff_result", true, "", Utils.payload_hash(Result.normalize(committed)), committed, {})

	var endpoint: Dictionary = Endpoint.create("ENET", "127.0.0.1", 19001, "simulation")
	_write("valid_network_endpoint", "network_endpoint", true, "", Utils.payload_hash(Endpoint.normalize(endpoint)), endpoint, {})
	var space: Dictionary = Space.create(
		"moon", "persistent", "main", "body/moon/fixed", "cube_sphere", 1,
		["region/moon/a"], 1
	)
	_write("valid_simulation_space", "simulation_space", true, "", Utils.payload_hash(Space.normalize(space)), space, {})
	var route: Dictionary = Route.create(
		"route/golden/1", "ENTITY", "entity/item/golden", "sim-a", 4,
		"lease/golden/1", "region/moon/a", endpoint, 1, 100, 200
	)
	_write("valid_authority_route", "authority_route", true, "", Utils.payload_hash(Route.normalize(route)), route, {})
	var node: Dictionary = NodeDescriptor.create(
		"sim-a", "simulation-server",
		"s1-distributed-compute-contracts-fix1",
		"v16.9.0-simulation-s1-distributed-compute-fix1",
		"persistent", [space], endpoint, ["command", "delta", "snapshot"],
		"READY", 100, 110, 1
	)
	_write("valid_simulation_node", "simulation_node", true, "", NodeDescriptor.descriptor_hash(node), node, {})
	var region: Dictionary = Region.create(
		"region/moon/a", "main", "persistent", "moon", "cube_sphere", 1,
		{"kind": "PARTITION_PREFIX", "partition_prefix": "universe/main/instance/persistent/space/moon", "chunk_ids": []},
		"sim-a", 4, "ACTIVE", 1
	)
	_write("valid_authority_region", "authority_region", true, "", Utils.payload_hash(Region.normalize(region)), region, {})
	var ghost: Dictionary = Ghost.create(
		"replica/golden/1", "entity/item/golden", "sim-a", 4, 8,
		Snapshot.snapshot_hash(snapshot), "interest/golden", 101, 200
	)
	_write("valid_ghost_replica", "ghost_replica", true, "", Utils.payload_hash(Ghost.normalize(ghost)), ghost, {})
	var secondary_endpoint: Dictionary = Endpoint.create("ENET", "127.0.0.1", 19002, "simulation")
	var client_route: Dictionary = ClientRoute.create(
		"client-route/golden/1", "client/golden", "entity/item/golden",
		"sim-a", "sim-b", 4, 100, 200, "handoff_overlap", 1,
		endpoint, secondary_endpoint
	)
	_write("valid_client_route", "client_route", true, "", Utils.payload_hash(ClientRoute.normalize(client_route)), client_route, {})
	print("N0 golden fixtures generated")
	quit(0)


func _write(
	fixture_id: String,
	contract: String,
	expected_valid: bool,
	expected_error_code: String,
	expected_hash: String,
	value: Dictionary,
	context: Dictionary
) -> void:
	var document: Dictionary = {
		"schema": "planet_simulator.network_golden_fixture.v1",
		"fixture_id": fixture_id,
		"contract": contract,
		"expected_valid": expected_valid,
		"expected_error_code": expected_error_code,
		"expected_hash": expected_hash,
		"value": value,
		"context": context,
	}
	var path: String = "res://config/network/fixtures/%s.json" % fixture_id
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write fixture: %s" % path)
		return
	file.store_string(JSON.stringify(document, "  ", true, true) + "\n")
	file.close()

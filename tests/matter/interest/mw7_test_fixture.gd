extends RefCounted

const MW5FixtureScript = preload("res://tests/matter/persistence/mw5_test_fixture.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const SweptShapeScript = preload("res://scripts/simulation/matter/mutation/matter_swept_shape.gd")
const RegionScript = preload("res://scripts/simulation/matter/interest/matter_interest_region.gd")
const GatewayScript = preload("res://scripts/network/loopback/network_command_gateway.gd")
const CommandTransportScript = preload("res://scripts/network/loopback/loopback_command_transport.gd")
const ReplicationAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_replication_transport_adapter.gd")
const AuthorityScript = preload("res://scripts/simulation/matter/network/matter_authoritative_server.gd")
const InterestServerScript = preload("res://scripts/simulation/matter/interest/matter_interest_server.gd")
const InterestReplicaScript = preload("res://scripts/simulation/matter/interest/matter_interest_replica_client.gd")
const SubscriptionScript = preload("res://scripts/simulation/matter/interest/matter_interest_subscription.gd")

const AUTHORITY_OWNER_ID: String = "authority/mw7-matter-server"
const AUTHORITY_EPOCH: int = 1
const ENERGY_BUDGET_J: float = 9000000000000000.0
const CELL_LEVEL: int = 5


static func create_authority(root_path: String, max_replay_deltas: int = 64) -> Dictionary:
	var context: Dictionary = MW5FixtureScript.create_context(root_path)
	if not bool(context.get("success", false)):
		return context
	var authority = AuthorityScript.new()
	var authority_setup: Dictionary = authority.configure(
		context["body"],
		context["grid_profile"],
		context["service"],
		AUTHORITY_OWNER_ID,
		AUTHORITY_EPOCH,
		max_replay_deltas
	)
	if not bool(authority_setup.get("success", false)):
		return authority_setup
	var gateway = GatewayScript.new()
	gateway.setup(AUTHORITY_EPOCH)
	var registered: Dictionary = authority.register_gateway(gateway)
	if not bool(registered.get("success", false)):
		return registered
	var command_transport = CommandTransportScript.new()
	command_transport.setup(gateway)
	var interest_server = InterestServerScript.new()
	var interest_setup: Dictionary = interest_server.configure(
		context["body"],
		context["grid_profile"],
		context["service"],
		authority,
		AUTHORITY_OWNER_ID,
		AUTHORITY_EPOCH,
		max_replay_deltas
	)
	if not bool(interest_setup.get("success", false)):
		return interest_setup
	return {
		"success": true,
		"context": context,
		"authority": authority,
		"interest_server": interest_server,
		"gateway": gateway,
		"command_transport": command_transport,
		"replication_adapter": ReplicationAdapterScript.new(
			"adapter/mw7-interest", 512
		),
	}


static func create_replica(setup: Dictionary, client_id: String, presenter = null):
	var replica = InterestReplicaScript.new()
	var configured: Dictionary = replica.configure(
		setup["context"]["body"],
		setup["context"]["grid_profile"],
		AUTHORITY_OWNER_ID,
		AUTHORITY_EPOCH,
		client_id,
		presenter
	)
	return replica if bool(configured.get("success", false)) else null


static func connect_replica(
	setup: Dictionary,
	replica,
	peer_id: String,
	session_id: String,
	actor_id: String
) -> Dictionary:
	var activated: Dictionary = replica.activate_session(peer_id, session_id)
	if not bool(activated.get("success", false)):
		return activated
	var authority_connected: Dictionary = setup["authority"].connect_interest_peer(
		peer_id,
		String(replica.subscription()["client_id"]),
		session_id,
		actor_id
	)
	if not bool(authority_connected.get("success", false)):
		return authority_connected
	return setup["interest_server"].connect_peer(peer_id, replica.create_sync_request())


static func reconnect_replica(
	setup: Dictionary,
	replica,
	old_peer_id: String,
	new_peer_id: String,
	new_session_id: String,
	actor_id: String
) -> Dictionary:
	setup["interest_server"].disconnect_peer(old_peer_id)
	setup["authority"].disconnect_peer(old_peer_id)
	var activated: Dictionary = replica.activate_session(new_peer_id, new_session_id)
	if not bool(activated.get("success", false)):
		return activated
	var authority_connected: Dictionary = setup["authority"].connect_interest_peer(
		new_peer_id,
		String(replica.subscription()["client_id"]),
		new_session_id,
		actor_id
	)
	if not bool(authority_connected.get("success", false)):
		return authority_connected
	return setup["interest_server"].connect_peer(new_peer_id, replica.create_sync_request())


static func request(
	setup: Dictionary,
	fixture_value: Dictionary,
	operation_id: String,
	actor_id: String
) -> Dictionary:
	return setup["context"]["service"].create_excavation_request(
		operation_id,
		actor_id,
		"tool/mw7-network-drill",
		fixture_value["start_m"],
		fixture_value["end_m"],
		float(fixture_value["radius_m"]),
		ENERGY_BUDGET_J,
		701
	)


static func surface_fixtures(
	setup: Dictionary,
	axis: Vector3,
	maximum_count: int = 8
) -> Array[Dictionary]:
	var context: Dictionary = setup["context"]
	var normalized_axis: Vector3 = axis.normalized()
	var tangent_a: Vector3 = normalized_axis.cross(Vector3.UP)
	if tangent_a.length_squared() < 0.01:
		tangent_a = normalized_axis.cross(Vector3.RIGHT)
	tangent_a = tangent_a.normalized()
	var tangent_b: Vector3 = normalized_axis.cross(tangent_a).normalized()
	var by_address_id: Dictionary = {}
	for a_step in range(-10, 11):
		for b_step in range(-10, 11):
			var direction: Vector3 = (
				normalized_axis
				+ tangent_a * float(a_step) * 0.025
				+ tangent_b * float(b_step) * 0.025
			).normalized()
			var radius_m: float = GeneratorScript.surface_radius_validated(
				context["generator_profile"], context["feature_catalog"], direction
			)
			var surface_m: Vector3 = direction * radius_m
			var start_m: Vector3 = surface_m + direction * 6.0
			var end_m: Vector3 = surface_m - direction * 11.0
			var shape: Dictionary = RequestScript.create_shape(
				"CAPSULE", _array(start_m), _array(end_m), 4.0
			)
			var targets: Array = SweptShapeScript.affected_brick_addresses(
				context["grid_profile"], shape, CELL_LEVEL
			)
			if targets.size() != 1:
				continue
			var address: Dictionary = targets[0]
			var address_id: String = String(address["address_id"])
			if by_address_id.has(address_id):
				continue
			by_address_id[address_id] = {
				"start_m": start_m,
				"end_m": end_m,
				"center_m": (start_m + end_m) * 0.5,
				"radius_m": 4.0,
				"address": address,
			}
			if by_address_id.size() >= maximum_count:
				break
		if by_address_id.size() >= maximum_count:
			break
	var result: Array[Dictionary] = []
	var address_ids: Array = by_address_id.keys()
	address_ids.sort()
	for address_id in address_ids:
		result.append(by_address_id[address_id])
	return result


static func nearby_fixtures(
	setup: Dictionary,
	axis: Vector3,
	radius_cells: int,
	maximum_count: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = surface_fixtures(setup, axis, 32)
	if candidates.is_empty():
		return []
	var best: Array[Dictionary] = []
	var best_center: Dictionary = {}
	for center_fixture in candidates:
		var subscription: Dictionary = SubscriptionScript.create(
			"subscription/mw7/fixture-probe",
			"client/mw7/fixture-probe",
			AUTHORITY_EPOCH,
			1,
			CELL_LEVEL,
			center_fixture["address"]["cell_address"],
			radius_cells
		)
		var group: Array[Dictionary] = []
		for fixture_value in candidates:
			if RegionScript.contains_cell_address(
				setup["context"]["grid_profile"],
				subscription,
				fixture_value["address"]["cell_address"]
			):
				group.append(fixture_value)
		if group.size() > best.size():
			best = group
			best_center = center_fixture
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["address"]["address_id"]) < String(b["address"]["address_id"])
	)
	var ordered: Array[Dictionary] = []
	var best_center_address_id: String = ""
	if not best_center.is_empty():
		best_center_address_id = String(best_center["address"]["address_id"])
		ordered.append(best_center)
	for fixture_value in best:
		if String(fixture_value["address"]["address_id"]) == best_center_address_id:
			continue
		ordered.append(fixture_value)
	if ordered.size() > maximum_count:
		ordered.resize(maximum_count)
	return ordered


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

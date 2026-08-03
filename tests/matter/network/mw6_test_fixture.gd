extends RefCounted

const MW5FixtureScript = preload("res://tests/matter/persistence/mw5_test_fixture.gd")
const GatewayScript = preload("res://scripts/network/loopback/network_command_gateway.gd")
const CommandTransportScript = preload("res://scripts/network/loopback/loopback_command_transport.gd")
const ReplicationAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_replication_transport_adapter.gd")
const AuthorityScript = preload("res://scripts/simulation/matter/network/matter_authoritative_server.gd")
const ReplicaScript = preload("res://scripts/simulation/matter/network/matter_replica_client.gd")

const AUTHORITY_OWNER_ID: String = "authority/mw6-matter-server"
const AUTHORITY_EPOCH: int = 1
const ENERGY_BUDGET_J: float = 9000000000000000.0


static func create_authority(
	root_path: String,
	max_replay_deltas: int = 64,
	preseed_durable_state: bool = false
) -> Dictionary:
	var context: Dictionary = MW5FixtureScript.create_context(root_path)
	if not bool(context.get("success", false)):
		return context
	var preseed_result: Dictionary = {}
	if preseed_durable_state:
		var fixture_value: Dictionary = MW5FixtureScript.single_cell_fixture(
			context["generator_profile"],
			context["feature_catalog"],
			context["grid_profile"]
		)
		if fixture_value.is_empty():
			return {"success": false, "error_code": "MW6_PRESEED_FIXTURE_MISSING"}
		var preseed_request: Dictionary = context["service"].create_excavation_request(
			"operation/mw6/durable-preseed",
			"actor/mw6/durable-preseed",
			"tool/mw6-network-drill",
			fixture_value["start_m"],
			fixture_value["end_m"],
			float(fixture_value["radius_m"]),
			ENERGY_BUDGET_J,
			600
		)
		preseed_result = context["service"].execute(preseed_request)
		if String(preseed_result.get("status", "")) != "COMMITTED":
			return {"success": false, "error_code": "MW6_PRESEED_MUTATION_FAILED"}
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
	var gateway_setup: Dictionary = authority.register_gateway(gateway)
	if not bool(gateway_setup.get("success", false)):
		return gateway_setup
	var command_transport = CommandTransportScript.new()
	command_transport.setup(gateway)
	return {
		"success": true,
		"context": context,
		"authority": authority,
		"gateway": gateway,
		"command_transport": command_transport,
		"replication_adapter": ReplicationAdapterScript.new(
			"adapter/mw6-replication", 256
		),
		"preseed_result": preseed_result,
	}


static func create_replica(authority_context: Dictionary, client_id: String, presenter = null):
	var replica = ReplicaScript.new()
	var setup: Dictionary = replica.configure(
		authority_context["context"]["body"],
		authority_context["context"]["grid_profile"],
		AUTHORITY_OWNER_ID,
		AUTHORITY_EPOCH,
		client_id,
		presenter
	)
	return replica if bool(setup.get("success", false)) else null


static func connect_replica(
	authority_context: Dictionary,
	replica,
	peer_id: String,
	session_id: String,
	actor_id: String
) -> Dictionary:
	var activated: Dictionary = replica.activate_session(peer_id, session_id)
	if not bool(activated.get("success", false)):
		return activated
	var sync_request: Dictionary = replica.create_sync_request()
	return authority_context["authority"].connect_peer(
		peer_id,
		String(sync_request.get("client_id", "")),
		session_id,
		actor_id,
		sync_request
	)


static func fixture(authority_context: Dictionary) -> Dictionary:
	return MW5FixtureScript.single_cell_fixture(
		authority_context["context"]["generator_profile"],
		authority_context["context"]["feature_catalog"],
		authority_context["context"]["grid_profile"]
	)


static func request(
	authority_context: Dictionary,
	fixture_value: Dictionary,
	operation_id: String,
	actor_id: String,
	energy_budget_j: float = ENERGY_BUDGET_J
) -> Dictionary:
	return authority_context["context"]["service"].create_excavation_request(
		operation_id,
		actor_id,
		"tool/mw6-network-drill",
		fixture_value["start_m"],
		fixture_value["end_m"],
		float(fixture_value["radius_m"]),
		energy_budget_j,
		601
	)

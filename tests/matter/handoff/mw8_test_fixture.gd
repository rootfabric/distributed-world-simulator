extends RefCounted

const MW5FixtureScript = preload("res://tests/matter/persistence/mw5_test_fixture.gd")
const MW7FixtureScript = preload("res://tests/matter/interest/mw7_test_fixture.gd")
const AuthorityScript = preload("res://scripts/simulation/matter/network/matter_authoritative_server.gd")
const InterestServerScript = preload("res://scripts/simulation/matter/interest/matter_interest_server.gd")
const InterestReplicaScript = preload("res://scripts/simulation/matter/interest/matter_interest_replica_client.gd")
const GatewayScript = preload("res://scripts/network/loopback/network_command_gateway.gd")
const CommandTransportScript = preload("res://scripts/network/loopback/loopback_command_transport.gd")
const ReplicationAdapterScript = preload("res://scripts/network/bus/adapters/in_memory_replication_transport_adapter.gd")
const DirectoryScript = preload("res://scripts/simulation/matter/handoff/matter_authority_directory.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")
const GateScript = preload("res://scripts/simulation/matter/handoff/matter_regional_authority_gate.gd")
const EndpointScript = preload("res://scripts/simulation/matter/handoff/matter_handoff_endpoint.gd")
const CoordinatorScript = preload("res://scripts/simulation/matter/handoff/matter_handoff_coordinator.gd")

const SOURCE_OWNER_ID: String = "authority/mw8-source"
const TARGET_OWNER_ID: String = "authority/mw8-target"
const SOURCE_EPOCH: int = 1
const TARGET_EPOCH: int = 2
const CELL_LEVEL: int = 5
const REGION_ID: String = "region/mw8-positive"


static func create_cluster(root_path: String, replay_limit: int = 64) -> Dictionary:
	var source_context: Dictionary = MW5FixtureScript.create_context(root_path.path_join("source"))
	var target_context: Dictionary = MW5FixtureScript.create_context(root_path.path_join("target"))
	if not bool(source_context.get("success", false)):
		return source_context
	if not bool(target_context.get("success", false)):
		return target_context
	if String(source_context["body"]["checksum"]) != String(target_context["body"]["checksum"]):
		return {"success": false, "error_code": "MW8_FIXTURE_BODY_MISMATCH"}
	var probe_setup: Dictionary = {"context": source_context}
	var fixtures: Array[Dictionary] = MW7FixtureScript.nearby_fixtures(
		probe_setup, Vector3.RIGHT, 1, 6
	)
	if fixtures.size() < 3:
		return {"success": false, "error_code": "MW8_FIXTURE_NEEDS_THREE_REGION_CELLS"}
	var region: Dictionary = RegionScript.create(
		REGION_ID,
		String(source_context["body"]["body_id"]),
		CELL_LEVEL,
		fixtures[0]["address"]["cell_address"],
		1
	)
	var directory = DirectoryScript.new()
	var directory_setup: Dictionary = directory.configure(
		String(source_context["body"]["body_id"]), source_context["grid_profile"]
	)
	if not bool(directory_setup.get("success", false)):
		return directory_setup
	var registered: Dictionary = directory.register_region(region, SOURCE_OWNER_ID, SOURCE_EPOCH)
	if not bool(registered.get("success", false)):
		return registered
	var source: Dictionary = _create_server(
		"endpoint/mw8-source", source_context, SOURCE_OWNER_ID, SOURCE_EPOCH,
		directory, replay_limit
	)
	if not bool(source.get("success", false)):
		return source
	var target: Dictionary = _create_server(
		"endpoint/mw8-target", target_context, TARGET_OWNER_ID, TARGET_EPOCH,
		directory, replay_limit
	)
	if not bool(target.get("success", false)):
		return target
	var coordinator = CoordinatorScript.new()
	var coordinator_setup: Dictionary = coordinator.configure(directory)
	if not bool(coordinator_setup.get("success", false)):
		return coordinator_setup
	return {
		"success": true,
		"source_context": source_context,
		"target_context": target_context,
		"fixtures": fixtures,
		"region": region,
		"directory": directory,
		"source": source,
		"target": target,
		"coordinator": coordinator,
	}


static func shutdown_cluster(cluster: Dictionary) -> Dictionary:
	var failures: Array = []
	for server_key in ["source", "target"]:
		if typeof(cluster.get(server_key)) != TYPE_DICTIONARY:
			continue
		var server: Dictionary = cluster[server_key]
		var interest_server = server.get("interest_server")
		if interest_server == null or not interest_server.has_method("shutdown"):
			continue
		var shutdown_result: Dictionary = interest_server.shutdown()
		if not bool(shutdown_result.get("success", false)):
			failures.append({"server_key": server_key, "cause": shutdown_result})
	if not failures.is_empty():
		return {"success": false, "error_code": "MW8_CLUSTER_SHUTDOWN_FAILED", "details": failures}
	return {"success": true, "error_code": "", "details": {}}


static func create_replica(
	cluster: Dictionary,
	server_key: String,
	client_id: String
):
	var server: Dictionary = cluster[server_key]
	var replica = InterestReplicaScript.new()
	var configured: Dictionary = replica.configure(
		cluster["source_context"]["body"],
		cluster["source_context"]["grid_profile"],
		server["owner_id"],
		server["authority_epoch"],
		client_id
	)
	return replica if bool(configured.get("success", false)) else null


static func connect_replica(
	cluster: Dictionary,
	server_key: String,
	replica,
	peer_id: String,
	session_id: String,
	actor_id: String
) -> Dictionary:
	var server: Dictionary = cluster[server_key]
	var activated: Dictionary = replica.activate_session(peer_id, session_id)
	if not bool(activated.get("success", false)):
		return activated
	var authority_connected: Dictionary = server["authority"].connect_interest_peer(
		peer_id,
		String(replica.subscription()["client_id"]),
		session_id,
		actor_id
	)
	if not bool(authority_connected.get("success", false)):
		return authority_connected
	return server["interest_server"].connect_peer(peer_id, replica.create_sync_request())


static func request(
	cluster: Dictionary,
	server_key: String,
	fixture_value: Dictionary,
	operation_id: String,
	actor_id: String
) -> Dictionary:
	return cluster[server_key]["context"]["service"].create_excavation_request(
		operation_id,
		actor_id,
		"tool/mw8-regional-drill",
		fixture_value["start_m"],
		fixture_value["end_m"],
		float(fixture_value["radius_m"]),
		MW5FixtureScript.JSON_SAFE_ENERGY_BUDGET_J,
		801
	)


static func send_mutation(
	cluster: Dictionary,
	server_key: String,
	replica,
	fixture_value: Dictionary,
	operation_id: String,
	actor_id: String,
	message_id: String
) -> Dictionary:
	var server: Dictionary = cluster[server_key]
	var request_value: Dictionary = request(
		cluster, server_key, fixture_value, operation_id, actor_id
	)
	if request_value.is_empty():
		return {"success": false, "error_code": "MW8_REQUEST_BUILD_FAILED"}
	var command: Dictionary = replica.create_mutation_command(request_value, message_id)
	if command.is_empty():
		return {"success": false, "error_code": "MW8_COMMAND_BUILD_FAILED"}
	var wire: Dictionary = server["command_transport"].send(command)
	if not bool(wire.get("success", false)):
		return {
			"success": false,
			"error_code": String(wire.get("result", {}).get("error_code", "MW8_COMMAND_TRANSPORT_FAILED")),
			"wire": wire,
			"request": request_value,
		}
	var accepted: Dictionary = replica.accept_command_result(Dictionary(wire.get("result", {})))
	accepted["request"] = request_value
	accepted["wire"] = wire
	return accepted


static func dispatch_and_poll(
	cluster: Dictionary,
	server_key: String,
	replica,
	peer_id: String
) -> Dictionary:
	var server: Dictionary = cluster[server_key]
	var dispatched: Dictionary = server["interest_server"].dispatch_peer(
		peer_id, server["replication_adapter"]
	)
	if not bool(dispatched.get("success", false)):
		return dispatched
	return replica.poll_replication(server["replication_adapter"])


static func _create_server(
	endpoint_id: String,
	context: Dictionary,
	owner_id: String,
	authority_epoch: int,
	directory,
	replay_limit: int
) -> Dictionary:
	var authority = AuthorityScript.new()
	var authority_setup: Dictionary = authority.configure(
		context["body"], context["grid_profile"], context["service"],
		owner_id, authority_epoch, replay_limit
	)
	if not bool(authority_setup.get("success", false)):
		return authority_setup
	var gate = GateScript.new()
	var gate_setup: Dictionary = gate.configure(owner_id, authority_epoch, directory)
	if not bool(gate_setup.get("success", false)):
		return gate_setup
	var gate_registered: Dictionary = authority.set_command_authority_gate(gate)
	if not bool(gate_registered.get("success", false)):
		return gate_registered
	var gateway = GatewayScript.new()
	gateway.setup(authority_epoch)
	var handler_registered: Dictionary = authority.register_gateway(gateway)
	if not bool(handler_registered.get("success", false)):
		return handler_registered
	var command_transport = CommandTransportScript.new()
	command_transport.setup(gateway)
	var interest_server = InterestServerScript.new()
	var interest_setup: Dictionary = interest_server.configure(
		context["body"], context["grid_profile"], context["service"], authority,
		owner_id, authority_epoch, replay_limit
	)
	if not bool(interest_setup.get("success", false)):
		return interest_setup
	var endpoint = EndpointScript.new()
	var endpoint_setup: Dictionary = endpoint.configure(
		endpoint_id,
		context["body"],
		context["grid_profile"],
		context["service"],
		owner_id,
		authority_epoch,
		directory,
		authority
	)
	if not bool(endpoint_setup.get("success", false)):
		return endpoint_setup
	return {
		"success": true,
		"context": context,
		"owner_id": owner_id,
		"authority_epoch": authority_epoch,
		"authority": authority,
		"gate": gate,
		"gateway": gateway,
		"command_transport": command_transport,
		"interest_server": interest_server,
		"endpoint": endpoint,
		"replication_adapter": ReplicationAdapterScript.new(
			"adapter/%s" % endpoint_id.sha256_text(), 512
		),
	}

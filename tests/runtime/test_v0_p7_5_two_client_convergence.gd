extends SceneTree

const BubbleScript = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const MatterAuthorityScript = preload(
	"res://scripts/simulation/matter/network/matter_authoritative_server.gd"
)
const MatterInterestServerScript = preload(
	"res://scripts/simulation/matter/interest/matter_interest_server.gd"
)
const MatterInterestReplicaScript = preload(
	"res://scripts/simulation/matter/interest/matter_interest_replica_client.gd"
)
const MatterInterestRegionScript = preload(
	"res://scripts/simulation/matter/interest/matter_interest_region.gd"
)
const GatewayScript = preload("res://scripts/network/loopback/network_command_gateway.gd")
const CommandTransportScript = preload(
	"res://scripts/network/loopback/loopback_command_transport.gd"
)
const ReplicationAdapterScript = preload(
	"res://scripts/network/bus/adapters/in_memory_replication_transport_adapter.gd"
)
const GameplayServiceScript = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"
)
const GameplayReplicaStoreScript = preload(
	"res://scripts/runtime/host_client/multiplayer_gameplay_replica_store.gd"
)
const AuthoritativeItemPortScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_authoritative_item_graph_output_port.gd"
)
const MaterialDeliveryScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd"
)
const ItemReplicaAdapterScript = preload(
	"res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd"
)
const RepresentationSourceScript = preload(
	"res://scripts/simulation/representation/contracts/representation_source_revision.gd"
)
const MatterRepresentationAdapterScript = preload(
	"res://scripts/simulation/representation/network/matter_representation_interest_adapter.gd"
)
const ScopeBindingScript = preload(
	"res://scripts/simulation/representation/network/contracts/representation_stream_scope_binding.gd"
)
const ObserverScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_two_client_convergence_observer.gd"
)

const AUTHORITY_OWNER := "authority/p7-5-matter"
const AUTHORITY_EPOCH := 1
const PLAYER_A := "a"
const PLAYER_B := "b"
const ACTOR_A := "player/a"
const ACTOR_B := "player/b"
const PEER_A := "peer/p7-5/a/1"
const PEER_B := "peer/p7-5/b/1"
const MATTER_SESSION_A := "session/p7-5/matter/a/1"
const MATTER_SESSION_B := "session/p7-5/matter/b/1"
const GAMEPLAY_SESSION_A := "transport-session/p7-5/a/1"
const GAMEPLAY_SESSION_B := "transport-session/p7-5/b/1"
const OPERATION_ID := "operation/p7-5/lunar-dig/1"
const MESSAGE_ID := "message/p7-5/lunar-dig/1"
const TOOL_ID := "item/tool/p7-5-test"
const SURFACE_RADIUS_M := 1737425.0

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var setup := _build_lunar_network()
	_assert_success(setup, "build lunar MW6/MW7 network")
	if not bool(setup.get("success", false)):
		_finish()
		return

	var bubble = setup["bubble"]
	var authority = setup["authority"]
	var interest_server = setup["interest_server"]
	var replication = setup["replication_adapter"]
	var client_a = setup["client_a"]
	var client_b = setup["client_b"]
	var request: Dictionary = setup["request"]
	var center_cell: Dictionary = setup["center_cell"]

	# Real two-client MW7 subscriptions over the exact same lunar region.
	_assert_success(
		client_a.set_interest("subscription/p7-5/a/shared", 1, center_cell, 1),
		"client A shared lunar interest"
	)
	_assert_success(
		client_b.set_interest("subscription/p7-5/b/shared", 1, center_cell, 1),
		"client B shared lunar interest"
	)
	_assert_success(
		_connect_interest(authority, interest_server, client_a, PEER_A, MATTER_SESSION_A, ACTOR_A),
		"connect client A to existing MW6/MW7"
	)
	_assert_success(
		_connect_interest(authority, interest_server, client_b, PEER_B, MATTER_SESSION_B, ACTOR_B),
		"connect client B to existing MW6/MW7"
	)

	var gameplay = GameplayServiceScript.new()
	_assert_success(gameplay.setup("authority/p7-5/gameplay", 1, 0, {
		"profile": GameplayServiceScript.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/p7-5/lunar",
	}), "configure existing NetworkedGameplayService")
	_assert_success(
		gameplay.join(PLAYER_A, GAMEPLAY_SESSION_A, "operation/p7-5/gameplay/join-a"),
		"gameplay client A joins"
	)
	_assert_success(
		gameplay.join(PLAYER_B, GAMEPLAY_SESSION_B, "operation/p7-5/gameplay/join-b"),
		"gameplay client B joins"
	)

	var gameplay_replica_a = GameplayReplicaStoreScript.new()
	var gameplay_replica_b = GameplayReplicaStoreScript.new()
	var gameplay_before: Dictionary = gameplay.create_snapshot()
	_assert_success(
		gameplay_replica_a.accept_snapshot(gameplay_before),
		"client A accepts aggregate baseline"
	)
	_assert_success(
		gameplay_replica_b.accept_snapshot(gameplay_before),
		"client B accepts aggregate baseline"
	)

	# Client A performs one real canonical Matter mutation through existing MW6.
	var command: Dictionary = client_a.create_mutation_command(request, MESSAGE_ID)
	_assert_true(not command.is_empty(), "client A builds canonical MW6 Matter command")
	var transported: Dictionary = setup["command_transport"].send(command)
	_assert_success(transported, "MW6 loopback transport accepts client A dig")
	var result_envelope: Dictionary = transported.get("result", {})
	var accepted_result: Dictionary = client_a.accept_command_result(result_envelope)
	_assert_success(accepted_result, "client A accepts MW6 authoritative command result")
	var matter_result: Dictionary = accepted_result.get("details", {}).get("result", {})
	_assert_true(
		String(matter_result.get("status", "")) == "COMMITTED",
		"client A dig commits at canonical Matter owner"
	)
	_assert_true(
		Array(matter_result.get("created_aggregate_ids", [])).size() == 1,
		"canonical dig creates exactly one MatterMaterialBatch"
	)
	_assert_true(
		interest_server.outbound_count(PEER_A) > 0,
		"MW7 queues relevant Matter update for client A"
	)
	_assert_true(
		interest_server.outbound_count(PEER_B) > 0,
		"MW7 queues same relevant Matter update for client B"
	)
	_assert_success(
		_dispatch_and_poll(interest_server, replication, client_a, PEER_A),
		"dispatch MW7 update to client A"
	)
	_assert_success(
		_dispatch_and_poll(interest_server, replication, client_b, PEER_B),
		"dispatch MW7 update to client B"
	)
	_assert_true(
		client_a.snapshot_store().content_hash() == client_b.snapshot_store().content_hash(),
		"A/B lunar sparse Matter stores converge"
	)
	_assert_true(
		client_a.source_global_stream_sequence() == authority.stream_sequence(),
		"client A reaches authoritative Matter cursor"
	)
	_assert_true(
		client_b.source_global_stream_sequence() == authority.stream_sequence(),
		"client B reaches authoritative Matter cursor"
	)

	# Deliver the exact committed MatterMaterialBatch through P7.3, but through
	# the P7.4 authoritative aggregate port so the existing gameplay revision
	# owner advances exactly once.
	var output_port = AuthoritativeItemPortScript.new()
	_assert_success(output_port.configure(gameplay), "bind P7.4 authoritative Item Graph port")
	var material_delivery = MaterialDeliveryScript.new()
	_assert_success(
		material_delivery.configure(bubble.excavation_service(), output_port),
		"bind P7.3 material delivery to P7.4 aggregate seam"
	)
	var aggregate_before := int(gameplay.get_report().get("revision", -1))
	var delivered: Dictionary = material_delivery.deliver_committed(request, matter_result)
	_assert_success(delivered, "deliver exact Matter batch to canonical Item Graph")
	var delivery: Dictionary = delivered.get("details", {}).get("delivery", {})
	_assert_true(not bool(delivery.get("replay", true)), "first material delivery is fresh")
	_assert_true(bool(delivery.get("item_graph_mutated", false)), "fresh delivery mutates Item Graph once")
	_assert_true(int(delivery.get("output_quantity", 0)) > 0, "real lunar dig yields canonical ore")
	var aggregate_after := int(gameplay.get_report().get("revision", -1))
	_assert_true(
		aggregate_after == aggregate_before + 1,
		"P7.4 aggregate revision advances exactly once on fresh delivery"
	)

	# Both gameplay clients consume the real client-visible aggregate snapshot.
	var gameplay_after: Dictionary = gameplay.create_snapshot()
	_assert_success(gameplay_replica_a.accept_snapshot(gameplay_after), "client A accepts aggregate update")
	_assert_success(gameplay_replica_b.accept_snapshot(gameplay_after), "client B accepts aggregate update")
	_assert_true(
		int(gameplay_replica_a.get_snapshot().get("revision", -1)) == aggregate_after,
		"client A aggregate revision converges"
	)
	_assert_true(
		int(gameplay_replica_b.get_snapshot().get("revision", -1)) == aggregate_after,
		"client B aggregate revision converges"
	)

	# Existing M7 adapter builds each client-local item view while preserving one
	# canonical revision/checksum identity.
	var canonical_items: Dictionary = gameplay.create_canonical_item_graph_snapshot()
	var item_adapter_a = ItemReplicaAdapterScript.new()
	var item_adapter_b = ItemReplicaAdapterScript.new()
	_assert_success(item_adapter_a.setup(PLAYER_A), "configure existing M7 item adapter A")
	_assert_success(item_adapter_b.setup(PLAYER_B), "configure existing M7 item adapter B")
	var item_a_result: Dictionary = item_adapter_a.create_replica_snapshot(canonical_items)
	var item_b_result: Dictionary = item_adapter_b.create_replica_snapshot(canonical_items)
	_assert_success(item_a_result, "build client A Item Graph replica")
	_assert_success(item_b_result, "build client B Item Graph replica")
	var item_a: Dictionary = item_a_result.get("details", {})
	var item_b: Dictionary = item_b_result.get("details", {})
	_assert_true(
		int(item_a.get("canonical_revision", -1)) == int(item_b.get("canonical_revision", -2)),
		"A/B Item Graph canonical revisions converge"
	)
	_assert_true(
		String(item_a.get("canonical_checksum", "")) == String(item_b.get("canonical_checksum", "-")),
		"A/B Item Graph canonical checksums converge"
	)

	var source := _representation_source(bubble, client_a)
	_assert_true(not source.is_empty(), "build shared Matter representation source revision")
	var representation_a := _project_representation(client_a.subscription(), source)
	var representation_b := _project_representation(client_b.subscription(), source)
	_assert_success(representation_a, "RL3 projection for client A")
	_assert_success(representation_b, "RL3 projection for client B")
	var request_a: Dictionary = representation_a.get("details", {}).get("stream_request", {})
	var request_b: Dictionary = representation_b.get("details", {}).get("stream_request", {})

	var observer = ObserverScript.new()
	var contract := observer.contract_report()
	_assert_true(not bool(contract.get("canonical_state_owned", true)), "P7.5 observer owns no canonical state")
	_assert_true(not bool(contract.get("network_frames_sent", true)), "P7.5 observer sends no network frames")
	_assert_true(not bool(contract.get("delivery_receipt_store", true)), "P7.5 owns no delivery receipt store")
	_assert_true(not bool(contract.get("replay_ledger_owned", true)), "P7.5 owns no replay ledger")
	_assert_true(String(contract.get("replication_owner", "")) == "MW6", "P7.5 keeps MW6 replication owner")
	_assert_true(String(contract.get("interest_owner", "")) == "MW7", "P7.5 keeps MW7 interest owner")
	_assert_true(String(contract.get("meshing_owner", "")) == "RL2", "P7.5 keeps RL2 meshing owner")
	_assert_true(String(contract.get("representation_stream_owner", "")) == "RL3", "P7.5 keeps RL3 streaming owner")
	_assert_true(String(contract.get("aggregate_revision_owner", "")) == "NETWORKED_GAMEPLAY_SERVICE", "P7.5 keeps P7.4 aggregate revision owner")

	var converged: Dictionary = observer.evaluate(
		client_a,
		client_b,
		gameplay_replica_a.get_snapshot(),
		gameplay_replica_b.get_snapshot(),
		item_a,
		item_b,
		canonical_items,
		request_a,
		request_b
	)
	_assert_success(converged, "P7.5 A/B canonical convergence")
	_assert_true(bool(converged.get("details", {}).get("converged", false)), "P7.5 observer reports converged")
	_assert_true(
		String(converged.get("details", {}).get("identity", {}).get("matter_store_hash", ""))
			== String(client_a.snapshot_store().content_hash()),
		"convergence identity binds shared Matter store"
	)
	_assert_true(
		int(converged.get("details", {}).get("identity", {}).get("gameplay_revision", -1))
			== aggregate_after,
		"convergence identity binds P7.4 aggregate revision"
	)

	# Interest exit must break shared-region convergence; re-entry must restore it
	# using existing MW7 snapshot/replay semantics, not a P7 cache.
	var away_cell := _away_cell(bubble.grid_profile(), center_cell)
	_assert_true(not away_cell.is_empty(), "build distinct MW7 away cell")
	_assert_success(
		client_b.set_interest("subscription/p7-5/b/away", 2, away_cell, 0),
		"client B leaves shared Matter region"
	)
	_assert_success(
		interest_server.update_interest(PEER_B, client_b.create_sync_request()),
		"MW7 accepts client B interest exit"
	)
	_assert_success(
		_dispatch_and_poll(interest_server, replication, client_b, PEER_B),
		"MW7 applies client B away-region snapshot"
	)
	var diverged: Dictionary = observer.evaluate(
		client_a,
		client_b,
		gameplay_replica_a.get_snapshot(),
		gameplay_replica_b.get_snapshot(),
		item_a,
		item_b,
		canonical_items,
		request_a,
		request_b
	)
	_assert_error(
		diverged,
		"P7_5_MATTER_INTEREST_SCOPE_DIVERGED",
		"observer fails closed while B is outside A shared region"
	)

	_assert_success(
		client_b.set_interest("subscription/p7-5/b/reenter", 3, center_cell, 1),
		"client B requests shared-region re-entry"
	)
	_assert_success(
		interest_server.update_interest(PEER_B, client_b.create_sync_request()),
		"MW7 accepts client B shared-region re-entry"
	)
	_assert_success(
		_dispatch_and_poll(interest_server, replication, client_b, PEER_B),
		"MW7 reconstructs client B shared-region state"
	)
	_assert_true(
		client_b.snapshot_store().content_hash() == client_a.snapshot_store().content_hash(),
		"client B reconverges to client A Matter store after interest re-entry"
	)
	_assert_true(
		client_b.source_global_stream_sequence() == client_a.source_global_stream_sequence(),
		"client B reconverges to authoritative Matter cursor after re-entry"
	)
	var representation_b_reentered := _project_representation(client_b.subscription(), source)
	_assert_success(representation_b_reentered, "RL3 projection after client B re-entry")
	var reconverged: Dictionary = observer.evaluate(
		client_a,
		client_b,
		gameplay_replica_a.get_snapshot(),
		gameplay_replica_b.get_snapshot(),
		item_a,
		item_b,
		canonical_items,
		request_a,
		representation_b_reentered.get("details", {}).get("stream_request", {})
	)
	_assert_success(reconverged, "P7.5 reconverges after MW7 interest re-entry")

	# Exact duplicate command and material delivery are mutation-free at the
	# existing owners. No new MW7 delta or aggregate revision may appear.
	var matter_cursor_before_replay := authority.stream_sequence()
	var gameplay_revision_before_replay := int(gameplay.get_report().get("revision", -1))
	var replay_transport: Dictionary = setup["command_transport"].send(command)
	_assert_success(replay_transport, "replay exact MW6 command")
	var replay_command: Dictionary = client_a.accept_command_result(
		replay_transport.get("result", {})
	)
	_assert_success(replay_command, "client A accepts exact gateway/MW6 replay result")
	_assert_true(
		Dictionary(replay_command.get("details", {}).get("result", {})) == matter_result,
		"exact network replay returns the same canonical Matter result"
	)
	_assert_true(
		authority.stream_sequence() == matter_cursor_before_replay,
		"exact network replay leaves Matter cursor unchanged"
	)
	_assert_true(interest_server.outbound_count(PEER_A) == 0, "MW6 replay queues no A interest delta")
	_assert_true(interest_server.outbound_count(PEER_B) == 0, "MW6 replay queues no B interest delta")

	var delivery_replay: Dictionary = material_delivery.deliver_committed(request, matter_result)
	_assert_success(delivery_replay, "replay exact P7 material delivery")
	_assert_true(
		bool(delivery_replay.get("details", {}).get("delivery", {}).get("replay", false)),
		"canonical Item Graph owns delivery replay"
	)
	_assert_true(
		not bool(delivery_replay.get("details", {}).get("delivery", {}).get("item_graph_mutated", true)),
		"Item Graph replay is mutation-free"
	)
	_assert_true(
		int(gameplay.get_report().get("revision", -1)) == gameplay_revision_before_replay,
		"P7.4 aggregate revision does not advance on replay"
	)
	var gameplay_replay_snapshot: Dictionary = gameplay.create_snapshot()
	var a_replay_accept: Dictionary = gameplay_replica_a.accept_snapshot(gameplay_replay_snapshot)
	var b_replay_accept: Dictionary = gameplay_replica_b.accept_snapshot(gameplay_replay_snapshot)
	_assert_success(a_replay_accept, "client A accepts aggregate snapshot replay")
	_assert_success(b_replay_accept, "client B accepts aggregate snapshot replay")
	_assert_true(bool(a_replay_accept.get("details", {}).get("replay", false)), "client A aggregate replay deduplicated")
	_assert_true(bool(b_replay_accept.get("details", {}).get("replay", false)), "client B aggregate replay deduplicated")
	_assert_true(
		gameplay.create_canonical_item_graph_snapshot() == canonical_items,
		"duplicate delivery leaves canonical Item Graph byte-stable"
	)

	var final_convergence: Dictionary = observer.evaluate(
		client_a,
		client_b,
		gameplay_replica_a.get_snapshot(),
		gameplay_replica_b.get_snapshot(),
		item_a,
		item_b,
		canonical_items,
		request_a,
		representation_b_reentered.get("details", {}).get("stream_request", {})
	)
	_assert_success(final_convergence, "P7.5 remains converged after exact replays")
	_assert_success(gameplay.shutdown(), "shutdown gameplay service")
	_finish()


func _build_lunar_network() -> Dictionary:
	var bubble = BubbleScript.new()
	var configured: Dictionary = bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": 32.0,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 3,
		"brick_interior_resolution": 8,
		"ghost_border_samples": 1,
		"container_id": "container/p7-5/moon-output",
	})
	if not bool(configured.get("success", false)):
		return configured
	var center := bubble.anchor_body_fixed_m()
	var request: Dictionary = bubble.create_excavation_request(
		OPERATION_ID,
		ACTOR_A,
		TOOL_ID,
		center + Vector3(2.5, -0.5, 0.0),
		center + Vector3(3.5, -0.5, 0.0),
		0.75,
		1000000000.0,
		1
	)
	if request.is_empty() or Array(request.get("target_bricks", [])).is_empty():
		return _failure("P7_5_LUNAR_REQUEST_BUILD_FAILED")
	var center_cell: Dictionary = Dictionary(
		Dictionary(Array(request["target_bricks"])[0]).get("cell_address", {})
	).duplicate(true)

	var authority = MatterAuthorityScript.new()
	var authority_setup: Dictionary = authority.configure(
		bubble.body_definition(),
		bubble.grid_profile(),
		bubble.excavation_service(),
		AUTHORITY_OWNER,
		AUTHORITY_EPOCH,
		64
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
	var interest_server = MatterInterestServerScript.new()
	var interest_setup: Dictionary = interest_server.configure(
		bubble.body_definition(),
		bubble.grid_profile(),
		bubble.excavation_service(),
		authority,
		AUTHORITY_OWNER,
		AUTHORITY_EPOCH,
		64
	)
	if not bool(interest_setup.get("success", false)):
		return interest_setup
	var client_a = MatterInterestReplicaScript.new()
	var client_b = MatterInterestReplicaScript.new()
	var a_setup: Dictionary = client_a.configure(
		bubble.body_definition(),
		bubble.grid_profile(),
		AUTHORITY_OWNER,
		AUTHORITY_EPOCH,
		"client/p7-5/a"
	)
	if not bool(a_setup.get("success", false)):
		return a_setup
	var b_setup: Dictionary = client_b.configure(
		bubble.body_definition(),
		bubble.grid_profile(),
		AUTHORITY_OWNER,
		AUTHORITY_EPOCH,
		"client/p7-5/b"
	)
	if not bool(b_setup.get("success", false)):
		return b_setup
	return _success({
		"bubble": bubble,
		"authority": authority,
		"interest_server": interest_server,
		"client_a": client_a,
		"client_b": client_b,
		"gateway": gateway,
		"command_transport": command_transport,
		"replication_adapter": ReplicationAdapterScript.new(
			"adapter/p7-5-interest", 512
		),
		"request": request,
		"center_cell": center_cell,
	})


func _connect_interest(
	authority,
	interest_server,
	client,
	peer_id: String,
	session_id: String,
	actor_id: String
) -> Dictionary:
	var activated: Dictionary = client.activate_session(peer_id, session_id)
	if not bool(activated.get("success", false)):
		return activated
	var authority_connected: Dictionary = authority.connect_interest_peer(
		peer_id,
		String(
			client.subscription().get(
				"client_id",
				client.pending_subscription().get("client_id", "")
			)
		),
		session_id,
		actor_id
	)
	if not bool(authority_connected.get("success", false)):
		return authority_connected
	return interest_server.connect_peer(peer_id, client.create_sync_request())


func _dispatch_and_poll(interest_server, replication, client, peer_id: String) -> Dictionary:
	var dispatched: Dictionary = interest_server.dispatch_peer(peer_id, replication, 64)
	if not bool(dispatched.get("success", false)):
		return dispatched
	var polled: Dictionary = client.poll_replication(replication, 64)
	if not bool(polled.get("success", false)):
		return polled
	return _success({
		"dispatched": int(dispatched.get("details", {}).get("dispatched", 0)),
		"applied": int(polled.get("details", {}).get("applied", 0)),
	})


func _representation_source(bubble, client) -> Dictionary:
	var store_hash := String(client.snapshot_store().content_hash())
	var dependency_hash := String(bubble.grid_profile().get("checksum", ""))
	return RepresentationSourceScript.create(
		"MATTER",
		String(bubble.body_definition().get("body_id", "")),
		AUTHORITY_EPOCH,
		int(client.source_global_stream_sequence()),
		store_hash,
		dependency_hash
	)


func _project_representation(subscription: Dictionary, source: Dictionary) -> Dictionary:
	var scope_chain: Array = [
		ScopeBindingScript.create(2, "region/p7-5-macro"),
		ScopeBindingScript.create(1, "region/p7-5-regional"),
		ScopeBindingScript.create(0, "region/p7-5-detail"),
	]
	return MatterRepresentationAdapterScript.project(
		subscription,
		source,
		scope_chain,
		100.0,
		1000.0,
		3.0,
		0.5,
		false,
		false,
		512,
		["DETAIL", "MACRO_PROXY", "SIMPLIFIED_MESH"],
		[],
		["RAW"],
		true,
		12.0,
		3,
		64,
		128,
		128,
		0
	)


func _away_cell(grid_profile: Dictionary, center_cell: Dictionary) -> Dictionary:
	var indices: Array = MatterInterestRegionScript.indices_for_cell(center_cell)
	if indices.size() != 3:
		return {}
	var level := int(center_cell.get("level", -1))
	var axis_count := 1 << level
	if axis_count < 2:
		return {}
	var x := (int(indices[0]) + maxi(1, axis_count >> 1)) % axis_count
	return MatterInterestRegionScript.cell_for_indices(
		grid_profile,
		level,
		x,
		int(indices[1]),
		int(indices[2])
	)


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert_true(not bool(result.get("success", false)), "%s rejects" % message)
	_assert_true(
		String(result.get("error_code", "")) == error_code,
		"%s expected=%s actual=%s" % [
			message,
			error_code,
			String(result.get("error_code", "")),
		]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.5] %s" % message)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}


func _finish() -> void:
	if _failures == 0:
		print("V0-P7.5 two-client convergence: PASS (%d assertions, 0 failures)" % _assertions)
		quit(0)
		return
	print("V0-P7.5 two-client convergence: FAIL (%d assertions, %d failures)" % [
		_assertions, _failures,
	])
	quit(1)

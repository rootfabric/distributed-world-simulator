extends RefCounted

# Composition only: one existing native M3 owner, one accepted LunarBubble/MW4
# at authority/a, MW8 directory, P7 authorization and MW6 replication.
# No client state, fallback authority or new replay ledger is introduced.
const Bubble = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const Bootstrap = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp_bootstrap_surface.gd")
const MatterServer = preload("res://scripts/simulation/matter/network/matter_authoritative_server.gd")
const Region = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")
const Directory = preload("res://scripts/simulation/matter/handoff/matter_authority_directory.gd")
const RegionalGate = preload("res://scripts/simulation/matter/handoff/matter_regional_authority_gate.gd")
const P7Gate = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_command_authority_gate.gd")
const Codec = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const Request = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const NetworkCommand = preload("res://scripts/network/contracts/network_command_envelope.gd")
const Envelope = preload("res://scripts/network/bus/replication_envelope.gd")
const OutputPort = preload("res://scripts/runtime/networked_gameplay/p7/p7_authoritative_item_graph_output_port.gd")
const Delivery = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const OWNER := "authority/a"
const EPOCH := 1
const MAX_DIG_OPERATIONS := 8
const MAX_REQUEST_BYTES := 65536
const MAX_FRAME_BYTES := 1048576
const REACH_M := 4.5
# This bounded level-one bootstrap has 2 m samples. A 0.75 m stroke only
# perturbed already-negative SDF samples below vacuum boundary nodes, giving
# different mesh hashes without a visible surface opening. The real tool must
# intersect the first solid lattice layer, still within the unchanged P7 reach.
const DIG_STROKE_M := 2.0

class PlayerProjection extends RefCounted:
	func project(player: Dictionary, _request: Dictionary) -> Dictionary:
		var p: Dictionary = player.get("position", {})
		if not p.has_all(["x", "y", "z"]):
			return {"success": false, "error_code": "MVP4_PLAYER_POSITION_MISSING"}
		return {"success": true, "position_m": [float(p["x"]), float(p["y"]) + 1737425.0, float(p["z"])]}

class ActorGates extends RefCounted:
	var gates: Dictionary = {}
	func authorize_mutation(request: Dictionary) -> Dictionary:
		var actor := String(request.get("actor_id", "")).trim_prefix("player/")
		if not gates.has(actor):
			return {"success": false, "error_code": "MVP4_UNKNOWN_ACTOR"}
		return gates[actor].authorize_mutation(request)

class FrameSink extends RefCounted:
	var messages: Array = []
	func send(envelope: Dictionary) -> Dictionary:
		if messages.size() >= 1 or JSON.stringify(envelope).to_utf8_buffer().size() > 1048576:
			return {"success": false, "error_code": "MVP4_REPLICATION_FRAME_BUDGET"}
		messages.append(envelope.duplicate(true))
		return {"success": true}

var _configured := false
var _gameplay = null
var _bubble = null
var _matter = null
var _directory = null
var _regional_gate = null
var _gates = null
var _projection = null
var _delivery = null
var _output = null
var _sessions: Dictionary = {}
var _decisions: Dictionary = {}
var _plan_key := PackedByteArray()
var _connected: Dictionary = {}
var _initial_store_hash := ""
var _dig_observations: Array = []

static func peer(actor: String) -> String:
	return "peer/mvp4/" + actor

static func client(actor: String) -> String:
	return "client/mvp4/" + actor

static func ok(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func fail(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}

func configure(gameplay, decisions: Dictionary, sessions: Dictionary) -> Dictionary:
	if _configured or gameplay == null or not gameplay.has_method("get_canonical_item_graph_port"):
		return fail("MVP4_NATIVE_OWNER_REQUIRED")
	if gameplay.get_report().get("authority_owner_id") != OWNER:
		return fail("MVP4_SINGLE_REGION_OWNER_REQUIRED")
	for actor in ["a", "b"]:
		if not decisions.has(actor) or not decisions[actor].has_method("authorize_write") or not sessions.get(actor) is String or String(sessions[actor]).is_empty():
			return fail("MVP4_IDENTITY_AUTHORITY_BINDING_REQUIRED")
	_gameplay = gameplay
	_sessions = sessions.duplicate(true)
	_decisions = decisions.duplicate()
	_plan_key = Crypto.new().generate_random_bytes(32)
	_bubble = Bubble.new()
	var result: Dictionary = _bubble.configure(Bootstrap.DESCRIPTOR.duplicate(true))
	if not bool(result.get("success", false)): return result
	var snapshots: Array = _bubble.materialize_presentation_level()
	if snapshots.size() != 8: return fail("MVP4_BOUNDED_BOOTSTRAP_REQUIRED")
	_initial_store_hash = _bubble.snapshot_store().content_hash()
	_directory = Directory.new()
	result = _directory.configure(String(_bubble.body_definition()["body_id"]), _bubble.grid_profile())
	if not bool(result.get("success", false)): return result
	var region := Region.create("region/mvp4/shared", String(_bubble.body_definition()["body_id"]), 1, snapshots[0]["address"]["cell_address"], 1)
	result = _directory.register_region(region, OWNER, EPOCH)
	if not bool(result.get("success", false)): return result
	_regional_gate = RegionalGate.new()
	result = _regional_gate.configure(OWNER, EPOCH, _directory)
	if not bool(result.get("success", false)): return result
	_projection = PlayerProjection.new()
	_gates = ActorGates.new()
	for actor in ["a", "b"]:
		var gate = P7Gate.new()
		result = gate.configure(_gameplay, _gameplay.get_canonical_item_graph_port(), decisions[actor], _regional_gate, OWNER, EPOCH, REACH_M, Callable(_projection, "project"))
		if not bool(result.get("success", false)): return result
		_gates.gates[actor] = gate
	_matter = MatterServer.new()
	result = _matter.configure(_bubble.body_definition(), _bubble.grid_profile(), _bubble.excavation_service(), OWNER, EPOCH, 16)
	if not bool(result.get("success", false)): return result
	result = _matter.set_command_authority_gate(_gates)
	if not bool(result.get("success", false)): return result
	_output = OutputPort.new()
	result = _output.configure(_gameplay)
	if not bool(result.get("success", false)): return result
	_delivery = Delivery.new()
	result = _delivery.configure(_bubble.excavation_service(), _output)
	if not bool(result.get("success", false)): return result
	_configured = true
	return ok(report())

func _identity(actor: String, session: String) -> Dictionary:
	if not _configured or not _sessions.has(actor): return fail("MVP4_UNKNOWN_ACTOR")
	var player: Dictionary = _gameplay.get_player(actor)
	if session != _sessions[actor] or player.get("transport_session_id") != session:
		return fail("MVP4_STALE_PLAYER_SESSION")
	if player.get("logical_player_id") != actor or player.get("player_entity_id") != "player/" + actor or player.get("connected") != true:
		return fail("MVP4_PLAYER_IDENTITY_INVALID")
	var authorized: Dictionary = _decisions[actor].authorize_write(OWNER, EPOCH)
	if not bool(authorized.get("success", false)): return authorized
	return ok({"player": player})

func equip_tool(actor: String, session: String) -> Dictionary:
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	var player: Dictionary = identity["details"]["player"]
	var output: Dictionary = _gameplay.apply_canonical_server_output("operation/mvp4/bootstrap-tool/" + actor, actor, "item/tool/mining", 1, "source/mvp4/bootstrap")
	if not bool(output.get("success", false)): return output
	var item_id := String(output.get("details", {}).get("output_item_id", ""))
	if item_id.is_empty(): return fail("MVP4_TOOL_OUTPUT_MISSING")
	return _gameplay.handle_canonical_item_command(actor, session, int(player["ownership_epoch"]), "operation/mvp4/bootstrap-equip/" + actor, "item.equip", {"item_id": item_id, "slot_id": "tool/main"})

func connect_replica(actor: String, session: String, sync_request: Dictionary) -> Dictionary:
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	if _connected.has(actor): return fail("MVP4_REPLICA_ALREADY_CONNECTED")
	var result: Dictionary = _matter.connect_peer(peer(actor), client(actor), session, "player/" + actor, sync_request)
	if bool(result.get("success", false)): _connected[actor] = true
	return result

func poll_replica(actor: String, session: String) -> Dictionary:
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	if not _connected.has(actor): return fail("MVP4_REPLICA_NOT_CONNECTED")
	var sink = FrameSink.new()
	var result: Dictionary = _matter.dispatch_peer(peer(actor), sink, 1)
	if not bool(result.get("success", false)): return result
	return ok({"messages": sink.messages, "remaining": _matter.outbound_count(peer(actor)), "state_hash": _matter.current_state_hash(), "stream_sequence": _matter.stream_sequence()})

func acknowledge_replica(actor: String, session: String, ack: Dictionary) -> Dictionary:
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	return _matter.acknowledge(peer(actor), ack)

func prepare_dig(actor: String, session: String, operation_id: String, direction_value: Array) -> Dictionary:
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	if not operation_id.begins_with("operation/mvp4/" + actor + "/") or operation_id.length() > 128:
		return fail("MVP4_OPERATION_BINDING_INVALID")
	if direction_value.size() != 3: return fail("MVP4_AIM_DIRECTION_INVALID")
	for coordinate in direction_value:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
			return fail("MVP4_AIM_DIRECTION_INVALID")
	var direction := Vector3(float(direction_value[0]), float(direction_value[1]), float(direction_value[2]))
	if absf(direction.length() - 1.0) > 0.000001: return fail("MVP4_AIM_DIRECTION_INVALID")
	var player: Dictionary = identity["details"]["player"]
	var projected: Dictionary = _projection.project(player, {})
	if not bool(projected.get("success", false)): return projected
	var p: Array = projected["position_m"]
	var origin := Vector3(float(p[0]), float(p[1]), float(p[2])) + Vector3.UP * 1.6
	var query: Dictionary = _bubble.query_service().raycast(origin, direction, 3.0, _bubble.mutation_level(), 0.2, 0.15, 128)
	if not bool(query.get("success", false)) or not bool(query.get("details", {}).get("hit", false)):
		return fail("MVP4_CANONICAL_AIM_MISS")
	var hit: Vector3 = query["details"]["position_m"]
	var tool: Dictionary = _gameplay.get_canonical_item_graph_port().get_equipped_item(actor, "tool/main")
	if tool.is_empty(): return fail("P7_MINING_TOOL_REQUIRED")
	var request: Dictionary = _bubble.create_excavation_request(operation_id, "player/" + actor, String(tool["item_id"]), hit - direction * 0.25, hit + direction * DIG_STROKE_M, 1.25, 1000000000.0, int(_gameplay.get_report()["server_tick"]))
	if request.is_empty(): return fail("MVP4_BOUNDED_DIG_PLAN_INVALID")
	var authorized: Dictionary = _gates.authorize_mutation(request)
	if not bool(authorized.get("success", false)): return authorized
	var transport := Codec.encode_persistence_json(request)
	return ok({"request_transport": transport, "plan_mac": _plan_mac(actor, session, transport), "aim_source": "CANONICAL_MATTER_QUERY", "hit_position_m": [hit.x, hit.y, hit.z], "player_position_m": p, "stroke_depth_m": DIG_STROKE_M})

func _plan_mac(actor: String, session: String, transport: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _plan_key, (actor + "\n" + session + "\n" + transport).to_utf8_buffer()).hex_encode()

func execute_prepared(actor: String, session: String, plan: Dictionary) -> Dictionary:
	var identity := _identity(actor, session)
	if not bool(identity.get("success", false)): return identity
	if not _connected.has(actor): return fail("MVP4_REPLICA_NOT_CONNECTED")
	var request_transport := String(plan.get("request_transport", ""))
	if request_transport.to_utf8_buffer().size() > MAX_REQUEST_BYTES: return fail("MVP4_DIG_REQUEST_BUDGET")
	var supplied_mac := String(plan.get("plan_mac", ""))
	if supplied_mac.length() != 64 or not Crypto.new().constant_time_compare(supplied_mac.to_utf8_buffer(), _plan_mac(actor, session, request_transport).to_utf8_buffer()):
		return fail("MVP4_CANONICAL_AIM_ATTESTATION_INVALID")
	var request: Dictionary = Codec.rehydrate_request(Codec.decode_persistence_json(request_transport))
	if request.is_empty() or not bool(Request.validate(request).get("success", false)):
		return fail("MVP4_INVALID_CANONICAL_REQUEST")
	if request.get("actor_id") != "player/" + actor or not String(request.get("operation_id", "")).begins_with("operation/mvp4/" + actor + "/"):
		return fail("MVP4_DIG_ACTOR_BINDING_INVALID")
	var journal = _bubble.excavation_service().mutation_journal()
	if not journal.has_operation(String(request["operation_id"])) and journal.size() >= MAX_DIG_OPERATIONS:
		return fail("MVP4_DIG_SESSION_BUDGET")
	var payload := {"peer_id": peer(actor), "session_id": session, "request_transport": request_transport}
	var envelope := NetworkCommand.create("message/mvp4/" + String(request["operation_id"]).sha256_text(), String(request["operation_id"]), String(_bubble.body_definition()["body_id"]), "MATTER_MUTATION", payload, -1, EPOCH, int(request["client_tick"]), 0)
	var before := report()
	var result: Dictionary = _matter.handle_gateway_command(payload, envelope)
	if not bool(result.get("success", false)): return result
	var native: Dictionary = Codec.rehydrate_result(Codec.decode_persistence_json(String(result.get("payload", {}).get("matter_result_transport", ""))))
	if native.get("status") != "COMMITTED": return fail("MVP4_MATTER_NOT_COMMITTED")
	var delivered: Dictionary = _delivery.deliver_committed(request, native)
	if not bool(delivered.get("success", false)): return delivered
	var after := report()
	if not bool(result.get("payload", {}).get("replay", false)):
		_dig_observations.append({"actor": actor, "operation_id": request["operation_id"], "before_store_hash": before["store_hash"], "after_store_hash": after["store_hash"], "before_stream": before["stream_sequence"], "after_stream": after["stream_sequence"], "changed_bricks": native.get("changed_bricks", []), "removed_mass_kg": native.get("removed_mass_kg", 0.0), "route": "P7_1_MW8_MW6_MW4", "output_delivery": delivered.get("details", {})})
	return ok({"matter_result_transport": result["payload"]["matter_result_transport"], "replay": result["payload"].get("replay", false), "state_hash": _matter.current_state_hash(), "stream_sequence": _matter.stream_sequence(), "store_hash": after["store_hash"]})

func report() -> Dictionary:
	return {"schema": "distributed_world_simulator.mvp4_shared_dig_authority.v1", "configured": _configured, "authority_id": OWNER, "authority_epoch": EPOCH, "matter_region_count": 1, "initial_store_hash": _initial_store_hash, "store_hash": _bubble.snapshot_store().content_hash() if _bubble != null else "", "state_hash": _matter.current_state_hash() if _matter != null else "", "stream_sequence": _matter.stream_sequence() if _matter != null else 0, "dig_observations": _dig_observations.duplicate(true), "connected_replicas": _connected.keys(), "canonical_player_owner": "NETWORKED_GAMEPLAY_SERVICE", "canonical_matter_owner": "LUNAR_BUBBLE_MW4", "replication_owner": "MW6", "mvp4_predicate_verified": false, "mvp5_material_output_verified": false}

func shutdown() -> void:
	_matter = null
	_gates = null
	_delivery = null
	_output = null
	_projection = null
	_regional_gate = null
	_directory = null
	_bubble = null
	_gameplay = null
	_configured = false
	_plan_key = PackedByteArray()
	_decisions.clear()

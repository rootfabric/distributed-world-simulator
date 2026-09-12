extends SceneTree

# R5 diagnostic composition uses the real accepted P6/SM1 chain and M3 Service.
# It proves routable commands/fencing/carry preparation, NOT completed migration.
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Registry = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const Ledger = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const Admission = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const Closure = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const Route = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const Carry = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Pivot = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_gateway_route_pivot.gd")
const Projection = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")
const Shadow = preload("res://scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd")
const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

var assertions := 0
var failures: Array[String] = []
var evidence: Dictionary = {}


class M3Adapter:
	extends RefCounted
	const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
	const Hash = preload("res://scripts/network/contracts/network_contract_utils.gd")
	var service
	var coordinator
	var p6_route
	var authority_id := ""
	var player_id := ""
	var client_session := ""
	var transport_session := ""
	var executions := 0

	func readiness() -> Dictionary:
		var player: Dictionary = service.get_player(player_id)
		if player.is_empty():
			return {"success": false, "error_code": "MVP3_CANONICAL_PLAYER_NOT_STAGED"}
		if player.get("player_entity_id") != "player/" + player_id or player.get("transport_session_id") != transport_session or player.get("connected") != true:
			return {"success": false, "error_code": "MVP3_CANONICAL_LIVE_BINDING_MISMATCH"}
		return {"success": true}

	func dto(command: Dictionary) -> Dictionary:
		var op: String = str(command.get("operation_id", ""))
		var epoch: int = int(service.create_snapshot().get("authority_epoch", 0))
		var ownership_epoch: int = int(service.get_player(player_id).get("ownership_epoch", 0))
		return InputDTO.create("message/m1/move/%s" % op.sha256_text().left(12), op, player_id, transport_session, epoch, ownership_epoch, int(command.get("input_sequence", 0)), "MOVEMENT_DELTA", {"delta_x": command.get("delta_x", 0.0), "delta_z": command.get("delta_z", 0.0)})

	func preflight(operation_id: String, command: Dictionary) -> Dictionary:
		var state: Dictionary = service.create_snapshot()
		if state.get("authority_owner_id") != authority_id:
			return {"success": false, "error_code": "MVP3_SERVICE_OWNER_MISMATCH"}
		var authorized: Dictionary = coordinator.authorize_write(authority_id, int(state.get("authority_epoch", 0)))
		if not bool(authorized.get("success", false)):
			return authorized
		var ready: Dictionary = readiness()
		if not bool(ready.get("success", false)):
			return ready
		if command.get("operation_id") != operation_id or command.get("canonical_player_id") != player_id or command.get("canonical_entity_id") != "player/" + player_id or command.get("transport_session_id") != transport_session:
			return {"success": false, "error_code": "MVP3_COMMAND_BINDING_MISMATCH"}
		var wire: Dictionary = dto(command)
		var valid: Dictionary = InputDTO.validate(wire)
		if not bool(valid.get("success", false)):
			return valid
		var replay: Dictionary = service.export_replay_state().get("service_operation_ledger", {}).get(operation_id, {})
		if not replay.is_empty():
			if replay.get("fingerprint") != Hash.payload_hash(wire):
				return {"success": false, "error_code": "OPERATION_REPLAY_CONFLICT"}
			return replay.get("result", {"success": false})
		return {"success": true}

	func execute_command(command: Dictionary) -> Dictionary:
		var checked: Dictionary = preflight(str(command.get("operation_id", "")), command)
		if not bool(checked.get("success", false)):
			return checked
		var result: Dictionary = service.handle_player_input(dto(command))
		if bool(result.get("success", false)) and not bool(result.get("replay", false)):
			executions += 1
		return result

	func route_command(session: String, operation_id: String, command: Dictionary) -> Dictionary:
		if session != client_session:
			return {"success": false, "error_code": "MVP3_CLIENT_SESSION_MISMATCH"}
		var checked: Dictionary = preflight(operation_id, command)
		if not bool(checked.get("success", false)):
			return checked
		var routed: Dictionary = p6_route.route_command(session, operation_id, command)
		# An outer route receipt is not by itself proof of successful gameplay.
		if bool(routed.get("success", false)) and routed.get("details", {}).get("result") == "EXECUTED":
			var outcome: Dictionary = routed.get("details", {}).get("outcome", {})
			if not bool(outcome.get("success", false)):
				return {"success": false, "error_code": "MVP3_CANONICAL_EXECUTION_REJECTED", "details": {"cause": outcome}}
		return routed


func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, description: String) -> void:
	assertions += 1
	if not ok:
		failures.append(description)
		push_error(description)


func command(player: String, sequence: int, dx: float = 0.25) -> Dictionary:
	return {"domain_id": "p6-domain/outpost-world-state", "command_kind": "PLAYER_INTERACTION", "operation_id": "operation/mvp3/bound-%s-%d" % [player, sequence], "canonical_player_id": player, "canonical_entity_id": "player/" + player, "transport_session_id": "transport-session/mvp3/" + player, "input_sequence": sequence, "delta_x": dx, "delta_z": 0.0}


func send(pivot, player: String, value: Dictionary) -> Dictionary:
	return pivot.route_command("client-session/mvp3/" + player, value["operation_id"], value)


func adapter(service, coordinator, registry, ledger, admission, closure, player: String, authority: String):
	var handler := M3Adapter.new()
	handler.service = service
	handler.coordinator = coordinator
	handler.authority_id = authority
	handler.player_id = player
	handler.client_session = "client-session/mvp3/" + player
	handler.transport_session = "transport-session/mvp3/" + player
	handler.p6_route = Route.new()
	check(bool(handler.p6_route.configure(registry, ledger, admission, closure, handler).get("success", false)), "accepted P6 route bound to real M3 handler")
	return handler


func _run() -> void:
	evidence = {"schema": "distributed_world_simulator.mvp3_bound_sm1_m3_probe.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "mvp3_predicate_verified": false, "integrated_graphical_migration_proven": false, "test_only": true}
	var source = Service.new()
	var target = Service.new()
	check(bool(source.setup("authority/a", 1).get("success", false)), "real source configured")
	check(bool(target.setup("authority/b", 2).get("success", false)), "real target configured")
	var registry = Registry.new()
	var ledger = Ledger.new()
	check(bool(ledger.configure(128).get("success", false)), "accepted P6 admission ledger configured")
	for player in ["a", "b"]:
		check(bool(source.join(player, "transport-session/mvp3/" + player, "operation/mvp3/join-" + player).get("success", false)), "real M3 player joined: " + player)
		# Explicit protocol aliases, NOT replacement identities of M3 actors.
		check(bool(registry.bind("client-session/mvp3/" + player, "player/mvp3/" + player, "entity/mvp3/" + player).get("success", false)), "accepted P6 alias binding: " + player)
	var admission = Admission.new()
	var closure = Closure.new()
	check(bool(admission.configure(registry, ledger).get("success", false)), "accepted P6 admission configured")
	check(bool(closure.configure(registry, ledger).get("success", false)), "accepted P6 closure configured")
	var coordinator_a = Coordinator.new()
	var coordinator_b = Coordinator.new()
	for entry in [["a", coordinator_a], ["b", coordinator_b]]:
		check(bool(entry[1].configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + entry[0], "player_entity_id": "entity/mvp3/" + entry[0], "last_input_sequence": 0, "last_operation_id": ""}).get("success", false)), "per-player SM1 coordinator configured")
	var handler_a = adapter(source, coordinator_a, registry, ledger, admission, closure, "a", "authority/a")
	var handler_b = adapter(source, coordinator_b, registry, ledger, admission, closure, "b", "authority/a")
	var target_a = adapter(target, coordinator_a, registry, ledger, admission, closure, "a", "authority/b")
	var pivot_a = Pivot.new()
	var pivot_b = Pivot.new()
	check(bool(pivot_a.configure({"authority/a": handler_a, "authority/b": target_a}, coordinator_a, "gateway/mvp3", "client-session/mvp3/a").get("success", false)), "accepted SM1 pivot A configured")
	check(bool(pivot_b.configure({"authority/a": handler_b}, coordinator_b, "gateway/mvp3", "client-session/mvp3/b").get("success", false)), "independent SM1 pivot B configured")
	var identity: Dictionary = pivot_a.get_client_route_identity()
	var initial: Dictionary = source.create_snapshot()
	var initial_b: Dictionary = source.get_player("b")
	var first_a := command("a", 1)
	var routed_a: Dictionary = send(pivot_a, "a", first_a)
	check(bool(routed_a.get("success", false)) and handler_a.executions == 1, "accepted pivot invokes real M3 A command")
	check(source.get_player("a").get("last_input_sequence") == 1, "real M3 A input watermark advanced")
	check(source.get_player("b") == initial_b, "A command leaves unrelated B record untouched")
	check(ledger.is_applied("player/mvp3/a", first_a["operation_id"]), "P6 admission reflects actual A execution")
	var after_a: Dictionary = source.create_snapshot()
	check(bool(send(pivot_a, "a", first_a).get("success", false)), "exact replay through accepted chain")
	check(source.create_snapshot() == after_a and handler_a.executions == 1, "exact replay does not execute M3 twice")
	var conflict := first_a.duplicate(true)
	conflict["delta_x"] = -0.25
	var conflict_result: Dictionary = send(pivot_a, "a", conflict)
	check(conflict_result.get("error_code") == "OPERATION_REPLAY_CONFLICT", "changed-payload replay rejected before P6 id-only shortcut")
	check(source.create_snapshot() == after_a, "conflicting replay changes no canonical state")
	var routed_b: Dictionary = send(pivot_b, "b", command("b", 1))
	check(bool(routed_b.get("success", false)) and handler_b.executions == 1, "B independently controls a real second M3 player")

	var carrying = Carry.new()
	check(bool(carrying.configure(registry, ledger, closure, coordinator_a).get("success", false)), "real accepted PlayerCarryingDomain configured")
	var transfer := "transfer/mvp3/bound-a-b"
	check(bool(coordinator_a.begin_transfer(transfer, "authority/a", "authority/b", 1).get("success", false)), "real SM1 source freeze")
	var frozen_a: Dictionary = source.get_player("a")
	var frozen_route: Dictionary = send(pivot_a, "a", command("a", 2))
	check(frozen_route.get("error_code") == "SM1_ROUTE_FROZEN_DURING_AUTHORITY_TRANSFER", "accepted pivot blocks A input during freeze")
	var frozen_handler: Dictionary = handler_a.execute_command(command("a", 2))
	check(frozen_handler.get("error_code") == "SM1_AUTHORITY_TRANSFER_WRITE_FENCED", "bound handler also consults accepted fence")
	check(source.get_player("a") == frozen_a, "actual canonical A state did not change while fenced")
	var b_during: Dictionary = send(pivot_b, "b", command("b", 2))
	check(bool(b_during.get("success", false)) and source.get_player("b").get("last_input_sequence") == 2, "B remains independently controllable while A is frozen")
	check(source.get_player("a") == frozen_a, "B movement does not mutate frozen A")
	check(not ledger.is_pending("player/mvp3/a", command("a", 2)["operation_id"]), "fenced input does not poison P6 pending ledger")
	var prepared: Dictionary = carrying.prepare_transfer(transfer, "client-session/mvp3/a", 1, first_a["operation_id"])
	check(bool(prepared.get("success", false)), "real carry manifest captures committed M3 operation after freeze")
	check(prepared.get("details", {}).get("manifest", {}).get("captured_after_source_freeze") == true, "carrying evidence contains freeze proof")
	var projection = Projection.new()
	check(bool(projection.configure_from_canonical_sources({"gameplay": source.create_snapshot(), "item_graph": source.create_canonical_item_graph_snapshot(), "construction": {}}).get("success", false)), "P6 read-only projection uses actual source snapshots")
	var shadow = Shadow.new()
	check(bool(shadow.configure(projection).get("success", false)), "accepted P6 read-only shadow configured")
	var warm: Dictionary = carrying.build_composite_warm_report(transfer, shadow.get_report())
	check(bool(warm.get("success", false)), "accepted carrying warm chain built")
	check(bool(coordinator_a.validate_warm_target(transfer, "authority/b", warm.get("details", {}).get("warm_report", {})).get("success", false)), "existing SM1 validates its control-plane warm evidence")

	# This is the EXACT remaining boundary: control-plane warm proof is not
	# live M3 player staging. Do not activate B on the strength of a projection.
	var target_ready: Dictionary = target_a.readiness()
	check(target_ready.get("error_code") == "MVP3_CANONICAL_PLAYER_NOT_STAGED", "real target has no staged live canonical player")
	var restore_attempt: Dictionary = target.restore_durable_state(source.export_durable_state())
	check(restore_attempt.get("error_code") == "GAMEPLAY_RECOVERY_OWNER_MISMATCH", "restart restore cannot supply the missing live staging hook")
	check(target.get_player("a").is_empty(), "failed restore did not create target player")
	check(coordinator_a.snapshot().get("state") == "TARGET_WARM_VALIDATED", "no ownership commit or target activation invented")
	check(pivot_a.get_client_route_identity() == identity, "gateway endpoint/session remain unchanged")
	var source_before_abort: Dictionary = source.create_snapshot()
	check(bool(coordinator_a.abort_before_commit(transfer, "authority/a").get("success", false)), "existing SM1 safely aborts before missing data-plane staging")
	check(source.create_snapshot() == source_before_abort, "control-plane abort does not rewrite canonical player state")
	check(bool(send(pivot_a, "a", command("a", 2)).get("success", false)), "A can continue through real route after safe abort")
	check(source.get_player("a").get("last_input_sequence") == 2, "A input sequence continues without rejoin")
	check(source.get_player("b").get("last_input_sequence") == 2, "B input sequence remains intact")
	check(registry.get_report().get("counters", {}).get("rebinds", -1) == 0, "no P6 identity rebind occurred")
	evidence.merge({"assertions": assertions, "failures": failures, "diagnostic_status": "BOUND_ROUTE_AND_STAGING_GAP_REPRODUCED" if failures.is_empty() else "DIAGNOSTIC_FAILED", "initial": initial, "final": source.create_snapshot(), "target_snapshot": target.create_snapshot(), "a_route_result": routed_a, "b_route_result": routed_b, "a_frozen_route": frozen_route, "a_frozen_handler": frozen_handler, "b_during_a_freeze": b_during, "conflicting_replay": conflict_result, "carry_prepare": prepared, "warm_evidence": warm, "target_readiness": target_ready, "restart_restore_attempt": restore_attempt, "final_coordinator": coordinator_a.snapshot(), "client_route_before": identity, "client_route_after": pivot_a.get_client_route_identity(), "alias_mapping": {"a": {"logical_player_id": "a", "player_entity_id": "player/a", "p6_logical_alias": "player/mvp3/a", "p6_entity_alias": "entity/mvp3/a"}, "b": {"logical_player_id": "b", "player_entity_id": "player/b", "p6_logical_alias": "player/mvp3/b", "p6_entity_alias": "entity/mvp3/b"}}, "scope": "TEST_ONLY_BOUND_PUBLIC_COMMAND_PORTS; DOES_NOT_PROVE_M3_FIXED_TICK_OR_PROCESS_NETWORK_INTEGRATION"})
	source.shutdown()
	target.shutdown()
	var saved: Dictionary = AtomicJson.write_dictionary(OS.get_environment("DWS_MVP3_BOUND_OUTPUT"), evidence)
	print("MVP3_BOUND_SM1_M3_ROUTE assertions=%d failures=%d product_verified=false" % [assertions, failures.size()])
	quit(0 if failures.is_empty() and bool(saved.get("success", false)) else 1)

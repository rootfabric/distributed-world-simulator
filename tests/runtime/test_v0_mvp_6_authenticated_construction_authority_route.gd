extends "res://tests/runtime/test_v0_mvp_6_cross_authority_prerequisites.gd"

const AuthenticatedEndpoint6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_authenticated_construction_authority_endpoint.gd")

var actor_route_observations: Dictionary = {}


func exercise_authenticated_actor_route() -> bool:
	if not setup6(): return false
	if not seed6(): return false
	var owner = state["owners"]["authority/a"]
	var graph = owner.get_canonical_item_graph_port()
	if not success(owner.apply_canonical_server_output(
		"operation/mvp6/actor-route/extra", "a", "item/ore", 3,
		"source/mvp6/actor-route"
	), "eight real native ore units for authenticated C17 route"): return false
	var ore_id := String(receipts6["a"]["ore"]["details"]["output_item_id"])
	if not success(native_command6("a", "actor-route-stage-ore", "item.transfer", {
		"item_id": ore_id,
		"quantity": 5,
		"target_container_id": "inventory/a",
		"target_slot_index": -1,
	}), "native ore staged for C17 BUILD"): return false
	if not check(ore6(graph.create_snapshot(), "a") == 8, "authenticated C17 route starts with exact eight ore"): return false

	var fixture := fresh_factory_seam("authenticated-c17")
	if fixture.is_empty(): return false
	var bridge = fixture["bridge"]
	var native_gateway = fixture["detail"]["gateway"]
	var witness = NativeSnapshotWitness.new(fixture["detail"]["authoritative_adapter"])
	var endpoint = AuthenticatedEndpoint6.new()
	if not success(endpoint.setup("server/mvp6/a", "cell/mvp6/a", native_gateway, witness), "authenticated C17 endpoint delegates existing owner"): return false
	var routing_session: Dictionary = bridge.get_player_session("a")
	if not success(endpoint.bind_authenticated_player("a", routing_session), "bind authenticated M3 player to C17 route"): return false
	var report: Dictionary = endpoint.get_route_report()
	if not check(report.get("bound_actor_ids", []) == ["a"] and int(report.get("binding_count", 0)) == 1, "C17 adapter records one routing binding"): return false
	if not check(
		not bool(report.get("canonical_construction_owned", true))
		and not bool(report.get("session_store_owned", true))
		and not bool(report.get("permission_store_owned", true))
		and not bool(report.get("terminal_replay_owned", true)),
		"C17 adapter owns no canonical or replay truth"
	): return false

	var bundle: Dictionary = bridge.get_snapshot_packet()["state_bundle"]
	var command := construction_command6(fixture["session"], 0, "actor-route-build-0", 0, bundle)
	if not success(ConstructionCommand6.validate(command), "authenticated route BUILD command validates"): return false
	var before_items: Dictionary = graph.create_snapshot()
	var before_bundle: Dictionary = native_gateway.get_state_bundle()
	var accepted: Dictionary = endpoint.submit(command)
	if not success(accepted, "C17 endpoint preserves authenticated actor context into P4 BUILD"): return false
	if not check(ore6(graph.create_snapshot(), "a") == 6, "C17 BUILD consumes exactly two canonical ore"): return false
	if not check(witness.transfer_calls == 0, "C17 command routing does not invoke transfer backend"): return false

	var after_first_items: Dictionary = graph.create_snapshot()
	var after_first_bundle: Dictionary = native_gateway.get_state_bundle()
	var replay: Dictionary = endpoint.submit(command)
	if not success(replay, "C17 exact BUILD replay succeeds terminally"): return false
	if not check(bool(replay.get("replay", false)), "C17 exact BUILD replay is marked replay"): return false
	if not check(graph.create_snapshot() == after_first_items, "C17 replay cannot spend material twice"): return false
	if not check(native_gateway.get_state_bundle() == after_first_bundle, "C17 replay cannot publish duplicate Construction state"): return false

	var unbound_command := ConstructionCommand6.create(
		"multiplayer-command/mvp6/actor-route/unbound",
		"client/m3/unbound",
		"session/m3/unbound/1",
		1,
		0,
		ConstructionGrant6.ACTION_BUILD,
		ConstructionAuthority6.CONSTRUCT_ID,
		construct_checksum6(after_first_bundle),
		int(after_first_bundle.get("server_generation", 0)),
		int(fixture["session"].get("permission_epoch", 0)),
		Dictionary(command.get("payload", {})).duplicate(true)
	)
	if not success(ConstructionCommand6.validate(unbound_command), "unbound route negative is a valid command envelope"): return false
	var before_unbound_items: Dictionary = graph.create_snapshot()
	var before_unbound_bundle: Dictionary = native_gateway.get_state_bundle()
	var unbound: Dictionary = endpoint.submit(unbound_command)
	if not check(
		not bool(unbound.get("success", false))
		and String(unbound.get("error_code", "")) == "MVP6_CONSTRUCTION_ACTOR_ROUTE_NOT_BOUND",
		"unbound C17 session is rejected before canonical gateway mutation"
	): return false
	if not check(graph.create_snapshot() == before_unbound_items, "unbound C17 route cannot mutate Item Graph"): return false
	if not check(native_gateway.get_state_bundle() == before_unbound_bundle, "unbound C17 route cannot mutate Construction bundle"): return false

	actor_route_observations = {
		"route_report": report,
		"command": command,
		"accepted": accepted,
		"replay": replay,
		"unbound_result": unbound,
		"items_before": before_items,
		"bundle_before": before_bundle,
		"items_after": after_first_items,
		"bundle_after": after_first_bundle,
		"transfer_calls": witness.transfer_calls,
	}
	return true


func run() -> void:
	var okay := exercise_authenticated_actor_route()
	var report := {
		"schema": "distributed_world_simulator.mvp6_authenticated_c17_route_test.v1",
		"subject_head": OS.get_environment("EXPECTED_HEAD"),
		"subject_tree": OS.get_environment("EXPECTED_TREE"),
		"passed": okay and failures.is_empty(),
		"assertions": assertions,
		"failures": failures,
		"observations": actor_route_observations,
		"authenticated_actor_context_preserved": okay and failures.is_empty(),
		"terminal_replay_preserved": okay and failures.is_empty(),
		"unbound_session_rejected": okay and failures.is_empty(),
		"canonical_owner_duplicated": false,
		"cross_authority_construction_seam_verified": false,
		"mvp6_predicate_verified": false,
		"independent_verdict": false,
	}
	cleanup6()
	var output := OS.get_environment("MVP6_C17_ROUTE_RESULT")
	var saved := output.is_empty()
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_AUTHENTICATED_C17_ROUTE assertions=%d failures=%d passed=%s" % [assertions, failures.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

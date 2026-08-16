extends SceneTree

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const RouteContract = preload("res://scripts/runtime/seamless/sm0/sm0_p7_route_contract.gd")
const RouterNode = preload("res://scripts/runtime/seamless/sm0/sm0_p7_router_node.gd")

var _assertions := 0
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failed = true
		push_error("ASSERTION FAILED: %s" % message)


func _payload(revision: int, x: float) -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"state_revision": revision,
		"position": {"x": x, "y": 0.0, "z": 0.0},
	}


func _run() -> void:
	var route_ac := Topology.plan_route(Topology.AUTHORITY_A, Topology.AUTHORITY_C)
	_assert_true(route_ac == [Topology.AUTHORITY_A, Topology.AUTHORITY_B, Topology.AUTHORITY_C], "A->C route must traverse B")
	var route_ca := Topology.plan_route(Topology.AUTHORITY_C, Topology.AUTHORITY_A)
	_assert_true(route_ca == [Topology.AUTHORITY_C, Topology.AUTHORITY_B, Topology.AUTHORITY_A], "C->A route must traverse B")
	_assert_true(Topology.plan_route(Topology.AUTHORITY_A, Topology.AUTHORITY_B) == [Topology.AUTHORITY_A, Topology.AUTHORITY_B], "A->B must be direct")
	_assert_true(Topology.plan_route(Topology.AUTHORITY_B, Topology.AUTHORITY_B) == [Topology.AUTHORITY_B], "B->B must be local")
	_assert_true(not Topology.are_adjacent(Topology.AUTHORITY_A, Topology.AUTHORITY_C), "A and C must not be adjacent")
	_assert_true(Topology.are_adjacent(Topology.AUTHORITY_A, Topology.AUTHORITY_B), "A and B must be adjacent")
	_assert_true(Topology.are_adjacent(Topology.AUTHORITY_B, Topology.AUTHORITY_C), "B and C must be adjacent")

	var valid := RouteContract.create_probe("route/contract/ac", Topology.AUTHORITY_A, Topology.AUTHORITY_C, 4, _payload(7, -2.0))
	_assert_true(bool(RouteContract.validate(valid).get("success", false)), "valid route envelope must validate")
	_assert_true(RouteContract.current_authority(valid) == Topology.AUTHORITY_A, "origin current authority must be A")
	var at_b := RouteContract.advance(valid)
	_assert_true(RouteContract.current_authority(at_b) == Topology.AUTHORITY_B, "advanced current authority must be B")
	_assert_true(RouteContract.previous_authority(at_b) == Topology.AUTHORITY_A, "B previous authority must be A")
	_assert_true(RouteContract.next_authority(at_b) == Topology.AUTHORITY_C, "B next authority must be C")
	var at_c := RouteContract.advance(at_b)
	_assert_true(RouteContract.current_authority(at_c) == Topology.AUTHORITY_C, "second advance must arrive at C")
	_assert_true(RouteContract.next_authority(at_c).is_empty(), "destination must not have a next hop")

	var non_adjacent := valid.duplicate(true)
	non_adjacent["route_path"] = [Topology.AUTHORITY_A, Topology.AUTHORITY_C]
	non_adjacent = Utils.finalize_json_checksum(non_adjacent)
	_assert_true(String(RouteContract.validate(non_adjacent).get("error_code", "")) == "SM0_P7_ROUTE_NON_ADJACENT_HOP", "non-adjacent A->C must fail closed")
	var looped := valid.duplicate(true)
	looped["route_path"] = [Topology.AUTHORITY_A, Topology.AUTHORITY_B, Topology.AUTHORITY_A, Topology.AUTHORITY_C]
	looped = Utils.finalize_json_checksum(looped)
	_assert_true(String(RouteContract.validate(looped).get("error_code", "")) == "SM0_P7_ROUTE_LOOP_FORBIDDEN", "routing loop must fail closed")
	var payload_mutated := valid.duplicate(true)
	payload_mutated["payload"]["state_revision"] = 8
	_assert_true(String(RouteContract.validate(payload_mutated).get("error_code", "")) == "SM0_P7_ROUTE_PAYLOAD_HASH_MISMATCH", "payload mutation without rebind must fail")
	var checksum_mutated := valid.duplicate(true)
	checksum_mutated["hop_index"] = 1
	_assert_true(String(RouteContract.validate(checksum_mutated).get("error_code", "")) == "SM0_P7_ROUTE_CHECKSUM_MISMATCH", "hop mutation without checksum must fail")

	var a := RouterNode.new()
	var b := RouterNode.new()
	var c := RouterNode.new()
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	var a_setup := a.setup({
		"authority_id": Topology.AUTHORITY_A,
		"zone_id": Topology.ZONE_A,
		"listen_port": 26210,
		"neighbor_endpoints": {Topology.AUTHORITY_B: {"host": "127.0.0.1", "port": 26211}},
	})
	var b_setup := b.setup({
		"authority_id": Topology.AUTHORITY_B,
		"zone_id": Topology.ZONE_B,
		"listen_port": 26211,
		"neighbor_endpoints": {
			Topology.AUTHORITY_A: {"host": "127.0.0.1", "port": 26210},
			Topology.AUTHORITY_C: {"host": "127.0.0.1", "port": 26212},
		},
	})
	var c_setup := c.setup({
		"authority_id": Topology.AUTHORITY_C,
		"zone_id": Topology.ZONE_C,
		"listen_port": 26212,
		"neighbor_endpoints": {Topology.AUTHORITY_B: {"host": "127.0.0.1", "port": 26211}},
	})
	_assert_true(bool(a_setup.get("success", false)), "router A must start")
	_assert_true(bool(b_setup.get("success", false)), "router B must start")
	_assert_true(bool(c_setup.get("success", false)), "router C must start")
	_assert_true(int(a.status_for_tests().get("writer_count", -1)) == 0, "router A must never be a gameplay writer")
	_assert_true(int(b.status_for_tests().get("writer_count", -1)) == 0, "router B must never be a gameplay writer")
	_assert_true(int(c.status_for_tests().get("writer_count", -1)) == 0, "router C must never be a gameplay writer")

	var ac_id := "route/runtime/a-c"
	_assert_true(bool(a.originate_probe(Topology.AUTHORITY_C, ac_id, 5, _payload(11, -1.0)).get("success", false)), "A must originate A->C")
	for _i in range(12): await process_frame
	var c_deliveries: Dictionary = Dictionary(c.status_for_tests().get("deliveries", {}))
	_assert_true(c_deliveries.has(ac_id), "C must receive A->C route")
	var ac_delivery: Dictionary = Dictionary(c_deliveries.get(ac_id, {}))
	_assert_true(Array(ac_delivery.get("route_path", [])) == [Topology.AUTHORITY_A, Topology.AUTHORITY_B, Topology.AUTHORITY_C], "A->C delivered path must be A-B-C")
	_assert_true(String(Dictionary(ac_delivery.get("payload", {})).get("player_entity_id", "")) == "player/a", "A->C must preserve player identity")
	_assert_true(int(b.status_for_tests().get("forwarded_count", 0)) >= 1, "B must forward A->C")

	var ca_id := "route/runtime/c-a"
	_assert_true(bool(c.originate_probe(Topology.AUTHORITY_A, ca_id, 6, _payload(12, 1.0)).get("success", false)), "C must originate C->A")
	for _i in range(12): await process_frame
	var a_deliveries: Dictionary = Dictionary(a.status_for_tests().get("deliveries", {}))
	_assert_true(a_deliveries.has(ca_id), "A must receive C->A route")
	var ca_delivery: Dictionary = Dictionary(a_deliveries.get(ca_id, {}))
	_assert_true(Array(ca_delivery.get("route_path", [])) == [Topology.AUTHORITY_C, Topology.AUTHORITY_B, Topology.AUTHORITY_A], "C->A delivered path must be C-B-A")
	_assert_true(int(b.status_for_tests().get("forwarded_count", 0)) >= 2, "B must forward both long routes")

	var ab_id := "route/runtime/a-b"
	_assert_true(bool(a.originate_probe(Topology.AUTHORITY_B, ab_id, 7, _payload(13, -0.5)).get("success", false)), "A must originate direct A->B")
	for _i in range(8): await process_frame
	var b_deliveries: Dictionary = Dictionary(b.status_for_tests().get("deliveries", {}))
	_assert_true(b_deliveries.has(ab_id), "B must receive direct A->B")
	_assert_true(Array(Dictionary(b_deliveries.get(ab_id, {})).get("route_path", [])) == [Topology.AUTHORITY_A, Topology.AUTHORITY_B], "direct delivery path must be A-B")

	var replay_original := RouteContract.advance(RouteContract.create_probe(ac_id, Topology.AUTHORITY_A, Topology.AUTHORITY_C, 5, _payload(11, -1.0)))
	var replay_result := b.accept_envelope_for_tests(replay_original, Topology.AUTHORITY_A)
	_assert_true(bool(replay_result.get("success", false)), "exact route replay must be accepted idempotently")
	_assert_true(int(b.status_for_tests().get("replay_count", 0)) >= 1, "B must record exact replay")
	var conflict := RouteContract.advance(RouteContract.create_probe(ac_id, Topology.AUTHORITY_A, Topology.AUTHORITY_C, 5, _payload(99, -1.0)))
	var conflict_result := b.accept_envelope_for_tests(conflict, Topology.AUTHORITY_A)
	_assert_true(String(conflict_result.get("error_code", "")) == "SM0_P7_ROUTE_REPLAY_CONFLICT", "same route id with different payload must fail closed")
	var wrong_hop := RouteContract.create_probe("route/runtime/wrong-hop", Topology.AUTHORITY_A, Topology.AUTHORITY_C, 8, _payload(14, 0.0))
	var wrong_hop_result := b.accept_envelope_for_tests(wrong_hop, Topology.AUTHORITY_A)
	_assert_true(String(wrong_hop_result.get("error_code", "")) == "SM0_P7_ROUTE_CURRENT_HOP_MISMATCH", "router must reject envelope addressed to another current hop")

	a.shutdown(0, "test-complete")
	b.shutdown(0, "test-complete")
	c.shutdown(0, "test-complete")
	if _failed:
		print("SM0 P7 three-authority routing: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 P7 three-authority routing: PASS (%d assertions)" % _assertions)
	quit(0)

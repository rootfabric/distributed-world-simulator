extends SceneTree

const Topology = preload("res://scripts/runtime/seamless/sm0/sm0_p7_three_authority_topology.gd")
const TransferContract = preload("res://scripts/runtime/seamless/sm0/sm0_p7_1_transfer_contract.gd")
const HandoffNode = preload("res://scripts/runtime/seamless/sm0/sm0_p7_1_canonical_handoff_node.gd")
const EXPECTED_ASSERTIONS := 53

var _assertions := 0
var _failed := false


func _init() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failed = true
		push_error("ASSERTION FAILED: %s" % message)


func _package(revision: int = 5, sequence: int = 3, x: float = -2.0) -> Dictionary:
	return {
		"logical_player_id": "a",
		"player_entity_id": "player/a",
		"state_revision": revision,
		"last_input_sequence": sequence,
		"position": {"x": x, "y": 0.0, "z": 0.0},
		"velocity": {"x": 0.25, "y": 0.0, "z": 0.0},
		"orientation_yaw": 0.5,
	}


func _wait_owner(node: Node, owner: String, max_frames: int = 120) -> bool:
	for _i in range(max_frames):
		if String(node.status_for_tests().get("owner_authority_id", "")) == owner and int(node.status_for_tests().get("writer_count", 0)) == (1 if owner == String(node.status_for_tests().get("authority_id", "")) else 0):
			return true
		await process_frame
	return false


func _run() -> void:
	var package := _package()
	var prepare := TransferContract.create(
		"route/p7-1/prepare", "handoff/p7-1/a-c/2/1", TransferContract.PHASE_PREPARE,
		Topology.AUTHORITY_A, Topology.AUTHORITY_C, 1, 2, package
	)
	_assert_true(bool(TransferContract.validate(prepare).get("success", false)), "valid PREPARE must validate")
	_assert_true(Array(prepare.get("route_path", [])) == [Topology.AUTHORITY_A, Topology.AUTHORITY_B, Topology.AUTHORITY_C], "A->C PREPARE must route through B")
	_assert_true(TransferContract.current_authority(prepare) == Topology.AUTHORITY_A, "PREPARE origin must be A")
	var prepare_b := TransferContract.advance(prepare)
	_assert_true(TransferContract.current_authority(prepare_b) == Topology.AUTHORITY_B, "advanced PREPARE must be at B")
	_assert_true(TransferContract.next_authority(prepare_b) == Topology.AUTHORITY_C, "B must route PREPARE to C")
	var proof := TransferContract.create_retire_proof("handoff/p7-1/a-c/2/1", String(prepare.get("package_hash", "")), 1, 2)
	var commit := TransferContract.create(
		"route/p7-1/commit", "handoff/p7-1/a-c/2/1", TransferContract.PHASE_COMMIT,
		Topology.AUTHORITY_A, Topology.AUTHORITY_C, 1, 2, package, proof
	)
	_assert_true(bool(TransferContract.validate(commit).get("success", false)), "COMMIT with retirement proof must validate")
	var premature := TransferContract.create(
		"route/p7-1/premature", "handoff/p7-1/a-c/2/2", TransferContract.PHASE_PREPARE,
		Topology.AUTHORITY_A, Topology.AUTHORITY_C, 1, 2, package, proof
	)
	_assert_true(String(TransferContract.validate(premature).get("error_code", "")) == "SM0_P7_1_RETIRE_PROOF_PREMATURE", "PREPARE must reject premature retirement proof")
	var bad_commit := commit.duplicate(true)
	bad_commit["retire_proof"] = "bad-proof"
	_assert_true(String(TransferContract.validate(bad_commit).get("error_code", "")) == "SM0_P7_1_RETIRE_PROOF_INVALID", "COMMIT must reject invalid retirement proof")
	var wrong_epoch := TransferContract.create(
		"route/p7-1/wrong-epoch", "handoff/p7-1/a-c/4/1", TransferContract.PHASE_PREPARE,
		Topology.AUTHORITY_A, Topology.AUTHORITY_C, 1, 4, package
	)
	_assert_true(String(TransferContract.validate(wrong_epoch).get("error_code", "")) == "SM0_P7_1_TRANSFER_EPOCH_INVALID", "target epoch must be source+1")

	var a := HandoffNode.new()
	var b := HandoffNode.new()
	var c := HandoffNode.new()
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	var a_setup := a.setup({
		"authority_id": Topology.AUTHORITY_A,
		"zone_id": Topology.ZONE_A,
		"listen_port": 26310,
		"neighbor_endpoints": {Topology.AUTHORITY_B: {"host": "127.0.0.1", "port": 26311}},
	})
	var b_setup := b.setup({
		"authority_id": Topology.AUTHORITY_B,
		"zone_id": Topology.ZONE_B,
		"listen_port": 26311,
		"neighbor_endpoints": {
			Topology.AUTHORITY_A: {"host": "127.0.0.1", "port": 26310},
			Topology.AUTHORITY_C: {"host": "127.0.0.1", "port": 26312},
		},
	})
	var c_setup := c.setup({
		"authority_id": Topology.AUTHORITY_C,
		"zone_id": Topology.ZONE_C,
		"listen_port": 26312,
		"neighbor_endpoints": {Topology.AUTHORITY_B: {"host": "127.0.0.1", "port": 26311}},
	})
	_assert_true(bool(a_setup.get("success", false)), "A endpoint must start")
	_assert_true(bool(b_setup.get("success", false)), "B transit must start")
	_assert_true(bool(c_setup.get("success", false)), "C endpoint must start")
	_assert_true(int(a.status_for_tests().get("writer_count", 0)) == 1, "A must start as sole writer")
	_assert_true(int(b.status_for_tests().get("writer_count", -1)) == 0, "B must start writer-free")
	_assert_true(int(c.status_for_tests().get("writer_count", -1)) == 0, "C must start writer-free")
	_assert_true(not bool(b.status_for_tests().get("authority_present", true)), "B must not instantiate gameplay authority")
	_assert_true(bool(b.status_for_tests().get("transit_only", false)), "B must be transit-only")
	_assert_true(String(Dictionary(a.status_for_tests().get("player", {})).get("player_entity_id", "")) == "player/a", "A canonical identity must be player/a")
	_assert_true(String(c.move_owner_for_tests(0.5, 0.0).get("error_code", "")) == "SM0_P7_1_NOT_MUTABLE_OWNER", "C cannot mutate before ownership")
	_assert_true(String(b.begin_transfer_for_tests(Topology.AUTHORITY_C).get("error_code", "")) == "SM0_P7_1_TRANSIT_CANNOT_OWN", "B cannot originate canonical handoff")

	var moved_a := a.move_owner_for_tests(0.75, 0.0)
	_assert_true(bool(moved_a.get("success", false)), "A canonical owner must move before transfer")
	var a_before: Dictionary = Dictionary(moved_a.get("details", {}).get("player", {}))
	var outbound := a.begin_transfer_for_tests(Topology.AUTHORITY_C)
	_assert_true(bool(outbound.get("success", false)), "A must originate canonical A->C handoff")
	_assert_true(int(a.status_for_tests().get("writer_count", -1)) == 0, "A must be frozen and writer-free after PREPARE starts")
	_assert_true(not String(a.status_for_tests().get("frozen_transfer_id", "")).is_empty(), "A must expose frozen transfer id")
	_assert_true(await _wait_owner(c, Topology.AUTHORITY_C), "C must become canonical owner")
	for _i in range(12): await process_frame
	var a_mid := a.status_for_tests()
	var b_mid := b.status_for_tests()
	var c_mid := c.status_for_tests()
	_assert_true(String(a_mid.get("owner_authority_id", "")) == Topology.AUTHORITY_C, "A directory must converge to C owner")
	_assert_true(int(a_mid.get("writer_count", -1)) == 0, "A must have no writer after outbound commit")
	_assert_true(int(c_mid.get("writer_count", 0)) == 1, "C must be sole canonical writer after outbound commit")
	_assert_true(int(b_mid.get("writer_count", -1)) == 0, "B must remain writer-free during handoff")
	_assert_true(not bool(b_mid.get("authority_present", true)), "B must remain without gameplay authority during handoff")
	var c_player: Dictionary = Dictionary(c_mid.get("player", {}))
	_assert_true(String(c_player.get("player_entity_id", "")) == String(a_before.get("player_entity_id", "")), "A->C must preserve player_entity_id")
	_assert_true(int(c_player.get("last_input_sequence", -1)) >= int(a_before.get("last_input_sequence", 0)), "A->C must preserve input sequence")
	_assert_true(absf(float(Dictionary(c_player.get("position", {})).get("x", 0.0)) - float(Dictionary(a_before.get("position", {})).get("x", 0.0))) < 0.000001, "A->C must preserve position")
	_assert_true(int(b_mid.get("forwarded_count", 0)) >= 4, "B must forward all four outbound protocol phases")
	_assert_true(int(b_mid.get("rejected_count", 0)) == 0, "B must have no routing rejection on valid outbound handoff")

	var moved_c := c.move_owner_for_tests(0.5, 0.0)
	_assert_true(bool(moved_c.get("success", false)), "C canonical owner must move before return")
	var c_before_return: Dictionary = Dictionary(moved_c.get("details", {}).get("player", {}))
	var inbound := c.begin_transfer_for_tests(Topology.AUTHORITY_A)
	_assert_true(bool(inbound.get("success", false)), "C must originate canonical C->A handoff")
	_assert_true(int(c.status_for_tests().get("writer_count", -1)) == 0, "C must freeze before return commit")
	_assert_true(await _wait_owner(a, Topology.AUTHORITY_A), "A must regain canonical ownership")
	for _i in range(12): await process_frame
	var a_final := a.status_for_tests()
	var b_final := b.status_for_tests()
	var c_final := c.status_for_tests()
	_assert_true(int(a_final.get("writer_count", 0)) == 1, "A must finish as sole writer")
	_assert_true(int(c_final.get("writer_count", -1)) == 0, "C must finish writer-free")
	_assert_true(int(b_final.get("writer_count", -1)) == 0, "B must remain writer-free after round trip")
	_assert_true(String(a_final.get("owner_authority_id", "")) == Topology.AUTHORITY_A, "A must finish as directory owner")
	_assert_true(int(a_final.get("authority_epoch", 0)) == 3, "round trip must advance authority epoch 1->2->3")
	_assert_true(int(c_final.get("authority_epoch", 0)) == 3, "C directory must converge to epoch 3")
	var a_player_final: Dictionary = Dictionary(a_final.get("player", {}))
	_assert_true(String(a_player_final.get("player_entity_id", "")) == "player/a", "round trip must preserve player/a identity")
	_assert_true(int(a_player_final.get("last_input_sequence", -1)) >= int(c_before_return.get("last_input_sequence", 0)), "return must preserve monotonic input sequence")
	_assert_true(absf(float(Dictionary(a_player_final.get("position", {})).get("x", 0.0)) - float(Dictionary(c_before_return.get("position", {})).get("x", 0.0))) < 0.000001, "return must preserve latest C position")
	_assert_true(int(b_final.get("forwarded_count", 0)) >= 8, "B must forward both four-phase handoffs")
	_assert_true(int(b_final.get("rejected_count", 0)) == 0, "B must remain rejection-free for valid round trip")
	_assert_true(int(a_final.get("completed_transfer_count", 0)) >= 1, "A must record committed inbound transfer")
	_assert_true(int(c_final.get("completed_transfer_count", 0)) >= 1, "C must record committed inbound transfer")
	_assert_true(String(a.move_owner_for_tests(0.1, 0.0).get("error_code", "")) != "SM0_P7_1_NOT_MUTABLE_OWNER", "final A owner must be mutable")

	a.shutdown(0, "test-complete")
	b.shutdown(0, "test-complete")
	c.shutdown(0, "test-complete")
	if _assertions != EXPECTED_ASSERTIONS:
		_failed = true
		push_error("ASSERTION COUNT MISMATCH: expected %d got %d" % [EXPECTED_ASSERTIONS, _assertions])
	if _failed:
		print("SM0 P7.1 routed canonical handoff: FAIL (%d assertions)" % _assertions)
		quit(1)
		return
	print("SM0 P7.1 routed canonical handoff: PASS (%d assertions)" % _assertions)
	quit(0)
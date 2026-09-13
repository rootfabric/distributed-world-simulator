extends SceneTree

# Real canonical owner tests. This is neither a manual input run nor an
# independent acceptance verdict. No private fields or replacement owner.
const FixedService = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_fixed_tick_gameplay_service.gd")
const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

var assertions := 0
var failures: Array[String] = []
var owned_services: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures.append(label)
		push_error(label)
	return value

func ok(result: Dictionary, label: String) -> bool:
	return check(bool(result.get("success", false)), label + ": " + String(result.get("error_code", "")))

func fixture() -> Dictionary:
	var owner = FixedService.new()
	owned_services.append(owner)
	if not ok(owner.setup("authority/a", 1, 0, {"profile": FixedService.PROFILE_MULTIPLAYER_CORE, "fixed_tick_authority": true, "region_id": "region/mvp3/fixed-contract"}), "canonical fixed owner setup"):
		return {}
	var decisions: Dictionary = {}
	for actor in ["a", "b"]:
		if not ok(owner.join(actor, "transport-session/mvp3/fixed/" + actor, "operation/mvp3/fixed/join/" + actor), "canonical join " + actor):
			return {}
		var decision = Coordinator.new()
		if not ok(decision.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "accepted decision " + actor):
			return {}
		decisions[actor] = decision
		if not ok(owner.get_live_player_transfer_port().bind_player(actor, "transport-session/mvp3/fixed/" + actor, 1, decision), "live owner binding " + actor):
			return {}
	return {"owner": owner, "decisions": decisions}

func command(actor: String, sequence: int, suffix: String = "", axis: float = 1.0) -> Dictionary:
	var operation := "operation/mvp3/fixed/%s/%d%s" % [actor, sequence, suffix]
	return InputDTO.create("message/mvp3/fixed/%s/%d%s" % [actor, sequence, suffix], operation, actor, "transport-session/mvp3/fixed/" + actor, 1, 1, sequence, "MOVEMENT_INTENT", {"move_x": axis, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false, "delta_seconds": 1.0 / 60.0})

func next_tick(owner) -> bool:
	return ok(owner.advance_fixed_server_tick(int(owner.get_report().get("server_tick", -1)) + 1), "canonical next fixed tick")

func run() -> void:
	var regular := fixture()
	var flooded := fixture()
	if regular.is_empty() or flooded.is_empty():
		finish()
		return
	var normal = regular["owner"]
	var burst = flooded["owner"]
	var initial_normal: Dictionary = normal.get_player("a")
	var initial_burst: Dictionary = burst.get_player("a")
	check(initial_normal == initial_burst, "rate comparison starts from identical canonical records")
	var baseline_graph: Dictionary = burst.create_canonical_item_graph_snapshot()
	for tick in range(1, 61):
		if not next_tick(normal) or not next_tick(burst):
			break
		var wire := command("a", tick)
		var normal_result: Dictionary = normal.handle_live_fixed_player_input(wire, 1.0 / 60.0)
		var burst_result: Dictionary = burst.handle_live_fixed_player_input(wire, 1.0 / 60.0)
		if not ok(normal_result, "regular fixed input") or not ok(burst_result, "flood baseline fixed input"):
			break
		check(burst_result.get("details", {}).get("server_simulation", {}).get("fixed_tick") == true, "receipt comes from actual fixed simulation")
		var after: Dictionary = burst.get_player("a")
		var replay: Dictionary = burst.handle_live_fixed_player_input(wire, 1.0 / 60.0)
		check(bool(replay.get("success", false)) and bool(replay.get("replay", false)) and burst.get_player("a") == after, "exact replay does not add displacement or revision")
		for packet in range(8):
			var excessive: Dictionary = burst.handle_live_fixed_player_input(command("a", 10000 + tick * 10 + packet, "-flood"), 1.0 / 60.0)
			check(excessive.get("error_code") == "LIVE_FIXED_INPUT_TICK_ALREADY_CONSUMED", "packet burst cannot create extra physics steps")
		check(burst.get_player("a") == after, "packet flood leaves canonical state unchanged")
	check(normal.get_player("a") == burst.get_player("a"), "60 regular and burst-loaded ticks yield byte-equal player state")
	var movement := float(burst.get_player("a").get("position", {}).get("x", 0.0)) - float(initial_burst.get("position", {}).get("x", 0.0))
	check(is_equal_approx(movement, 6.0), "one second of 60 Hz walking covers exactly six metres")
	var before_bad: Dictionary = burst.get_player("a")
	check(burst.handle_live_fixed_player_input(command("a", 61), 1.0).get("error_code") == "INVALID_FIXED_TICK_DELTA", "caller cannot scale canonical dt")
	var conflict := command("a", 60, "", -1.0)
	check(burst.handle_live_fixed_player_input(conflict, 1.0 / 60.0).get("error_code") == "OPERATION_REPLAY_CONFLICT", "same operation with different direction is rejected")
	var corrupt := command("a", 61)
	corrupt["payload"]["move_x"] = -1.0
	check(not bool(burst.handle_live_fixed_player_input(corrupt, 1.0 / 60.0).get("success", false)), "corrupted checksum is rejected")
	check(burst.get_player("a") == before_bad, "invalid dt replay and checksum controls cannot mutate state")
	if next_tick(burst):
		var stale: Dictionary = burst.handle_live_fixed_player_input(command("a", 60, "-new-operation"), 1.0 / 60.0)
		check(stale.get("error_code") == "STALE_INPUT_SEQUENCE", "fresh operation cannot disguise stale input")
		var stale_receipt: Dictionary = burst.export_live_player_replay("a").get(command("a", 60, "-new-operation")["operation_id"], {})
		check(stale_receipt.get("result", {}).get("success") == false, "rejected input remains a rejected canonical receipt")
	var freeze: Dictionary = flooded["decisions"]["a"].begin_transfer("transfer/mvp3/fixed/fence", "authority/a", "authority/b", 1)
	if ok(freeze, "real accepted freeze") and next_tick(burst):
		var frozen_record: Dictionary = burst.get_player("a")
		var denied: Dictionary = burst.handle_live_fixed_player_input(command("a", 61), 1.0 / 60.0)
		check(denied.get("error_code") == "LIVE_PLAYER_AUTHORITY_NOT_READY", "new fixed receipt cannot bypass frozen owner")
		var direct: Dictionary = burst.simulate_fixed_movement_tick("a", "transport-session/mvp3/fixed/a", 1, 61, command("a", 61)["payload"], 1.0 / 60.0)
		check(not bool(direct.get("success", false)), "direct fixed owner method is also fenced")
		check(burst.get_player("a") == frozen_record, "frozen actor snapshot stays unchanged")
		ok(burst.handle_live_fixed_player_input(command("b", 1), 1.0 / 60.0), "other player remains independently writable")
	check(burst.create_canonical_item_graph_snapshot() == baseline_graph, "fixed movement never migrates or mutates the Item Graph")
	finish()

func finish() -> void:
	for owner in owned_services:
		owner.shutdown()
	var report := {"schema": "distributed_world_simulator.mvp3_fixed_input_contract.v1", "passed": failures.is_empty(), "assertions": assertions, "failures": failures, "manual_input_executed": false, "independent_verdict": false}
	var path := OS.get_environment("MVP3_FIXED_INPUT_RESULT")
	if not path.is_empty():
		check(Support.write_json(path, report), "write exact fixed-input report")
	print("MVP3_FIXED_INPUT_CONTRACT assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

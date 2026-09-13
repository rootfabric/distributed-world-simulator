extends SceneTree

const Service = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_fixed_tick_gameplay_service.gd")
const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Bridge = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_shared_dig_authority.gd")
const Surface = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_replica_surface.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

var assertions := 0
var failures: Array[String] = []
var owner = null
var bridge = null
var replicas: Dictionary = {}
var decisions: Dictionary = {}
var sessions := {"a": "transport-session/mvp4/test/a", "b": "transport-session/mvp4/test/b"}
var observations: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures.append(label)
		push_error(label)
	return value

func success(result: Dictionary, label: String) -> bool:
	return check(bool(result.get("success", false)), label + ":" + String(result.get("error_code", "")))

func drain(actor: String) -> bool:
	for _iteration in range(16):
		var polled: Dictionary = bridge.poll_replica(actor, sessions[actor])
		if not success(polled, "poll " + actor): return false
		for envelope in polled["details"]["messages"]:
			# The same JSON representation used by the real ENet protocol.
			var wire: Dictionary = JSON.parse_string(JSON.stringify(envelope))
			if not success(replicas[actor].consume(wire), "consume " + actor): return false
		if int(polled["details"]["remaining"]) == 0:
			return success(bridge.acknowledge_replica(actor, sessions[actor], replicas[actor].create_ack()), "canonical ack " + actor)
	return check(false, "bounded frame drain")

func run() -> void:
	owner = Service.new()
	if not success(owner.setup("authority/a", 1, 0, {"profile": Service.PROFILE_MULTIPLAYER_CORE, "fixed_tick_authority": true}), "native owner setup"):
		finish(); return
	for actor in ["a", "b"]:
		if not success(owner.join(actor, sessions[actor], "operation/mvp4/join/" + actor), "join " + actor):
			finish(); return
		var coordinator = Coordinator.new()
		if not success(coordinator.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "SM1 " + actor):
			finish(); return
		decisions[actor] = coordinator
	bridge = Bridge.new()
	if not success(bridge.configure(owner, decisions, sessions), "existing owner composition"):
		finish(); return
	for actor in ["a", "b"]:
		var projection = Surface.new()
		root.add_child(projection)
		replicas[actor] = projection
		if not success(projection.configure_actor(actor, sessions[actor], false), "replica " + actor):
			finish(); return
		if not success(bridge.connect_replica(actor, sessions[actor], projection.create_sync_request()), "connect " + actor) or not drain(actor):
			finish(); return
	var before: Dictionary = bridge.report()
	var a_before: Dictionary = replicas["a"].contract_report()
	var b_before: Dictionary = replicas["b"].contract_report()
	check(a_before["store_hash"] == before["store_hash"] and b_before["store_hash"] == before["store_hash"], "both derive exact bootstrap")
	check(a_before["geometry_hash"] == b_before["geometry_hash"], "independent baseline geometry agrees")
	check(bridge.prepare_dig("a", sessions["a"], "operation/mvp4/a/no-tool", [0.0, -1.0, 0.0]).get("error_code") == "P7_MINING_TOOL_REQUIRED", "unequipped digging denied")
	check(not bool(bridge.prepare_dig("a", "transport-session/foreign", "operation/mvp4/a/foreign", [0.0, -1.0, 0.0]).get("success", false)), "foreign session denied")
	for direction in [[NAN, -1.0, 0.0], [0.0, -100.0, 0.0], [0.0, -1.0]]:
		check(not bool(bridge.prepare_dig("a", sessions["a"], "operation/mvp4/a/bad-aim", direction).get("success", false)), "invalid aim denied")
	for actor in ["a", "b"]:
		if not success(bridge.equip_tool(actor, sessions[actor]), "canonical tool " + actor):
			finish(); return
	var prepared: Dictionary = bridge.prepare_dig("a", sessions["a"], "operation/mvp4/a/dig-1", [0.0, -1.0, 0.0])
	if not success(prepared, "canonical server aim"):
		finish(); return
	var plan: Dictionary = prepared["details"]
	check(plan.get("aim_source") == "CANONICAL_MATTER_QUERY", "actual server query provenance")
	var tampered := plan.duplicate(true)
	tampered["request_transport"] = String(plan["request_transport"]) + " "
	check(bridge.execute_prepared("a", sessions["a"], tampered).get("error_code") == "MVP4_CANONICAL_AIM_ATTESTATION_INVALID", "changed prepared bytes denied even when valid JSON")
	check(not bool(bridge.execute_prepared("b", sessions["b"], plan).get("success", false)), "other actor cannot reuse prepared aim")
	check(bridge.report()["store_hash"] == before["store_hash"], "negative controls leave Matter unchanged")
	var result: Dictionary = bridge.execute_prepared("a", sessions["a"], plan)
	if not success(result, "P7 MW8 MW6 MW4 committed dig"):
		finish(); return
	var after: Dictionary = bridge.report()
	check(after["store_hash"] != before["store_hash"] and int(after["stream_sequence"]) == 1, "canonical mutation occurred once")
	check(replicas["b"].contract_report()["geometry_hash"] == b_before["geometry_hash"], "no client-local speculative carve")
	if not drain("a") or not drain("b"):
		finish(); return
	var a_after: Dictionary = replicas["a"].contract_report()
	var b_after: Dictionary = replicas["b"].contract_report()
	check(a_after["store_hash"] == after["store_hash"] and b_after["store_hash"] == after["store_hash"], "both independent stores equal native canonical state")
	check(a_after["geometry_hash"] == b_after["geometry_hash"] and a_after["geometry_hash"] != a_before["geometry_hash"], "both actually remesh the same visible hole")
	check(a_after["replica"]["state_hash"] == after["state_hash"] and b_after["replica"]["state_hash"] == after["state_hash"], "MW6 independently verifies source state hash")
	var replay: Dictionary = bridge.execute_prepared("a", sessions["a"], plan)
	success(replay, "exact replay")
	check(replay.get("details", {}).get("replay") == true and bridge.report()["store_hash"] == after["store_hash"] and bridge.report()["stream_sequence"] == 1, "replay never repeats carve")
	if success(decisions["a"].begin_transfer("transfer/mvp4/freeze-control", "authority/a", "authority/b", 1), "real SM1 freeze"):
		check(not bool(bridge.execute_prepared("a", sessions["a"], plan).get("success", false)), "frozen source cannot dig or replay through authorization")
		check(bridge.report()["store_hash"] == after["store_hash"], "frozen source never changes Matter")
	observations = {"before": before, "after": after, "client_a_before": a_before, "client_b_before": b_before, "client_a_after": a_after, "client_b_after": b_after}
	finish()

func finish() -> void:
	var report := {"schema": "distributed_world_simulator.mvp4_focused_dig.v1", "passed": failures.is_empty(), "assertions": assertions, "failures": failures, "observations": observations, "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "mvp4_predicate_verified": false, "graphical_processes_executed": false, "independent_verdict": false}
	var out := OS.get_environment("MVP4_FOCUSED_RESULT")
	if not out.is_empty() and not Support.write_json(out, report):
		failures.append("cannot persist report")
	if bridge != null: bridge.shutdown()
	if owner != null: owner.shutdown()
	for projection in replicas.values(): projection.queue_free()
	print("MVP4_SHARED_CANONICAL_DIG assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

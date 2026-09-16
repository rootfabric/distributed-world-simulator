extends "res://tests/runtime/test_v0_mvp_4_shared_canonical_dig.gd"

# Reuse only setup helpers/assertion/drain utilities, not the MVP4 verdict.
const Bridge5 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_material_output_authority.gd")
const Delivery5 = preload("res://scripts/runtime/networked_gameplay/p7/p7_matter_material_delivery_coordinator.gd")

class FaultPort extends RefCounted:
	var inner = null
	var mode := ""
	var armed := true
	var apply_calls := 0
	var successful_inner_calls := 0
	func create_snapshot() -> Dictionary: return inner.create_snapshot()
	func preflight_server_output(op: String, actor: String, definition: String, quantity: int, source: String = "") -> Dictionary:
		return inner.preflight_server_output(op, actor, definition, quantity, source)
	func apply_server_output(op: String, actor: String, definition: String, quantity: int, source: String = "") -> Dictionary:
		apply_calls += 1
		if armed and mode == "before_apply":
			armed = false
			return {"success": false, "error_code": "TEST_OUTPUT_PORT_UNAVAILABLE"}
		var result: Dictionary = inner.apply_server_output(op, actor, definition, quantity, source)
		if bool(result.get("success", false)): successful_inner_calls += 1
		if armed and mode == "after_apply" and bool(result.get("success", false)):
			armed = false
			return {"success": false, "error_code": "TEST_OUTPUT_ACK_LOST"}
		return result

var cases5: Array = []

func setup_case5() -> bool:
	owner = Service.new()
	if not success(owner.setup("authority/a", 1, 0, {"profile": Service.PROFILE_MULTIPLAYER_CORE, "fixed_tick_authority": true}), "native owner setup"): return false
	for actor in ["a", "b"]:
		if not success(owner.join(actor, sessions[actor], "operation/mvp5/join/" + actor), "native join"): return false
		var coordinator = Coordinator.new()
		if not success(coordinator.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "SM1 decision"): return false
		decisions[actor] = coordinator
	bridge = Bridge5.new()
	if not success(bridge.configure(owner, decisions, sessions), "MVP5 same owners"): return false
	for actor in ["a", "b"]:
		var projection = Surface.new()
		root.add_child(projection)
		replicas[actor] = projection
		if not success(projection.configure_actor(actor, sessions[actor], false), "read-only replica"): return false
		if not success(bridge.connect_replica(actor, sessions[actor], projection.create_sync_request()), "connect") or not drain(actor): return false
		if not success(bridge.equip_tool(actor, sessions[actor]), "equip native tool"): return false
	return true

func graph5() -> Dictionary:
	return owner.get_canonical_item_graph_port().create_snapshot()

func case5(mode: String, actor: String) -> bool:
	if not setup_case5(): return false
	var operation := "operation/mvp4/" + actor + "/mvp5-" + mode
	var prepared: Dictionary = bridge.prepare_dig(actor, sessions[actor], operation, [0.0, -1.0, 0.0])
	if not success(prepared, "canonical prepared dig " + mode): return false
	var plan: Dictionary = prepared["details"]
	var initial_graph := graph5()
	var initial_matter: Dictionary = bridge.report()
	var initial_view: Dictionary = bridge.material_snapshot(actor, sessions[actor])
	if not success(initial_view, "initial canonical material view"): return false
	var altered := plan.duplicate(true)
	altered["request_transport"] = String(altered["request_transport"]) + " "
	check(not bool(bridge.execute_prepared(actor, sessions[actor], altered).get("success", false)), "tampered prepared request rejected")
	check(not bool(bridge.material_snapshot(actor, "foreign-session").get("success", false)), "foreign material read rejected")
	var other := "b" if actor == "a" else "a"
	check(not bool(bridge.execute_prepared(other, sessions[other], plan).get("success", false)), "foreign actor cannot replay plan")
	check(graph5() == initial_graph, "negative requests do not mutate Item Graph")
	var fault = FaultPort.new()
	fault.inner = bridge._output
	fault.mode = mode
	var delivery = Delivery5.new()
	if not success(delivery.configure(bridge._bubble.excavation_service(), fault), "test proxy over REAL canonical output port"): return false
	bridge._delivery = delivery
	var first: Dictionary = bridge.execute_prepared(actor, sessions[actor], plan)
	var failed_graph := graph5()
	if mode in ["before_apply", "after_apply"]:
		check(first.get("success") == false and first.get("error_code") == "P7_ITEM_GRAPH_OUTPUT_REJECTED", "injected failure remains failure")
		check(bridge.report()["stream_sequence"] == 1 and bridge.report()["store_hash"] != initial_matter["store_hash"], "Matter already committed despite delivery failure")
		check((failed_graph == initial_graph) == (mode == "before_apply"), "correct failure window around real Item Graph application")
		first = bridge.execute_prepared(actor, sessions[actor], plan)
	if not success(first, "recover committed batch " + mode): return false
	var receipt: Dictionary = first["details"]["material_output"]
	var stable_graph := graph5()
	var stable_matter: Dictionary = bridge.report()
	var view_a: Dictionary = bridge.material_snapshot("a", sessions["a"])
	var view_b: Dictionary = bridge.material_snapshot("b", sessions["b"])
	if not success(view_a, "A read") or not success(view_b, "B read"): return false
	var quantity := int(receipt["output_quantity"])
	check(quantity > 0 and not String(receipt["output_item_id"]).is_empty(), "positive native output and stable id")
	check(receipt["logical_player_id"] == actor, "canonical output belongs to authenticated actor")
	check(absf(float(receipt["total_mass_kg"]) - float(receipt["represented_mass_kg"]) - float(receipt["residual_mass_kg"])) <= 0.000000001, "exact policy mass conservation")
	check(float(receipt["represented_mass_kg"]) == float(quantity) and float(receipt["residual_mass_kg"]) >= 0.0 and float(receipt["residual_mass_kg"]) < 1.0, "kilograms and explicit floor residual")
	check(int(view_a["details"]["totals"][actor]) - int(initial_view["details"]["totals"][actor]) == quantity, "actual canonical inventory delta equals output")
	check(view_a == view_b, "two clients receive identical owner projection")
	check(receipt["matter_replay"] == (mode in ["before_apply", "after_apply"]), "Matter replay is independent from delivery replay")
	check(receipt["output_created_this_call"] == (mode != "after_apply"), "first delivery after pre-apply failure is fresh; lost-ACK retry is not")
	check(receipt["item_graph_replay"] == (mode == "after_apply"), "canonical Item Graph replay classification")
	check(int(stable_graph["revision"]) == int(initial_graph["revision"]) + 1, "exactly one Item Graph mutation across failure and retry")
	check(int(stable_graph["tick"]) == int(initial_graph["tick"]) + 1, "exactly one Item Graph tick")
	var ids: Array = []
	for item in view_a["details"]["items"]:
		if item["item_id"] == receipt["output_item_id"]: ids.append(item["item_id"])
	check(ids.size() == 1, "single actual output item")
	var retries: Array = []
	for _index in range(3):
		var replay: Dictionary = bridge.execute_prepared(actor, sessions[actor], plan)
		if not success(replay, "repeat canonical operation"): return false
		var replay_receipt: Dictionary = replay["details"]["material_output"]
		check(replay_receipt["output_item_id"] == receipt["output_item_id"] and replay_receipt["output_quantity"] == quantity and replay_receipt["batch_checksum"] == receipt["batch_checksum"], "replay preserves output identity and quantity")
		check(replay_receipt["item_graph_replay"] == true and replay_receipt["output_created_this_call"] == false and replay_receipt["matter_replay"] == true, "both canonical effects replay")
		check(graph5() == stable_graph and bridge.report()["store_hash"] == stable_matter["store_hash"] and bridge.report()["stream_sequence"] == 1, "no extra carve, graph revision, tick or output")
		retries.append(replay_receipt)
	# A later legitimate canonical operation must not invalidate old replay or
	# cause old issuance to be recreated. This is not another mining output.
	if not success(owner.apply_canonical_server_output("operation/mvp5/unrelated/" + mode, other, "item/tool/mining", 1, "source/mvp5/test-fixture"), "unrelated native operation"): return false
	var late_before := graph5()
	var late: Dictionary = bridge.execute_prepared(actor, sessions[actor], plan)
	if not success(late, "late replay after another canonical operation"): return false
	check(graph5() == late_before and late["details"]["material_output"]["output_item_id"] == receipt["output_item_id"], "late replay cannot duplicate output")
	var conflict: Dictionary = owner.get_canonical_item_graph_port().preflight_server_output(String(receipt["output_operation_id"]), actor, String(receipt["output_definition_id"]), quantity + 1, String(receipt["source_id"]))
	check(conflict.get("success") == false and conflict.get("error_code") == "OPERATION_REPLAY_CONFLICT", "canonical ledger rejects changed output payload")
	check(graph5() == late_before, "replay conflict leaves native state untouched")
	view_a["details"]["totals"][actor] = -999
	check(bridge.material_snapshot(actor, sessions[actor])["details"]["totals"][actor] != -999, "returned projection cannot become canonical state")
	if not drain("a") or not drain("b"): return false
	if not success(decisions[actor].begin_transfer("transfer/mvp5/freeze/" + mode, "authority/a", "authority/b", 1), "freeze real SM1 source"): return false
	check(not bool(bridge.execute_prepared(actor, sessions[actor], plan).get("success", false)), "frozen authority cannot replay a known operation")
	check(not bool(bridge.material_snapshot(actor, sessions[actor]).get("success", false)), "frozen material view fails closed")
	check(graph5() == late_before, "frozen source makes no output")
	cases5.append({"mode": mode, "actor": actor, "initial_graph": initial_graph, "failure_window_graph": failed_graph, "final_graph": stable_graph, "receipt": receipt, "retries": retries, "material_view": view_b, "port_apply_calls": fault.apply_calls, "port_successful_inner_calls": fault.successful_inner_calls})
	fault.inner = null
	cleanup5()
	return true

func cleanup5() -> void:
	if bridge != null: bridge.shutdown()
	bridge = null
	if owner != null: owner.shutdown()
	owner = null
	for projection in replicas.values():
		if is_instance_valid(projection): projection.free()
	replicas.clear()
	decisions.clear()

func run() -> void:
	for spec in [["normal", "a"], ["before_apply", "a"], ["after_apply", "a"], ["actor_b", "b"]]:
		if not case5(spec[0], spec[1]): break
	finish()

func finish() -> void:
	cleanup5()
	var passed := failures.is_empty() and cases5.size() == 4
	var report := {"schema": "distributed_world_simulator.mvp5_exactly_once_focused.v1", "passed": passed, "assertions": assertions, "failures": failures, "cases": cases5, "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "mvp5_predicate_verified": false, "independent_verdict": false, "restart_executed": false}
	var out := OS.get_environment("MVP5_FOCUSED_RESULT")
	if not out.is_empty() and not Support.write_json(out, report): passed = false
	print("MVP5_EXACTLY_ONCE_MATERIAL assertions=%d failures=%d cases=%d passed=%s" % [assertions, failures.size(), cases5.size(), str(passed)])
	quit(0 if passed else 1)

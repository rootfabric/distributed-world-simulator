extends "res://tests/runtime/test_v0_mvp_6_native_item_handoff.gd"

# Additional falsifiers. A rejected semantic result must also preserve native
# ledger attribution, and direct native execution must honor ownership epochs.
var attacks6: Array = []

func run() -> void:
	var okay := setup6()
	if okay: okay = seed6()
	if okay:
		var owner = services[0]
		var graph = owner.get_canonical_item_graph_port()
		var before: Dictionary = graph.export_replay_state()
		var before_graph: Dictionary = graph.create_snapshot()
		var foreign: Dictionary = owner.handle_canonical_item_command("b", "transport-session/mvp3/b", 1, "operation/mvp6/a/equip", "inventory.select_hotbar", {"selected_hotbar_index": 0})
		check(foreign.get("success") == false and foreign.get("error_code") == "OPERATION_REPLAY_CONFLICT", "foreign command replay is rejected")
		check(graph.export_replay_state() == before, "rejected foreign replay cannot reattribute another actor's native ledger entry")
		check(graph.create_snapshot() == before_graph, "foreign replay does not mutate current graph")
		attacks6.append({"kind": "foreign_command_replay", "result": foreign, "ledger_unchanged": graph.export_replay_state() == before})
		var prior: Dictionary = graph.export_replay_state()
		var foreign_output: Dictionary = owner.apply_canonical_server_output("operation/mvp6/a/ore", "b", "item/ore", 5, "source/mvp6/native-test")
		check(foreign_output.get("success") == false and foreign_output.get("error_code") == "OPERATION_REPLAY_CONFLICT", "foreign trusted output operation rejected")
		check(graph.export_replay_state() == prior, "rejected output cannot steal native replay attribution")
		attacks6.append({"kind": "foreign_output_replay", "result": foreign_output, "ledger_unchanged": graph.export_replay_state() == prior})
		for epoch in [0, 2, 999]:
			var baseline: Dictionary = graph.create_snapshot()
			var ledger: Dictionary = graph.export_replay_state()
			var stale: Dictionary = graph.execute("a", epoch, "operation/mvp6/security/stale/" + str(epoch), "inventory.select_hotbar", {"selected_hotbar_index": 0})
			check(stale.get("success") == false, "direct native wrong ownership epoch denied: " + str(epoch))
			check(graph.create_snapshot() == baseline and graph.export_replay_state() == ledger, "wrong epoch changes neither graph nor ledger: " + str(epoch))
			attacks6.append({"kind": "wrong_epoch", "epoch": epoch, "result": stale})
		var live: Dictionary = owner.handle_canonical_item_command("a", "transport-session/mvp3/a", 1, "operation/mvp6/a/equip", "item.equip", {"item_id": receipts6["a"]["tool"]["details"]["output_item_id"], "slot_id": "tool/main"})
		check(live.get("success") == true and live.get("replay") == true, "legitimate original actor still receives original replay")
	var report := {"schema": "distributed_world_simulator.mvp6_native_replay_security.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "passed": okay and failures.is_empty(), "assertions": assertions, "failures": failures, "attacks": attacks6, "mvp6_predicate_verified": false, "independent_verdict": false}
	cleanup6()
	var saved := true
	var output := OS.get_environment("MVP6_SECURITY_RESULT")
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_NATIVE_REPLAY_SECURITY assertions=%d failures=%d passed=%s" % [assertions, failures.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

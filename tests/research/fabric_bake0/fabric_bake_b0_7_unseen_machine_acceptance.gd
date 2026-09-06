extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const Protocol = preload("res://scripts/research/fabric_bake0/unseen_machine_challenge_protocol_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/unseen_machine_challenge_fixture_v1.gd")

var checks := 0

func _check(condition: bool, label: String) -> void:
	if not condition:
		push_error("B0.7 UNSEEN ASSERTION FAILED: %s" % label)
		quit(1)
		return
	checks += 1

func _init() -> void:
	_check(Fixture.FREEZE_HEAD == "9dda6872081c19ce2add86bb590a9aa4925c6ac9", "fixture is seeded by immutable kernel freeze")
	var selected := _selected_case()
	_check(selected in ["alpha", "beta", "gamma", "guard"], "explicit durable challenge case selected")
	if selected == "guard":
		_run_guard_case()
		return
	_run_machine_case(selected)

func _run_machine_case(selected: String) -> void:
	var cases := Fixture.all_cases()
	var case_data: Dictionary = {}
	for candidate in cases:
		if String(candidate["name"]) == selected:
			case_data = candidate
			break
	_check(not case_data.is_empty(), "%s fixture exists" % selected)
	if case_data.is_empty():
		return
	var base: Dictionary = case_data["base"]
	var successor: Dictionary = case_data["successor"]
	_check(not base.is_empty() and not successor.is_empty(), "%s fixtures build" % selected)
	_check(bool(Graph.validate(base).get("success", false)) and bool(Graph.validate(successor).get("success", false)), "%s fixtures validate" % selected)
	_check(int(case_data["internal_count"]) >= 128, "%s hidden state is nontrivial" % selected)
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var outcome := Protocol.run_case(
		base, successor,
		String(case_data["failure_event_id"]),
		case_data["failed_edge_ids"],
		case_data["excitations"],
		String(case_data["observation_port_id"])
	)
	_check(bool(outcome.get("success", false)), "%s generic challenge lifecycle passes" % selected)
	if not bool(outcome.get("success", false)):
		print("B0_7_CASE_ERROR[%s]=%s details=%s" % [selected, outcome.get("error_code", ""), outcome.get("details", {})])
		return
	var result: Dictionary = outcome["details"]
	_check(int(result["full_equation_count"]) == int(case_data["internal_count"]) + 4, "%s full equation count is fixture-derived" % selected)
	_check(int(result["reduced_equation_count"]) == 4, "%s automatic bake retains only boundary state" % selected)
	_check(float(result["runtime_work_ratio"]) >= 1000.0, "%s reduction is computationally meaningful" % selected)
	_check(float(result["base_max_flow_error"]) <= GenericCompiler.FLOW_ERROR_LIMIT, "%s base FULL/BAKE flow parity" % selected)
	_check(float(result["successor_max_flow_error"]) <= GenericCompiler.FLOW_ERROR_LIMIT, "%s successor FULL/BAKE flow parity" % selected)
	_check(float(result["base_max_power_error"]) <= GenericCompiler.POWER_ERROR_LIMIT, "%s base FULL/BAKE power parity" % selected)
	_check(float(result["successor_max_power_error"]) <= GenericCompiler.POWER_ERROR_LIMIT, "%s successor FULL/BAKE power parity" % selected)
	_check(String(result["stale_error"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "%s stale pre-failure bake is fenced" % selected)
	_check(float(result["observation_flow_delta"]) > 1.0e-6, "%s failure changes downstream boundary function" % selected)
	_check(int(result["base_active_edges"]) == int(result["successor_active_edges"]) + 1, "%s exactly one declared topology edge fails" % selected)
	_check(Utils.is_lower_hex_64(result["artifact_hash"]) and Utils.is_lower_hex_64(result["descriptor_hash"]), "%s deterministic rebuilt artifact identities exist" % selected)
	_check(Utils.is_lower_hex_64(result["result_hash"]), "%s deterministic case hash exists" % selected)
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	print("B0_7_CASE=%s" % selected)
	print("B0_7_FULL_EQUATIONS=%d" % int(result["full_equation_count"]))
	print("B0_7_REDUCED_EQUATIONS=%d" % int(result["reduced_equation_count"]))
	print("B0_7_WORK_RATIO=%f" % float(result["runtime_work_ratio"]))
	print("B0_7_MAX_FLOW_ERROR=%s" % str(maxf(float(result["base_max_flow_error"]), float(result["successor_max_flow_error"]))))
	print("B0_7_MAX_POWER_ERROR=%s" % str(maxf(float(result["base_max_power_error"]), float(result["successor_max_power_error"]))))
	print("B0_7_OBSERVATION_DELTA=%s" % str(float(result["observation_flow_delta"])))
	print("B0_7_COMPILE_US=%d/%d" % [int(result["base_compile_us_observed"]), int(result["successor_compile_us_observed"])])
	print("B0_7_EVAL_US=%d/%d" % [int(result["full_eval_us_observed"]), int(result["reduced_eval_us_observed"])])
	print("B0_7_MEMORY=%d/%d/%d" % [memory_before, memory_after, memory_after - memory_before])
	print("B0_7_CASE_HASH=%s" % String(result["result_hash"]))
	print("FABRIC-BAKE B0.7 UNSEEN MACHINE: PASS (%d assertions) case=%s challenge=%s" % [checks, selected, String(result["result_hash"])])
	quit(0)

func _run_guard_case() -> void:
	var cases := Fixture.all_cases()
	_check(cases.size() == 3, "three unseen machine fixtures exist")
	if cases.size() != 3:
		return
	var machine_ids: Array = []
	var graph_hashes: Array = []
	var counts: Array = []
	for case_data in cases:
		_check(not case_data["base"].is_empty() and bool(Graph.validate(case_data["base"]).get("success", false)), "%s base graph validates" % String(case_data["name"]))
		machine_ids.append(String(case_data["base"]["machine_id"]))
		graph_hashes.append(String(case_data["base"]["graph_hash"]))
		counts.append(int(case_data["internal_count"]))
	var sorted_ids := Utils.sorted_strings(machine_ids)
	var sorted_hashes := Utils.sorted_strings(graph_hashes)
	_check(sorted_ids[0] != sorted_ids[1] and sorted_ids[1] != sorted_ids[2], "all unseen machine identities are distinct")
	_check(sorted_hashes[0] != sorted_hashes[1] and sorted_hashes[1] != sorted_hashes[2], "all unseen topologies are distinct")
	_check(counts[0] < counts[1] and counts[1] < counts[2], "hidden equation counts increase across challenge ladder")
	var unsafe := Fixture.unsafe_case()
	_check(not unsafe.is_empty() and bool(Graph.validate(unsafe).get("success", false)), "adversarial unsafe graph is structurally valid")
	var unsafe_result := Protocol.expect_no_safe_bake(unsafe)
	_check(bool(unsafe_result.get("success", false)), "disconnected hidden state fails closed")
	if not bool(unsafe_result.get("success", false)):
		print("B0_7_GUARD_ERROR=%s details=%s" % [unsafe_result.get("error_code", ""), unsafe_result.get("details", {})])
		return
	_check(String(unsafe_result["details"]["reason"]) == "RANK_DEFICIENCY", "unsafe graph fails for exact rank reason")
	var forged := Fixture.forged_successor(cases[0])
	_check(not forged.is_empty() and bool(Graph.validate(forged).get("success", false)), "forged successor is internally well-formed")
	var forged_check := Protocol.validate_successor(cases[0]["base"], forged, String(cases[0]["failure_event_id"]), cases[0]["failed_edge_ids"])
	_check(not bool(forged_check.get("success", false)) and String(forged_check.get("error_code", "")) == "B0_7_SUCCESSOR_EDGE_METADATA_CHANGED", "challenge protocol rejects hidden law change")
	var guard_hash := Utils.canonical_hash({
		"freeze_head": Fixture.FREEZE_HEAD,
		"machine_ids": machine_ids,
		"graph_hashes": graph_hashes,
		"internal_counts": counts,
		"unsafe_reason": unsafe_result["details"]["reason"],
		"forged_error": forged_check.get("error_code", ""),
	})
	print("B0_7_CASE=guard")
	print("B0_7_UNSAFE_REASON=%s" % String(unsafe_result["details"]["reason"]))
	print("B0_7_FORGED_ERROR=%s" % String(forged_check.get("error_code", "")))
	print("B0_7_CASE_HASH=%s" % guard_hash)
	print("FABRIC-BAKE B0.7 UNSEEN MACHINE: PASS (%d assertions) case=guard challenge=%s" % [checks, guard_hash])
	quit(0)

func _selected_case() -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--case="):
			return String(arg).trim_prefix("--case=")
	return ""

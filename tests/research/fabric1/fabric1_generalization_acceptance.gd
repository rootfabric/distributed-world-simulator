extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/fabric1_generalized_runtime_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Fixture = preload("res://tests/research/fabric1/fabric1_generalization_fixture_v1.gd")

const FLOW_TOL := 2.0e-8
const POWER_TOL := 2.0e-8

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	var subject := Fixture.build(48)
	_check(not subject.is_empty(), "three generic components construct")
	if subject.is_empty():
		_finish(); return
	_test_composition(subject)
	_test_reduction(subject)
	_test_runtime_lifecycle(subject)
	_test_determinism(subject)
	_finish()

func _test_composition(subject: Dictionary) -> void:
	var spec: Dictionary = subject["spec"]
	_check(spec["boundary_node_ids"].size() == 4, "composition exposes four external ports")
	_check(spec["internal_node_ids"].size() == 148, "composition seals connector ports into internal topology")
	_check(int(subject["composition"]["component_count"]) == 3, "three components retained in composition evidence")
	_check(int(subject["composition"]["connector_count"]) == 2, "two generic connectors compose subsystems")
	var reordered := Fixture.reordered(subject)
	_check(not reordered.is_empty(), "reordered components compose")
	_check(String(reordered.get("graph_hash", "")) == String(spec["graph_hash"]), "composition is deterministic under input order")
	var overlap := Fixture.overlapping_component(subject)
	_check(not bool(overlap.get("success", false)), "overlapping canonical node ownership fails closed")
	_check(String(overlap.get("error_code", "")) == "FABRIC1_COMPONENT_INVALID" or String(overlap.get("error_code", "")) == "FABRIC1_COMPOSITION_NODE_OVERLAP", "overlap rejection is explicit")
	var double_bound := Fixture.double_bound_connector(subject)
	_check(not bool(double_bound.get("success", false)), "double-bound physical port fails closed")
	_check(String(double_bound.get("error_code", "")) == "FABRIC1_CONNECTOR_PORT_ALREADY_BOUND", "double-bound port rejection exact")

func _test_reduction(subject: Dictionary) -> void:
	var compiled := GenericCompiler.compile(subject["spec"])
	_check(String(compiled.get("status", "")) == "BAKE_READY", "composed machine automatically bakes")
	if String(compiled.get("status", "")) != "BAKE_READY": return
	var descriptor: Dictionary = compiled["compile_result"]["diagnostics"]["reduction"]
	_check(int(descriptor["full_equation_count"]) == 152, "full composed equation count exact")
	_check(int(descriptor["reduced_equation_count"]) == 4, "automatic bake preserves only four boundary equations")
	_check(float(descriptor["runtime_work_ratio"]) > 1000.0, "reduction has meaningful computational advantage")
	for excitation in subject["excitations"]:
		var full := Reducer.evaluate_full(compiled["context"]["linear_system"], excitation, GenericCompiler.PIVOT_TOLERANCE)
		var reduced := Reducer.evaluate_reduced(descriptor, excitation)
		_check(bool(full.get("success", false)) and bool(reduced.get("success", false)), "full/reduced evaluation succeeds")
		if bool(full.get("success", false)) and bool(reduced.get("success", false)):
			_check(_max_delta(full["details"]["boundary_flow"], reduced["details"]["boundary_flow"]) <= FLOW_TOL, "full/bake boundary flow parity")
			_check(absf(float(full["details"]["boundary_power"]) - float(reduced["details"]["boundary_power"])) <= POWER_TOL, "full/bake power parity")

func _test_runtime_lifecycle(subject: Dictionary) -> void:
	var runtime := Runtime.new()
	var started := runtime.start_baked(subject["spec"], 0)
	_check(bool(started.get("success", false)), "generalized runtime starts baked")
	if not bool(started.get("success", false)): return
	var baked_before := runtime.execute(subject["excitations"][0])
	_check(bool(baked_before.get("success", false)), "baked execution succeeds before refinement")
	var refined := runtime.refine_to_full("GUARD_MARGIN", 1)
	_check(bool(refined.get("success", false)) and String(runtime.status()["mode"]) == "FULL", "guard refinement returns FULL detail")
	var full_before := runtime.execute(subject["excitations"][0])
	_check(bool(full_before.get("success", false)), "full execution succeeds after refinement")
	if bool(baked_before.get("success", false)) and bool(full_before.get("success", false)):
		_check(_max_delta(baked_before["details"]["boundary_flow"], full_before["details"]["boundary_flow"]) <= FLOW_TOL, "refinement preserves boundary flow")
	var successor := Fixture.successor(subject)
	_check(not successor.is_empty(), "external canonical successor builds")
	if successor.is_empty(): return
	var failure := runtime.apply_canonical_failure(successor, subject["event_id"], [subject["critical_edge_id"]], 2)
	_check(bool(failure.get("success", false)), "canonical failure observed by generalized runtime")
	_check(String(failure.get("details", {}).get("stale_error", "")) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "old bake fenced immediately")
	var full_after := runtime.execute(subject["excitations"][0])
	_check(bool(full_after.get("success", false)), "successor executes FULL before rebake")
	if bool(full_before.get("success", false)) and bool(full_after.get("success", false)):
		var port_index: int = int(successor["boundary_node_ids"].find(subject["observation_port_id"]))
		_check(port_index >= 0, "observation port retained across canonical mutation")
		if port_index >= 0:
			_check(absf(float(full_before["details"]["boundary_flow"][port_index]) - float(full_after["details"]["boundary_flow"][port_index])) > 1.0e-3, "canonical failure changes downstream function")
	var duplicate := runtime.apply_canonical_failure(successor, subject["event_id"], [subject["critical_edge_id"]], 3)
	_check(not bool(duplicate.get("success", false)), "canonical event cannot commit twice")
	var rebaked := runtime.rebake(3)
	_check(bool(rebaked.get("success", false)) and String(runtime.status()["mode"]) == "BAKED", "successor safely rebakes")
	var baked_after := runtime.execute(subject["excitations"][0])
	_check(bool(baked_after.get("success", false)), "rebaked successor executes")
	if bool(full_after.get("success", false)) and bool(baked_after.get("success", false)):
		_check(_max_delta(full_after["details"]["boundary_flow"], baked_after["details"]["boundary_flow"]) <= FLOW_TOL, "successor FULL/bake parity after mutation")
	var capsule_result := runtime.capture_capsule()
	_check(bool(capsule_result.get("success", false)), "derived restart capsule captures")
	if not bool(capsule_result.get("success", false)): return
	var capsule: Dictionary = capsule_result["details"]["capsule"]
	_check(capsule["canonical"] == false and capsule["derived"] == true and capsule["discardable"] == true, "capsule cannot become canonical truth")
	var restarted := Runtime.new()
	var restored := restarted.restore(successor, capsule)
	_check(bool(restored.get("success", false)), "fresh runtime restores from authoritative successor + derived capsule")
	var replay := restarted.execute(subject["excitations"][0])
	_check(bool(replay.get("success", false)), "restored runtime executes")
	if bool(replay.get("success", false)) and bool(baked_after.get("success", false)):
		_check(_max_delta(replay["details"]["boundary_flow"], baked_after["details"]["boundary_flow"]) <= FLOW_TOL, "restart preserves boundary result")
	_check(String(restarted.status()["transition_hash"]) == String(runtime.status()["transition_hash"]), "restart preserves deterministic transition identity")
	var stale_restore := Runtime.new().restore(subject["spec"], capsule)
	_check(not bool(stale_restore.get("success", false)) and String(stale_restore.get("error_code", "")) == "FABRIC1_CAPSULE_STALE", "capsule cannot rewind canonical source")
	var corrupt := capsule.duplicate(true)
	corrupt["transition_count"] = int(corrupt["transition_count"]) + 1
	var corrupt_restore := Runtime.new().restore(successor, corrupt)
	_check(not bool(corrupt_restore.get("success", false)) and String(corrupt_restore.get("error_code", "")) == "FABRIC1_CAPSULE_CHECKSUM_INVALID", "corrupt runtime capsule fails closed")
	_check(int(runtime.status()["canonical_writes"]) == 0, "FABRIC1 representation runtime performs zero canonical writes")

func _test_determinism(subject: Dictionary) -> void:
	var a := _deterministic_run(subject)
	var b := _deterministic_run(subject)
	_check(not a.is_empty() and not b.is_empty(), "deterministic twin runs complete")
	_check(Utils.canonical_hash(a) == Utils.canonical_hash(b), "generalized lifecycle deterministic in-process")
	if not a.is_empty():
		print("FABRIC1_CORE_HASH=", Utils.canonical_hash(a))

func _deterministic_run(subject: Dictionary) -> Dictionary:
	var runtime := Runtime.new()
	if not bool(runtime.start_baked(subject["spec"], 10).get("success", false)): return {}
	if not bool(runtime.refine_to_full("REPLAY_GUARD", 11).get("success", false)): return {}
	var successor := Fixture.successor(subject)
	if successor.is_empty(): return {}
	if not bool(runtime.apply_canonical_failure(successor, subject["event_id"], [subject["critical_edge_id"]], 12).get("success", false)): return {}
	if not bool(runtime.rebake(13).get("success", false)): return {}
	var execution := runtime.execute(subject["excitations"][1])
	if not bool(execution.get("success", false)): return {}
	return {"status": runtime.status(), "flow": execution["details"]["boundary_flow"], "power": execution["details"]["boundary_power"]}

func _max_delta(a: Array, b: Array) -> float:
	if a.size() != b.size(): return INF
	var result := 0.0
	for index in range(a.size()): result = maxf(result, absf(float(a[index]) - float(b[index])))
	return result

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC1 Generalization Core: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures: push_error("FABRIC1 FAIL: " + failure)
	print("FABRIC1 Generalization Core: FAIL (%d/%d)" % [_failures.size(), _checks])
	quit(1)

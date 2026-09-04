extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/complex2c_modular_machine_extension_v1.gd")
const E = preload("res://scripts/research/fabric_bake0/complex2e_modular_machine_extension_v1.gd")
const Perf = preload("res://scripts/research/fabric_bake0/complex2_perf_scaling_v1.gd")

const EXPECTED_KINDS := ["CONTACT_BAKE", "DYNAMIC_ROM", "FULL", "HYBRID_BAKE", "STRUCTURAL_BAKE"]
var assertions := 0
var failures: Array = []

func _initialize() -> void:
	# Non-duplicating closure: C.build carries A+B construction identity, C.run
	# certifies compliant/coupled execution, E.run carries D and E continuation,
	# PERF certifies the 500/1000/2000 scale matrix.
	var built_c := C.build()
	_check(bool(built_c.get("success", false)), "A+B+C build chain must succeed", built_c)
	var machine: Dictionary = built_c.get("parent_machine", {})
	_check(int(machine.get("parts", []).size()) == 2000, "A canonical close subject must remain 2000 parts", machine.get("parts", []).size())
	_check(int(machine.get("modules", []).size()) == 25, "A canonical close subject must remain 25 modules", machine.get("modules", []).size())
	_check(int(machine.get("moving_subsystems", []).size()) == 6, "A must retain six moving subsystems", machine.get("moving_subsystems", []).size())
	_check(int(machine.get("contact_zones", []).size()) == 3, "A must retain three contact zones", machine.get("contact_zones", []).size())
	var parent_b: Dictionary = built_c.get("parent_b", {})
	_check(String(parent_b.get("parent_backend_hash", "")) != String(parent_b.get("extended_backend_hash", "")), "B must remain a real HYBRID backend extension", [parent_b.get("parent_backend_hash"), parent_b.get("extended_backend_hash")])
	_check(not String(parent_b.get("compliant_section", {}).get("section_hash", "")).is_empty(), "B compliant section must exist", parent_b.get("compliant_section"))
	_check(String(built_c.get("parent_dynamic_backend_hash", "")) != String(built_c.get("extended_dynamic_backend_hash", "")), "C must remain a real DYNAMIC backend extension", [built_c.get("parent_dynamic_backend_hash"), built_c.get("extended_dynamic_backend_hash")])

	var c := C.run_experiment()
	_check(bool(c.get("success", false)), "C executable experiment must succeed", c)
	_check(float(c.get("runtime_mixed_full_max_delta", INF)) <= 1.0e-12, "C mixed must equal FULL", c.get("runtime_mixed_full_max_delta"))
	_check(float(c.get("representation_swap_handoff_error", INF)) <= 1.0e-12, "C representation handoff must be exact", c.get("representation_swap_handoff_error"))
	_check(Array(c.get("final_representation_kinds", [])) == EXPECTED_KINDS, "C must restore exact five-kind registry", c.get("final_representation_kinds"))
	_check(String(c.get("parent_b_hybrid_backend_hash", "")) == String(c.get("final_hybrid_backend_hash", "")), "C must preserve B HYBRID backend", [c.get("parent_b_hybrid_backend_hash"), c.get("final_hybrid_backend_hash")])
	_check(float(c.get("coupled", {}).get("max_energy_balance_residual_j", INF)) <= 1.0e-12, "C energy identity must remain exact", c.get("coupled", {}).get("max_energy_balance_residual_j"))

	var e := E.run_experiment()
	_check(bool(e.get("success", false)), "D+E continuation must succeed", e)
	_check(not String(e.get("parent_d_experiment_hash", "")).is_empty(), "E must carry D executable experiment identity", e.get("parent_d_experiment_hash"))
	_check(bool(e.get("settled", {}).get("success", false)), "E must reach settled state", e.get("settled"))
	_check(float(e.get("settled", {}).get("settled_energy_j", INF)) <= 0.0025, "E settled energy must be inside envelope", e.get("settled", {}).get("settled_energy_j"))
	_check(int(e.get("rebake_generation", 0)) == 6, "E exact lifecycle rebake generation must remain 6", e.get("rebake_generation"))
	_check(float(e.get("rebake_state_handoff_error", INF)) <= 1.0e-12, "E rebake handoff must be exact", e.get("rebake_state_handoff_error"))
	_check(String(e.get("old_source_slice_hash", "")) == String(e.get("rebaked_source_slice_hash", "")), "E settle/rebake must not forge canonical source mutation", [e.get("old_source_slice_hash"), e.get("rebaked_source_slice_hash")])
	_check(String(e.get("old_dynamic_backend_hash", "")) != String(e.get("rebaked_dynamic_backend_hash", "")), "E must really rebake derived DYNAMIC backend", [e.get("old_dynamic_backend_hash"), e.get("rebaked_dynamic_backend_hash")])
	_check(String(e.get("structural_topology_hash_before_rebake", "")) == String(e.get("structural_topology_hash_after_reimpact", "")), "E must retain D structural topology through rebake/re-impact", [e.get("structural_topology_hash_before_rebake"), e.get("structural_topology_hash_after_reimpact")])
	_check(float(e.get("runtime_quiet_mixed_full_delta", INF)) <= 1.0e-12, "E quiet mixed must equal FULL", e.get("runtime_quiet_mixed_full_delta"))
	_check(float(e.get("runtime_reimpact_mixed_full_delta", INF)) <= 1.0e-12, "E re-impact mixed must equal FULL", e.get("runtime_reimpact_mixed_full_delta"))
	_check(float(e.get("runtime_contact_state_delta", 0.0)) > 0.0, "E re-impact must produce CONTACT response", e.get("runtime_contact_state_delta"))
	_check(Array(e.get("final_representation_kinds", [])) == EXPECTED_KINDS, "E must retain exact five representation kinds", e.get("final_representation_kinds"))
	_check(String(e.get("parent_b_hybrid_backend_hash", "")) == String(e.get("final_hybrid_backend_hash", "")), "D/E must preserve B HYBRID backend", [e.get("parent_b_hybrid_backend_hash"), e.get("final_hybrid_backend_hash")])

	var perf := Perf.run_matrix()
	_check(bool(perf.get("success", false)), "PERF matrix must succeed", perf)
	var perf_cases: Array = Array(perf.get("cases", []))
	var perf_counts: Array = []
	for raw_case in perf_cases:
		perf_counts.append(int(raw_case.get("part_count", 0)))
	_check(perf_counts == [500, 1000, 2000], "PERF must certify exact 500/1000/2000 matrix", perf_counts)
	_check(perf_cases.size() == 3, "PERF must contain exactly three cases", perf_cases.size())
	for raw_case in perf.get("cases", []):
		var case_result: Dictionary = raw_case
		_check(float(case_result.get("mixed_full_max_delta", INF)) <= 1.0e-12, "PERF mixed/FULL must remain exact", [case_result.get("part_count"), case_result.get("mixed_full_max_delta")])
		_check(float(case_result.get("local_rebake_state_handoff_error", INF)) <= 1.0e-12, "PERF local rebake handoff must remain exact", [case_result.get("part_count"), case_result.get("local_rebake_state_handoff_error")])
		_check(Array(case_result.get("local_rebake_regions", [])) == [Fixture.REGION_DYNAMIC], "PERF rebuild must remain local to DYNAMIC", [case_result.get("part_count"), case_result.get("local_rebake_regions")])
		_check(int(case_result.get("timing_us", {}).get("total", 0)) <= int(case_result.get("budget_us", 0)), "PERF case must remain inside declared budget", [case_result.get("part_count"), case_result.get("timing_us", {}).get("total"), case_result.get("budget_us")])

	var closure_hash := Utils.canonical_hash({
		"schema": "planet_simulator.fabric_complex2_close_r1.v1",
		"a_machine": String(machine.get("machine_hash", "")),
		"b_extension": String(parent_b.get("extension_hash", "")),
		"c": String(c["experiment_hash"]),
		"d": String(e["parent_d_experiment_hash"]),
		"e": String(e["experiment_hash"]),
		"perf": String(perf["matrix_hash"]),
		"representation_kinds": EXPECTED_KINDS,
		"fabric019_authorized": false,
	})
	_check(not closure_hash.is_empty(), "closure hash must exist", closure_hash)
	if not failures.is_empty():
		for failure in failures:
			push_error("COMPLEX2-CLOSE ASSERTION FAILED: %s" % failure)
		print("FABRIC COMPLEX2-CLOSE Acceptance: FAIL (%d/%d failed)" % [failures.size(), assertions])
		quit(1)
		return
	print("COMPLEX2_CLOSE_HASH=%s" % closure_hash)
	print("COMPLEX2_PERF_HASH=%s" % String(perf["matrix_hash"]))
	print("FABRIC COMPLEX2-CLOSE Acceptance: PASS (%d assertions) A+B+C+D+E+PERF" % assertions)
	quit(0)

func _check(condition: bool, message: String, details = null) -> void:
	assertions += 1
	if not condition:
		failures.append("%s :: %s" % [message, str(details)])

extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")
const Structural = preload("res://scripts/research/fabric_bake0/complex2_independent_structural_failure_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/complex2_settle_rebake_reimpact_v1.gd")
const Adapter = preload("res://scripts/research/fabric_bake0/bridge2_region_adapter_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge2_mixed_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2_perf_scaling_r1.v1"
const PART_COUNTS := [500, 1000, 2000]
const MODULE_COUNT := 25
const DT := 0.01
const RUNTIME_STEPS := 16
const REBAKE_GENERATION := 7
const CASE_BUDGET_US := {500: 12000000, 1000: 12000000, 2000: 12000000}
const LOCAL_REBAKE_BUDGET_US := 250000

static func run_matrix() -> Dictionary:
	var cases: Array = []
	for part_count in PART_COUNTS:
		var case_result := run_case(part_count)
		if not bool(case_result.get("success", false)):
			return _failure("COMPLEX2PERF_CASE_FAILED", {"part_count": part_count, "case": case_result})
		cases.append(case_result)
	var deterministic_cases: Array = []
	for case_result in cases:
		deterministic_cases.append({
			"part_count": int(case_result["part_count"]),
			"parts_per_module": int(case_result["parts_per_module"]),
			"region_part_counts": case_result["region_part_counts"],
			"scan_hash": String(case_result["scan_hash"]),
			"structural_before_hash": String(case_result["structural_before_hash"]),
			"structural_after_hash": String(case_result["structural_after_hash"]),
			"settled_state_hash": String(case_result["settled_state_hash"]),
			"reimpact_hash": String(case_result["reimpact_hash"]),
			"final_state_hash": String(case_result["final_state_hash"]),
			"rebake_artifact_hash": String(case_result["rebake_artifact_hash"]),
		})
	return {
		"success": true,
		"schema": SCHEMA,
		"cases": cases,
		"matrix_hash": Utils.canonical_hash({"schema": SCHEMA, "cases": deterministic_cases}),
	}

static func run_case(part_count: int) -> Dictionary:
	if not PART_COUNTS.has(part_count) or part_count % MODULE_COUNT != 0:
		return _failure("COMPLEX2PERF_UNSUPPORTED_PART_COUNT", part_count)
	var total_begin := Time.get_ticks_usec()
	var build_begin := Time.get_ticks_usec()
	var machine := _scaled_machine(part_count)
	var build_us := Time.get_ticks_usec() - build_begin
	if not bool(machine.get("success", false)):
		return machine

	var scan_begin := Time.get_ticks_usec()
	var scan := _scan_parts(machine)
	var scan_us := Time.get_ticks_usec() - scan_begin
	if int(scan["part_count"]) != part_count:
		return _failure("COMPLEX2PERF_SCAN_COUNT_MISMATCH", scan)

	var structural_begin := Time.get_ticks_usec()
	var structural := Structural.run_failure(machine)
	var structural_us := Time.get_ticks_usec() - structural_begin
	if not bool(structural.get("success", false)):
		return _failure("COMPLEX2PERF_STRUCTURAL_FAILURE_FAILED", structural)
	var failed_machine: Dictionary = structural["failed_machine"]

	var settle_begin := Time.get_ticks_usec()
	var settled := Lifecycle.settle_after_first_impact(failed_machine)
	if not bool(settled.get("success", false)):
		return _failure("COMPLEX2PERF_SETTLE_FAILED", settled)
	var reimpact := Lifecycle.reimpact_from_settled(
		settled["assembly"], settled["settled_state"], settled["settled_reference"]
	)
	if not bool(reimpact.get("success", false)):
		return _failure("COMPLEX2PERF_REIMPACT_FAILED", reimpact)
	var settle_us := Time.get_ticks_usec() - settle_begin

	var registry: Dictionary = machine["registry"]
	var started := Runtime.start(registry, machine["initial_state"])
	if not bool(started.get("success", false)):
		return _failure("COMPLEX2PERF_SESSION_START_FAILED", started)
	var session: Dictionary = started["details"]["session"]
	var reference: Dictionary = machine["initial_state"].duplicate(true)
	var runtime_begin := Time.get_ticks_usec()
	var max_delta := 0.0
	for step_index in range(RUNTIME_STEPS):
		var flows := {
			Fixture.REGION_DYNAMIC: 0.04 + 0.001 * step_index,
			Fixture.REGION_CONTACT: 0.02 if step_index % 4 == 0 else 0.0,
		}
		var mixed := Runtime.step(session, registry, flows, DT)
		var full := Runtime.full_reference_step(registry, reference, flows, DT)
		if not bool(mixed.get("success", false)):
			return _failure("COMPLEX2PERF_MIXED_STEP_FAILED", {"step": step_index, "result": mixed})
		if not bool(full.get("success", false)):
			return _failure("COMPLEX2PERF_FULL_STEP_FAILED", {"step": step_index, "result": full})
		session = mixed["details"]["session"]
		reference = full["details"]["state_values"]
		max_delta = maxf(max_delta, _state_error(session["state_values"], reference))
	var runtime_us := Time.get_ticks_usec() - runtime_begin

	var dynamic_region := Registry.region_by_id(registry, Fixture.REGION_DYNAMIC)
	if dynamic_region.is_empty():
		return _failure("COMPLEX2PERF_DYNAMIC_REGION_MISSING")
	var backend_hash := Utils.canonical_hash({
		"kind": "COMPLEX2_PERF_SETTLED_DYNAMIC_REBAKE_R1",
		"part_count": part_count,
		"settled_state_hash": String(settled["settled_state_hash"]),
		"structural_topology_hash": String(structural["after_topology_hash"]),
	})
	var rebake_adapter := Adapter.create(
		Fixture.REGION_DYNAMIC,
		"DYNAMIC_ROM",
		String(dynamic_region["state_id"]),
		dynamic_region["adapter"]["source_slice"],
		backend_hash,
		float(dynamic_region["adapter"]["storage"]),
		float(dynamic_region["adapter"]["damping"]),
		REBAKE_GENERATION
	)
	if rebake_adapter.is_empty():
		return _failure("COMPLEX2PERF_REBAKE_ADAPTER_FAILED")
	var rebake_begin := Time.get_ticks_usec()
	var rebaked := Runtime.rebuild_region(session, registry, rebake_adapter)
	var local_rebake_us := Time.get_ticks_usec() - rebake_begin
	if not bool(rebaked.get("success", false)):
		return _failure("COMPLEX2PERF_LOCAL_REBAKE_FAILED", rebaked)
	if float(rebaked["details"]["state_handoff_error"]) != 0.0:
		return _failure("COMPLEX2PERF_REBAKE_HANDOFF_NONZERO", rebaked["details"])
	var final_session: Dictionary = rebaked["details"]["session"]
	var final_registry: Dictionary = rebaked["details"]["registry"]
	var final_dynamic := Registry.region_by_id(final_registry, Fixture.REGION_DYNAMIC)
	var total_us := Time.get_ticks_usec() - total_begin
	if total_us > int(CASE_BUDGET_US[part_count]):
		return _failure("COMPLEX2PERF_CASE_BUDGET_EXCEEDED", {"part_count": part_count, "total_us": total_us, "budget_us": CASE_BUDGET_US[part_count]})
	if local_rebake_us > LOCAL_REBAKE_BUDGET_US:
		return _failure("COMPLEX2PERF_LOCAL_REBAKE_BUDGET_EXCEEDED", {"part_count": part_count, "local_rebake_us": local_rebake_us})

	return {
		"success": true,
		"schema": SCHEMA,
		"part_count": part_count,
		"parts_per_module": int(part_count / MODULE_COUNT),
		"module_count": machine["modules"].size(),
		"support_count": machine["supports"].size(),
		"region_part_counts": scan["region_part_counts"],
		"scan_hash": scan["scan_hash"],
		"structural_before_hash": structural["before_topology_hash"],
		"structural_after_hash": structural["after_topology_hash"],
		"structural_component_count": structural["component_count_after"],
		"settle_step": settled["settled_step"],
		"settled_energy_j": settled["settled_energy_j"],
		"settled_state_hash": settled["settled_state_hash"],
		"reimpact_peak_energy_j": reimpact["peak_energy_j"],
		"reimpact_hash": reimpact["experiment_hash"],
		"mixed_full_max_delta": max_delta,
		"local_rebake_regions": [Fixture.REGION_DYNAMIC],
		"local_rebake_state_handoff_error": float(rebaked["details"]["state_handoff_error"]),
		"rebake_generation": int(final_dynamic["adapter"]["artifact"]["build_generation"]),
		"rebake_artifact_hash": String(final_dynamic["adapter"]["artifact"]["checksum"]),
		"final_state_hash": Utils.canonical_hash(final_session["state_values"]),
		"timing_us": {
			"build": build_us,
			"scan": scan_us,
			"structural_failure": structural_us,
			"settle_and_reimpact": settle_us,
			"mixed_runtime": runtime_us,
			"local_rebake": local_rebake_us,
			"total": total_us,
		},
		"budget_us": int(CASE_BUDGET_US[part_count]),
	}

static func _scaled_machine(part_count: int) -> Dictionary:
	var base := Fixture.build()
	if not bool(base.get("success", false)):
		return _failure("COMPLEX2PERF_BASE_BUILD_FAILED", base)
	var machine: Dictionary = base.duplicate(true)
	var ppm := int(part_count / MODULE_COUNT)
	var modules: Array = []
	for source_module in machine["modules"]:
		var module: Dictionary = Dictionary(source_module).duplicate(true)
		var index := int(module["index"])
		module["part_start"] = index * ppm
		module["part_count"] = ppm
		modules.append(module)
	var parts: Array = []
	for module in modules:
		for local_index in range(ppm):
			var global_index := int(module["part_start"]) + local_index
			parts.append({
				"part_id": "part/complex2-%04d" % global_index,
				"module_id": String(module["module_id"]),
				"region_id": String(module["region_id"]),
			})
	machine["modules"] = modules
	machine["parts"] = parts
	machine["perf_part_count"] = part_count
	machine["perf_scale_hash"] = Utils.canonical_hash({
		"part_count": part_count,
		"parts_per_module": ppm,
		"parts": parts,
	})
	return machine

static func _scan_parts(machine: Dictionary) -> Dictionary:
	var counts := {
		Fixture.REGION_STRUCTURAL: 0,
		Fixture.REGION_FULL: 0,
		Fixture.REGION_CONTACT: 0,
		Fixture.REGION_DYNAMIC: 0,
		Fixture.REGION_HYBRID: 0,
	}
	var ordered_ids: Array = []
	for part in machine["parts"]:
		var region_id := String(part["region_id"])
		counts[region_id] = int(counts.get(region_id, 0)) + 1
		ordered_ids.append(String(part["part_id"]))
	return {
		"part_count": machine["parts"].size(),
		"region_part_counts": counts,
		"scan_hash": Utils.canonical_hash({"ids": ordered_ids, "counts": counts}),
	}

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in a.keys():
		error = maxf(error, absf(float(a[key]) - float(b[key])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

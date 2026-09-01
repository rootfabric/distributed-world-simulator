extends SceneTree

const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullValidation = preload("res://scripts/research/fabric_bake0/dynamic_rom_full_validation_reference_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const ROMRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const RuntimeEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

const DT := 0.01
var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var built := _build()
	if built.is_empty():
		_finish()
		return
	_test_contract(built)
	_test_residual_bound_sequence(built)
	_test_flow_guard(built)
	_test_horizon_guard(built)
	_test_validity_exit(built)
	_test_fail_closed_tamper(built)
	_finish()

func _build() -> Dictionary:
	var fixture := Fixture.build("ZERO")
	var full := FullCompiler.compile(fixture["request"])
	_check(bool(full.get("success", false)), "B0.4-C FULL predecessor compiles")
	if not bool(full.get("success", false)):
		return {}
	var reduced := ROMCompiler.compile(full["model"])
	_check(bool(reduced.get("success", false)), "B0.4-C ROM predecessor compiles")
	if not bool(reduced.get("success", false)):
		return {}
	var certification := Certification.create(full["model"], reduced["descriptor"])
	_check(not certification.is_empty(), "runtime certification creates")
	if certification.is_empty():
		return {}
	return {
		"fixture": fixture,
		"full_model": full["model"],
		"descriptor": reduced["descriptor"],
		"certification": certification,
	}

func _test_contract(built: Dictionary) -> void:
	var c: Dictionary = built["certification"]
	_check(bool(Certification.validate(c).get("success", false)), "runtime certification validates")
	_check(String(c["rom_descriptor_hash"]) == String(built["descriptor"]["descriptor_hash"]), "certification binds exact ROM")
	_check(String(c["full_model_hash"]) == String(built["full_model"]["model_hash"]), "certification binds exact FULL model")
	_check(String(c["source_binding_checksum"]) == String(built["full_model"]["source_binding"]["checksum"]), "certification binds exact source/dependencies")
	_check(float(c["alpha_dissipation_lower_bound"]) > 0.0, "strict dissipativity lower bound positive")
	_check(absf(float(c["max_step_s"]) - 0.02) <= 1.0e-15, "certified max step frozen")
	_check(absf(float(c["max_flow_l1"]) - 1.0) <= 1.0e-15, "certified flow L1 frozen")
	_check(float(c["initial_error_c_norm_max"]) == 0.0, "R1 initial error bound exact zero")
	_check(bool(ValidatedDomain.validate(c["validated_domain"]).get("success", false)), "ValidatedDomain valid")
	_check(bool(ErrorEnvelope.validate(c["error_envelope"]).get("success", false)), "ErrorEnvelope valid")
	_check(c["refinement_guards"].size() == 3, "three refinement guards frozen")
	var ids: Array = []
	for guard in c["refinement_guards"]:
		_check(bool(RefinementGuard.validate(guard).get("success", false)), "refinement guard validates")
		ids.append(String(guard["guard_id"]))
	_check(ids.has(Certification.ERROR_GUARD_ID), "error guard present")
	_check(ids.has(Certification.FLOW_GUARD_ID), "flow-domain guard present")
	_check(ids.has(Certification.HORIZON_GUARD_ID), "horizon guard present")
	_check(float(c["error_envelope"]["effort_abs"]) == Certification.EFFORT_ERROR_ABS_MAX, "static effort envelope frozen")
	_check(float(c["error_envelope"]["effort_rel"]) == 1.0e-3, "parent B0.4 relative target recorded")
	_check(String(c["certification_hash"]).length() == 64, "certification identity present")

func _test_residual_bound_sequence(built: Dictionary) -> void:
	var model: Dictionary = built["full_model"]
	var descriptor: Dictionary = built["descriptor"]
	var certification: Dictionary = built["certification"]
	var full_prepared := FullValidation.prepare(model, DT)
	var rom_initial := ROMRuntime.initial_state(descriptor)
	var rom_prepared := ROMRuntime.prepare_step(descriptor, DT)
	_check(bool(full_prepared.get("success", false)), "prepared FULL validation reference")
	_check(bool(rom_initial.get("success", false)), "ROM initial state for C")
	_check(bool(rom_prepared.get("success", false)), "prepared ROM operator for C")
	if not bool(full_prepared.get("success", false)) or not bool(rom_initial.get("success", false)) or not bool(rom_prepared.get("success", false)):
		return
	var full_values: Array = FullValidation.zero_state(full_prepared)
	var rom_state: Dictionary = rom_initial["state"]
	var error_c_bound := float(certification["initial_error_c_norm_max"])
	var max_actual_error := 0.0
	var max_estimated_error := 0.0
	var max_residual_norm := 0.0
	for step in range(300):
		var t := DT * float(step + 1)
		var flows := _safe_probe_flows(step, t)
		var full_step := FullValidation.step(full_prepared, full_values, flows)
		var old_rom_values: Array = rom_state["values"].duplicate()
		var rom_step := ROMRuntime.step_prepared(descriptor, rom_state, flows, DT, rom_prepared)
		if not bool(full_step.get("success", false)) or not bool(rom_step.get("success", false)):
			_check(false, "prepared FULL/ROM step succeeds")
			return
		full_values = full_step["values"]
		rom_state = rom_step["state"]
		var estimate := Certification.estimate_after_step(
			certification,
			model,
			descriptor,
			error_c_bound,
			old_rom_values,
			rom_state["values"],
			flows,
			DT,
			t
		)
		_check(bool(estimate.get("success", false)), "residual estimator step %d creates" % step)
		if not bool(estimate.get("success", false)):
			return
		var details: Dictionary = estimate["details"]
		error_c_bound = float(details["error_c_norm_bound"])
		var estimator: Dictionary = details["estimator"]
		_check(bool(RuntimeEstimator.validate_against(estimator, certification["error_envelope"]).get("success", false)), "runtime estimator inside ErrorEnvelope")
		var safety := Certification.evaluate_runtime(certification, details)
		_check(bool(safety.get("success", false)), "safe deterministic probe remains certified")
		if not bool(safety.get("success", false)):
			return
		var full_by_id := _boundary_by_id(full_step["boundary"])
		var rom_by_id := _boundary_by_id(rom_step["boundary"])
		var actual_step_error := 0.0
		for port_id in descriptor["port_ids"]:
			actual_step_error = maxf(
				actual_step_error,
				absf(float(full_by_id[String(port_id)]["effort"]) - float(rom_by_id[String(port_id)]["effort"]))
			)
		_check(actual_step_error <= float(estimator["effort_error_bound"]) + 5.0e-12, "actual boundary error below conservative estimator")
		max_actual_error = maxf(max_actual_error, actual_step_error)
		max_estimated_error = maxf(max_estimated_error, float(estimator["effort_error_bound"]))
		max_residual_norm = maxf(max_residual_norm, float(details["residual_dual_c_norm"]))
	print("B0.4-C residual certificate: actual_max=%s estimated_max=%s residual_dual_max=%s" % [
		String.num_scientific(max_actual_error),
		String.num_scientific(max_estimated_error),
		String.num_scientific(max_residual_norm),
	])
	_check(max_actual_error <= 1.0e-3, "measured boundary error remains under frozen B0.4 target")
	_check(max_estimated_error <= Certification.ERROR_GUARD_TRIGGER - Certification.ERROR_GUARD_UNCERTAINTY, "safe suite estimator remains before error guard")

func _test_flow_guard(built: Dictionary) -> void:
	var estimate := _one_estimate(built, _flows([0.96, 0.0, 0.0, 0.0]), 0.01)
	_check(bool(estimate.get("success", false)), "near-flow-limit estimator creates")
	if not bool(estimate.get("success", false)):
		return
	var safety := Certification.evaluate_runtime(built["certification"], estimate["details"])
	_check(not bool(safety.get("success", false)), "flow guard refines before validity exit")
	_check(String(safety.get("error_code", "")) == "DYNAMIC_ROM_REFINEMENT_REQUIRED", "flow guard returns refinement")
	_check(String(safety["details"]["guard_id"]) == Certification.FLOW_GUARD_ID, "flow guard identity exact")

func _test_horizon_guard(built: Dictionary) -> void:
	var estimate := _one_estimate(built, _flows([0.0, 0.0, 0.0, 0.0]), 3.81)
	_check(bool(estimate.get("success", false)), "near-horizon estimator creates")
	if not bool(estimate.get("success", false)):
		return
	var safety := Certification.evaluate_runtime(built["certification"], estimate["details"])
	_check(not bool(safety.get("success", false)), "horizon guard refines before validity exit")
	_check(String(safety.get("error_code", "")) == "DYNAMIC_ROM_REFINEMENT_REQUIRED", "horizon guard returns refinement")
	_check(String(safety["details"]["guard_id"]) == Certification.HORIZON_GUARD_ID, "horizon guard identity exact")

func _test_validity_exit(built: Dictionary) -> void:
	var flow_estimate := _one_estimate(built, _flows([1.01, 0.0, 0.0, 0.0]), 0.01)
	_check(bool(flow_estimate.get("success", false)), "out-of-domain flow estimator still observable")
	if bool(flow_estimate.get("success", false)):
		var flow_safety := Certification.evaluate_runtime(built["certification"], flow_estimate["details"])
		_check(not bool(flow_safety.get("success", false)), "flow validity exit fails closed")
		_check(String(flow_safety.get("error_code", "")) == "DYNAMIC_ROM_VALIDITY_EXIT", "flow validity exit code exact")
		_check(String(flow_safety["details"]["fallback"]) == "FULL_OR_NO_SAFE_BAKE", "flow validity exit fallback exact")

	var horizon_estimate := _one_estimate(built, _flows([0.0, 0.0, 0.0, 0.0]), 4.01)
	_check(bool(horizon_estimate.get("success", false)), "out-of-horizon estimator still observable")
	if bool(horizon_estimate.get("success", false)):
		var horizon_safety := Certification.evaluate_runtime(built["certification"], horizon_estimate["details"])
		_check(not bool(horizon_safety.get("success", false)), "horizon validity exit fails closed")
		_check(String(horizon_safety.get("error_code", "")) == "DYNAMIC_ROM_VALIDITY_EXIT", "horizon validity code exact")

func _test_fail_closed_tamper(built: Dictionary) -> void:
	var certification: Dictionary = built["certification"]
	var tampered := certification.duplicate(true)
	tampered["alpha_dissipation_lower_bound"] = 0.0
	tampered["checksum"] = Utils.compute_checksum(tampered)
	var checked := Certification.validate(tampered)
	_check(not bool(checked.get("success", false)), "zero dissipativity certificate rejected")

	var too_large_step := Certification.estimate_after_step(
		certification,
		built["full_model"],
		built["descriptor"],
		0.0,
		_zero_rom_values(built["descriptor"]),
		_zero_rom_values(built["descriptor"]),
		_flows([0.0, 0.0, 0.0, 0.0]),
		0.03,
		0.03
	)
	_check(not bool(too_large_step.get("success", false)), "step beyond certified max rejected")
	_check(String(too_large_step.get("error_code", "")) == "DYNAMIC_ROM_CERTIFIED_STEP_OUTSIDE_DOMAIN", "large-step rejection exact")

func _one_estimate(built: Dictionary, flows: Dictionary, elapsed_s: float) -> Dictionary:
	var descriptor: Dictionary = built["descriptor"]
	var initial := ROMRuntime.initial_state(descriptor)
	if not bool(initial.get("success", false)):
		return initial
	var prepared := ROMRuntime.prepare_step(descriptor, DT)
	if not bool(prepared.get("success", false)):
		return prepared
	var old_values: Array = initial["state"]["values"].duplicate()
	var step := ROMRuntime.step_prepared(descriptor, initial["state"], flows, DT, prepared)
	if not bool(step.get("success", false)):
		return step
	return Certification.estimate_after_step(
		built["certification"],
		built["full_model"],
		descriptor,
		0.0,
		old_values,
		step["state"]["values"],
		flows,
		DT,
		elapsed_s
	)

func _safe_probe_flows(step: int, time_s: float) -> Dictionary:
	var a := 0.20 * sin(TAU * 0.35 * time_s)
	var b := 0.10 * sin(TAU * 0.11 * time_s)
	var c := 0.06 * float(int((step * 37 + 11) % 101) - 50) / 50.0
	var d := 0.04 * sin(TAU * (0.08 * time_s + 0.08 * time_s * time_s))
	return _flows([a, b, c, d])

func _flows(values: Array) -> Dictionary:
	return {
		"port/electrical/000-left": float(values[0]),
		"port/electrical/170-mid-a": float(values[1]),
		"port/electrical/341-mid-b": float(values[2]),
		"port/electrical/511-right": float(values[3]),
	}

func _zero_rom_values(descriptor: Dictionary) -> Array:
	var values: Array = []
	values.resize(int(descriptor["reduced_state_count"]))
	values.fill(0.0)
	return values

func _boundary_by_id(boundary: Array) -> Dictionary:
	var output := {}
	for item in boundary:
		output[String(item["port_id"])] = item
	return output

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC-BAKE B0.4-C Runtime Error / Refinement Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("B0.4-C: %s" % failure)
	print("FABRIC-BAKE B0.4-C Runtime Error / Refinement Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

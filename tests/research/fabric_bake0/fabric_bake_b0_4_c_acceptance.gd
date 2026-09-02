extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullValidation = preload("res://scripts/research/fabric_bake0/dynamic_rom_full_validation_reference_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const ROMRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_v1.gd")
const Certification = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_certification_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const RuntimeEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")
const RefinementGuard = preload("res://scripts/research/fabric_bake0/refinement_guard_v1.gd")
const RuntimeCertificate = preload("res://scripts/research/fabric_bake0/rom_runtime_certificate_v1.gd")
const RuntimeMonitor = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_monitor_v1.gd")
const ContactCompiler = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_compiler_v1.gd")
const ContactRuntime = preload("res://scripts/research/fabric_bake0/contact_wrench_bake_runtime_v1.gd")
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
	_test_free_response(built)
	_test_runtime_certificate_contract(built)
	_test_component_threshold_semantics(built)
	_test_deterministic_invalidation_and_fallback(built)
	_test_source_revision_invalidation(built)
	_test_persistent_contact_observable(built)
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


func _test_free_response(built: Dictionary) -> void:
	var descriptor: Dictionary = built["descriptor"]
	var initial := ROMRuntime.initial_state(descriptor)
	var prepared := ROMRuntime.prepare_step(descriptor, DT)
	_check(bool(initial.get("success", false)), "free-response ROM initial state")
	_check(bool(prepared.get("success", false)), "free-response prepared operator")
	if not bool(initial.get("success", false)) or not bool(prepared.get("success", false)):
		return
	var state: Dictionary = initial["state"]
	var error_bound := 0.0
	for step in range(12):
		var old_values: Array = state["values"].duplicate()
		var advanced := ROMRuntime.step_prepared(descriptor, state, _flows([0.0, 0.0, 0.0, 0.0]), DT, prepared)
		_check(bool(advanced.get("success", false)), "free-response ROM step")
		if not bool(advanced.get("success", false)):
			return
		state = advanced["state"]
		var estimate := Certification.estimate_after_step(
			built["certification"], built["full_model"], descriptor, error_bound,
			old_values, state["values"], _flows([0.0, 0.0, 0.0, 0.0]), DT, DT * float(step + 1)
		)
		_check(bool(estimate.get("success", false)), "free-response residual estimate")
		if not bool(estimate.get("success", false)):
			return
		error_bound = float(estimate["details"]["error_c_norm_bound"])
		var runtime := Certification.build_runtime_certificate(built["certification"], estimate["details"])
		_check(bool(runtime.get("success", false)), "free-response runtime certificate")
		if not bool(runtime.get("success", false)):
			return
		_check(bool(runtime["details"]["certificate"]["valid"]), "free response remains certified")
	_check(error_bound <= 1.0e-12, "zero-input free response has negligible state residual")

func _test_runtime_certificate_contract(built: Dictionary) -> void:
	var estimate := _one_estimate(built, _flows([0.12, -0.05, 0.03, 0.02]), 0.01)
	_check(bool(estimate.get("success", false)), "runtime certificate probe estimate creates")
	if not bool(estimate.get("success", false)):
		return
	var built_certificate := Certification.build_runtime_certificate(built["certification"], estimate["details"])
	_check(bool(built_certificate.get("success", false)), "unified RomRuntimeCertificate creates")
	if not bool(built_certificate.get("success", false)):
		return
	var runtime_certificate: Dictionary = built_certificate["details"]["certificate"]
	_check(bool(RuntimeCertificate.validate(runtime_certificate).get("success", false)), "RomRuntimeCertificate validates")
	_check(bool(runtime_certificate["valid"]), "safe runtime certificate valid")
	_check(float(runtime_certificate["residual_norm"]) >= 0.0, "runtime certificate residual norm observable")
	_check(float(runtime_certificate["relative_residual"]) <= float(runtime_certificate["threshold"]), "relative runtime residual within normalized threshold")
	_check(float(runtime_certificate["state_error"]) >= 0.0, "state residual metric present")
	_check(float(runtime_certificate["port_error"]) >= 0.0, "port/wrench residual metric present")
	_check(float(runtime_certificate["energy_error"]) >= 0.0, "energy residual metric present")
	_check(float(runtime_certificate["constraint_error"]) == 0.0, "no-active-constraint model explicitly reports zero constraint residual")
	_check(RuntimeCertificate.COMPONENTS.has(String(runtime_certificate["worst_component"])), "worst component deterministic")
	_check(String(runtime_certificate["reason"]) == "CERTIFIED", "valid runtime certificate reason exact")

func _test_component_threshold_semantics(built: Dictionary) -> void:
	var thresholds := Certification.runtime_component_thresholds()
	var source_hash := String(built["certification"]["source_binding_checksum"])
	var descriptor_hash := String(built["descriptor"]["descriptor_hash"])
	var at_threshold := RuntimeCertificate.create(
		source_hash, descriptor_hash, 0.0,
		float(thresholds["state"]), 0.0, 0.0, 0.0, thresholds, 0.0
	)
	_check(not at_threshold.is_empty(), "threshold equality certificate creates")
	_check(bool(at_threshold["valid"]), "residual == threshold remains valid by contract")
	_check(absf(float(at_threshold["relative_residual"]) - 1.0) <= 1.0e-15, "threshold equality normalized exactly")

	var state_invalid := RuntimeCertificate.create(
		source_hash, descriptor_hash, 1.0,
		float(thresholds["state"]) * 1.01, 0.0, 0.0, 0.0, thresholds, 0.0
	)
	_check(not bool(state_invalid["valid"]), "state residual crossing invalidates certificate")
	_check(String(state_invalid["reason"]) == "STATE_RESIDUAL_EXCEEDED", "state residual reason exact")

	var port_invalid := RuntimeCertificate.create(
		source_hash, descriptor_hash, 1.0,
		0.0, float(thresholds["port"]) * 1.01, 0.0, 0.0, thresholds, 0.0
	)
	_check(not bool(port_invalid["valid"]), "port/wrench residual crossing invalidates certificate")
	_check(String(port_invalid["reason"]) == "PORT_RESIDUAL_EXCEEDED", "port/wrench residual reason exact")

	var energy_invalid := RuntimeCertificate.create(
		source_hash, descriptor_hash, 1.0,
		0.0, 0.0, float(thresholds["energy"]) * 1.01, 0.0, thresholds, 0.0
	)
	_check(not bool(energy_invalid["valid"]), "energy residual crossing invalidates certificate")
	_check(String(energy_invalid["reason"]) == "ENERGY_RESIDUAL_EXCEEDED", "energy residual reason exact")

	var constraint_invalid := RuntimeCertificate.create(
		source_hash, descriptor_hash, 1.0,
		0.0, 0.0, 0.0, float(thresholds["constraint"]) * 1.01, thresholds, 0.0
	)
	_check(not bool(constraint_invalid["valid"]), "constraint residual crossing invalidates certificate")
	_check(String(constraint_invalid["reason"]) == "CONSTRAINT_RESIDUAL_EXCEEDED", "constraint residual reason exact")

	var nonfinite := RuntimeCertificate.create(
		source_hash, descriptor_hash, 0.0,
		NAN, 0.0, 0.0, 0.0, thresholds, 0.0
	)
	_check(nonfinite.is_empty(), "NaN runtime observable cannot certify")
	var missing_threshold := thresholds.duplicate(true)
	missing_threshold.erase("constraint")
	var missing := RuntimeCertificate.create(
		source_hash, descriptor_hash, 0.0,
		0.0, 0.0, 0.0, 0.0, missing_threshold, 0.0
	)
	_check(missing.is_empty(), "missing required observable threshold cannot certify")

func _test_deterministic_invalidation_and_fallback(built: Dictionary) -> void:
	var model: Dictionary = built["full_model"]
	var descriptor: Dictionary = built["descriptor"]
	var certification: Dictionary = built["certification"]
	var full_prepared := FullValidation.prepare(model, DT)
	var rom_initial := ROMRuntime.initial_state(descriptor)
	var rom_prepared := ROMRuntime.prepare_step(descriptor, DT)
	_check(bool(full_prepared.get("success", false)), "fallback FULL operator prepared")
	_check(bool(rom_initial.get("success", false)), "fallback ROM state prepared")
	_check(bool(rom_prepared.get("success", false)), "fallback ROM operator prepared")
	if not bool(full_prepared.get("success", false)) or not bool(rom_initial.get("success", false)) or not bool(rom_prepared.get("success", false)):
		return

	var source_hash := String(certification["source_binding_checksum"])
	var monitor := RuntimeMonitor.create(source_hash, String(descriptor["descriptor_hash"]))
	_check(not monitor.is_empty(), "ROM runtime monitor creates ACTIVE")
	var canonical_values: Array = FullValidation.zero_state(full_prepared)
	var reference_values: Array = FullValidation.zero_state(full_prepared)
	var rom_state: Dictionary = rom_initial["state"]
	var error_bound := 0.0
	var last_valid_certificate: Dictionary = {}
	var crossed := false
	var invalidation_reason := ""

	for step in range(36):
		var flows := _safe_probe_flows(step, DT * float(step + 1))
		if step >= 18:
			flows = _flows([0.35, -0.15, 0.11, 0.08])

		var canonical_step := FullValidation.step(full_prepared, canonical_values, flows)
		var reference_step := FullValidation.step(full_prepared, reference_values, flows)
		_check(bool(canonical_step.get("success", false)) and bool(reference_step.get("success", false)), "canonical FULL fallback step succeeds")
		if not bool(canonical_step.get("success", false)) or not bool(reference_step.get("success", false)):
			return
		canonical_values = canonical_step["values"]
		reference_values = reference_step["values"]
		_check(_max_abs_difference(canonical_values, reference_values) <= 1.0e-15, "canonical FULL path unchanged by ROM monitoring")

		if String(monitor["state"]) == RuntimeMonitor.ROM_INVALID:
			continue

		var old_rom_values: Array = rom_state["values"].duplicate()
		var rom_step := ROMRuntime.step_prepared(descriptor, rom_state, flows, DT, rom_prepared)
		_check(bool(rom_step.get("success", false)), "candidate ROM step succeeds before certification decision")
		if not bool(rom_step.get("success", false)):
			return
		var candidate_values: Array = rom_step["state"]["values"].duplicate()
		if step == 18:
			candidate_values[0] = float(candidate_values[0]) + 0.25

		var estimate := Certification.estimate_after_step(
			certification, model, descriptor, error_bound,
			old_rom_values, candidate_values, flows, DT, DT * float(step + 1)
		)
		_check(bool(estimate.get("success", false)), "runtime residual remains observable across threshold crossing")
		if not bool(estimate.get("success", false)):
			return
		var built_certificate := Certification.build_runtime_certificate(certification, estimate["details"])
		_check(bool(built_certificate.get("success", false)), "threshold-crossing runtime certificate creates")
		if not bool(built_certificate.get("success", false)):
			return
		var runtime_certificate: Dictionary = built_certificate["details"]["certificate"]

		if step < 18:
			_check(bool(runtime_certificate["valid"]), "ROM valid before changing-load disturbance")
			last_valid_certificate = runtime_certificate
		else:
			_check(not bool(runtime_certificate["valid"]), "residual crosses threshold after changing-load disturbance")
			_check(float(runtime_certificate["relative_residual"]) > float(runtime_certificate["threshold"]), "crossing is numerically explicit")
			crossed = true

		var observed := RuntimeMonitor.observe(monitor, runtime_certificate, source_hash, step)
		_check(bool(observed.get("success", false)), "runtime monitor accepts deterministic observation")
		if not bool(observed.get("success", false)):
			return
		monitor = observed["details"]["monitor"]
		if step < 18:
			_check(String(monitor["state"]) == RuntimeMonitor.ROM_ACTIVE, "valid certificate keeps ROM_ACTIVE")
			rom_state = rom_step["state"]
			error_bound = float(estimate["details"]["error_c_norm_bound"])
		else:
			_check(String(monitor["state"]) == RuntimeMonitor.ROM_INVALID, "threshold crossing transitions ROM_ACTIVE -> ROM_INVALID")
			invalidation_reason = String(monitor["invalidation_reason"])
			var forbidden := RuntimeMonitor.can_execute(monitor)
			_check(not bool(forbidden.get("success", false)), "ROM execution forbidden immediately after invalidation")

	_check(crossed, "threshold crossing observed")
	_check(not invalidation_reason.is_empty(), "deterministic invalidation reason retained")
	_check(_max_abs_difference(canonical_values, reference_values) <= 1.0e-15, "FULL fallback continues canonical state without replacement jump")
	if not last_valid_certificate.is_empty():
		var sticky := RuntimeMonitor.observe(monitor, last_valid_certificate, source_hash, 100)
		_check(bool(sticky.get("success", false)), "post-invalidation observation is deterministic")
		if bool(sticky.get("success", false)):
			var sticky_monitor: Dictionary = sticky["details"]["monitor"]
			_check(String(sticky_monitor["state"]) == RuntimeMonitor.ROM_INVALID, "ROM_INVALID is sticky")
			_check(String(sticky_monitor["invalidation_reason"]) == invalidation_reason, "sticky invalidation preserves first reason")

func _test_source_revision_invalidation(built: Dictionary) -> void:
	var estimate := _one_estimate(built, _flows([0.1, 0.0, 0.0, 0.0]), 0.01)
	_check(bool(estimate.get("success", false)), "source-revision probe estimate creates")
	if not bool(estimate.get("success", false)):
		return
	var built_certificate := Certification.build_runtime_certificate(built["certification"], estimate["details"])
	_check(bool(built_certificate.get("success", false)), "source-revision probe certificate creates")
	if not bool(built_certificate.get("success", false)):
		return
	var monitor := RuntimeMonitor.create(
		String(built["certification"]["source_binding_checksum"]),
		String(built["descriptor"]["descriptor_hash"])
	)
	var changed_source := "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
	if changed_source == String(built["certification"]["source_binding_checksum"]):
		changed_source = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	var observed := RuntimeMonitor.observe(monitor, built_certificate["details"]["certificate"], changed_source, 1)
	_check(bool(observed.get("success", false)), "source mismatch produces invalidation transition")
	if not bool(observed.get("success", false)):
		return
	monitor = observed["details"]["monitor"]
	_check(String(monitor["state"]) == RuntimeMonitor.ROM_INVALID, "source revision mismatch invalidates ROM")
	_check(String(monitor["invalidation_reason"]) == "SOURCE_REVISION_MISMATCH", "source revision invalidation reason exact")
	_check(not bool(RuntimeMonitor.can_execute(monitor).get("success", false)), "source-revision-stale ROM execution forbidden")

func _test_persistent_contact_observable(built: Dictionary) -> void:
	var points := _contact_grid_points(21, 1.0, 0.75)
	var request := {
		"model_id": "artifact/b0-4-c-contact-observable",
		"patch_id": "contact-patch/b0-4-c-grid",
		"source_frontier_hash": String(built["full_model"]["source_binding"]["frontier_hash"]),
		"physical_graph_hash": String(built["full_model"]["source_binding"]["fabric_graph_hash"]),
		"parent_artifact_checksum": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
		"authority_checksum": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
		"origin": Vector3.ZERO,
		"normal": Vector3(0.0, 0.0, 1.0),
		"t1": Vector3(1.0, 0.0, 0.0),
		"t2": Vector3(0.0, 1.0, 0.0),
		"points": points,
		"normal_support_limit": 12.0,
		"mu_tangent": 0.6,
		"mu_rolling": 0.08,
		"mu_torsion": 0.05,
		"effective_radius": 0.4,
		"minimum_reduction_ratio": 2.0,
	}
	var compiled := ContactCompiler.compile(request)
	_check(bool(compiled.get("ok", false)), "B0.3 persistent-contact artifact compiles inside B0.4-C observable test")
	if not bool(compiled.get("ok", false)):
		return
	var artifact: Dictionary = compiled["model"]
	var persistent := ContactRuntime.normal_support_guard(artifact, 3.0)
	_check(bool(persistent.get("persistent_contact_feasible", false)), "persistent contact remains feasible")
	_check(not bool(persistent.get("capacity_exceeded", true)), "persistent contact inside wrench capacity")
	var dissipative := ContactRuntime.maximum_dissipation_wrench(
		artifact, [0.2, -0.4, 0.0, 0.3, 0.0, 0.0]
	)
	_check(bool(dissipative.get("ok", false)), "persistent contact wrench observable evaluates")
	if bool(dissipative.get("ok", false)):
		_check(float(dissipative["contact_power"]) <= 2.0e-10, "persistent contact does not invent energy")

	var thresholds := Certification.runtime_component_thresholds()
	var safe_contact_certificate := RuntimeCertificate.create(
		String(built["certification"]["source_binding_checksum"]),
		String(built["descriptor"]["descriptor_hash"]),
		0.0, 0.0, 0.0, 0.0, 0.0, thresholds, 0.0
	)
	_check(bool(safe_contact_certificate["valid"]), "feasible persistent contact observable can remain certified")

	var overload := ContactRuntime.normal_support_guard(artifact, 12.5)
	_check(bool(overload.get("capacity_exceeded", false)), "contact overload is an explicit constraint exit")
	var constraint_error := maxf(0.0, -float(overload["capacity_margin"]))
	var overload_certificate := RuntimeCertificate.create(
		String(built["certification"]["source_binding_checksum"]),
		String(built["descriptor"]["descriptor_hash"]),
		constraint_error, 0.0, 0.0, 0.0, constraint_error, thresholds, 0.0
	)
	_check(not bool(overload_certificate["valid"]), "contact constraint residual invalidates unified runtime certificate")
	_check(String(overload_certificate["worst_component"]) == "CONSTRAINT", "contact capacity exit classified as constraint residual")

func _contact_grid_points(size: int, half_x: float, half_y: float) -> Array:
	var points: Array = []
	for iy in range(size):
		for ix in range(size):
			var x := lerpf(-half_x, half_x, float(ix) / float(size - 1))
			var y := lerpf(-half_y, half_y, float(iy) / float(size - 1))
			points.append({"id": "member/%03d/%03d" % [iy, ix], "position": Vector3(x, y, 0.0)})
	return points

func _max_abs_difference(a: Array, b: Array) -> float:
	if a.size() != b.size():
		return INF
	var result := 0.0
	for index in range(a.size()):
		result = maxf(result, absf(float(a[index]) - float(b[index])))
	return result

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

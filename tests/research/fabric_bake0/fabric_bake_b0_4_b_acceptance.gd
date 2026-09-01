extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const CompilerA = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const FullSolver = preload("res://scripts/research/fabric_bake0/dynamic_full_reference_solver_v1.gd")
const CompilerB = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd")
const Binding = preload("res://scripts/research/fabric_bake0/dynamic_rom_artifact_binding_v1.gd")
const RomRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

const DT := 0.005
const RESPONSE_REL_LIMIT := 1.0e-3
const RESPONSE_ABS_LIMIT := 1.0e-3

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var compiled := _compile_reference("ZERO")
	if compiled.is_empty():
		_finish()
		return
	var full_model: Dictionary = compiled["full_model"]
	var reduction: Dictionary = compiled["reduction"]
	var descriptor: Dictionary = reduction["descriptor"]

	_test_descriptor_contract(full_model, reduction)
	_test_order_determinism()
	_test_fail_closed(full_model, descriptor)
	_test_dynamic_response(full_model, descriptor)
	_test_rom_passivity_after_drive(descriptor)
	_test_runtime_determinism(descriptor)
	_finish()

func _compile_reference(profile: String) -> Dictionary:
	var fixture := Fixture.build(profile)
	var full := CompilerA.compile(fixture["request"])
	_check(bool(full.get("success", false)), "B0.4-A FULL reference compiles")
	if not bool(full.get("success", false)):
		return {}
	var reduction := CompilerB.compile(full["model"])
	_check(bool(reduction.get("success", false)), "B0.4-B reduction compiles")
	if not bool(reduction.get("success", false)):
		return {}
	return {
		"fixture": fixture,
		"full_model": full["model"],
		"reduction": reduction,
	}

func _test_descriptor_contract(full_model: Dictionary, reduction: Dictionary) -> void:
	_check(String(reduction["status"]) == CompilerB.STATUS_READY, "B0.4-B status exact")
	var descriptor: Dictionary = reduction["descriptor"]
	var binding: Dictionary = reduction["artifact_binding"]
	_check(bool(Descriptor.validate(descriptor).get("success", false)), "ROM descriptor validates")
	_check(bool(Binding.validate(binding).get("success", false)), "artifact interface binding validates")
	_check(int(descriptor["full_state_count"]) == 512, "FULL state count frozen at 512")
	_check(int(descriptor["reduced_state_count"]) == 24, "ROM has exactly 24 reduced states")
	_check(float(descriptor["reduction_ratio"]) >= 20.0, "state-count reduction >= 20x")
	_check(absf(float(descriptor["reduction_ratio"]) - (512.0 / 24.0)) <= 1.0e-12, "reduction ratio exact")
	_check(String(descriptor["basis_method"]) == Descriptor.BASIS_METHOD, "basis method exact")
	_check(descriptor["laplace_shifts"] == CompilerB.LAPLACE_SHIFTS, "frozen rational shifts exact")
	_check(descriptor["basis_matrix"].size() == 512, "basis has one row per FULL state")
	_check(descriptor["basis_matrix"][0].size() == 24, "basis has 24 columns")
	_check(String(descriptor["full_model_hash"]) == String(full_model["model_hash"]), "descriptor binds exact FULL model")
	_check(String(descriptor["source_binding_checksum"]) == String(full_model["source_binding"]["checksum"]), "descriptor binds source provenance")
	_check(String(descriptor["boundary_contract_hash"]) == String(full_model["boundary_contract"]["contract_hash"]), "descriptor binds boundary contract")
	_check(String(descriptor["full_state_schema_hash"]) == String(full_model["full_state_schema"]["schema_hash"]), "descriptor binds FULL state schema")
	_check(String(descriptor["basis_hash"]).length() == 64, "basis hash present")
	_check(String(descriptor["descriptor_hash"]).length() == 64, "descriptor hash present")
	_check(String(descriptor["reduced_state_schema_hash"]).length() == 64, "reduced state schema hash present")

	var passivity: Dictionary = descriptor["passivity_certificate"]
	_check(bool(passivity["certified"]), "congruence passivity certificate GREEN")
	_check(String(passivity["certificate_kind"]) == "CONGRUENCE_PASSIVITY_SPD_R1", "passivity certificate kind exact")
	_check(float(passivity["c_orthonormality_error"]) <= CompilerB.ORTHONORMALITY_TOLERANCE, "C-orthonormal basis certified")
	_check(float(passivity["mass_symmetry_error"]) <= 1.0e-12, "reduced mass symmetric")
	_check(float(passivity["dissipation_symmetry_error"]) <= 1.0e-12, "reduced dissipation symmetric")
	_check(float(passivity["mass_min_cholesky_pivot"]) > 1.0e-10, "reduced mass SPD")
	_check(float(passivity["dissipation_min_cholesky_pivot"]) > 1.0e-10, "reduced dissipation SPD")

	var interpolation: Dictionary = descriptor["interpolation_certificate"]
	_check(bool(interpolation["certified"]), "rational interpolation certificate GREEN")
	_check(int(interpolation["probe_count"]) == 24, "24 shift/port interpolation probes certified")
	_check(float(interpolation["max_abs_boundary_error"]) <= CompilerB.INTERPOLATION_TOLERANCE, "interpolation absolute error certified")
	_check(float(interpolation["max_relative_boundary_error"]) <= CompilerB.INTERPOLATION_TOLERANCE, "interpolation relative error certified")

	_check(String(binding["reduction_class"]) == "APPROXIMATE", "artifact binding reduction class approximate")
	_check(binding["execution_ready"] == false, "B0.4-B artifact binding is not runtime-ready")
	_check(String(binding["source_binding_checksum"]) == String(descriptor["source_binding_checksum"]), "artifact binding source exact")
	_check(String(binding["boundary_contract_hash"]) == String(descriptor["boundary_contract_hash"]), "artifact binding boundary exact")
	_check(String(binding["reduced_model_descriptor_hash"]) == String(descriptor["descriptor_hash"]), "artifact binding descriptor exact")
	_check(String(binding["reduced_state_schema_hash"]) == String(descriptor["reduced_state_schema_hash"]), "artifact binding reduced schema exact")
	_check(binding["required_before_execution"] == Binding.REQUIRED_BEFORE_EXECUTION, "B0.4-C/D execution prerequisites frozen")

func _test_order_determinism() -> void:
	var fixture := Fixture.build("ZERO")
	var full_a := CompilerA.compile(fixture["request"])
	var full_b := CompilerA.compile(Fixture.reversed_request(fixture))
	_check(bool(full_a.get("success", false)) and bool(full_b.get("success", false)), "forward/reversed FULL compile")
	if not bool(full_a.get("success", false)) or not bool(full_b.get("success", false)):
		return
	var rom_a := CompilerB.compile(full_a["model"])
	var rom_b := CompilerB.compile(full_b["model"])
	_check(bool(rom_a.get("success", false)) and bool(rom_b.get("success", false)), "forward/reversed ROM compile")
	if not bool(rom_a.get("success", false)) or not bool(rom_b.get("success", false)):
		return
	_check(String(rom_a["descriptor"]["descriptor_hash"]) == String(rom_b["descriptor"]["descriptor_hash"]), "presentation order does not change ROM identity")
	_check(String(rom_a["descriptor"]["basis_hash"]) == String(rom_b["descriptor"]["basis_hash"]), "presentation order does not change basis")
	_check(String(rom_a["artifact_binding"]["binding_hash"]) == String(rom_b["artifact_binding"]["binding_hash"]), "presentation order does not change artifact binding")

func _test_fail_closed(full_model: Dictionary, descriptor: Dictionary) -> void:
	var target25 := CompilerB.compile(full_model, 25)
	_check(not bool(target25.get("success", false)), "25-state target rejected")
	_check(String(target25.get("reason", "")) == "B0_4_B_R1_REQUIRES_24_REDUCED_STATES", "25-state rejection reason exact")

	var wrong_shifts := CompilerB.compile(full_model, 24, [0.0, 0.1, 1.0, 5.0, 20.0, 100.0])
	_check(not bool(wrong_shifts.get("success", false)), "unfrozen shift set rejected")
	_check(String(wrong_shifts.get("reason", "")) == "B0_4_B_R1_SHIFT_SET_MISMATCH", "shift-set rejection reason exact")

	var tampered_model: Dictionary = full_model.duplicate(true)
	tampered_model["storage_nodes"] = Array(tampered_model["storage_nodes"]).duplicate(true)
	tampered_model["storage_nodes"][5] = Dictionary(tampered_model["storage_nodes"][5]).duplicate(true)
	tampered_model["storage_nodes"][5]["storage_coefficient"] = 0.0
	var tampered := CompilerB.compile(tampered_model)
	_check(not bool(tampered.get("success", false)), "invalid FULL predecessor rejected")

	var binding := Binding.create(descriptor)
	var unsafe_binding: Dictionary = binding.duplicate(true)
	unsafe_binding["execution_ready"] = true
	unsafe_binding["binding_hash"] = Utils.canonical_hash(_binding_payload(unsafe_binding))
	unsafe_binding["checksum"] = Utils.compute_checksum(unsafe_binding)
	var unsafe_check := Binding.validate(unsafe_binding)
	_check(not bool(unsafe_check.get("success", false)), "B0.4-B cannot mark artifact execution-ready")
	_check(String(unsafe_check.get("error_code", "")) == "B0_4_B_ROM_EXECUTION_MUST_REMAIN_BLOCKED", "execution-block reason exact")

func _test_dynamic_response(full_model: Dictionary, descriptor: Dictionary) -> void:
	var probes := [
		{"name": "step", "steps": 240},
		{"name": "impulse", "steps": 240},
		{"name": "multi", "steps": 240},
		{"name": "chirp", "steps": 320},
		{"name": "broadband", "steps": 320},
	]
	var worst_relative := 0.0
	var worst_absolute := 0.0
	for probe in probes:
		var result := _compare_probe(full_model, descriptor, String(probe["name"]), int(probe["steps"]))
		_check(bool(result.get("success", false)), "%s FULL-vs-ROM probe executes" % probe["name"])
		if not bool(result.get("success", false)):
			continue
		worst_relative = maxf(worst_relative, float(result["relative_l2_error"]))
		worst_absolute = maxf(worst_absolute, float(result["max_abs_error"]))
		_check(float(result["relative_l2_error"]) <= RESPONSE_REL_LIMIT, "%s relative boundary response <= 1e-3" % probe["name"])
		_check(float(result["max_abs_error"]) <= RESPONSE_ABS_LIMIT, "%s absolute boundary response <= 1e-3" % probe["name"])
		_check(float(result["max_rom_unaccounted_energy_creation"]) <= 1.0e-10, "%s ROM creates no unaccounted energy" % probe["name"])
	print("B0.4-B observed deterministic validation suite: max_relative=%s max_abs=%s (not yet B0.4-C ErrorEnvelope)" % [
		String.num_scientific(worst_relative),
		String.num_scientific(worst_absolute),
	])

func _compare_probe(full_model: Dictionary, descriptor: Dictionary, probe: String, steps: int) -> Dictionary:
	var full_initial := FullSolver.initial_state(full_model)
	var rom_initial := RomRuntime.initial_state(descriptor)
	if not bool(full_initial.get("success", false)) or not bool(rom_initial.get("success", false)):
		return {"success": false}
	var full_state: Dictionary = full_initial["state"]
	var rom_state: Dictionary = rom_initial["state"]
	var prepared := RomRuntime.prepare_step(descriptor, DT)
	if not bool(prepared.get("success", false)):
		return {"success": false}
	var sum_error_sq := 0.0
	var sum_full_sq := 0.0
	var max_abs_error := 0.0
	var max_rom_unaccounted := 0.0
	for step_index in range(steps):
		var flows := _probe_flows(descriptor["port_ids"], probe, step_index, steps)
		var full_step := FullSolver.step(full_model, full_state, flows, DT)
		var rom_step := RomRuntime.step_prepared(descriptor, rom_state, flows, DT, prepared)
		if not bool(full_step.get("success", false)) or not bool(rom_step.get("success", false)):
			return {"success": false}
		full_state = full_step["state"]
		rom_state = rom_step["state"]
		max_rom_unaccounted = maxf(max_rom_unaccounted, float(rom_step["energy"]["unaccounted_energy_creation"]))
		for port_index in range(descriptor["port_ids"].size()):
			var full_effort := float(full_step["boundary"][port_index]["effort"])
			var rom_effort := float(rom_step["boundary"][port_index]["effort"])
			var error := full_effort - rom_effort
			sum_error_sq += error * error
			sum_full_sq += full_effort * full_effort
			max_abs_error = maxf(max_abs_error, absf(error))
	return {
		"success": true,
		"relative_l2_error": sqrt(sum_error_sq / maxf(sum_full_sq, 1.0e-30)),
		"max_abs_error": max_abs_error,
		"max_rom_unaccounted_energy_creation": max_rom_unaccounted,
	}

func _test_rom_passivity_after_drive(descriptor: Dictionary) -> void:
	var initial := RomRuntime.initial_state(descriptor)
	_check(bool(initial.get("success", false)), "ROM passivity initial state")
	if not bool(initial.get("success", false)):
		return
	var drive: Array = []
	for _index in range(120):
		var flows := _zero_flows(descriptor["port_ids"])
		flows[String(descriptor["port_ids"][0])] = 0.45
		drive.append(flows)
	var driven := RomRuntime.advance_sequence(descriptor, initial["state"], drive, DT)
	_check(bool(driven.get("success", false)), "ROM drive sequence executes")
	if not bool(driven.get("success", false)):
		return
	var driven_energy := float(driven["summary"]["final_stored_energy"])
	_check(driven_energy > 0.0, "ROM stores boundary energy")
	_check(float(driven["summary"]["max_unaccounted_energy_creation"]) <= 1.0e-10, "driven ROM has no invented energy")

	var decay: Array = []
	for _index in range(240):
		decay.append(_zero_flows(descriptor["port_ids"]))
	var decayed := RomRuntime.advance_sequence(descriptor, driven["state"], decay, DT)
	_check(bool(decayed.get("success", false)), "ROM zero-input decay executes")
	if not bool(decayed.get("success", false)):
		return
	_check(float(decayed["summary"]["final_stored_energy"]) < driven_energy, "ROM zero-input stored energy decays")
	_check(float(decayed["summary"]["dissipated_energy"]) > 0.0, "ROM physical dissipation positive")
	_check(float(decayed["summary"]["numerical_dissipation_energy"]) >= 0.0, "ROM numerical dissipation nonnegative")
	_check(float(decayed["summary"]["max_unaccounted_energy_creation"]) <= 1.0e-10, "decaying ROM has no invented energy")

func _test_runtime_determinism(descriptor: Dictionary) -> void:
	var initial_a := RomRuntime.initial_state(descriptor)
	var initial_b := RomRuntime.initial_state(descriptor)
	var sequence: Array = []
	for index in range(180):
		sequence.append(_probe_flows(descriptor["port_ids"], "broadband", index, 180))
	var a := RomRuntime.advance_sequence(descriptor, initial_a["state"], sequence, DT)
	var b := RomRuntime.advance_sequence(descriptor, initial_b["state"], sequence, DT)
	_check(bool(a.get("success", false)) and bool(b.get("success", false)), "ROM deterministic twin runs execute")
	if bool(a.get("success", false)) and bool(b.get("success", false)):
		_check(String(a["state"]["checksum"]) == String(b["state"]["checksum"]), "ROM final state checksum deterministic")
		_check(a["state"]["values"] == b["state"]["values"], "ROM final state values deterministic")
		_check(a["summary"] == b["summary"], "ROM energy summary deterministic")

func _probe_flows(port_ids: Array, probe: String, step_index: int, steps: int) -> Dictionary:
	var flows := _zero_flows(port_ids)
	match probe:
		"step":
			flows[String(port_ids[0])] = 0.5
		"impulse":
			flows[String(port_ids[0])] = 1.0 if step_index == 0 else 0.0
		"multi":
			flows[String(port_ids[0])] = 0.30
			flows[String(port_ids[1])] = -0.10
			flows[String(port_ids[2])] = 0.05
			flows[String(port_ids[3])] = 0.02
		"chirp":
			var t := float(step_index) * DT
			var total_t := maxf(DT, float(steps - 1) * DT)
			var f0 := 0.1
			var f1 := 20.0
			var phase := 2.0 * PI * (f0 * t + 0.5 * (f1 - f0) * t * t / total_t)
			flows[String(port_ids[0])] = 0.4 * sin(phase)
		"broadband":
			for port_index in range(port_ids.size()):
				var raw := int((step_index * 37 + port_index * 17 + step_index * step_index * 3 + 11) % 101) - 50
				flows[String(port_ids[port_index])] = float(raw) / 250.0
	return flows

func _zero_flows(port_ids: Array) -> Dictionary:
	var output := {}
	for port_id in port_ids:
		output[String(port_id)] = 0.0
	return output

func _binding_payload(value: Dictionary) -> Dictionary:
	var payload := value.duplicate(true)
	payload.erase("binding_hash")
	payload.erase("checksum")
	return payload

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC-BAKE B0.4-B Certified Reduction Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("B0.4-B: %s" % failure)
	print("FABRIC-BAKE B0.4-B Certified Reduction Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

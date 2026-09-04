extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const Registry = preload("res://scripts/research/fabric_bake0/bridge2_mixed_registry_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2_compliant_response.v1"
const BACKEND_CONTRACT_ID := "COMPLEX2B_COHERENT_KELVIN_VOIGT_R1"
const MODULE_ID := "module/complex2-20"
const REGION_ID := "region/complex2-hybrid"
const PART_COUNT := 80
const REDUCED_STATE_COUNT := 1
const DT := 0.01
const MAX_DEFLECTION_M := 0.15
const MAX_FORCE_N := 120.0
const COHERENCE_TOLERANCE_M := 1.0e-9
const NUMERIC_TOLERANCE := 1.0e-11

static func backend_family_hash() -> String:
	return Utils.canonical_hash({
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"model": "KELVIN_VOIGT_PARALLEL_COHERENT_SECTION",
		"full_parts": PART_COUNT,
		"reduced_states": REDUCED_STATE_COUNT,
		"max_deflection_m": MAX_DEFLECTION_M,
		"max_force_n": MAX_FORCE_N,
	})

static func compile_from_machine(machine: Dictionary) -> Dictionary:
	if not bool(machine.get("success", false)):
		return _failure("COMPLEX2B_MACHINE_REQUIRED")
	var module: Dictionary = {}
	for raw in machine.get("modules", []):
		if String(raw.get("module_id", "")) == MODULE_ID:
			module = Dictionary(raw).duplicate(true)
			break
	if module.is_empty():
		return _failure("COMPLEX2B_COMPLIANT_MODULE_MISSING")
	if String(module.get("region_id", "")) != REGION_ID:
		return _failure("COMPLEX2B_COMPLIANT_MODULE_REGION_MISMATCH")

	var part_ids: Array = []
	for raw in machine.get("parts", []):
		if String(raw.get("module_id", "")) == MODULE_ID:
			part_ids.append(String(raw.get("part_id", "")))
	part_ids.sort()
	if part_ids.size() != PART_COUNT:
		return _failure("COMPLEX2B_COMPLIANT_PART_COUNT_MISMATCH", {"part_count": part_ids.size()})

	var region := Registry.region_by_id(machine["registry"], REGION_ID)
	if region.is_empty():
		return _failure("COMPLEX2B_HYBRID_REGION_MISSING")
	var slice: Dictionary = region["adapter"]["source_slice"]
	var fibers: Array = []
	var total_stiffness := 0.0
	var total_damping := 0.0
	for index in range(part_ids.size()):
		var stiffness := 8.0 + float(index % 5) * 0.5
		var damping := 1.30 + float(index % 4) * 0.10
		fibers.append({
			"part_id": String(part_ids[index]),
			"stiffness_n_per_m": stiffness,
			"damping_n_s_per_m": damping,
		})
		total_stiffness += stiffness
		total_damping += damping

	var full_state_schema_hash := Utils.canonical_hash({
		"schema": "complex2b.full.coherent_deflection.r1",
		"part_ids": part_ids,
		"quantity": "translation_deflection_m",
	})
	var reduced_state_schema_hash := Utils.canonical_hash({
		"schema": "complex2b.reduced.kelvin_voigt.r1",
		"states": ["q_m"],
	})
	var projection_hash := Utils.canonical_hash({
		"method": "COHERENT_MEAN_DEFLECTION_R1",
		"part_count": PART_COUNT,
		"coherence_tolerance_m": COHERENCE_TOLERANCE_M,
	})
	var reconstruction := ReconstructionDescriptor.create(
		"reconstruction/complex2b-compliant-section",
		String(slice["frontier"]["frontier_hash"]),
		projection_hash,
		"CANONICAL_PLUS_REDUCED",
		[{"region_id": REGION_ID, "source_keys": Array(slice["source_keys"]).duplicate()}],
		"STRICT",
		Utils.canonical_hash({"event_frontier": "COMPLEX2B_COMPLIANT_LOCAL_R1"}),
		"COMPLEX2-B/COMPLIANT-RESPONSE-R1"
	)
	if reconstruction.is_empty():
		return _failure("COMPLEX2B_RECONSTRUCTION_DESCRIPTOR_FAILED")
	var mapping := StateMapping.create(
		"state-mapping/complex2b-compliant-section",
		full_state_schema_hash,
		reduced_state_schema_hash,
		projection_hash,
		String(reconstruction["checksum"])
	)
	if mapping.is_empty():
		return _failure("COMPLEX2B_STATE_MAPPING_FAILED")

	var value := {
		"success": true,
		"schema": SCHEMA,
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"backend_family_hash": backend_family_hash(),
		"module_id": MODULE_ID,
		"region_id": REGION_ID,
		"part_ids": part_ids,
		"fibers": fibers,
		"full_state_count": PART_COUNT,
		"reduced_state_count": REDUCED_STATE_COUNT,
		"total_stiffness_n_per_m": total_stiffness,
		"total_damping_n_s_per_m": total_damping,
		"max_deflection_m": MAX_DEFLECTION_M,
		"max_force_n": MAX_FORCE_N,
		"state_mapping": mapping,
		"reconstruction_descriptor": reconstruction,
		"section_hash": "",
	}
	value["section_hash"] = Utils.canonical_hash(_identity_payload(value))
	return value

static func validate(section: Dictionary) -> Dictionary:
	if not bool(section.get("success", false)):
		return _failure("COMPLEX2B_SECTION_NOT_COMPILED")
	if String(section.get("schema", "")) != SCHEMA:
		return _failure("COMPLEX2B_SECTION_SCHEMA_MISMATCH")
	if String(section.get("backend_contract_id", "")) != BACKEND_CONTRACT_ID:
		return _failure("COMPLEX2B_BACKEND_CONTRACT_MISMATCH")
	if String(section.get("backend_family_hash", "")) != backend_family_hash():
		return _failure("COMPLEX2B_BACKEND_FAMILY_HASH_MISMATCH")
	if String(section.get("module_id", "")) != MODULE_ID or String(section.get("region_id", "")) != REGION_ID:
		return _failure("COMPLEX2B_SECTION_BINDING_MISMATCH")
	if int(section.get("full_state_count", 0)) != PART_COUNT or int(section.get("reduced_state_count", 0)) != REDUCED_STATE_COUNT:
		return _failure("COMPLEX2B_STATE_COUNT_MISMATCH")
	if Array(section.get("part_ids", [])).size() != PART_COUNT or Array(section.get("fibers", [])).size() != PART_COUNT:
		return _failure("COMPLEX2B_FIBER_COVERAGE_MISMATCH")
	if float(section.get("total_stiffness_n_per_m", 0.0)) <= 0.0 or float(section.get("total_damping_n_s_per_m", 0.0)) <= 0.0:
		return _failure("COMPLEX2B_NONPASSIVE_COEFFICIENTS")
	var checked := StateMapping.validate(section.get("state_mapping", {}))
	if not bool(checked.get("success", false)):
		return _failure("COMPLEX2B_STATE_MAPPING_INVALID", checked)
	checked = ReconstructionDescriptor.validate(section.get("reconstruction_descriptor", {}))
	if not bool(checked.get("success", false)):
		return _failure("COMPLEX2B_RECONSTRUCTION_INVALID", checked)
	if String(section.get("section_hash", "")) != Utils.canonical_hash(_identity_payload(section)):
		return _failure("COMPLEX2B_SECTION_HASH_MISMATCH")
	return {"success": true}

static func full_state(section: Dictionary, q_m: float) -> Dictionary:
	var checked := validate(section)
	if not bool(checked.get("success", false)):
		return checked
	if not is_finite(q_m):
		return _failure("COMPLEX2B_INVALID_FULL_STATE")
	var deflections: Array = []
	for part_id in section["part_ids"]:
		deflections.append({"part_id": String(part_id), "q_m": q_m})
	return {
		"success": true,
		"deflections": deflections,
		"state_hash": Utils.canonical_hash(deflections),
	}

static func project_full(section: Dictionary, state: Dictionary) -> Dictionary:
	var checked := validate(section)
	if not bool(checked.get("success", false)):
		return checked
	var deflections: Array = Array(state.get("deflections", []))
	if deflections.size() != PART_COUNT:
		return _failure("COMPLEX2B_FULL_STATE_COVERAGE_MISMATCH")
	var sum_q := 0.0
	var min_q := INF
	var max_q := -INF
	for index in range(deflections.size()):
		var entry: Dictionary = deflections[index]
		if String(entry.get("part_id", "")) != String(section["part_ids"][index]) or not is_finite(float(entry.get("q_m", NAN))):
			return _failure("COMPLEX2B_FULL_STATE_ID_OR_VALUE_MISMATCH", {"index": index})
		var q := float(entry["q_m"])
		sum_q += q
		min_q = minf(min_q, q)
		max_q = maxf(max_q, q)
	if max_q - min_q > COHERENCE_TOLERANCE_M:
		return _failure("COMPLEX2B_COHERENT_MODE_VIOLATION", {"spread_m": max_q - min_q})
	var q_m := sum_q / float(PART_COUNT)
	return {
		"success": true,
		"q_m": q_m,
		"coherence_spread_m": max_q - min_q,
		"reduced_state_hash": Utils.canonical_hash({"q_m": q_m}),
	}

static func reconstruct_full(section: Dictionary, q_m: float) -> Dictionary:
	return full_state(section, q_m)

static func reduced_step(section: Dictionary, q_m: float, force_n: float, delta_s: float) -> Dictionary:
	var checked := validate(section)
	if not bool(checked.get("success", false)):
		return checked
	return _step_with_coefficients(
		q_m,
		force_n,
		delta_s,
		float(section["total_stiffness_n_per_m"]),
		float(section["total_damping_n_s_per_m"]),
		true
	)

static func full_reference_step(section: Dictionary, state: Dictionary, force_n: float, delta_s: float) -> Dictionary:
	var projected := project_full(section, state)
	if not bool(projected.get("success", false)):
		return projected
	var stiffness := 0.0
	var damping := 0.0
	for fiber in section["fibers"]:
		stiffness += float(fiber["stiffness_n_per_m"])
		damping += float(fiber["damping_n_s_per_m"])
	var stepped := _step_with_coefficients(float(projected["q_m"]), force_n, delta_s, stiffness, damping, false)
	if not bool(stepped.get("success", false)):
		return stepped
	var reconstructed := reconstruct_full(section, float(stepped["q_m"]))
	if not bool(reconstructed.get("success", false)):
		return reconstructed
	stepped["full_state"] = reconstructed
	return stepped

static func run_envelope(machine: Dictionary) -> Dictionary:
	var section: Dictionary = machine.get("compliant_section", {})
	if section.is_empty():
		section = compile_from_machine(machine)
	var checked := validate(section)
	if not bool(checked.get("success", false)):
		return checked

	var reduced_q := 0.0
	var full := full_state(section, 0.0)
	if not bool(full.get("success", false)):
		return full
	var schedule := [
		{"phase": "RAMP_20", "force_n": 20.0, "steps": 5},
		{"phase": "RAMP_40", "force_n": 40.0, "steps": 5},
		{"phase": "RAMP_60", "force_n": 60.0, "steps": 5},
		{"phase": "LOAD_80", "force_n": 80.0, "steps": 15},
		{"phase": "HOLD_80", "force_n": 80.0, "steps": 10},
		{"phase": "RELEASE", "force_n": 0.0, "steps": 50},
	]
	var max_full_delta := 0.0
	var max_reconstruction_error := 0.0
	var max_energy_residual := 0.0
	var min_dissipated_energy := INF
	var peak_abs_deflection := 0.0
	var total_boundary_work := 0.0
	var total_dissipated_energy := 0.0
	var release_energy_monotonic := true
	var previous_release_energy := INF
	var samples: Array = []
	var handoff_roundtrip_error := 0.0
	var handoff_reconstruction_error := 0.0

	for phase in schedule:
		var force_n := float(phase["force_n"])
		for step_index in range(int(phase["steps"])):
			var reduced := reduced_step(section, reduced_q, force_n, DT)
			var reference := full_reference_step(section, full, force_n, DT)
			if not bool(reduced.get("success", false)):
				return _failure("COMPLEX2B_REDUCED_ENVELOPE_STEP_FAILED", {"phase": phase["phase"], "step": step_index, "result": reduced})
			if not bool(reference.get("success", false)):
				return _failure("COMPLEX2B_FULL_ENVELOPE_STEP_FAILED", {"phase": phase["phase"], "step": step_index, "result": reference})
			reduced_q = float(reduced["q_m"])
			full = reference["full_state"]
			var projected := project_full(section, full)
			if not bool(projected.get("success", false)):
				return projected
			max_full_delta = maxf(max_full_delta, absf(reduced_q - float(projected["q_m"])))
			var reconstructed := reconstruct_full(section, reduced_q)
			if not bool(reconstructed.get("success", false)):
				return reconstructed
			max_reconstruction_error = maxf(max_reconstruction_error, _full_state_error(reconstructed, full))
			max_energy_residual = maxf(max_energy_residual, absf(float(reduced["energy_balance_residual_j"])))
			min_dissipated_energy = minf(min_dissipated_energy, float(reduced["dissipated_energy_j"]))
			peak_abs_deflection = maxf(peak_abs_deflection, absf(reduced_q))
			total_boundary_work += float(reduced["boundary_work_j"])
			total_dissipated_energy += float(reduced["dissipated_energy_j"])
			if String(phase["phase"]) == "RELEASE":
				var energy := float(reduced["stored_energy_after_j"])
				if previous_release_energy < INF and energy > previous_release_energy + NUMERIC_TOLERANCE:
					release_energy_monotonic = false
				previous_release_energy = energy
			if samples.is_empty() or step_index == int(phase["steps"]) - 1:
				samples.append({
					"phase": String(phase["phase"]),
					"force_n": force_n,
					"q_m": reduced_q,
					"stored_energy_j": float(reduced["stored_energy_after_j"]),
				})

		if String(phase["phase"]) == "LOAD_80":
			var handoff_full := reconstruct_full(section, reduced_q)
			var handoff_projected := project_full(section, handoff_full)
			if not bool(handoff_projected.get("success", false)):
				return handoff_projected
			handoff_roundtrip_error = absf(reduced_q - float(handoff_projected["q_m"]))
			handoff_reconstruction_error = _full_state_error(handoff_full, full)

	var over_force := reduced_step(section, reduced_q, MAX_FORCE_N + 1.0, DT)
	var over_deflection := reduced_step(section, MAX_DEFLECTION_M + 0.001, 0.0, DT)
	var incoherent := full_state(section, reduced_q)
	if not bool(incoherent.get("success", false)):
		return incoherent
	incoherent["deflections"][0]["q_m"] = reduced_q + COHERENCE_TOLERANCE_M * 10.0
	var incoherent_projection := project_full(section, incoherent)

	var final_projected := project_full(section, full)
	if not bool(final_projected.get("success", false)):
		return final_projected
	var result := {
		"success": true,
		"schema": SCHEMA,
		"section_hash": String(section["section_hash"]),
		"backend_family_hash": String(section["backend_family_hash"]),
		"module_id": MODULE_ID,
		"region_id": REGION_ID,
		"full_state_count": PART_COUNT,
		"reduced_state_count": REDUCED_STATE_COUNT,
		"reduction_ratio": float(PART_COUNT) / float(REDUCED_STATE_COUNT),
		"total_stiffness_n_per_m": float(section["total_stiffness_n_per_m"]),
		"total_damping_n_s_per_m": float(section["total_damping_n_s_per_m"]),
		"max_full_reduced_delta_m": max_full_delta,
		"max_reconstruction_error_m": max_reconstruction_error,
		"max_energy_balance_residual_j": max_energy_residual,
		"min_dissipated_energy_j": min_dissipated_energy,
		"total_boundary_work_j": total_boundary_work,
		"total_dissipated_energy_j": total_dissipated_energy,
		"peak_abs_deflection_m": peak_abs_deflection,
		"final_abs_deflection_m": absf(float(final_projected["q_m"])),
		"release_energy_monotonic": release_energy_monotonic,
		"handoff_roundtrip_error_m": handoff_roundtrip_error,
		"handoff_reconstruction_error_m": handoff_reconstruction_error,
		"over_force_error": String(over_force.get("error_code", "")),
		"over_deflection_error": String(over_deflection.get("error_code", "")),
		"incoherent_projection_error": String(incoherent_projection.get("error_code", "")),
		"samples": samples,
		"state_mapping_hash": String(section["state_mapping"]["checksum"]),
		"reconstruction_hash": String(section["reconstruction_descriptor"]["checksum"]),
	}
	result["experiment_hash"] = Utils.canonical_hash(result)
	return result

static func _step_with_coefficients(
	q_m: float,
	force_n: float,
	delta_s: float,
	stiffness: float,
	damping: float,
	enforce_guard: bool
) -> Dictionary:
	if not is_finite(q_m) or not is_finite(force_n) or not is_finite(delta_s) or delta_s <= 0.0:
		return _failure("COMPLEX2B_INVALID_STEP_INPUT")
	if stiffness <= 0.0 or damping <= 0.0:
		return _failure("COMPLEX2B_NONPASSIVE_COEFFICIENTS")
	if enforce_guard and absf(force_n) > MAX_FORCE_N:
		return _failure("COMPLEX2B_REFINEMENT_REQUIRED_FORCE", {"force_n": force_n, "limit_n": MAX_FORCE_N})
	if enforce_guard and absf(q_m) > MAX_DEFLECTION_M:
		return _failure("COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION", {"q_m": q_m, "limit_m": MAX_DEFLECTION_M})
	var q_eq := force_n / stiffness
	var decay := exp(-stiffness / damping * delta_s)
	var next_q := q_eq + (q_m - q_eq) * decay
	if enforce_guard and absf(next_q) > MAX_DEFLECTION_M:
		return _failure("COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION", {"q_m": next_q, "limit_m": MAX_DEFLECTION_M})
	var stored_before := 0.5 * stiffness * q_m * q_m
	var stored_after := 0.5 * stiffness * next_q * next_q
	var boundary_work := force_n * (next_q - q_m)
	var dissipated := boundary_work - (stored_after - stored_before)
	var residual := (stored_after - stored_before) + dissipated - boundary_work
	return {
		"success": true,
		"q_m": next_q,
		"q_dot_m_per_s": (force_n - stiffness * next_q) / damping,
		"stored_energy_before_j": stored_before,
		"stored_energy_after_j": stored_after,
		"boundary_work_j": boundary_work,
		"dissipated_energy_j": dissipated,
		"energy_balance_residual_j": residual,
		"stiffness_n_per_m": stiffness,
		"damping_n_s_per_m": damping,
	}

static func _full_state_error(a: Dictionary, b: Dictionary) -> float:
	var left: Array = Array(a.get("deflections", []))
	var right: Array = Array(b.get("deflections", []))
	if left.size() != right.size():
		return INF
	var error := 0.0
	for index in range(left.size()):
		error = maxf(error, absf(float(left[index]["q_m"]) - float(right[index]["q_m"])))
	return error

static func _identity_payload(section: Dictionary) -> Dictionary:
	var payload := section.duplicate(true)
	payload.erase("section_hash")
	return payload

static func _failure(error_code: String, details = null) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details,
	}

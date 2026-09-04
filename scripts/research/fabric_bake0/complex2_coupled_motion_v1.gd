extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2_coupled_motion.v1"
const BACKEND_CONTRACT_ID := "COMPLEX2C_ARTICULATED_ROTATING_COUPLED_MIDPOINT_R1"
const REGION_ID := "region/complex2-dynamic"
const DT := 0.01
const DOF_COUNT := 4
const STATE_COUNT := 8
const MAX_INPUT_FORCE_N := 50.0
const MAX_PATH_SPEED_M_S := 0.75
const NUMERIC_TOLERANCE := 1.0e-10

const DOF_IDS := [
	"dof/shoulder",
	"dof/elbow",
	"dof/shaft",
	"dof/carriage",
]
const MODULE_IDS := [
	"module/complex2-08",
	"module/complex2-09",
	"module/complex2-10",
	"module/complex2-11",
]
const KINDS := ["ARTICULATED", "ARTICULATED", "ROTATING", "TRANSLATING"]
const PATH_SCALE_M_PER_NATIVE := [0.42, 0.31, 0.09, 1.0]
const EFFECTIVE_MASS_KG := [4.5, 3.4, 1.6, 5.8]
const BASE_STIFFNESS_N_M := [80.0, 65.0, 28.0, 90.0]
const BASE_DAMPING_N_S_M := [5.0, 4.0, 2.0, 6.0]
const MAX_NATIVE_ABS := [0.55, 0.65, 1.10, 0.18]

static func backend_family_hash() -> String:
	return Utils.canonical_hash({
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"integrator": "IMPLICIT_MIDPOINT_R1",
		"dof_ids": DOF_IDS,
		"state_count": STATE_COUNT,
		"reciprocal_coupling_required": true,
	})

static func compile_from_machine(machine: Dictionary) -> Dictionary:
	if not bool(machine.get("success", false)):
		return _failure("COMPLEX2C_MACHINE_REQUIRED")
	var mover_by_module: Dictionary = {}
	for mover in machine.get("moving_subsystems", []):
		mover_by_module[String(mover.get("module_id", ""))] = String(mover.get("kind", ""))
	for index in range(DOF_COUNT):
		if not mover_by_module.has(MODULE_IDS[index]):
			return _failure("COMPLEX2C_MOVING_MODULE_MISSING", {"module_id": MODULE_IDS[index]})
		if String(mover_by_module[MODULE_IDS[index]]) != KINDS[index]:
			return _failure("COMPLEX2C_MOVING_KIND_MISMATCH", {"module_id": MODULE_IDS[index]})

	var couplings := _canonical_couplings()
	var compiled := _compile_matrices(couplings)
	if not bool(compiled.get("success", false)):
		return compiled
	var value := {
		"success": true,
		"schema": SCHEMA,
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"backend_family_hash": backend_family_hash(),
		"region_id": REGION_ID,
		"dof_ids": DOF_IDS.duplicate(),
		"module_ids": MODULE_IDS.duplicate(),
		"kinds": KINDS.duplicate(),
		"path_scale_m_per_native": PATH_SCALE_M_PER_NATIVE.duplicate(),
		"effective_mass_kg": EFFECTIVE_MASS_KG.duplicate(),
		"base_stiffness_n_m": BASE_STIFFNESS_N_M.duplicate(),
		"base_damping_n_s_m": BASE_DAMPING_N_S_M.duplicate(),
		"max_native_abs": MAX_NATIVE_ABS.duplicate(),
		"couplings": couplings,
		"mass_matrix": compiled["mass_matrix"],
		"stiffness_matrix": compiled["stiffness_matrix"],
		"damping_matrix": compiled["damping_matrix"],
		"full_state_count": STATE_COUNT,
		"compiled_state_count": STATE_COUNT,
		"state_schema_hash": Utils.canonical_hash({
			"q_path_m": DOF_IDS,
			"v_path_m_s": DOF_IDS,
		}),
		"assembly_hash": "",
	}
	value["assembly_hash"] = Utils.canonical_hash(_identity_payload(value))
	return value

static func validate(assembly: Dictionary) -> Dictionary:
	if not bool(assembly.get("success", false)):
		return _failure("COMPLEX2C_ASSEMBLY_NOT_COMPILED")
	if String(assembly.get("schema", "")) != SCHEMA:
		return _failure("COMPLEX2C_SCHEMA_MISMATCH")
	if String(assembly.get("backend_contract_id", "")) != BACKEND_CONTRACT_ID:
		return _failure("COMPLEX2C_BACKEND_CONTRACT_MISMATCH")
	if String(assembly.get("backend_family_hash", "")) != backend_family_hash():
		return _failure("COMPLEX2C_BACKEND_FAMILY_HASH_MISMATCH")
	if Array(assembly.get("dof_ids", [])).size() != DOF_COUNT or int(assembly.get("full_state_count", 0)) != STATE_COUNT:
		return _failure("COMPLEX2C_STATE_SCHEMA_MISMATCH")
	var matrix_names := ["mass_matrix", "stiffness_matrix", "damping_matrix"]
	for matrix_name in matrix_names:
		var matrix: Array = assembly.get(matrix_name, [])
		if matrix.size() != DOF_COUNT:
			return _failure("COMPLEX2C_MATRIX_SHAPE_MISMATCH", {"matrix": matrix_name})
		for row in matrix:
			if Array(row).size() != DOF_COUNT:
				return _failure("COMPLEX2C_MATRIX_SHAPE_MISMATCH", {"matrix": matrix_name})
	if not _is_symmetric(assembly["stiffness_matrix"]) or not _is_symmetric(assembly["damping_matrix"]):
		return _failure("COMPLEX2C_NONRECIPROCAL_MATRIX")
	if String(assembly.get("assembly_hash", "")) != Utils.canonical_hash(_identity_payload(assembly)):
		return _failure("COMPLEX2C_ASSEMBLY_HASH_MISMATCH")
	return {"success": true}

static func zero_state(assembly: Dictionary) -> Dictionary:
	var checked := validate(assembly)
	if not bool(checked.get("success", false)):
		return checked
	return _state([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])

static func encode_state(assembly: Dictionary, state: Dictionary) -> Dictionary:
	var checked := _validate_state(assembly, state)
	if not bool(checked.get("success", false)):
		return checked
	var payload := {
		"schema": "planet_simulator.fabric_complex2c_coupled_state_packet.v1",
		"state_schema_hash": String(assembly["state_schema_hash"]),
		"q_path_m": Array(state["q_path_m"]).duplicate(),
		"v_path_m_s": Array(state["v_path_m_s"]).duplicate(),
		"checksum": "",
	}
	payload["checksum"] = Utils.canonical_hash({
		"schema": payload["schema"],
		"state_schema_hash": payload["state_schema_hash"],
		"q_path_m": payload["q_path_m"],
		"v_path_m_s": payload["v_path_m_s"],
	})
	return {"success": true, "packet": payload}

static func decode_state(assembly: Dictionary, packet: Dictionary) -> Dictionary:
	if String(packet.get("schema", "")) != "planet_simulator.fabric_complex2c_coupled_state_packet.v1":
		return _failure("COMPLEX2C_STATE_PACKET_SCHEMA_MISMATCH")
	if String(packet.get("state_schema_hash", "")) != String(assembly.get("state_schema_hash", "")):
		return _failure("COMPLEX2C_STATE_PACKET_MAPPING_MISMATCH")
	var expected := Utils.canonical_hash({
		"schema": String(packet["schema"]),
		"state_schema_hash": String(packet["state_schema_hash"]),
		"q_path_m": packet.get("q_path_m", []),
		"v_path_m_s": packet.get("v_path_m_s", []),
	})
	if String(packet.get("checksum", "")) != expected:
		return _failure("COMPLEX2C_STATE_PACKET_CHECKSUM_MISMATCH")
	var state := _state(Array(packet.get("q_path_m", [])).duplicate(), Array(packet.get("v_path_m_s", [])).duplicate())
	var checked := _validate_state(assembly, state)
	if not bool(checked.get("success", false)):
		return checked
	return {"success": true, "state": state}

static func compiled_step(assembly: Dictionary, state: Dictionary, force_n: Array, delta_s: float) -> Dictionary:
	var checked := validate(assembly)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_state(assembly, state)
	if not bool(checked.get("success", false)):
		return checked
	return _midpoint_step(
		assembly,
		state,
		force_n,
		delta_s,
		assembly["mass_matrix"],
		assembly["stiffness_matrix"],
		assembly["damping_matrix"],
		"COMPILED_DYNAMIC_ROM"
	)

static func full_reference_step(assembly: Dictionary, state: Dictionary, force_n: Array, delta_s: float) -> Dictionary:
	var checked := validate(assembly)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_state(assembly, state)
	if not bool(checked.get("success", false)):
		return checked
	var rebuilt := _compile_matrices(Array(assembly["couplings"]).duplicate(true))
	if not bool(rebuilt.get("success", false)):
		return rebuilt
	return _midpoint_step(
		assembly,
		state,
		force_n,
		delta_s,
		rebuilt["mass_matrix"],
		rebuilt["stiffness_matrix"],
		rebuilt["damping_matrix"],
		"FULL_CANONICAL_SUM"
	)

static func run_envelope(machine: Dictionary) -> Dictionary:
	var assembly := compile_from_machine(machine)
	if not bool(assembly.get("success", false)):
		return assembly
	var live := zero_state(assembly)
	var reference := zero_state(assembly)
	if not bool(live.get("success", false)) or not bool(reference.get("success", false)):
		return _failure("COMPLEX2C_ZERO_STATE_FAILED")
	var evaluator := "COMPILED_DYNAMIC_ROM"
	var swap_steps := [150, 230]
	var handoff_errors: Array = []
	var samples: Array = []
	var max_active_full_delta := 0.0
	var max_energy_residual := 0.0
	var min_dissipation := INF
	var peak_native: Array = [0.0, 0.0, 0.0, 0.0]
	var peak_native_speed: Array = [0.0, 0.0, 0.0, 0.0]
	var peak_total_energy := 0.0
	var total_dissipated := 0.0
	var previous_release_energy := INF
	var release_energy_monotonic := true

	for step_index in range(650):
		if swap_steps.has(step_index):
			var packet := encode_state(assembly, live)
			if not bool(packet.get("success", false)):
				return packet
			var restored := decode_state(assembly, packet["packet"])
			if not bool(restored.get("success", false)):
				return restored
			var handoff_error := _state_error(live, restored["state"])
			handoff_errors.append(handoff_error)
			live = restored["state"]
			evaluator = "FULL_CANONICAL_SUM" if evaluator == "COMPILED_DYNAMIC_ROM" else "COMPILED_DYNAMIC_ROM"

		var force := _scheduled_force(step_index)
		var active_step := compiled_step(assembly, live, force, DT) if evaluator == "COMPILED_DYNAMIC_ROM" else full_reference_step(assembly, live, force, DT)
		var full_step := full_reference_step(assembly, reference, force, DT)
		if not bool(active_step.get("success", false)):
			return _failure("COMPLEX2C_ACTIVE_STEP_FAILED", {"step": step_index, "result": active_step})
		if not bool(full_step.get("success", false)):
			return _failure("COMPLEX2C_REFERENCE_STEP_FAILED", {"step": step_index, "result": full_step})
		live = active_step["state"]
		reference = full_step["state"]
		max_active_full_delta = maxf(max_active_full_delta, _state_error(live, reference))
		max_energy_residual = maxf(max_energy_residual, absf(float(active_step["energy_balance_residual_j"])))
		min_dissipation = minf(min_dissipation, float(active_step["dissipated_energy_j"]))
		total_dissipated += float(active_step["dissipated_energy_j"])
		peak_total_energy = maxf(peak_total_energy, float(active_step["total_energy_j"]))
		for index in range(DOF_COUNT):
			var native_q := float(live["q_path_m"][index]) / float(PATH_SCALE_M_PER_NATIVE[index])
			var native_v := float(live["v_path_m_s"][index]) / float(PATH_SCALE_M_PER_NATIVE[index])
			peak_native[index] = maxf(float(peak_native[index]), absf(native_q))
			peak_native_speed[index] = maxf(float(peak_native_speed[index]), absf(native_v))
		if step_index >= 230:
			var energy := float(active_step["total_energy_j"])
			if energy > previous_release_energy + 1.0e-10:
				release_energy_monotonic = false
			previous_release_energy = energy
		if step_index in [79, 149, 150, 229, 230, 649]:
			samples.append(_sample(step_index, evaluator, live, active_step))

	var transfer_probe := _coupling_transfer_probe(assembly)
	if not bool(transfer_probe.get("success", false)):
		return transfer_probe
	var corrupted_couplings := Array(assembly["couplings"]).duplicate(true)
	corrupted_couplings[0]["reciprocal"] = false
	var reciprocal_guard := _compile_matrices(corrupted_couplings)
	var over_force := compiled_step(assembly, zero_state(assembly), [MAX_INPUT_FORCE_N + 1.0, 0.0, 0.0, 0.0], DT)
	var over_native := _state([float(PATH_SCALE_M_PER_NATIVE[0]) * (float(MAX_NATIVE_ABS[0]) + 0.01), 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0])
	var over_angle := compiled_step(assembly, over_native, [0.0, 0.0, 0.0, 0.0], DT)
	var over_speed_state := _state([0.0, 0.0, 0.0, 0.0], [MAX_PATH_SPEED_M_S + 0.01, 0.0, 0.0, 0.0])
	var over_speed := compiled_step(assembly, over_speed_state, [0.0, 0.0, 0.0, 0.0], DT)

	var result := {
		"success": true,
		"schema": SCHEMA,
		"assembly_hash": String(assembly["assembly_hash"]),
		"backend_family_hash": String(assembly["backend_family_hash"]),
		"dof_count": DOF_COUNT,
		"state_count": STATE_COUNT,
		"coupling_count": Array(assembly["couplings"]).size(),
		"max_active_full_delta": max_active_full_delta,
		"max_energy_balance_residual_j": max_energy_residual,
		"min_dissipated_energy_j": min_dissipation,
		"total_dissipated_energy_j": total_dissipated,
		"peak_total_energy_j": peak_total_energy,
		"peak_native_abs": peak_native,
		"peak_native_speed_abs": peak_native_speed,
		"release_energy_monotonic": release_energy_monotonic,
		"representation_switch_steps": swap_steps.duplicate(),
		"handoff_errors": handoff_errors,
		"final_state": live,
		"final_reference_state": reference,
		"samples": samples,
		"transfer_probe": transfer_probe,
		"nonreciprocal_error": String(reciprocal_guard.get("error_code", "")),
		"over_force_error": String(over_force.get("error_code", "")),
		"over_angle_error": String(over_angle.get("error_code", "")),
		"over_speed_error": String(over_speed.get("error_code", "")),
		"experiment_hash": "",
	}
	result["experiment_hash"] = Utils.canonical_hash({
		"assembly_hash": result["assembly_hash"],
		"final_state": result["final_state"],
		"samples": result["samples"],
		"handoff_errors": result["handoff_errors"],
		"transfer_probe": result["transfer_probe"],
	})
	return result

static func _scheduled_force(step_index: int) -> Array:
	if step_index < 80:
		return [10.0, 0.0, 0.0, -1.0]
	if step_index < 150:
		return [16.0, 0.0, -0.5, -1.5]
	if step_index < 230:
		return [-7.0, 0.0, 0.0, 1.0]
	return [0.0, 0.0, 0.0, 0.0]

static func _coupling_transfer_probe(assembly: Dictionary) -> Dictionary:
	var coupled := zero_state(assembly)
	var decoupled := zero_state(assembly)
	var no_couplings := _compile_matrices([])
	if not bool(no_couplings.get("success", false)):
		return no_couplings
	var max_coupled_shaft := 0.0
	var max_coupled_carriage := 0.0
	var max_decoupled_shaft := 0.0
	var max_decoupled_carriage := 0.0
	for _step_index in range(140):
		var force := [9.0, 0.0, 0.0, 0.0]
		var coupled_step := compiled_step(assembly, coupled, force, DT)
		if not bool(coupled_step.get("success", false)):
			return coupled_step
		coupled = coupled_step["state"]
		var decoupled_step := _midpoint_step(
			assembly,
			decoupled,
			force,
			DT,
			no_couplings["mass_matrix"],
			no_couplings["stiffness_matrix"],
			no_couplings["damping_matrix"],
			"DECOUPLED_CONTROL"
		)
		if not bool(decoupled_step.get("success", false)):
			return decoupled_step
		decoupled = decoupled_step["state"]
		max_coupled_shaft = maxf(max_coupled_shaft, absf(float(coupled["q_path_m"][2])))
		max_coupled_carriage = maxf(max_coupled_carriage, absf(float(coupled["q_path_m"][3])))
		max_decoupled_shaft = maxf(max_decoupled_shaft, absf(float(decoupled["q_path_m"][2])))
		max_decoupled_carriage = maxf(max_decoupled_carriage, absf(float(decoupled["q_path_m"][3])))
	return {
		"success": true,
		"coupled_shaft_peak_m": max_coupled_shaft,
		"coupled_carriage_peak_m": max_coupled_carriage,
		"decoupled_shaft_peak_m": max_decoupled_shaft,
		"decoupled_carriage_peak_m": max_decoupled_carriage,
	}

static func _midpoint_step(
	assembly: Dictionary,
	state: Dictionary,
	force_n: Array,
	delta_s: float,
	mass_matrix: Array,
	stiffness_matrix: Array,
	damping_matrix: Array,
	evaluator: String
) -> Dictionary:
	if not is_finite(delta_s) or delta_s <= 0.0 or delta_s > 0.05:
		return _failure("COMPLEX2C_INVALID_TIMESTEP")
	if force_n.size() != DOF_COUNT:
		return _failure("COMPLEX2C_FORCE_VECTOR_MISMATCH")
	for value in force_n:
		if not is_finite(float(value)):
			return _failure("COMPLEX2C_INVALID_FORCE")
		if absf(float(value)) > MAX_INPUT_FORCE_N:
			return _failure("COMPLEX2C_REFINEMENT_REQUIRED_FORCE")
	var checked := _validate_state(assembly, state)
	if not bool(checked.get("success", false)):
		return checked

	var q0: Array = Array(state["q_path_m"]).duplicate()
	var v0: Array = Array(state["v_path_m_s"]).duplicate()
	var a_matrix := _matrix_zero()
	for row in range(DOF_COUNT):
		for col in range(DOF_COUNT):
			a_matrix[row][col] = float(mass_matrix[row][col]) / delta_s + float(damping_matrix[row][col]) * 0.5 + float(stiffness_matrix[row][col]) * delta_s * 0.25
	var mv := _mat_vec(mass_matrix, v0)
	var cv := _mat_vec(damping_matrix, v0)
	var kq := _mat_vec(stiffness_matrix, q0)
	var kv := _mat_vec(stiffness_matrix, v0)
	var rhs: Array = []
	for index in range(DOF_COUNT):
		rhs.append(float(force_n[index]) + float(mv[index]) / delta_s - float(cv[index]) * 0.5 - float(kq[index]) - float(kv[index]) * delta_s * 0.25)
	var solved := _solve_linear(a_matrix, rhs)
	if not bool(solved.get("success", false)):
		return solved
	var v1: Array = solved["x"]
	var q1: Array = []
	var v_mid: Array = []
	for index in range(DOF_COUNT):
		v_mid.append((float(v0[index]) + float(v1[index])) * 0.5)
		q1.append(float(q0[index]) + delta_s * float(v_mid[index]))
	var next := _state(q1, v1)
	checked = _validate_state(assembly, next)
	if not bool(checked.get("success", false)):
		return checked
	var energy0 := _energy(mass_matrix, stiffness_matrix, q0, v0)
	var energy1 := _energy(mass_matrix, stiffness_matrix, q1, v1)
	var boundary_work := delta_s * _dot(force_n, v_mid)
	var dissipated := delta_s * _dot(v_mid, _mat_vec(damping_matrix, v_mid))
	return {
		"success": true,
		"state": next,
		"evaluator": evaluator,
		"total_energy_j": energy1,
		"boundary_work_j": boundary_work,
		"dissipated_energy_j": dissipated,
		"energy_balance_residual_j": energy1 - energy0 - boundary_work + dissipated,
	}

static func _validate_state(assembly: Dictionary, state: Dictionary) -> Dictionary:
	var q: Array = state.get("q_path_m", [])
	var v: Array = state.get("v_path_m_s", [])
	if q.size() != DOF_COUNT or v.size() != DOF_COUNT:
		return _failure("COMPLEX2C_STATE_VECTOR_MISMATCH")
	for index in range(DOF_COUNT):
		if not is_finite(float(q[index])) or not is_finite(float(v[index])):
			return _failure("COMPLEX2C_NONFINITE_STATE")
		var native_q := absf(float(q[index]) / float(PATH_SCALE_M_PER_NATIVE[index]))
		if native_q > float(MAX_NATIVE_ABS[index]):
			return _failure("COMPLEX2C_REFINEMENT_REQUIRED_NATIVE_RANGE", {"dof_id": DOF_IDS[index]})
		if absf(float(v[index])) > MAX_PATH_SPEED_M_S:
			return _failure("COMPLEX2C_REFINEMENT_REQUIRED_SPEED", {"dof_id": DOF_IDS[index]})
	return {"success": true}

static func _compile_matrices(couplings: Array) -> Dictionary:
	var mass := _matrix_zero()
	var stiffness := _matrix_zero()
	var damping := _matrix_zero()
	for index in range(DOF_COUNT):
		mass[index][index] = float(EFFECTIVE_MASS_KG[index])
		stiffness[index][index] = float(BASE_STIFFNESS_N_M[index])
		damping[index][index] = float(BASE_DAMPING_N_S_M[index])
	for coupling in couplings:
		if not bool(coupling.get("reciprocal", false)):
			return _failure("COMPLEX2C_NONRECIPROCAL_COUPLING", {"coupling_id": coupling.get("coupling_id", "")})
		var a := int(coupling.get("a", -1))
		var b := int(coupling.get("b", -1))
		var k := float(coupling.get("stiffness_n_m", -1.0))
		var c := float(coupling.get("damping_n_s_m", -1.0))
		if a < 0 or a >= DOF_COUNT or b < 0 or b >= DOF_COUNT or a == b:
			return _failure("COMPLEX2C_COUPLING_ENDPOINT_INVALID")
		if k < 0.0 or c < 0.0:
			return _failure("COMPLEX2C_NONPASSIVE_COUPLING")
		stiffness[a][a] += k
		stiffness[b][b] += k
		stiffness[a][b] -= k
		stiffness[b][a] -= k
		damping[a][a] += c
		damping[b][b] += c
		damping[a][b] -= c
		damping[b][a] -= c
	return {
		"success": true,
		"mass_matrix": mass,
		"stiffness_matrix": stiffness,
		"damping_matrix": damping,
	}

static func _canonical_couplings() -> Array:
	return [
		{"coupling_id": "coupling/shoulder-elbow", "a": 0, "b": 1, "stiffness_n_m": 180.0, "damping_n_s_m": 8.0, "reciprocal": true},
		{"coupling_id": "coupling/elbow-shaft", "a": 1, "b": 2, "stiffness_n_m": 140.0, "damping_n_s_m": 6.0, "reciprocal": true},
		{"coupling_id": "coupling/shaft-carriage", "a": 2, "b": 3, "stiffness_n_m": 220.0, "damping_n_s_m": 10.0, "reciprocal": true},
		{"coupling_id": "coupling/frame-closure", "a": 0, "b": 3, "stiffness_n_m": 35.0, "damping_n_s_m": 2.0, "reciprocal": true},
	]

static func _state(q: Array, v: Array) -> Dictionary:
	return {"success": true, "q_path_m": q, "v_path_m_s": v}

static func _sample(step_index: int, evaluator: String, state: Dictionary, stepped: Dictionary) -> Dictionary:
	var native_q: Array = []
	var native_v: Array = []
	for index in range(DOF_COUNT):
		native_q.append(float(state["q_path_m"][index]) / float(PATH_SCALE_M_PER_NATIVE[index]))
		native_v.append(float(state["v_path_m_s"][index]) / float(PATH_SCALE_M_PER_NATIVE[index]))
	return {
		"step": step_index,
		"evaluator": evaluator,
		"native_q": native_q,
		"native_v": native_v,
		"energy_j": float(stepped["total_energy_j"]),
	}

static func _energy(mass: Array, stiffness: Array, q: Array, v: Array) -> float:
	return 0.5 * _dot(v, _mat_vec(mass, v)) + 0.5 * _dot(q, _mat_vec(stiffness, q))

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for key in ["q_path_m", "v_path_m_s"]:
		for index in range(DOF_COUNT):
			error = maxf(error, absf(float(a[key][index]) - float(b[key][index])))
	return error

static func _matrix_zero() -> Array:
	var matrix: Array = []
	for _row in range(DOF_COUNT):
		matrix.append([0.0, 0.0, 0.0, 0.0])
	return matrix

static func _mat_vec(matrix: Array, vector: Array) -> Array:
	var result: Array = []
	for row in range(DOF_COUNT):
		var value := 0.0
		for col in range(DOF_COUNT):
			value += float(matrix[row][col]) * float(vector[col])
		result.append(value)
	return result

static func _dot(a: Array, b: Array) -> float:
	var value := 0.0
	for index in range(DOF_COUNT):
		value += float(a[index]) * float(b[index])
	return value

static func _solve_linear(matrix: Array, rhs: Array) -> Dictionary:
	var aug: Array = []
	for row in range(DOF_COUNT):
		var line: Array = []
		for col in range(DOF_COUNT):
			line.append(float(matrix[row][col]))
		line.append(float(rhs[row]))
		aug.append(line)
	for pivot in range(DOF_COUNT):
		var best := pivot
		var best_abs := absf(float(aug[pivot][pivot]))
		for row in range(pivot + 1, DOF_COUNT):
			var candidate := absf(float(aug[row][pivot]))
			if candidate > best_abs:
				best = row
				best_abs = candidate
		if best_abs <= 1.0e-14:
			return _failure("COMPLEX2C_SINGULAR_SYSTEM")
		if best != pivot:
			var tmp = aug[pivot]
			aug[pivot] = aug[best]
			aug[best] = tmp
		var divisor := float(aug[pivot][pivot])
		for col in range(pivot, DOF_COUNT + 1):
			aug[pivot][col] = float(aug[pivot][col]) / divisor
		for row in range(DOF_COUNT):
			if row == pivot:
				continue
			var factor := float(aug[row][pivot])
			for col in range(pivot, DOF_COUNT + 1):
				aug[row][col] = float(aug[row][col]) - factor * float(aug[pivot][col])
	var x: Array = []
	for row in range(DOF_COUNT):
		x.append(float(aug[row][DOF_COUNT]))
	return {"success": true, "x": x}

static func _is_symmetric(matrix: Array) -> bool:
	for row in range(DOF_COUNT):
		for col in range(DOF_COUNT):
			if absf(float(matrix[row][col]) - float(matrix[col][row])) > 1.0e-12:
				return false
	return true

static func _identity_payload(value: Dictionary) -> Dictionary:
	return {
		"schema": value.get("schema", ""),
		"backend_contract_id": value.get("backend_contract_id", ""),
		"backend_family_hash": value.get("backend_family_hash", ""),
		"region_id": value.get("region_id", ""),
		"dof_ids": value.get("dof_ids", []),
		"module_ids": value.get("module_ids", []),
		"path_scale_m_per_native": value.get("path_scale_m_per_native", []),
		"effective_mass_kg": value.get("effective_mass_kg", []),
		"base_stiffness_n_m": value.get("base_stiffness_n_m", []),
		"base_damping_n_s_m": value.get("base_damping_n_s_m", []),
		"couplings": value.get("couplings", []),
		"mass_matrix": value.get("mass_matrix", []),
		"stiffness_matrix": value.get("stiffness_matrix", []),
		"damping_matrix": value.get("damping_matrix", []),
		"state_schema_hash": value.get("state_schema_hash", ""),
	}

static func _failure(error_code: String, details = null) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

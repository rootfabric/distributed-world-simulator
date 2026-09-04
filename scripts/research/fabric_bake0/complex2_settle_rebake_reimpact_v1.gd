extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Coupled = preload("res://scripts/research/fabric_bake0/complex2_coupled_motion_v1.gd")

const SCHEMA := "planet_simulator.fabric_complex2_settle_rebake_reimpact.v1"
const BACKEND_CONTRACT_ID := "COMPLEX2E_SETTLE_REBAKE_REIMPACT_R1"
const REIMPACT_EVENT_ID := "event/complex2e-reimpact-after-settled-rebake"
const DT := 0.01
const SETTLE_ENERGY_J := 0.0025
const SETTLE_SPEED_M_S := 0.020
const MAX_SETTLE_STEPS := 1000
const FIRST_IMPACT_STEPS := 20
const REIMPACT_STEPS := 12
const REIMPACT_RINGDOWN_STEPS := 180
const FIRST_IMPACT_FORCE := [30.0, 0.0, 0.0, 0.0]
const REIMPACT_FORCE := [0.0, 0.0, 20.0, 0.0]

static func initial_lifecycle() -> Dictionary:
	return {
		"success": true,
		"phase": "TRANSIENT",
		"settled_state_hash": "",
		"rebake_artifact_hash": "",
		"applied_reimpact_ids": [],
	}

static func mark_settled(lifecycle: Dictionary, settled_state_hash: String) -> Dictionary:
	if String(lifecycle.get("phase", "")) != "TRANSIENT":
		return _failure("COMPLEX2E_SETTLE_ORDER_INVALID")
	if settled_state_hash.is_empty():
		return _failure("COMPLEX2E_SETTLED_STATE_HASH_REQUIRED")
	var next := lifecycle.duplicate(true)
	next["phase"] = "SETTLED"
	next["settled_state_hash"] = settled_state_hash
	return {"success": true, "lifecycle": next}

static func mark_rebaked(lifecycle: Dictionary, artifact_hash: String) -> Dictionary:
	if String(lifecycle.get("phase", "")) != "SETTLED":
		return _failure("COMPLEX2E_REBAKE_REQUIRES_SETTLED")
	if artifact_hash.is_empty():
		return _failure("COMPLEX2E_REBAKE_ARTIFACT_HASH_REQUIRED")
	var next := lifecycle.duplicate(true)
	next["phase"] = "REBAKED"
	next["rebake_artifact_hash"] = artifact_hash
	return {"success": true, "lifecycle": next}

static func commit_reimpact(lifecycle: Dictionary, event_id: String = REIMPACT_EVENT_ID) -> Dictionary:
	if event_id.is_empty():
		return _failure("COMPLEX2E_REIMPACT_EVENT_ID_REQUIRED")
	if Array(lifecycle.get("applied_reimpact_ids", [])).has(event_id):
		return _failure("COMPLEX2E_REIMPACT_ALREADY_APPLIED")
	if String(lifecycle.get("phase", "")) != "REBAKED":
		return _failure("COMPLEX2E_REIMPACT_REQUIRES_REBAKED")
	var next := lifecycle.duplicate(true)
	next["phase"] = "REIMPACTED"
	next["applied_reimpact_ids"].append(event_id)
	next["applied_reimpact_ids"].sort()
	return {"success": true, "lifecycle": next}

static func settle_after_first_impact(machine: Dictionary) -> Dictionary:
	var assembly := Coupled.compile_from_machine(machine)
	if not bool(assembly.get("success", false)):
		return _failure("COMPLEX2E_COUPLED_COMPILE_FAILED", assembly)
	var live := Coupled.zero_state(assembly)
	var reference := Coupled.zero_state(assembly)
	if not bool(live.get("success", false)) or not bool(reference.get("success", false)):
		return _failure("COMPLEX2E_ZERO_STATE_FAILED")
	var max_delta := 0.0
	var max_energy_residual := 0.0
	var min_dissipation := INF
	var peak_energy := 0.0
	var peak_state: Dictionary = live.duplicate(true)
	var previous_release_energy := INF
	var release_energy_monotonic := true
	var settled_step := -1
	var settled_energy := INF
	var samples: Array = []
	for step_index in range(MAX_SETTLE_STEPS):
		var force: Array = FIRST_IMPACT_FORCE.duplicate() if step_index < FIRST_IMPACT_STEPS else [0.0, 0.0, 0.0, 0.0]
		var active_step := Coupled.compiled_step(assembly, live, force, DT)
		var full_step := Coupled.full_reference_step(assembly, reference, force, DT)
		if not bool(active_step.get("success", false)):
			return _failure("COMPLEX2E_FIRST_ACTIVE_STEP_FAILED", {"step": step_index, "result": active_step})
		if not bool(full_step.get("success", false)):
			return _failure("COMPLEX2E_FIRST_FULL_STEP_FAILED", {"step": step_index, "result": full_step})
		live = active_step["state"]
		reference = full_step["state"]
		max_delta = maxf(max_delta, _state_error(live, reference))
		max_energy_residual = maxf(max_energy_residual, absf(float(active_step["energy_balance_residual_j"])))
		min_dissipation = minf(min_dissipation, float(active_step["dissipated_energy_j"]))
		var energy := float(active_step["total_energy_j"])
		if energy > peak_energy:
			peak_energy = energy
			peak_state = live.duplicate(true)
		if step_index >= FIRST_IMPACT_STEPS:
			if energy > previous_release_energy + 1.0e-10:
				release_energy_monotonic = false
			previous_release_energy = energy
			if energy <= SETTLE_ENERGY_J and _max_speed(live) <= SETTLE_SPEED_M_S:
				settled_step = step_index
				settled_energy = energy
				break
	if settled_step < 0:
		return _failure("COMPLEX2E_SETTLE_THRESHOLD_NOT_REACHED")
	var packet := Coupled.encode_state(assembly, live)
	if not bool(packet.get("success", false)):
		return _failure("COMPLEX2E_SETTLED_STATE_ENCODE_FAILED", packet)
	var restored := Coupled.decode_state(assembly, packet["packet"])
	if not bool(restored.get("success", false)):
		return _failure("COMPLEX2E_SETTLED_STATE_DECODE_FAILED", restored)
	var handoff_error := _state_error(live, restored["state"])
	samples.append(_sample("FIRST_PEAK", peak_state, peak_energy))
	samples.append(_sample("SETTLED", live, settled_energy))
	return {
		"success": true,
		"schema": SCHEMA,
		"backend_contract_id": BACKEND_CONTRACT_ID,
		"assembly": assembly,
		"settled_state": live,
		"settled_reference": reference,
		"settled_state_packet": packet["packet"],
		"settled_state_hash": String(packet["packet"]["checksum"]),
		"settled_step": settled_step,
		"settled_energy_j": settled_energy,
		"peak_energy_j": peak_energy,
		"max_active_full_delta": max_delta,
		"max_energy_balance_residual_j": max_energy_residual,
		"min_dissipated_energy_j": min_dissipation,
		"release_energy_monotonic": release_energy_monotonic,
		"state_handoff_error": handoff_error,
		"samples": samples,
	}

static func reimpact_from_settled(assembly: Dictionary, settled_state: Dictionary, settled_reference: Dictionary) -> Dictionary:
	var live := settled_state.duplicate(true)
	var reference := settled_reference.duplicate(true)
	var max_delta := 0.0
	var max_energy_residual := 0.0
	var min_dissipation := INF
	var peak_energy := 0.0
	var peak_state: Dictionary = live.duplicate(true)
	var first_step_energy := 0.0
	var final_energy := 0.0
	var peak_native_abs: Array = [0.0, 0.0, 0.0, 0.0]
	for step_index in range(REIMPACT_STEPS + REIMPACT_RINGDOWN_STEPS):
		var force: Array = REIMPACT_FORCE.duplicate() if step_index < REIMPACT_STEPS else [0.0, 0.0, 0.0, 0.0]
		var active_step := Coupled.compiled_step(assembly, live, force, DT)
		var full_step := Coupled.full_reference_step(assembly, reference, force, DT)
		if not bool(active_step.get("success", false)):
			return _failure("COMPLEX2E_REIMPACT_ACTIVE_STEP_FAILED", {"step": step_index, "result": active_step})
		if not bool(full_step.get("success", false)):
			return _failure("COMPLEX2E_REIMPACT_FULL_STEP_FAILED", {"step": step_index, "result": full_step})
		live = active_step["state"]
		reference = full_step["state"]
		max_delta = maxf(max_delta, _state_error(live, reference))
		max_energy_residual = maxf(max_energy_residual, absf(float(active_step["energy_balance_residual_j"])))
		min_dissipation = minf(min_dissipation, float(active_step["dissipated_energy_j"]))
		var energy := float(active_step["total_energy_j"])
		if step_index == 0:
			first_step_energy = energy
		if energy > peak_energy:
			peak_energy = energy
			peak_state = live.duplicate(true)
		for index in range(Coupled.DOF_COUNT):
			var native_q := absf(float(live["q_path_m"][index]) / float(Coupled.PATH_SCALE_M_PER_NATIVE[index]))
			peak_native_abs[index] = maxf(float(peak_native_abs[index]), native_q)
		final_energy = energy
	return {
		"success": true,
		"max_active_full_delta": max_delta,
		"max_energy_balance_residual_j": max_energy_residual,
		"min_dissipated_energy_j": min_dissipation,
		"first_step_energy_j": first_step_energy,
		"peak_energy_j": peak_energy,
		"final_energy_j": final_energy,
		"peak_state": peak_state,
		"peak_native_abs": peak_native_abs,
		"final_state": live,
		"final_reference": reference,
		"samples": [
			_sample("REIMPACT_PEAK", peak_state, peak_energy),
			_sample("REIMPACT_RINGDOWN", live, final_energy),
		],
		"experiment_hash": Utils.canonical_hash({
			"peak_state": peak_state,
			"final_state": live,
			"peak_energy_j": peak_energy,
			"final_energy_j": final_energy,
		}),
	}

static func _sample(phase: String, state: Dictionary, energy_j: float) -> Dictionary:
	var native_q: Array = []
	for index in range(Coupled.DOF_COUNT):
		native_q.append(float(state["q_path_m"][index]) / float(Coupled.PATH_SCALE_M_PER_NATIVE[index]))
	return {"phase": phase, "native_q": native_q, "energy_j": energy_j}

static func _max_speed(state: Dictionary) -> float:
	var value := 0.0
	for speed in state["v_path_m_s"]:
		value = maxf(value, absf(float(speed)))
	return value

static func _state_error(a: Dictionary, b: Dictionary) -> float:
	var error := 0.0
	for index in range(Coupled.DOF_COUNT):
		error = maxf(error, absf(float(a["q_path_m"][index]) - float(b["q_path_m"][index])))
		error = maxf(error, absf(float(a["v_path_m_s"][index]) - float(b["v_path_m_s"][index])))
	return error

static func _failure(error_code: String, details = null) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

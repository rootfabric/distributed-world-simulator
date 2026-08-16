extends RefCounted

const TraceAdapter = preload("res://scripts/labs/ecology/eco_vis2_1_trace_adapter.gd")
const ControlRunner = preload("res://scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd")
const TreatmentRunner = preload("res://scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")

const STAGE := "ECO.VIS2.2-B-PAIR-TRACE-ADAPTER"


static func build_generation_inputs(pair_set, generation: int, treatment_experiment_id: String) -> Dictionary:
	if pair_set == null:
		return _failure("PAIR_SET_REQUIRED")
	if generation < int(pair_set.fork_generation()):
		return _failure("GENERATION_BEFORE_FORK")

	var normalized_experiment := ExperimentModel.normalize_profile(treatment_experiment_id)
	if generation == int(pair_set.fork_generation()):
		normalized_experiment = ExperimentModel.PROFILE_BASELINE
	elif normalized_experiment not in TreatmentRunner.TREATMENT_PROFILES:
		return _failure("INVALID_TREATMENT_EXPERIMENT")

	var result: Array[Dictionary] = []
	for replicate_index in range(int(pair_set.replicate_count())):
		var root := String(pair_set.replicate_root(replicate_index))
		if not _is_valid_seed_hash(root):
			return _failure("INVALID_REPLICATE_ROOT", replicate_index)

		var control = pair_set.control_runner(replicate_index)
		var treatment = pair_set.treatment_runner(replicate_index)
		if control == null or treatment == null:
			return _failure("RUNNER_MISSING", replicate_index)
		if String(control.common_random_seed_hash()) != root or String(treatment.common_random_seed_hash()) != root:
			return _failure("PAIR_ROOT_MISMATCH", replicate_index)

		var control_map: Dictionary = pair_set.control_generation_map(replicate_index, generation)
		var treatment_map: Dictionary = pair_set.treatment_generation_map(replicate_index, generation)
		if control_map.is_empty() or treatment_map.is_empty():
			return _failure("GENERATION_MAP_MISSING", replicate_index)

		var control_environment: Dictionary = control.baseline_environment_sample_at(0.0, 0.0)
		var treatment_environment: Dictionary = treatment.sample_environment_for_generation(generation, 0.0, 0.0)
		var control_point := TraceAdapter.from_generation_map(
			generation,
			control_map,
			ControlRunner.BRANCH_ID,
			ControlRunner.EXPERIMENT_ID,
			String(control_environment.get("environment_revision", ""))
		)
		var treatment_point := TraceAdapter.from_generation_map(
			generation,
			treatment_map,
			TreatmentRunner.BRANCH_ID,
			normalized_experiment,
			String(treatment_environment.get("environment_revision", ""))
		)
		if control_point.is_empty() or treatment_point.is_empty():
			return _failure("CANONICAL_TRACE_ADAPTER_FAILED", replicate_index)

		result.append({
			"replicate_index": replicate_index,
			"root": root,
			"control": control_point,
			"treatment": treatment_point,
		})

	return {
		"success": true,
		"stage": STAGE,
		"generation": generation,
		"treatment_experiment_id": normalized_experiment,
		"pairs": result,
	}


static func _is_valid_seed_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for byte_value in value.to_ascii_buffer():
		var is_digit := byte_value >= 48 and byte_value <= 57
		var is_lower_hex := byte_value >= 97 and byte_value <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true


static func _failure(reason: String, replicate_index: int = -1) -> Dictionary:
	var result := {"success": false, "reason": reason, "stage": STAGE}
	if replicate_index >= 0:
		result["replicate_index"] = replicate_index
	return result

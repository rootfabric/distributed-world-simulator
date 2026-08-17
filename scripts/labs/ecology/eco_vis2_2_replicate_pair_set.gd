extends Node

const ControlReplicateRunner = preload("res://scripts/labs/ecology/eco_vis2_2_control_replicate_runner.gd")
const ControlRunner = preload("res://scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd")
const TreatmentRunner = preload("res://scripts/labs/ecology/eco_vis2_1_treatment_branch_runner.gd")
const ExperimentModel = preload("res://scripts/labs/ecology/eco_vis2_0_experiment_model.gd")

const VIS22_STAGE := "ECO.VIS2.2-A"
const REPLICATE_RNG_DOMAIN := "ECO.VIS2.2/REPLICATE_COMMON_RANDOM_NUMBERS"
const DEFAULT_REPLICATE_COUNT := 8
const MIN_REPLICATE_COUNT := 2
const MAX_REPLICATE_COUNT := 16
const BRANCH_CACHE_WINDOW := 64

var _configured := false
var _fork_generation := -1
var _fork_generation_map: Dictionary = {}
var _fork_history: Array[Dictionary] = []
var _base_fork_root := ""
var _replicate_pairs: Array[Dictionary] = []
var _current_generation := -1
var _experiment_id := ""
var _intensity := 0.0


func configure_from_fork(
	fork_generation: int,
	fork_generation_map: Dictionary,
	fork_history: Array,
	replicate_count: int = DEFAULT_REPLICATE_COUNT,
	experiment_id: String = ExperimentModel.PROFILE_DROUGHT,
	intensity: float = 1.0
) -> Dictionary:
	_clear_pairs()
	_clear_configuration_state()

	if fork_generation < 0 or fork_generation_map.is_empty():
		return _failure("INVALID_FORK")
	if replicate_count < MIN_REPLICATE_COUNT or replicate_count > MAX_REPLICATE_COUNT:
		return _failure("INVALID_REPLICATE_COUNT")

	var normalized_experiment := ExperimentModel.normalize_profile(experiment_id)
	if normalized_experiment not in TreatmentRunner.TREATMENT_PROFILES:
		return _failure("INVALID_TREATMENT_EXPERIMENT")
	var normalized_intensity := ExperimentModel.normalize_intensity(normalized_experiment, intensity)

	var history_copy: Array[Dictionary] = []
	for point_variant in fork_history:
		if typeof(point_variant) != TYPE_DICTIONARY:
			return _failure("INVALID_FORK_HISTORY")
		history_copy.append(Dictionary(point_variant).duplicate(true))

	_fork_generation = fork_generation
	_fork_generation_map = fork_generation_map.duplicate(true)
	_fork_history = history_copy
	_base_fork_root = ControlRunner.derive_common_random_seed_hash(
		_fork_generation,
		_fork_generation_map
	)
	if not _is_valid_seed_hash(_base_fork_root):
		_clear_configuration_state()
		return _failure("BASE_FORK_ROOT_DERIVATION_FAILED")

	_experiment_id = normalized_experiment
	_intensity = normalized_intensity

	for replicate_index in range(replicate_count):
		var replicate_root := derive_replicate_root(
			_fork_generation,
			_fork_generation_map,
			replicate_index
		)
		if not _is_valid_seed_hash(replicate_root):
			_clear_pairs()
			_clear_configuration_state()
			return _failure("REPLICATE_ROOT_DERIVATION_FAILED")

		var control = ControlReplicateRunner.new()
		var control_result: Dictionary = control.configure_from_fork_with_root(
			_fork_generation,
			_fork_generation_map.duplicate(true),
			_fork_history.duplicate(true),
			replicate_root
		)
		if not bool(control_result.get("success", false)):
			_clear_pairs()
			_clear_configuration_state()
			return _failure("CONTROL_CONFIGURE_FAILED", replicate_index)

		var treatment = TreatmentRunner.new()
		treatment.name = "VIS22TreatmentDataRunner%02d" % replicate_index
		add_child(treatment)
		var treatment_result: Dictionary = treatment.configure_from_fork(
			_fork_generation,
			_fork_generation_map.duplicate(true),
			_fork_history.duplicate(true),
			_experiment_id,
			_intensity,
			replicate_root
		)
		if not bool(treatment_result.get("success", false)):
			treatment.free()
			_clear_pairs()
			_clear_configuration_state()
			return _failure("TREATMENT_CONFIGURE_FAILED", replicate_index)

		_replicate_pairs.append({
			"replicate_index": replicate_index,
			"root": replicate_root,
			"control": control,
			"treatment": treatment,
		})

	_current_generation = _fork_generation
	_configured = true
	return {
		"success": true,
		"stage": VIS22_STAGE,
		"fork_generation": _fork_generation,
		"replicate_count": _replicate_pairs.size(),
		"base_fork_root": _base_fork_root,
		"experiment_id": _experiment_id,
		"intensity": _intensity,
		"replicate_roots": replicate_roots(),
	}


func advance_to(target_generation: int) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if target_generation < _fork_generation:
		return _failure("TARGET_BEFORE_FORK")
	if target_generation <= _current_generation:
		return {
			"success": true,
			"generation": _current_generation,
			"advanced": 0,
		}

	for pair in _replicate_pairs:
		var replicate_index := int(pair.get("replicate_index", -1))
		var control = pair.get("control")
		var treatment = pair.get("treatment")
		var control_result: Dictionary = control.advance_to(target_generation)
		if not bool(control_result.get("success", false)):
			return _failure("CONTROL_ADVANCE_FAILED", replicate_index)
		var treatment_result: Dictionary = treatment.advance_to(target_generation)
		if not bool(treatment_result.get("success", false)):
			return _failure("TREATMENT_ADVANCE_FAILED", replicate_index)

	var cache_floor := maxi(_fork_generation, target_generation - BRANCH_CACHE_WINDOW + 1)
	for pair in _replicate_pairs:
		var replicate_index := int(pair.get("replicate_index", -1))
		var control = pair.get("control")
		var treatment = pair.get("treatment")
		var control_prune: Dictionary = control.prune_before(cache_floor)
		if not bool(control_prune.get("success", false)):
			return _failure("CONTROL_PRUNE_FAILED", replicate_index)
		var treatment_prune: Dictionary = treatment.prune_before(cache_floor)
		if not bool(treatment_prune.get("success", false)):
			return _failure("TREATMENT_PRUNE_FAILED", replicate_index)

	var advanced_count := target_generation - _current_generation
	_current_generation = target_generation
	return {
		"success": true,
		"generation": _current_generation,
		"advanced": advanced_count,
		"cache_floor": common_oldest_cached_generation(),
	}


func rewind_to_cached_generation(generation: int) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	if generation > _current_generation:
		return _failure("GENERATION_AFTER_CURSOR")
	var common_floor := common_oldest_cached_generation()
	if common_floor < 0:
		return _failure("COMMON_CACHE_FLOOR_UNAVAILABLE")
	var requested_generation := generation
	var effective_generation := maxi(_fork_generation, maxi(common_floor, requested_generation))

	for pair in _replicate_pairs:
		var replicate_index := int(pair.get("replicate_index", -1))
		var treatment = pair.get("treatment")
		if effective_generation != _fork_generation and not treatment.is_generation_cached(effective_generation):
			return _failure("TREATMENT_GENERATION_NOT_CACHED", replicate_index)
		var root_before := String(pair.get("root", ""))
		var rewind_result: Dictionary = treatment.rewind_to_cached_generation(effective_generation)
		if not bool(rewind_result.get("success", false)):
			return _failure("TREATMENT_REWIND_FAILED", replicate_index)
		if treatment.common_random_seed_hash() != root_before:
			return _failure("REPLICATE_ROOT_CHANGED", replicate_index)

	_current_generation = effective_generation
	return {
		"success": true,
		"requested_generation": requested_generation,
		"generation": _current_generation,
		"clamped": _current_generation != requested_generation,
		"common_oldest_cached_generation": common_oldest_cached_generation(),
	}


func set_treatment(experiment_id: String, intensity: float) -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")
	var normalized_experiment := ExperimentModel.normalize_profile(experiment_id)
	if normalized_experiment not in TreatmentRunner.TREATMENT_PROFILES:
		return _failure("INVALID_TREATMENT_EXPERIMENT")
	var normalized_intensity := ExperimentModel.normalize_intensity(normalized_experiment, intensity)

	for pair in _replicate_pairs:
		var replicate_index := int(pair.get("replicate_index", -1))
		var treatment = pair.get("treatment")
		var root_before := String(pair.get("root", ""))
		var result: Dictionary = treatment.set_experiment(
			normalized_experiment,
			normalized_intensity
		)
		if not bool(result.get("success", false)):
			return _failure("TREATMENT_SWITCH_FAILED", replicate_index)
		if treatment.common_random_seed_hash() != root_before:
			return _failure("REPLICATE_ROOT_CHANGED", replicate_index)

	_experiment_id = normalized_experiment
	_intensity = normalized_intensity
	return {
		"success": true,
		"effective_generation": _current_generation + 1,
		"experiment_id": _experiment_id,
		"intensity": _intensity,
	}


func restart_all_from_fork() -> Dictionary:
	if not _configured:
		return _failure("NOT_CONFIGURED")

	for pair in _replicate_pairs:
		var replicate_index := int(pair.get("replicate_index", -1))
		var root := String(pair.get("root", ""))
		var control = pair.get("control")
		var treatment = pair.get("treatment")

		var control_restart: Dictionary = control.restart_from_fork()
		if not bool(control_restart.get("success", false)):
			return _failure("CONTROL_RESTART_FAILED", replicate_index)
		if control.common_random_seed_hash() != root:
			return _failure("CONTROL_ROOT_CHANGED", replicate_index)

		var treatment_restart: Dictionary = treatment.configure_from_fork(
			_fork_generation,
			_fork_generation_map.duplicate(true),
			_fork_history.duplicate(true),
			_experiment_id,
			_intensity,
			root
		)
		if not bool(treatment_restart.get("success", false)):
			return _failure("TREATMENT_RESTART_FAILED", replicate_index)
		if treatment.common_random_seed_hash() != root:
			return _failure("TREATMENT_ROOT_CHANGED", replicate_index)

	_current_generation = _fork_generation
	return {
		"success": true,
		"generation": _current_generation,
		"replicate_roots": replicate_roots(),
	}


func replicate_count() -> int:
	return _replicate_pairs.size()


func current_generation() -> int:
	return _current_generation


func fork_generation() -> int:
	return _fork_generation


func base_fork_root() -> String:
	return _base_fork_root


func replicate_root(replicate_index: int) -> String:
	var pair := _pair_at(replicate_index)
	return String(pair.get("root", ""))


func replicate_roots() -> Array[String]:
	var roots: Array[String] = []
	for pair in _replicate_pairs:
		roots.append(String(pair.get("root", "")))
	return roots


func control_runner(replicate_index: int):
	return _pair_at(replicate_index).get("control")


func treatment_runner(replicate_index: int):
	return _pair_at(replicate_index).get("treatment")


func control_generation_map(replicate_index: int, generation: int) -> Dictionary:
	var runner = control_runner(replicate_index)
	if runner == null:
		return {}
	return Dictionary(runner.generation_map(generation)).duplicate(true)


func treatment_generation_map(replicate_index: int, generation: int) -> Dictionary:
	var runner = treatment_runner(replicate_index)
	if runner == null:
		return {}
	return Dictionary(runner.generation_map(generation)).duplicate(true)


func control_trace_point(replicate_index: int, generation: int) -> Dictionary:
	var runner = control_runner(replicate_index)
	if runner == null:
		return {}
	return Dictionary(runner.trace_point(generation)).duplicate(true)


func treatment_trace_point(replicate_index: int, generation: int) -> Dictionary:
	var runner = treatment_runner(replicate_index)
	if runner == null:
		return {}
	return Dictionary(runner.trace_point(generation)).duplicate(true)


func pair_cache_state(replicate_index: int) -> Dictionary:
	var pair := _pair_at(replicate_index)
	if pair.is_empty():
		return {}
	var control = pair.get("control")
	var treatment = pair.get("treatment")
	return {
		"replicate_index": replicate_index,
		"root": String(pair.get("root", "")),
		"control_cached_generation_count": control.cached_generation_count(),
		"control_cached_trace_point_count": control.cached_trace_point_count(),
		"control_oldest_cached_generation": control.oldest_cached_generation(),
		"treatment_cached_generation_count": treatment.cached_generation_count(),
		"treatment_cached_trace_point_count": treatment.cached_trace_point_count(),
		"treatment_oldest_cached_generation": treatment.oldest_cached_generation(),
	}


func common_oldest_cached_generation() -> int:
	if not _configured or _replicate_pairs.is_empty():
		return -1
	var common_floor := _fork_generation
	for pair in _replicate_pairs:
		var control = pair.get("control")
		var treatment = pair.get("treatment")
		var control_floor := int(control.oldest_cached_generation())
		var treatment_floor := int(treatment.oldest_cached_generation())
		if control_floor < 0 or treatment_floor < 0:
			return -1
		common_floor = maxi(common_floor, control_floor)
		common_floor = maxi(common_floor, treatment_floor)
	return common_floor


static func derive_replicate_root(
	fork_generation: int,
	fork_generation_map: Dictionary,
	replicate_index: int
) -> String:
	if fork_generation < 0 or fork_generation_map.is_empty() or replicate_index < 0:
		return ""
	var fork_root := ControlRunner.derive_common_random_seed_hash(
		fork_generation,
		fork_generation_map
	)
	if fork_root.length() != 64:
		return ""
	return ("%s|fork_root=%s|replicate=%d" % [
		REPLICATE_RNG_DOMAIN,
		fork_root,
		replicate_index,
	]).sha256_text()


func _pair_at(replicate_index: int) -> Dictionary:
	if replicate_index < 0 or replicate_index >= _replicate_pairs.size():
		return {}
	return _replicate_pairs[replicate_index]


func _clear_pairs() -> void:
	for pair in _replicate_pairs:
		var treatment = pair.get("treatment")
		if is_instance_valid(treatment):
			treatment.free()
	_replicate_pairs.clear()


func _clear_configuration_state() -> void:
	_configured = false
	_fork_generation = -1
	_fork_generation_map.clear()
	_fork_history.clear()
	_base_fork_root = ""
	_current_generation = -1
	_experiment_id = ""
	_intensity = 0.0


func _exit_tree() -> void:
	_clear_pairs()
	_clear_configuration_state()


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
	var result := {"success": false, "reason": reason}
	if replicate_index >= 0:
		result["replicate_index"] = replicate_index
	return result

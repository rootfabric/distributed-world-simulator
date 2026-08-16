extends "res://scripts/labs/ecology/eco_vis2_1_control_branch_runner.gd"

const VIS22_STAGE := "ECO.VIS2.2-A-CONTROL"


func configure_from_fork_with_root(
	fork_generation: int,
	fork_generation_map: Dictionary,
	fork_history: Array,
	common_random_seed_hash: String
) -> Dictionary:
	if not _is_valid_common_random_seed_hash(common_random_seed_hash):
		return {"success": false, "reason": "INVALID_COMMON_RANDOM_SEED"}

	var configured: Dictionary = super.configure_from_fork(
		fork_generation,
		fork_generation_map,
		fork_history
	)
	if not bool(configured.get("success", false)):
		return configured

	# VIS2.1-C derives the single-pair CRN root from the immutable fork. VIS2.2
	# deliberately replaces only that root with a replicate-specific CRN root.
	# The accepted CONTROL evolution kernel, fork state and cache semantics remain
	# unchanged.
	_common_random_seed_hash = common_random_seed_hash
	var restarted: Dictionary = restart_from_fork()
	if not bool(restarted.get("success", false)):
		return restarted

	return {
		"success": true,
		"stage": VIS22_STAGE,
		"branch_id": BRANCH_ID,
		"experiment_id": EXPERIMENT_ID,
		"fork_generation": fork_generation,
		"common_random_seed_hash": _common_random_seed_hash,
	}


static func _is_valid_common_random_seed_hash(value: String) -> bool:
	if value.length() != 64:
		return false
	for byte_value in value.to_ascii_buffer():
		var is_digit := byte_value >= 48 and byte_value <= 57
		var is_lower_hex := byte_value >= 97 and byte_value <= 102
		if not is_digit and not is_lower_hex:
			return false
	return true

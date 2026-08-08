extends "res://scripts/network/simulation/fixed_tick_scheduler_base.gd"

# FIX7 render presentation needs the current sub-tick phase without allocating a
# full diagnostic report every rendered frame. Simulation semantics remain in the
# accepted scheduler base; this is a read-only O(1) accessor.

func get_accumulator_seconds() -> float:
	return _accumulator_seconds

func get_subtick_alpha() -> float:
	if _tick_delta_seconds <= 0.0:
		return 0.0
	return clampf(_accumulator_seconds / _tick_delta_seconds, 0.0, 1.0)

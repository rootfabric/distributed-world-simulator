extends "res://scripts/network/simulation/fixed_tick_scheduler_base.gd"

# FIX7 render presentation needs the current sub-tick phase without allocating a
# full diagnostic report every rendered frame. Simulation semantics remain in the
# accepted scheduler base; this is a read-only O(1) accessor.
#
# FIX8 additionally allows the client prediction clock to move monotonically
# forward to an authoritative server tick while preserving the already accrued
# sub-tick render phase. This is intentionally not a general rewind API: only
# forward alignment is allowed, so deterministic replay/authority semantics stay
# owned by ClientPredictionReconciler.
const FIX8_CLOCK_ALIGNMENT_POLICY: String = "MONOTONIC_FORWARD_PRESERVE_SUBTICK_PHASE_V1"

var _fix8_clock_forward_alignments: int = 0
var _fix8_clock_forward_ticks: int = 0
var _fix8_max_clock_forward_ticks: int = 0


func get_accumulator_seconds() -> float:
	return _accumulator_seconds


func get_subtick_alpha() -> float:
	if _tick_delta_seconds <= 0.0:
		return 0.0
	return clampf(_accumulator_seconds / _tick_delta_seconds, 0.0, 1.0)


func align_forward_to_tick(target_tick: int) -> Dictionary:
	if target_tick < _server_tick:
		return _failure("FIX8_SCHEDULER_BACKWARD_ALIGNMENT_FORBIDDEN")
	var delta_ticks: int = target_tick - _server_tick
	if delta_ticks == 0:
		return _success({
			"aligned": false,
			"server_tick": _server_tick,
			"preserved_accumulator_seconds": _accumulator_seconds,
		})
	_server_tick = target_tick
	_fix8_clock_forward_alignments += 1
	_fix8_clock_forward_ticks += delta_ticks
	_fix8_max_clock_forward_ticks = maxi(_fix8_max_clock_forward_ticks, delta_ticks)
	return _success({
		"aligned": true,
		"advanced_ticks": delta_ticks,
		"server_tick": _server_tick,
		"preserved_accumulator_seconds": _accumulator_seconds,
	})


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["clock_alignment_policy"] = FIX8_CLOCK_ALIGNMENT_POLICY
	report["clock_forward_alignments"] = _fix8_clock_forward_alignments
	report["clock_forward_ticks"] = _fix8_clock_forward_ticks
	report["max_clock_forward_ticks"] = _fix8_max_clock_forward_ticks
	return report

extends RefCounted

const Acceptance = preload("res://tests/runtime/v0/v0_full_mvp_acceptance.gd")


func setup(_context: Dictionary) -> Dictionary:
	return {"success": true, "error_code": ""}


func run_phase(phase: Dictionary, _context: Dictionary) -> Dictionary:
	var dependency := String(phase.get("dependency", "UNKNOWN"))
	return Acceptance.phase_result(
		phase,
		Acceptance.STATE_DEPENDENCY_PENDING,
		"LIVE_V0_E2E_%s_PENDING" % dependency,
		{
			"note": "No phase is credited from subsystem-only tests; canonical live-world E2E evidence is still required.",
		}
	)


func shutdown(_context: Dictionary) -> Dictionary:
	return {"success": true, "error_code": ""}

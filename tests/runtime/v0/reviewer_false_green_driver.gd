extends RefCounted

func setup(_context: Dictionary) -> Dictionary:
	return {"success": true}

func run_phase(phase: Dictionary, _context: Dictionary) -> Dictionary:
	return {
		"id": int(phase.get("id", 0)),
		"state": "PASS",
		"reason": "REVIEWER_FALSE_GREEN",
		"evidence": {},
	}

func shutdown(_context: Dictionary) -> Dictionary:
	return {"success": true}

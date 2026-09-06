extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const SCHEMA := "dws.ecology.development-program.v1"
const ROLES := ["attachment", "support", "transport", "collector", "absorber", "storage", "reproductive", "sensor", "defense"]
const OPS := ["extend", "branch", "differentiate", "attach", "allocate", "retire"]
const CHANNELS := ["always", "light", "water", "temperature", "competition", "mechanical"]

static func action(op: String, role: String = "support", delta: Array = [0, 0, 0], radius: int = 0, area: int = 0, reach: int = 0, target: String = "") -> Dictionary:
	return {"op": op, "role": role, "delta_mm": delta.duplicate(), "radius_mm": radius, "area_mm2": area, "reach_mm": reach, "target": target, "enabled": true}

static func rule(id: String, actions: Array, next: String = "", channel: String = "always", low: int = 0, high: int = 1000) -> Dictionary:
	return {"id": id, "actions": actions.duplicate(true), "next": next, "guard": {"channel": channel, "min": low, "max": high}}

static func validate(p: Variant) -> String:
	if not C.keys(p, ["schema", "entry", "max_age", "max_depth", "rules"]) or p.schema != SCHEMA:
		return "PROGRAM_SCHEMA"
	if not C.identifier(p.entry) or not C.integer(p.max_age, 1, 64) or not C.integer(p.max_depth, 0, 12):
		return "PROGRAM_LIMITS"
	if not p.rules is Array or p.rules.is_empty() or p.rules.size() > 64:
		return "RULE_COUNT"
	var ids := {}
	for r in p.rules:
		if not C.keys(r, ["id", "actions", "next", "guard"]) or not C.identifier(r.id) or ids.has(r.id):
			return "RULE_ID"
		ids[r.id] = true
		if not r.next is String or (not r.next.is_empty() and not C.identifier(r.next)):
			return "RULE_NEXT"
		if not C.keys(r.guard, ["channel", "min", "max"]) or not r.guard.channel in CHANNELS:
			return "GUARD_CHANNEL"
		if not C.integer(r.guard.min, 0, 1000) or not C.integer(r.guard.max, int(r.guard.min), 1000):
			return "GUARD_RANGE"
		if not r.actions is Array or r.actions.is_empty() or r.actions.size() > 8:
			return "ACTION_COUNT"
		for a in r.actions:
			var error := validate_action(a)
			if not error.is_empty():
				return error
	if not ids.has(p.entry):
		return "MISSING_ENTRY"
	for r in p.rules:
		if not r.next.is_empty() and not ids.has(r.next):
			return "DANGLING_NEXT"
		for a in r.actions:
			if a.op == "branch" and not ids.has(a.target):
				return "DANGLING_BRANCH"
	return ""

static func validate_action(a: Variant) -> String:
	if not C.keys(a, ["op", "role", "delta_mm", "radius_mm", "area_mm2", "reach_mm", "target", "enabled"]):
		return "ACTION_FIELDS"
	if not a.op in OPS or not a.role in ROLES or not a.enabled is bool or not a.target is String:
		return "ACTION_TYPE"
	if not C.vector(a.delta_mm, 2000) or not C.integer(a.radius_mm, 0, 100) or not C.integer(a.area_mm2, 0, 250000) or not C.integer(a.reach_mm, 0, 2000):
		return "ACTION_RANGE"
	if a.op == "branch" or a.op == "retire":
		if a.role != "support" or a.delta_mm != [0, 0, 0] or a.radius_mm != 0 or a.area_mm2 != 0 or a.reach_mm != 0:
			return "CONTROL_ACTION_PAYLOAD"
		if (a.op == "branch" and not C.identifier(a.target)) or (a.op == "retire" and a.target != ""):
			return "CONTROL_TARGET"
	else:
		if a.op == "attach":
			if a.role != "attachment" or not C.identifier(a.target) or a.reach_mm == 0:
				return "ATTACHMENT_CONTRACT"
		elif a.target != "":
			return "UNEXPECTED_TARGET"
		if a.op == "extend" and not a.role in ["support", "transport"]:
			return "EXTEND_ROLE"
		if a.op == "differentiate" and a.role in ["attachment", "support", "transport"]:
			return "DIFFERENTIATE_ROLE"
		if a.role != "collector" and a.area_mm2 != 0:
			return "AREA_ROLE"
		if not a.role in ["absorber", "attachment"] and a.reach_mm != 0:
			return "REACH_ROLE"
		if a.op == "allocate":
			if a.delta_mm != [0, 0, 0]:
				return "ALLOCATION_POSITION"
		elif a.radius_mm == 0:
			return "ZERO_RADIUS"
	return ""

static func normalized(p: Dictionary) -> Dictionary:
	var result := p.duplicate(true)
	result.rules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return result

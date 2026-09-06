extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const CHANNELS := ["light", "water", "temperature", "competition", "mechanical"]

static func create(water: int = 650, light: int = 700, with_host: bool = true) -> Dictionary:
	var supports: Array = [{"id": "ground", "kind": "plane_y", "position_mm": [0, 0, 0]}]
	if with_host:
		supports.append({"id": "host", "kind": "axis_y", "position_mm": [0, 0, 0]})
	return {"schema": "dws.ecology.synthetic-environment.v1", "channels": {"light": light, "water": water, "temperature": 500, "competition": 0, "mechanical": 0}, "supports": supports}

static func validate(env: Variant) -> String:
	if not C.keys(env, ["schema", "channels", "supports"]) or env.schema != "dws.ecology.synthetic-environment.v1" or not C.keys(env.channels, CHANNELS):
		return "ENVIRONMENT_SCHEMA"
	for name in CHANNELS:
		if not C.integer(env.channels[name], 0, 1000):
			return "ENVIRONMENT_CHANNEL"
	if not env.supports is Array or env.supports.size() > 64:
		return "SUPPORT_COUNT"
	var seen := {}
	for support in env.supports:
		if not C.keys(support, ["id", "kind", "position_mm"]) or not C.identifier(support.id) or seen.has(support.id):
			return "SUPPORT_ID"
		if not support.kind in ["plane_y", "axis_y", "point"] or not C.vector(support.position_mm, 10000000):
			return "SUPPORT_SHAPE"
		seen[support.id] = true
	return ""

static func can_attach(env: Dictionary, id: String, position: Array, reach: int) -> bool:
	for support in env.supports:
		if support.id != id:
			continue
		var projected: Array = position.duplicate()
		match support.kind:
			"plane_y": projected[1] = support.position_mm[1]
			"axis_y":
				projected[0] = support.position_mm[0]
				projected[2] = support.position_mm[2]
			"point": projected = support.position_mm
		return B.length_mm(position, projected) <= reach
	return false

extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const CHANNELS := ["light", "water", "temperature", "competition", "mechanical"]

static func create(water: int = 650, light: int = 700, with_host: bool = true) -> Dictionary:
	var supports: Array = [{"id": "ground", "kind": "plane_y", "position_mm": [0, 0, 0]}]
	if with_host:
		supports.append({"id": "host", "kind": "axis_y", "position_mm": [0, 0, 0]})
	return {"schema": "dws.ecology.synthetic-environment.v1", "channels": {"light": light, "water": water, "temperature": 500, "competition": 0, "mechanical": 0}, "supports": supports}

static func validate(env: Variant) -> String:
	if env is Dictionary and env.get("schema", "") == F.SAMPLE_SCHEMA:
		return F.validate_sample(env)
	if not C.keys(env, ["schema", "channels", "supports"]) or env.schema != "dws.ecology.synthetic-environment.v1" or not C.keys(env.channels, CHANNELS):
		return "ENVIRONMENT_SCHEMA"
	for name in CHANNELS:
		if not C.integer(env.channels[name], 0, 1000):
			return "ENVIRONMENT_CHANNEL"
	if not F.validate_supports(env.supports):
		return "SUPPORT_SHAPE"
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

extends "res://scripts/labs/ecology/eco_evo5_terrain_fly_lab.gd"

## EVO6/R3.1 presentation adapter. The parent R3 flyover remains unchanged;
## this lab fail-closes onto the generated-rule outcome artifact before any
## plant establishment, so visual survival/pigment channels come from R4 data.

const GENERATED_OUTCOMES_PATH := "res://validation/ecology/evo6_r31_generated_outcomes.v1.json"
const GENERATED_OUTCOMES_SCHEMA := "distributed_world_simulator.ecology.evo6_r31_generated_outcomes.v1"
var _evo6_generated_fates_loaded := false


func _establish(pos: Vector3, zone: String, hue_jitter: float, cell_key: String) -> void:
	if not _evo6_generated_fates_loaded:
		if not _load_evo6_generated_fates():
			push_error("ECO.EVO6 R3.1: generated outcome artifact missing or invalid")
			return
	super._establish(pos, zone, hue_jitter, cell_key)


func _load_evo6_generated_fates() -> bool:
	var outcomes_path := OS.get_environment("EVO6_GENERATED_OUTCOMES_PATH")
	if outcomes_path.is_empty():
		outcomes_path = GENERATED_OUTCOMES_PATH
	if not FileAccess.file_exists(outcomes_path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(outcomes_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var artifact: Dictionary = parsed
	if String(artifact.get("schema", "")) != GENERATED_OUTCOMES_SCHEMA:
		return false
	if String(artifact.get("version", "")) != "1.0.0":
		return false
	var raw_fates = artifact.get("fates", [])
	if typeof(raw_fates) != TYPE_ARRAY or (raw_fates as Array).is_empty():
		return false
	var loaded := {}
	for raw_fate in raw_fates as Array:
		if typeof(raw_fate) != TYPE_DICTIONARY:
			return false
		var fate: Dictionary = raw_fate
		var x_value = fate.get("x")
		var z_value = fate.get("z")
		if typeof(x_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(z_value) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if float(int(x_value)) != float(x_value) or float(int(z_value)) != float(z_value):
			return false
		if typeof(fate.get("survived")) != TYPE_BOOL:
			return false
		var pigment = fate.get("pigment", [])
		if typeof(pigment) != TYPE_ARRAY or (pigment as Array).size() != 3:
			return false
		var key := "%d|%d" % [int(fate["x"]), int(fate["z"])]
		if loaded.has(key):
			return false
		loaded[key] = fate
	if loaded.size() != (raw_fates as Array).size():
		return false
	_fates = loaded
	_evo6_generated_fates_loaded = true
	print("ECO.EVO6 R3.1 generated visual source: seed=%s digest=%s cells=%d" % [
		String(artifact.get("seed", "")),
		String(artifact.get("artifact_digest", "")),
		_fates.size(),
	])
	return true

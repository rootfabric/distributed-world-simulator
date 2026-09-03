class_name WorldFillShowcaseKit
extends RefCounted

## WF0.10 Observe / Showcase Toolkit (WORLD FILL train).
##
## Makes demos and visual regressions repeatable: one observation record
## bundles the caller-supplied read-only context (screenshot reference,
## simulation tick, region, authority, selected checksum, world-fill preset)
## with a fixed schema, plus the canonical set of spectator bookmarks.
##
## Guarantees:
## - DETERMINISTIC: records contain no wall-clock time; identity comes from
##   caller-supplied tick/ids only, so the same inputs re-render identically.
## - LOCAL-ONLY: records persist under user://world_memory/showcase/.
## - FAIL-SOFT: missing optional fields become reasons, never errors.
## - TRUTH-FREE: the kit owns no canonical state and reads nothing by itself;
##   the caller passes observation values in.

const SCHEMA := "world_fill.showcase_observation.v1"

const SHOWCASE_ROOT := "user://world_memory/showcase"

const SPECTATOR_BOOKMARKS := {
	"spawn": {"position": Vector3(0.0, 2.0, 18.0), "target": Vector3(0.0, 1.0, -2.0)},
	"outpost": {"position": Vector3(-14.0, 3.0, -10.0), "target": Vector3(0.0, 1.2, -8.0)},
	"dig_site": {"position": Vector3(12.0, 3.0, 10.0), "target": Vector3(6.0, 0.5, 6.0)},
	"seam": {"position": Vector3(0.0, 2.5, -9.0), "target": Vector3(0.0, 0.2, -14.0)},
	"handoff": {"position": Vector3(18.0, 4.0, -6.0), "target": Vector3(6.0, 1.0, -6.0)},
	"horizon": {"position": Vector3(0.0, 12.0, 24.0), "target": Vector3(0.0, 2.0, 0.0)},
}

const REQUIRED_FIELDS: Array[String] = ["simulation_tick", "world_fill_preset"]
const OPTIONAL_FIELDS: Array[String] = [
	"screenshot_path",
	"region_id",
	"authority_id",
	"checksum",
	"scene_id",
]


func list_bookmarks() -> Array[Dictionary]:
	var bookmarks: Array[Dictionary] = []
	var names := SPECTATOR_BOOKMARKS.keys()
	names.sort()
	for bookmark_name in names:
		var definition: Dictionary = SPECTATOR_BOOKMARKS[bookmark_name]
		bookmarks.append({
			"name": String(bookmark_name),
			"position": definition["position"],
			"target": definition["target"],
		})
	return bookmarks


func capture_observation(observed: Dictionary) -> Dictionary:
	var record := {
		"schema": SCHEMA,
		"world_fill_preset": String(observed.get("world_fill_preset", "")),
		"simulation_tick": int(observed.get("simulation_tick", -1)),
		"screenshot_path": String(observed.get("screenshot_path", "")),
		"region_id": String(observed.get("region_id", "")),
		"authority_id": String(observed.get("authority_id", "")),
		"checksum": String(observed.get("checksum", "")),
		"scene_id": String(observed.get("scene_id", "")),
	}
	var reasons := []
	for field in REQUIRED_FIELDS:
		if (record[field] is String and record[field] == "") or (record[field] is int and int(record[field]) < 0):
			reasons.append("MISSING_%s" % String(field).to_upper())
	record["complete"] = reasons.is_empty()
	record["reasons"] = reasons
	return record


func observation_path(observation_id: String) -> String:
	var sanitized := observation_id.replace("/", "_").replace("\\", "_").replace(" ", "_")
	return "%s/%s.json" % [SHOWCASE_ROOT, sanitized]


func save_observation(observation_id: String, record: Dictionary) -> bool:
	if observation_id == "":
		return false
	if String(record.get("schema", "")) != SCHEMA:
		return false
	DirAccess.make_dir_recursive_absolute(SHOWCASE_ROOT)
	var file := FileAccess.open(observation_path(observation_id), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record))
	file.close()
	return true


func load_observation(observation_id: String) -> Dictionary:
	var path := observation_path(observation_id)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func clear_observation(observation_id: String) -> void:
	var path := observation_path(observation_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

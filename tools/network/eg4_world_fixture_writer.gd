extends SceneTree

## EG4 fixture writer: regenerates the deterministic known-world fixture JSON
## from eg4_world_fixture_generator.gd and writes it atomically under
## tests/network/fixtures/. Run headless:
##   godot --headless --path <project> --script res://tools/network/eg4_world_fixture_writer.gd
## Output is byte-stable for a given seed/world count (pure arithmetic), so
## re-running it must never produce a diff.

const Generator = preload("res://tools/network/eg4_world_fixture_generator.gd")
const SnapshotScript = preload("res://scripts/network/gateway/gateway_world_graph_snapshot.gd")

const SEED := Generator.DEFAULT_SEED
const WORLD_COUNT := Generator.DEFAULT_WORLD_COUNT
const OUTPUT_PATH := "res://tests/network/fixtures/eg4_world_graph_fixture.json"


func _init() -> void:
	var snapshot: Dictionary = Generator.generate_world_graph_snapshot(SEED, WORLD_COUNT)
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		push_error("eg4 fixture writer generated an INVALID snapshot: %s" % String(validation.get("error_code", "")))
		quit(1)
		return
	var payload := {
		"schema": "planet_simulator.eg4_world_graph_fixture.v1",
		"seed": SEED,
		"world_count": WORLD_COUNT,
		"snapshot": snapshot,
	}
	var json := JSON.stringify(payload, "  ")
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("cannot open %s for writing" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(json + "\n")
	file.close()
	print("EG4_FIXTURE_WRITTEN worlds=%d relations=%d path=%s bytes=%d" % [
		(snapshot["worlds"] as Array).size(),
		(snapshot["relations"] as Array).size(),
		OUTPUT_PATH,
		json.length(),
	])
	quit(0)

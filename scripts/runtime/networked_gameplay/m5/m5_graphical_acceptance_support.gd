extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const CHECKPOINT := "v16.10.4-testing-m5-graphical-multiplayer-acceptance"
const BUILD_ID := "m5-ui-driven-graphical-multiplayer-acceptance"
const REPORT_SCHEMA := "planet_simulator.m5_graphical_acceptance_report.v1"
const CONTROL_SCHEMA := "planet_simulator.m5_graphical_acceptance_control.v1"


static func write(path: String, value: Dictionary) -> bool:
	if path.strip_edges().is_empty():
		return false
	return bool(AtomicJson.write_dictionary(path, value).get("success", false))


static func read(path: String) -> Dictionary:
	if path.strip_edges().is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}

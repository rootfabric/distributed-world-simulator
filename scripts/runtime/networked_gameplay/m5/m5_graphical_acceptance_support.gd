extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const CHECKPOINT := "v16.10.4-testing-m5-graphical-multiplayer-acceptance"
const BUILD_ID := "m5-ui-driven-graphical-multiplayer-acceptance"
const REPORT_SCHEMA := "planet_simulator.m5_graphical_acceptance_report.v1"
const CONTROL_SCHEMA := "planet_simulator.m5_graphical_acceptance_control.v1"

const WRITE_RETRY_TIMEOUT_MS := 5000
const WRITE_RETRY_DELAY_MS := 10


static func write(path: String, value: Dictionary) -> bool:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		return false
	var started_ms := Time.get_ticks_msec()
	var last_result: Dictionary = {}
	while Time.get_ticks_msec() - started_ms <= WRITE_RETRY_TIMEOUT_MS:
		last_result = AtomicJson.write_dictionary(normalized_path, value)
		if bool(last_result.get("success", false)):
			return true
		OS.delay_msec(WRITE_RETRY_DELAY_MS)
	push_error(
		"M5 atomic JSON publication failed after retries: path=%s result=%s"
		% [normalized_path, last_result]
	)
	return false


static func read(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return {}
	return AtomicJson.read_value(path)

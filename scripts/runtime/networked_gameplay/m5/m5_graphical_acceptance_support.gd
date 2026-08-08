extends RefCounted

const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const CHECKPOINT := "v16.10.4-testing-m5-graphical-multiplayer-acceptance"
const BUILD_ID := "m5-ui-driven-graphical-multiplayer-acceptance"
const REPORT_SCHEMA := "planet_simulator.m5_graphical_acceptance_report.v1"
const CONTROL_SCHEMA := "planet_simulator.m5_graphical_acceptance_control.v1"

const WRITE_RETRY_TIMEOUT_MS := 5000
const WRITE_RETRY_DELAY_MS := 10

# M5 result/control files are non-empty dictionaries with one writer per path.
# Windows atomic replace can expose a brief read gap while the old path is being
# replaced. Keep the last process-local successful snapshot so a coordinator
# read-modify-write never rebuilds control state from a transient empty read.
static var _read_cache: Dictionary = {}


static func write(path: String, value: Dictionary) -> bool:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		return false
	var started_ms := Time.get_ticks_msec()
	var last_result: Dictionary = {}
	while Time.get_ticks_msec() - started_ms <= WRITE_RETRY_TIMEOUT_MS:
		last_result = AtomicJson.write_dictionary(normalized_path, value)
		if bool(last_result.get("success", false)):
			_read_cache[normalized_path] = value.duplicate(true)
			return true
		OS.delay_msec(WRITE_RETRY_DELAY_MS)
	push_error(
		"M5 atomic JSON publication failed after retries: path=%s result=%s"
		% [normalized_path, last_result]
	)
	return false


static func read(path: String) -> Dictionary:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		return {}
	var value: Dictionary = AtomicJson.read_value(normalized_path)
	if not value.is_empty():
		_read_cache[normalized_path] = value.duplicate(true)
		return value
	if _read_cache.has(normalized_path):
		return Dictionary(_read_cache[normalized_path]).duplicate(true)
	return {}

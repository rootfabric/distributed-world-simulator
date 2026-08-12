extends SceneTree

const HostType = preload("res://scripts/characters/lab/quaternius_fpe_ch9_6_host.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host = HostType.new()
	root.add_child(host)

	var started_us := Time.get_ticks_usec()
	for _index in range(180):
		host._refresh_status()
	var elapsed_us := Time.get_ticks_usec() - started_us
	var report: Dictionary = host.get_fpe_status_performance_report()

	_assert(int(report.get("calls", 0)) == 180, "status throttle did not observe all virtual refresh calls")
	_assert(int(report.get("executed", 0)) == 1, "status throttle executed more than once inside a tight frame burst")
	_assert(int(report.get("skipped", 0)) == 179, "status throttle did not skip the expected per-frame rebuilds")
	_assert(int(report.get("interval_ms", 0)) >= 250, "status throttle interval is too aggressive")
	_assert(not bool(report.get("changes_gameplay_semantics", true)), "research host claims gameplay semantic changes")
	_assert(not bool(report.get("changes_network_authority", true)), "research host claims network authority changes")
	_assert(elapsed_us < 250000, "status throttle burst took unexpectedly long")

	host.free()
	_finish()


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FirstPersonEmbodiment performance gate: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FirstPersonEmbodiment performance gate: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

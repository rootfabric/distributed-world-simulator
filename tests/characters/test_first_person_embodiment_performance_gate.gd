extends SceneTree

const HostType = preload("res://scripts/characters/lab/quaternius_fpe_ch9_6_host.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Do not add the host to SceneTree. This gate isolates the research host's
	# automatic status suppression and pure canonical projection classifier from
	# external garments, ENet bootstrap, and accepted CH9 runtime side effects.
	var host = HostType.new()

	var started_us := Time.get_ticks_usec()
	for _index in range(180):
		host._refresh_status()
	var elapsed_us := Time.get_ticks_usec() - started_us
	var report: Dictionary = host.get_fpe_status_performance_report()

	_assert(int(report.get("calls", 0)) == 180, "status suppression did not observe all virtual refresh calls")
	_assert(int(report.get("executed", -1)) == 0, "automatic inherited heavy status rebuild executed unexpectedly")
	_assert(int(report.get("skipped", 0)) == 180, "automatic inherited heavy status calls were not all suppressed")
	_assert(not bool(report.get("automatic_heavy_status", true)), "research host still reports automatic heavy HUD enabled")
	_assert(int(report.get("max_us", -1)) == 0, "suppressed status path reported heavy execution cost")
	_assert(not bool(report.get("changes_gameplay_semantics", true)), "research host claims gameplay semantic changes")
	_assert(not bool(report.get("changes_network_authority", true)), "research host claims network authority changes")
	_assert(elapsed_us < 50000, "suppressed 180-call status burst took unexpectedly long")

	var base_snapshot := {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"revision": 10,
		"tick": 10,
		"checksum": "base",
		"inventories": {
			"a": {
				"inventory": ["item/a"],
				"hotbar": ["item/a"],
				"selected_hotbar_index": 0,
			},
		},
		"items": [{"item_id": "item/a", "quantity": 1}],
		"containers": [],
		"mounts": [],
		"open_containers": {},
	}
	var hotbar_only: Dictionary = base_snapshot.duplicate(true)
	hotbar_only["revision"] = 11
	hotbar_only["tick"] = 11
	hotbar_only["checksum"] = "hotbar"
	hotbar_only["inventories"]["a"]["selected_hotbar_index"] = 1
	_assert(
		host._classify_fpe_projection(base_snapshot, hotbar_only) == host.PROJECTION_HOTBAR_METADATA_ONLY,
		"selected_hotbar_index-only canonical change was not classified for fast path"
	)

	var structural: Dictionary = hotbar_only.duplicate(true)
	structural["revision"] = 12
	structural["tick"] = 12
	structural["checksum"] = "structural"
	structural["items"][0]["quantity"] = 2
	_assert(
		host._classify_fpe_projection(hotbar_only, structural) == host.PROJECTION_FULL,
		"structural Item Graph mutation was incorrectly classified as hotbar metadata"
	)

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

extends SceneTree

## ECO.EVO7 PAR2 — PLAY0 parallel-only recruitment test (v1).
##
## PLAY0 AUTO evolution stays responsive while EVERY generation's recruitment
## runs through the PAR2 canonical executor (parallel-only + bounded audits)
## injected through the existing LS3.3 seam (workbench.ecology.core). The
## test performs the injection; the playground source stays backend-blind.
##
## PASS requires: runtime init, generations keep committing (no fail-closed
## stop), audits occur only on the deterministic schedule, FPS evidence,
## no sustained stall, no backend failure. Frame-driven like the PAR1
## contention test.

const Play0Scene = preload("res://scenes/labs/ecology/eco_evo7_play0_live_planet_playground.tscn")
const Par2Executor = preload("res://scripts/ecology/perf/eco_evo7_par2_canonical_recruitment_executor_v1.gd")

const MIN_SECONDS := 190.0

var assertions := 0
var failures: Array[String] = []

var _playground = null
var _executor = null
var _started_msec := 0
var _last_sample_msec := 0
var _fps_samples: Array[int] = []
var _last_generation := -1
var _generation_advances := 0
var _stall_seconds := 0.0
var _last_progress_msec := 0
var _finished := false

func _init() -> void:
	var project_root := ProjectSettings.globalize_path("res://")
	var godot_bin := OS.get_environment("GODOT_BIN")
	if godot_bin.is_empty():
		godot_bin = "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
	var session_root := OS.get_environment("ECO_PAR0_SESSION_ROOT")
	if session_root.is_empty():
		session_root = project_root.path_join("artifacts/par0_sessions")

	_playground = Play0Scene.instantiate()
	_playground.auto_initialize = false
	root.add_child(_playground)
	if not _playground.initialize_runtime():
		_check(false, "PLAY0 runtime initializes")
		_finish()
		return
	_check(true, "PLAY0 runtime initializes")

	var workbench = _playground.get_workbench()
	if workbench == null:
		_check(false, "PLAY0 workbench available")
		_finish()
		return
	var ls33: Object = workbench.ecology.core
	_check(not ls33.has_recruitment_executor(), "no executor pre-injected")

	_executor = Par2Executor.new()
	if not _executor.setup({
		"backend": "PROCESS_POOL",
		"worker_count": 4,
		"godot_bin": godot_bin,
		"project_root": project_root,
		"session_root": session_root,
		"job_timeout_ms": 240_000,
		"audit_interval": 10,
		"audit_generation_1": true,
	}):
		_check(false, "PAR2 executor setup")
		_finish()
		return
	_check(ls33.set_recruitment_executor(_executor), "PAR2 executor injected through LS3.3 seam")
	_check(workbench.has_recruitment_executor(), "Workbench pass-through sees the executor")

	_playground.set_auto_evolution(true)
	_check(_playground.is_auto_evolution(), "AUTO evolution enabled")

	_started_msec = Time.get_ticks_msec()
	_last_sample_msec = _started_msec
	_last_progress_msec = _started_msec
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _finished:
		return
	var now := Time.get_ticks_msec()
	if now - _last_sample_msec >= 500:
		_last_sample_msec = now
		_fps_samples.append(int(Engine.get_frames_per_second()))
		var snapshot: Dictionary = _playground.get_published_snapshot()
		var generation := int(snapshot.get("generation", -1))
		if generation > _last_generation:
			if _last_generation >= 0:
				_generation_advances += 1
			_last_generation = generation
			_last_progress_msec = now
		if float(now - _last_progress_msec) > 60_000.0:
			_stall_seconds = float(now - _last_progress_msec) / 1000.0
	if float(now - _started_msec) >= MIN_SECONDS * 1000.0 or _stall_seconds > 0.0:
		_finish()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR2 PLAY0 CHECK FAIL: " + label)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _playground != null:
		if _playground.get_workbench() != null:
			var ls33: Object = _playground.get_workbench().ecology.core
			if ls33 != null:
				ls33.call("clear_recruitment_executor")
		_playground.set_auto_evolution(false)
	if _started_msec > 0:
		_check(_generation_advances >= 3, "generations keep committing under PAR2 (advances=%d)" % _generation_advances)
		_check(_stall_seconds == 0.0, "no sustained generation stall (worst=%.1fs)" % _stall_seconds)
		_check(_fps_samples.size() >= 100, "frame responsiveness samples collected (%d)" % _fps_samples.size())
		var fps_min := 10_000
		var fps_sum := 0
		for sample in _fps_samples:
			fps_min = mini(fps_min, int(sample))
			fps_sum += int(sample)
		var fps_mean := float(fps_sum) / float(maxi(1, _fps_samples.size()))
		if _executor != null:
			var telemetry: Dictionary = _executor.get_telemetry()
			var parallel_calls := int(telemetry.get("parallel_calls", 0))
			var audits := int(telemetry.get("serial_audit_calls", 0))
			var elision := float(telemetry.get("oracle_elided_generations", 0)) / float(maxi(1, parallel_calls))
			_check(absi(parallel_calls - _last_generation) <= 1, "every committed generation used parallel backend (calls=%d published_gen=%d)" % [parallel_calls, _last_generation])
			_check(audits == 1 + (_last_generation / 10), "audits on deterministic schedule (%d audits over %d gens)" % [audits, _last_generation])
			_check(elision >= 0.80, "oracle elision >=80%% live (%.1f%%)" % (elision * 100.0))
			print("PAR2_PLAY0_SUMMARY " + JSON.stringify({
				"seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
				"generation_advances": _generation_advances,
				"final_generation": _last_generation,
				"parallel_calls": parallel_calls,
				"serial_audit_calls": audits,
				"oracle_elision": elision,
				"fps_min": fps_min, "fps_mean": fps_mean,
				"stall_seconds": _stall_seconds,
			}))
	if _executor != null:
		_executor.shutdown()
	if failures.is_empty():
		print("ECO.EVO7 PAR2 PLAY0 Parallel-Only: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PAR2 PLAY0 FAIL: " + failure)
	print("ECO.EVO7 PAR2 PLAY0 Parallel-Only: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)

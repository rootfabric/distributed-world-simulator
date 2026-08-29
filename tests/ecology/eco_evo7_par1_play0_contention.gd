extends SceneTree

## ECO.EVO7 PAR1 — PLAY0 graphical contention test (v1).
##
## Drives the real PLAY0 scene with AUTO evolution for >=180 seconds while
## recruitment executes through a PAR1 direct backend injected through the
## existing LS3.3 executor seam (workbench.ecology.core). The test (not the
## playground source) performs the injection, so the PLAY0 source guard
## (no LS3.3/LS3.4 references inside the playground) stays satisfied.
##
## PASS requires:
##   - no black screen / init failure;
##   - generations keep committing (population evolves, generation grows);
##   - no backend failure (fail-closed would stop generations);
##   - no SceneTree/Node worker violation (Godot thread-safety checks stay
##     enabled; any violation aborts the engine);
##   - frame responsiveness evidence (FPS samples) + no sustained stall.
##
## The run is frame-driven: _init only performs setup; the measurement loop
## rides the process_frame signal so PLAY0 keeps rendering.

const Play0Scene = preload("res://scenes/labs/ecology/eco_evo7_play0_live_planet_playground.tscn")
const WorkerThreadBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_worker_thread_recruitment_backend_v1.gd")
const ProcessBackend = preload("res://scripts/ecology/perf/eco_evo7_par1_process_recruitment_backend_v1.gd")

const MIN_SECONDS := 190.0

var assertions := 0
var failures: Array[String] = []

var _playground = null
var _backend = null
var _backend_id := ""
var _worker_count := 4
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
	_backend_id = "WORKER_THREAD_POOL"
	var config := _load_config(project_root)
	if not config.is_empty():
		_backend_id = String(config.get("par1_selected_backend", _backend_id))
		_worker_count = int(config.get("par1_worker_count", _worker_count))

	_playground = Play0Scene.instantiate()
	_playground.auto_initialize = false
	root.add_child(_playground)
	if not _playground.initialize_runtime():
		_check(false, "PLAY0 runtime initializes (no black screen)")
		_finish()
		return
	_check(true, "PLAY0 runtime initializes (no black screen)")

	var workbench = _playground.get_workbench()
	if workbench == null:
		_check(false, "PLAY0 workbench available")
		_finish()
		return
	var ls33: Object = workbench.ecology.core
	_check(not ls33.has_recruitment_executor(), "no executor pre-injected")

	if _backend_id == "PROCESS_POOL":
		_backend = ProcessBackend.new()
		var godot_bin := OS.get_environment("GODOT_BIN")
		if godot_bin.is_empty():
			godot_bin = "C:/Godot/godot/bin/godot.windows.editor.double.x86_64.console.exe"
		var session_root := OS.get_environment("ECO_PAR0_SESSION_ROOT")
		if session_root.is_empty():
			session_root = project_root.path_join("artifacts/par0_sessions")
		if not _backend.setup({
			"worker_count": _worker_count, "godot_bin": godot_bin,
			"project_root": project_root, "session_root": session_root,
			"job_timeout_ms": 240_000,
		}):
			_check(false, "process backend setup")
			_finish()
			return
	else:
		_backend = WorkerThreadBackend.new()
		if not _backend.setup({"worker_count": _worker_count}):
			_check(false, "WTP backend setup")
			_finish()
			return
	_check(ls33.set_recruitment_executor(_backend), "selected backend injected through LS3.3 seam")
	_check(ls33.has_recruitment_executor(), "LS3.3 reports injected executor")

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

func _load_config(project_root: String) -> Dictionary:
	var path := project_root.path_join("config/ecology/eco-evo7-parallel-runtime.v1.json")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR1 CONTENTION CHECK FAIL: " + label)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _playground != null and _playground.get_workbench() != null:
		var ls33: Object = _playground.get_workbench().ecology.core
		if ls33 != null:
			ls33.call("clear_recruitment_executor")
	if _playground != null:
		_playground.set_auto_evolution(false)
	if _backend != null:
		_backend.call("shutdown")
	if _started_msec > 0:
		_check(_generation_advances >= 3, "generations keep committing under contention (advances=%d)" % _generation_advances)
		_check(_stall_seconds == 0.0, "no sustained generation stall (worst=%.1fs)" % _stall_seconds)
		_check(_fps_samples.size() >= 100, "frame responsiveness samples collected (%d)" % _fps_samples.size())
		var fps_min := 10_000
		var fps_sum := 0
		for sample in _fps_samples:
			fps_min = mini(fps_min, int(sample))
			fps_sum += int(sample)
		var fps_mean := float(fps_sum) / float(maxi(1, _fps_samples.size()))
		if _backend != null:
			var report: Dictionary = _backend.call("get_last_report")
			_check(not report.has("failure_code") or String(report.get("failure_code", "")) == "", "no backend failure during contention")
		print("PAR1_CONTENTION_SUMMARY " + JSON.stringify({
			"backend": _backend_id,
			"worker_count": _worker_count,
			"seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
			"generation_advances": _generation_advances,
			"final_generation": _last_generation,
			"fps_min": fps_min, "fps_mean": fps_mean,
			"stall_seconds": _stall_seconds,
		}))
	if failures.is_empty():
		print("ECO.EVO7 PAR1 PLAY0 Contention: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PAR1 CONTENTION FAIL: " + failure)
	print("ECO.EVO7 PAR1 PLAY0 Contention: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)

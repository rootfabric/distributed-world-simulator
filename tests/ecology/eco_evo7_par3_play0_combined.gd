extends SceneTree

## ECO.EVO7 PAR3 — PLAY0 combined parallel test (v1).
##
## Live PLAY0 with BOTH parallel paths active for >=5 graphical minutes:
##   - parallel deterministic candidate reproduction (PAR3 executor);
##   - parallel-only recruitment with bounded audits (PAR2 executor).
## AUTO evolution on. PASS requires: runtime init, generations keep
## committing, deterministic audit schedules for BOTH executors, no stall,
## FPS evidence, no backend failure, presentation snapshot follows committed
## ecology. If instability appears, a >=10-minute soak is required before
## any candidate claim (see checkpoint doc).

const Play0Scene = preload("res://scenes/labs/ecology/eco_evo7_play0_live_planet_playground.tscn")
const Par2Executor = preload("res://scripts/ecology/perf/eco_evo7_par2_canonical_recruitment_executor_v1.gd")
const Par3Executor = preload("res://scripts/ecology/perf/eco_evo7_par3_candidate_build_executor_v1.gd")
const LS33 = preload("res://scripts/ecology/shadow/eco_evo7_ls33_dispersal_recruitment_v1.gd")
const Workbench = preload("res://scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd")

const MIN_SECONDS := 310.0

var assertions := 0
var failures: Array[String] = []

var _playground = null
var _par2 = null
var _par3 = null
var _started_msec := 0
var _last_sample_msec := 0
var _fps_samples: Array[int] = []
var _last_generation := -1
var _generation_advances := 0
var _stall_seconds := 0.0
var _last_progress_msec := 0
var _finished := false
var _stop_requested := false

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

	_par2 = Par2Executor.new()
	if not _par2.setup({
		"backend": "PROCESS_POOL", "worker_count": 4,
		"godot_bin": godot_bin, "project_root": project_root,
		"session_root": session_root, "job_timeout_ms": 240_000,
		"audit_interval": 10, "audit_generation_1": true,
	}):
		_check(false, "PAR2 executor setup")
		_finish()
		return
	_par3 = Par3Executor.new()
	if not _par3.setup({
		"worker_count": 4,
		"ls33_schema": String(LS33.SCHEMA), "ls33_version": String(LS33.VERSION),
		"evolution_seed": int(Workbench.EVOLUTION_SEED),
		"offspring_per_parent": int(LS33.OFFSPRING_PER_PARENT),
		"godot_bin": godot_bin, "project_root": project_root,
		"session_root": session_root, "job_timeout_ms": 240_000,
		"audit_interval": 10, "audit_generation_1": true,
	}):
		_check(false, "PAR3 executor setup")
		_finish()
		return
	_check(workbench.set_candidate_executor(_par3), "PAR3 candidate executor injected through Workbench public facade")
	_check(workbench.has_candidate_executor(), "Workbench candidate facade sees executor")
	_check(workbench.set_recruitment_executor(_par2), "PAR2 recruitment executor injected through Workbench public facade")
	_check(workbench.has_recruitment_executor(), "Workbench recruitment facade sees executor")

	_playground.set_auto_evolution(true)
	_check(_playground.is_auto_evolution(), "AUTO evolution enabled")

	_started_msec = Time.get_ticks_msec()
	_last_sample_msec = _started_msec
	_last_progress_msec = _started_msec
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _finished:
		return
	if _stop_requested:
		## Let the already-started generation finish and be published before
		## reading PAR2/PAR3 telemetry. This removes phase-ahead cutoff races.
		if not _playground.is_generation_running():
			_finish()
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
		_stop_requested = true
		_playground.set_auto_evolution(false)
		if not _playground.is_generation_running():
			_finish()

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("PAR3 PLAY0 CHECK FAIL: " + label)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	if _playground != null:
		if _playground.get_workbench() != null:
			_playground.get_workbench().clear_candidate_executor()
			_playground.get_workbench().clear_recruitment_executor()
		_playground.set_auto_evolution(false)
	if _started_msec > 0:
		_check(_generation_advances >= 5, "generations keep committing under combined parallel (advances=%d)" % _generation_advances)
		_check(_stall_seconds == 0.0, "no sustained stall (worst=%.1fs)" % _stall_seconds)
		_check(_fps_samples.size() >= 100, "frame responsiveness samples (%d)" % _fps_samples.size())
		var fps_min := 10_000
		var fps_sum := 0
		for sample in _fps_samples:
			fps_min = mini(fps_min, int(sample))
			fps_sum += int(sample)
		var fps_mean := float(fps_sum) / float(maxi(1, _fps_samples.size()))
		var t2: Dictionary = _par2.get_telemetry() if _par2 != null else {}
		var t3: Dictionary = _par3.get_telemetry() if _par3 != null else {}
		if not t2.is_empty() and not t3.is_empty():
			var audits2 := int(t2.get("serial_audit_calls", 0))
			var audits3 := int(t3.get("serial_audit_calls", 0))
			_check(absi(int(t2.get("parallel_calls", 0)) - _last_generation) <= 1, "recruitment parallel every generation (%d/%d)" % [int(t2.get("parallel_calls", 0)), _last_generation])
			_check(absi(int(t3.get("parallel_calls", 0)) - _last_generation) <= 1, "candidate build parallel every generation (%d/%d)" % [int(t3.get("parallel_calls", 0)), _last_generation])
			_check(audits2 == 1 + (_last_generation / 10), "recruitment audits on schedule (%d over %d)" % [audits2, _last_generation])
			_check(audits3 == 1 + (_last_generation / 10), "candidate audits on schedule (%d over %d)" % [audits3, _last_generation])
			_check(bool(t3.get("last_audit_pass", false)), "last candidate audit passed live")
			print("PAR3_PLAY0_COMBINED_SUMMARY " + JSON.stringify({
				"seconds": float(Time.get_ticks_msec() - _started_msec) / 1000.0,
				"generation_advances": _generation_advances,
				"final_generation": _last_generation,
				"recruitment_parallel_calls": int(t2.get("parallel_calls", 0)),
				"recruitment_audits": audits2,
				"candidate_parallel_calls": int(t3.get("parallel_calls", 0)),
				"candidate_audits": audits3,
				"fps_min": fps_min, "fps_mean": fps_mean,
				"stall_seconds": _stall_seconds,
			}))
	if _par2 != null:
		_par2.shutdown()
	if _par3 != null:
		_par3.shutdown()
	if failures.is_empty():
		print("ECO.EVO7 PAR3 PLAY0 Combined Parallel: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		print("PAR3 PLAY0 FAIL: " + failure)
	print("ECO.EVO7 PAR3 PLAY0 Combined Parallel: FAIL (%d/%d assertions failed)" % [failures.size(), assertions])
	quit(1)

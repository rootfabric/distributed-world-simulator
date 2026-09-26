extends SceneTree
## Invoked only by run_exact.py. Explicit result path is required for this
## machine protocol; this helper is not discovered as a standalone test.
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var split := argument.split("=", true, 1)
		if split.size() == 2:
			if args.has(split[0]):
				push_error("A11_RESTART_DUPLICATE_ARGUMENT")
				quit(1)
				return
			args[split[0]] = split[1]
	if not args.has("--result") or String(args["--result"]).is_empty() or not args.has("--phase"):
		push_error("A11_RESTART_REQUIRED_RESULT_AND_PHASE")
		quit(1)
		return
	var phase := String(args["--phase"])
	var session := Session.new()
	var result: Dictionary = {}
	if phase in ["baseline", "checkpoint"]:
		result = session.start(Preset.create(20260912, 64))
	elif phase in ["resume", "reject"]:
		if not args.has("--path") or not args.has("--sha"):
			_finish(args, {"success": false, "error": "A11_RESTART_REQUIRED_RECEIPT"})
			return
		result = session.load_file(String(args["--path"]), String(args["--sha"]))
		if phase == "reject":
			_finish(args, {"success": not bool(result.get("success", false)) and session.controller == null,
				"rejected": not bool(result.get("success", false)), "error": result.get("error", "")})
			return
	else:
		_finish(args, {"success": false, "error": "A11_RESTART_UNKNOWN_PHASE"})
		return
	if not bool(result.get("success", false)):
		_finish(args, result)
		return
	var target := 8 if phase == "checkpoint" else 24
	result = session.controller.run_to_tick(target)
	if not bool(result.get("success", false)):
		_finish(args, result)
		return
	if phase == "checkpoint":
		if not args.has("--directory"):
			_finish(args, {"success": false, "error": "A11_RESTART_REQUIRED_DIRECTORY"})
			return
		result = session.save(String(args["--directory"]))
	else:
		var snapshot: Dictionary = session.controller.get_snapshot()
		result = {"success": true, "tick": snapshot.tick, "state_hash": snapshot.canonical_state_hash,
			"field_hash": snapshot.field_hash, "population": snapshot.population,
			"presentation": snapshot.presentation, "metrics": session.controller.get_metrics()}
	_finish(args, result)

func _finish(args: Dictionary, result: Dictionary) -> void:
	result["pid"] = OS.get_process_id()
	result["phase"] = String(args["--phase"])
	var file := FileAccess.open(String(args["--result"]), FileAccess.WRITE)
	if file == null:
		push_error("A11_RESTART_RESULT_WRITE")
		quit(1)
		return
	file.store_string(JSON.stringify(result))
	file.flush()
	var error := file.get_error()
	file.close()
	var success := bool(result.get("success", false)) and error == OK
	print("EVO_ARCH2_A11_RESTART_WORKER " + String(result.phase) + " " + ("PASS" if success else "FAIL"))
	quit(0 if success else 1)

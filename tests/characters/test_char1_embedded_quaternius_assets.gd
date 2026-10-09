extends SceneTree

# Strict bundle gate: a real, installed Quaternius rig and animation library
# must be in the project. Safe procedural fallback is deliberately a failure.
const Bootstrap = preload("res://scripts/characters/runtime/production_avatar_bootstrap.gd")
const Host = preload("res://scripts/characters/avatar/player_avatar_host.gd")
const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var runtime: Dictionary = Bootstrap.create_runtime()
	_check(bool(runtime.get("success", false)), "avatar bootstrap must succeed")
	if not bool(runtime.get("success", false)):
		_finish(null)
		return
	var host := Host.new()
	get_root().add_child(host)
	var data: Dictionary = runtime.get("details", {})
	var setup_result: Dictionary = host.setup(
		data.get("catalog"), data.get("providers"),
		"character/quaternius/regular", true
	)
	_check(bool(setup_result.get("success", false)), "real avatar host setup")
	if not bool(setup_result.get("success", false)):
		_finish(host)
		return
	_check(
		host.get_active_character_id() == "character/quaternius/regular",
		"exact Quaternius character selected"
	)
	var report: Dictionary = host.create_report()
	var presenter: Dictionary = report.get("presenter", {})
	var engine: Dictionary = presenter.get("engine", {})
	var mode := String(engine.get("asset_mode", ""))
	_check(mode in ["QUATERNIUS_RETARGET", "QUATERNIUS_EMBEDDED"],
		"real rig + animations required; mode was %s" % mode)
	_check(String(presenter.get("provider_id", "")) == "avatar/quaternius",
		"provider interface selected Quaternius")
	_check(bool(engine.get("target_skeleton", false)), "real skeleton loaded")
	_check(bool(engine.get("animation_ready", false)), "semantic animations resolved")
	_check(not bool(engine.get("root_motion_applied", true)), "no visual root-motion ownership")
	var model_path := String(engine.get("model_path", ""))
	_check(
		model_path.to_lower().contains("superhero_male_fullbody")
		and model_path.begins_with("res://assets/external/quaternius/"),
		"the tested Superhero Male FullBody glTF is packaged: %s" % model_path
	)
	_check(ResourceLoader.exists(model_path), "real model path exists")
	if mode == "QUATERNIUS_RETARGET":
		_check(int(engine.get("matched_bones", 0)) >= 50,
			"retarget maps at least 50 real bones")
		_check(String(engine.get("animation_path", "")).to_lower().contains("ual1_standard"),
			"UAL1_Standard real animation library selected")

	var states: Array[Dictionary] = [
		{"semantic": "idle", "speed": 0.0},
		{"semantic": "walk", "speed": 2.0},
		{"semantic": "run", "speed": 6.0},
	]
	for index in range(states.size()):
		var item: Dictionary = states[index]
		var motion := {
			"schema": Contract.MOTION_SCHEMA,
			"velocity": {"x": 0.0, "y": 0.0, "z": float(item["speed"])},
			"grounded": true,
			"facing_yaw": 0.0,
			"state_revision": index + 1,
		}
		var applied: Dictionary = host.apply_motion_state(motion)
		_check(bool(applied.get("success", false)),
			"%s motion accepted" % item["semantic"])
		engine = host.create_report().get("presenter", {}).get("engine", {})
		_check(String(engine.get("current_semantic", "")) == String(item["semantic"]),
			"%s uses real animation semantic" % item["semantic"])
		_check(not String(engine.get("current_animation", "")).is_empty(),
			"%s uses real animation clip" % item["semantic"])
		_check(String(engine.get("asset_mode", "")) == mode,
			"%s cannot turn into fallback" % item["semantic"])
	_finish(host)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish(host) -> void:
	if host != null:
		host.shutdown()
		host.queue_free()
	if failures.is_empty():
		print("CHAR1 EMBEDDED REAL AVATAR: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("[CHAR1 embedded] %s" % failure)
	print("CHAR1 EMBEDDED REAL AVATAR: FAIL (%d assertions, %d failures)" % [
		assertions, failures.size()
	])
	quit(1)

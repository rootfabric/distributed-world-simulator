extends SceneTree

const ProfileLoaderScript = preload(
	"res://scripts/actors/controllers/controller_profile_loader.gd"
)

const PROFILE_PATHS := [
	"res://config/controllers/lunar_humanoid.json",
	"res://config/controllers/lunar_jetpack.json",
	"res://config/controllers/earth_humanoid.json",
]

var failures: Array[String] = []


func _init() -> void:
	var profile_ids: Dictionary = {}
	for path in PROFILE_PATHS:
		var profile: Dictionary = ProfileLoaderScript.load_profile(path)
		_assert(not profile.is_empty(), "Profile could not be loaded: %s" % path)
		if profile.is_empty():
			continue
		var profile_id: String = String(profile.get("profile_id", ""))
		_assert(not profile_ids.has(profile_id), "Duplicate profile_id: %s" % profile_id)
		profile_ids[profile_id] = true
		_assert(profile.get("movement", {}) is Dictionary, "Movement config missing: %s" % path)
		_assert(profile.get("camera", {}) is Dictionary, "Camera config missing: %s" % path)
		_assert(profile.get("capabilities", []) is Array, "Capabilities missing: %s" % path)
		var script_path: String = String(profile.get("controller_script", ""))
		_assert(ResourceLoader.exists(script_path), "Controller script missing: %s" % script_path)
		var controller_script = load(script_path)
		_assert(controller_script != null, "Controller script failed to load: %s" % script_path)
		if controller_script != null:
			var controller = controller_script.new()
			_assert(controller.has_method("setup"), "Controller setup contract missing: %s" % profile_id)
			_assert(controller.has_method("physics_step"), "Controller physics contract missing: %s" % profile_id)
			_assert(controller.has_method("handle_input"), "Controller input contract missing: %s" % profile_id)
			controller.free()

	_assert(profile_ids.has("lunar_humanoid"), "lunar_humanoid profile is missing.")
	_assert(profile_ids.has("lunar_jetpack"), "lunar_jetpack profile is missing.")
	_assert(profile_ids.has("earth_humanoid"), "earth_humanoid template is missing.")

	if failures.is_empty():
		print("Controller profile integration tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Controller profile integration tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

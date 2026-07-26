extends SceneTree

const ProfileLoaderScript = preload(
	"res://scripts/actors/controllers/controller_profile_loader.gd"
)

const PROFILES := {
	"lunar_humanoid": "res://config/controllers/lunar_humanoid.json",
	"lunar_jetpack": "res://config/controllers/lunar_jetpack.json",
	"earth_humanoid": "res://config/controllers/earth_humanoid.json",
	"flat_humanoid": "res://config/controllers/flat_humanoid.json",
}

var failures: Array[String] = []


func _init() -> void:
	for expected_id in PROFILES.keys():
		var path: String = String(PROFILES[expected_id])
		var profile: Dictionary = ProfileLoaderScript.load_profile(path)
		_assert(not profile.is_empty(), "Controller profile failed to load: %s" % path)
		_assert(
			String(profile.get("profile_id", "")) == String(expected_id),
			"Unexpected profile_id in %s" % path
		)
		_assert(
			String(profile.get("schema", ""))
			== "planet_simulator.controller_profile.v1",
			"Built-in profile still uses a legacy schema: %s" % path
		)

	var legacy_profile := {
		"schema": "lunar.controller_profile.v1",
		"profile_id": "legacy_test",
		"controller_script": "res://scripts/actors/controllers/flat_humanoid_controller.gd",
		"movement": {},
		"camera": {},
		"capabilities": [],
	}
	_assert(
		ProfileLoaderScript.validate_profile(legacy_profile).is_empty(),
		"Legacy controller profile compatibility was broken."
	)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("Controller profile tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Controller profile tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

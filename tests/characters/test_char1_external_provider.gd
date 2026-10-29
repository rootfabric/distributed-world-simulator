extends SceneTree

# Demonstrates a provider unknown to production code, loaded via manifest only.
const Bootstrap = preload("res://scripts/characters/runtime/production_avatar_bootstrap.gd")
const Host = preload("res://scripts/characters/avatar/player_avatar_host.gd")
const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var catalog_value = JSON.parse_string(FileAccess.get_file_as_string(Bootstrap.CATALOG_PATH))
	var manifest_value = JSON.parse_string(FileAccess.get_file_as_string(Bootstrap.PROVIDER_MANIFEST_PATH))
	_check(catalog_value is Dictionary, "source catalog readable")
	_check(manifest_value is Dictionary, "source manifest readable")
	if not catalog_value is Dictionary or not manifest_value is Dictionary:
		_finish(null)
		return
	var catalog: Dictionary = Dictionary(catalog_value).duplicate(true)
	var manifest: Dictionary = Dictionary(manifest_value).duplicate(true)
	var extra: Dictionary = Dictionary(catalog.get("characters", [])[1]).duplicate(true)
	extra["character_id"] = "character/external/test"
	extra["display_name"] = "External Test Avatar"
	extra["provider_id"] = "avatar/external_test"
	extra["default_appearance"] = {
		"appearance_id": "appearance/external/test",
		"appearance_revision": 1,
		"parameters": {},
	}
	var catalog_entries: Array = catalog.get("characters", [])
	catalog_entries.append(extra)
	catalog["characters"] = catalog_entries
	var descriptors: Array = manifest.get("providers", [])
	descriptors.append({
		"provider_id": "avatar/external_test",
		"factory_script": "res://tests/characters/support/mock_avatar_provider.gd",
	})
	manifest["providers"] = descriptors
	var catalog_path := "user://char1-external-provider-catalog.json"
	var manifest_path := "user://char1-external-provider-manifest.json"
	_write(catalog_path, catalog)
	_write(manifest_path, manifest)
	var built: Dictionary = Bootstrap.create_runtime(catalog_path, manifest_path)
	_check(bool(built.get("success", false)), "external provider bootstrap succeeds")
	if not bool(built.get("success", false)):
		_finish(null)
		return
	var host := Host.new()
	get_root().add_child(host)
	var details: Dictionary = built.get("details", {})
	var setup: Dictionary = host.setup(details.get("catalog"), details.get("providers"), "character/external/test", true)
	_check(bool(setup.get("success", false)), "external character instantiates")
	if not bool(setup.get("success", false)):
		_finish(host)
		return
	host.set_first_person_mode(true)
	var motion := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {"x": 3.1, "y": 0.0, "z": 0.0},
		"grounded": true,
		"facing_yaw": 0.6,
		"state_revision": 5,
	}
	var action := {
		"schema": Contract.ACTION_SCHEMA,
		"action_id": "action/use",
		"action_sequence": 9,
		"active": true,
	}
	_check(bool(host.apply_motion_state(motion).get("success", false)), "external accepts motion")
	_check(bool(host.apply_action_state(action).get("success", false)), "external accepts action")
	_check(host.get_socket(&"hand_right") != null, "external exposes socket")
	_check(bool(host.create_report().get("presenter", {}).get("external_provider", false)), "external presenter active")
	var builtin: Dictionary = host.switch_avatar("character/procedural/standard")
	_check(bool(builtin.get("success", false)), "switch external to built-in")
	var back: Dictionary = host.switch_avatar("character/external/test")
	_check(bool(back.get("success", false)), "switch built-in to external")
	var report: Dictionary = host.create_report()
	_check(bool(report.get("first_person_mode", false)), "first-person mode survives")
	_check(bool(report.get("presenter", {}).get("has_motion_state", false)), "motion survives")
	_check(bool(report.get("presenter", {}).get("has_action_state", false)), "action survives")
	var unknown: Dictionary = host.switch_avatar("character/does-not-exist")
	_check(not bool(unknown.get("success", false)), "unknown avatar rejected")
	_check(host.get_active_character_id() == "character/external/test", "failed swap retains active avatar")
	_finish(host)

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()

func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)

func _finish(host) -> void:
	if host != null:
		host.shutdown()
		host.queue_free()
	if failures.is_empty():
		print("CHAR1 EXTERNAL PROVIDER: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("[CHAR1 external] " + failure)
		print("CHAR1 EXTERNAL PROVIDER: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)

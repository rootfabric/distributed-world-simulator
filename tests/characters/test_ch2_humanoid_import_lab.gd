extends SceneTree

const CatalogLoader = preload("res://scripts/characters/registry/character_catalog_loader.gd")
const Validator = preload("res://scripts/characters/importing/humanoid_import_validator.gd")

var assertions := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("CH2 ASSERTION FAILED: %s" % message)

func _run() -> void:
	var loader := CatalogLoader.new()
	var loaded: Dictionary = loader.load_registry("res://config/characters/procedural-humanoid-catalog.v1.json")
	_check(bool(loaded.get("success", false)), "catalog loads")
	if not bool(loaded.get("success", false)):
		quit(1)
		return
	var registry = loaded.details.registry
	var report: Dictionary = registry.create_report()
	_check(int(report.get("definition_count", 0)) == 3, "three definitions")
	_check(String(report.get("fallback_character_id", "")) == "human/procedural/standard", "fallback id")
	_check(registry.has_definition(&"human/procedural/standard"), "standard definition")
	_check(registry.has_definition(&"human/procedural/slim"), "slim definition")
	_check(registry.has_definition(&"human/test_dummy"), "dummy definition")
	_check(registry.get_definition(&"missing").character_id == "human/procedural/standard", "catalog fallback")
	var validator := Validator.new()
	var validation_parent := Node3D.new()
	validation_parent.name = "ImportValidationParent"
	get_root().add_child(validation_parent)
	for character_id in registry.get_character_ids():
		var definition = registry.get_definition(character_id)
		var result: Dictionary = validator.validate_definition(definition, validation_parent)
		_check(bool(result.get("success", false)), "%s validates" % character_id)
		_check(int(result.get("details", {}).get("bone_count", 0)) == 12, "%s bone count" % character_id)
		_check(int(result.get("details", {}).get("animation_count", 0)) >= 11, "%s animation count" % character_id)
		_check(int(result.get("details", {}).get("socket_count", 0)) == 7, "%s socket count" % character_id)
		_check(definition.body_profile.body_profile_id == "body/human_standard", "%s shared body profile" % character_id)
		_check(definition.animation_profile.resolve(&"action/pickup") == &"pickup", "%s action semantic" % character_id)
		_check(definition.socket_profile.resolve_path(&"flashlight") == NodePath("VisualRoot/Sockets/HandRight"), "%s flashlight socket" % character_id)
	await process_frame
	var packed = load("res://scenes/labs/character/procedural_humanoid.tscn")
	_check(packed is PackedScene, "procedural scene loads")
	var instance = (packed as PackedScene).instantiate()
	validation_parent.add_child(instance)
	instance.build_now()
	var humanoid_report: Dictionary = instance.create_report()
	_check(bool(humanoid_report.get("built", false)), "procedural humanoid built")
	_check(int(humanoid_report.get("bone_count", 0)) == 12, "procedural bone count")
	_check(Array(humanoid_report.get("animations", [])).has("walk"), "walk animation")
	_check(Array(humanoid_report.get("animations", [])).has("run"), "run animation")
	_check(Array(humanoid_report.get("animations", [])).has("pickup"), "pickup animation")
	_check(instance.get_socket(&"HandRight") != null, "direct socket access")
	_check(instance.get_animation_player().is_playing(), "idle starts automatically")
	instance.apply_appearance({"body_color":[1.0,0.0,0.0,1.0]})
	_check(instance.get_node_or_null("VisualRoot/Torso/Mesh") != null, "body mesh remains after appearance")
	instance.queue_free()
	validation_parent.queue_free()
	await process_frame
	print("CH2 PASS: %d assertions" % assertions if failures == 0 else "CH2 FAIL: %d/%d" % [failures, assertions])
	quit(0 if failures == 0 else 1)

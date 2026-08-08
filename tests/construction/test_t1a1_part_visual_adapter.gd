extends SceneTree
const FixtureBuilder = preload("res://scripts/labs/t1/t1_complex_construct_fixture_builder.gd")
const CatalogScript = preload("res://scripts/labs/t1/presentation/t1_part_visual_catalog.gd")
const Adapter = preload("res://scripts/labs/t1/presentation/t1_part_visual_adapter.gd")
const VisualProfile = preload("res://scripts/labs/t1/presentation/t1_part_visual_profile.gd")
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var catalog = CatalogScript.new()
	var loaded: Dictionary = catalog.load_catalog()
	_ok(loaded, "catalog loads")
	_assert(int(loaded.get("profile_count", 0)) == 4, "four representation classes are catalogued")
	_assert(String(loaded.get("manifest_hash", "")).length() == 64, "catalog manifest hash is sha256")
	for semantic_class in VisualProfile.REPRESENTATION_CLASSES:
		var resolved: Dictionary = catalog.resolve_semantic(semantic_class)
		_ok(resolved, "%s binding resolves" % semantic_class)
		if bool(resolved.get("success", false)):
			_assert(String(resolved["profile"]["representation_class"]) == semantic_class, "%s representation class preserved" % semantic_class)
	for fixture_id in ["D0", "D1"]:
		var fixture_result: Dictionary = FixtureBuilder.build_profile(fixture_id)
		_ok(fixture_result, "%s fixture builds" % fixture_id)
		if not bool(fixture_result.get("success", false)): continue
		var fixture: Dictionary = fixture_result["fixture"]
		var before := String(fixture["fixture_checksum"])
		for mode in ["NEAR", "MID", "FAR"]:
			var plan_result: Dictionary = Adapter.build_fixture_plan(fixture, catalog, mode)
			_ok(plan_result, "%s %s presentation plan builds" % [fixture_id, mode])
			if not bool(plan_result.get("success", false)): continue
			var plan: Dictionary = plan_result["plan"]
			_assert(int(plan["part_count"]) == int(fixture["part_count"]), "%s %s plan preserves part count" % [fixture_id, mode])
			_assert(String(plan["fixture_checksum"]) == before, "%s %s plan references canonical fixture checksum" % [fixture_id, mode])
			_assert(String(fixture["fixture_checksum"]) == before, "%s %s visual adaptation does not mutate fixture checksum" % [fixture_id, mode])
			_assert(String(plan["checksum"]) == Adapter.compute_plan_checksum(plan), "%s %s plan checksum validates" % [fixture_id, mode])
			_assert(String(plan["parts"][0]["part_id"]) == String(fixture["part_ids"][0]), "%s %s first identity preserved" % [fixture_id, mode])
			_assert(String(plan["parts"][-1]["part_id"]) == String(fixture["part_ids"][-1]), "%s %s last identity preserved" % [fixture_id, mode])
	var d0: Dictionary = FixtureBuilder.build_profile("D0")["fixture"]
	var near_plan: Dictionary = Adapter.build_fixture_plan(d0, catalog, "NEAR")["plan"]
	var far_plan: Dictionary = Adapter.build_fixture_plan(d0, catalog, "FAR")["plan"]
	_assert(String(near_plan["checksum"]) != String(far_plan["checksum"]), "detail mode changes presentation checksum")
	_assert(String(near_plan["fixture_checksum"]) == String(far_plan["fixture_checksum"]), "detail mode cannot change canonical fixture checksum")
	var classes := {}
	for part in near_plan["parts"]: classes[String(part["representation_class"])] = int(classes.get(String(part["representation_class"]), 0)) + 1
	_assert(int(classes.get("STRUCTURAL_CELL",0)) == 40, "D0 structural routing count")
	_assert(int(classes.get("STATIC_COMPLEX_MESH",0)) == 8, "D0 static-complex routing count")
	_assert(int(classes.get("INSTANCED_MESH",0)) == 8, "D0 instanced routing count")
	_assert(int(classes.get("INTERACTIVE_FIXTURE",0)) == 8, "D0 interactive routing count")
	var invalid_mode := Adapter.build_fixture_plan(d0, catalog, "ULTRA")
	_assert(not bool(invalid_mode.get("success", false)), "unknown detail mode rejected")
	_test_demo_scene_adapter()
	_finish()

func _test_demo_scene_adapter() -> void:
	var packed = load("res://scenes/labs/t1_complex_construct_demo.tscn")
	_assert(packed is PackedScene, "T1 demo scene loads with T1A.1 adapter")
	if not (packed is PackedScene): return
	var instance = packed.instantiate()
	_assert(instance.has_method("build_presentation_plan"), "demo scene exposes presentation-plan boundary")
	var result: Dictionary = instance.call("build_presentation_plan", "D0", "MID")
	_ok(result, "demo scene builds MID presentation plan")
	if bool(result.get("success", false)):
		_assert(int(result["plan"]["part_count"]) == 64, "demo scene keeps D0 part count")
		_assert(String(result["plan"]["fixture_checksum"]) == String(FixtureBuilder.build_profile("D0")["fixture"]["fixture_checksum"]), "demo scene presentation keeps fixture checksum")
	instance.free()
func _ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])
func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _finish() -> void:
	if failures.is_empty():
		print("T1A.1 part visual adapter: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("T1A.1 part visual adapter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)

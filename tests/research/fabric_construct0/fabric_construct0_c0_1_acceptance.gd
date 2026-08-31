extends SceneTree

const Factory = preload("res://scripts/labs/fabric_construct0/construct0_preset_factory.gd")

var _assertions := 0
var _failures: Array[String] = []

func _init() -> void:
	_check(Factory.PRESETS == ["TABLE", "BRIDGE", "CART", "PLANK"], "preset order")
	for preset in Factory.PRESETS:
		var built := Factory.build(preset)
		_check(bool(built.get("success", false)), "%s builds" % preset)
		if not bool(built.get("success", false)):
			continue
		var snapshot: Dictionary = built["snapshot"]
		var descriptor: Dictionary = built["runtime_descriptor"]
		var model: Dictionary = built["contact_model"]
		var slide: Dictionary = built["maximum_dissipation"]
		var guard: Dictionary = built["support_guard"]
		_check(Array(snapshot["parts"]).size() >= 3, "%s compound part count" % preset)
		_check(Array(snapshot["bonds"]).size() == Array(snapshot["parts"]).size() - 1, "%s connected bond count" % preset)
		_check(Array(descriptor["part_descriptors"]).size() == Array(snapshot["parts"]).size(), "%s runtime projection count" % preset)
		_check(int(model["full_member_count"]) == Factory.CONTACT_GRID * Factory.CONTACT_GRID, "%s full contact count" % preset)
		_check(int(model["generator_count"]) == 4, "%s convex support generators" % preset)
		_check(float(model["reduction_ratio"]) > 100.0, "%s meaningful contact reduction" % preset)
		_check(bool(built["reverse_model_hash_equal"]), "%s reverse contact input deterministic" % preset)
		_check(String(model["source_frontier_hash"]) == String(snapshot["checksum"]), "%s model bound to canonical snapshot" % preset)
		_check(not bool(model["warm_start_persisted"]), "%s warm start not persisted" % preset)
		_check(not bool(model["contact_age_persisted"]), "%s contact age not persisted" % preset)
		_check(float(slide["contact_power"]) <= 1.0e-10, "%s passive maximum dissipation" % preset)
		_check(bool(guard["persistent_contact_feasible"]), "%s support guard feasible" % preset)

	var unsupported := Factory.unsupported_non_coplanar_probe("TABLE")
	_check(not bool(unsupported.get("ok", true)), "non-coplanar probe rejected")
	_check(String(unsupported.get("status", "")) == "NO_SAFE_BAKE", "non-coplanar returns NO_SAFE_BAKE")
	_check(String(unsupported.get("reason", "")) == "NON_COPLANAR_CONTACT_PATCH", "non-coplanar reason explicit")

	var packed = load("res://scenes/labs/fabric_construct0_lab.tscn")
	_check(packed is PackedScene, "C0.1 scene parses")
	if packed is PackedScene:
		var instance = packed.instantiate()
		_check(instance is Node3D, "C0.1 scene instantiates")
		instance.free()

	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 C0.1 Acceptance: PASS (%d assertions)" % _assertions)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 C0.1: %s" % failure)
	print("FABRIC CONSTRUCT0 C0.1 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _assertions])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)

extends SceneTree

## WF0.1 Environmental Dressing Contract tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_1_dressing_contract.gd

const DressingScript = preload("res://scripts/world_fill/dressing/world_fill_dressing.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_determinism_same_inputs_same_outputs()
	_test_seed_changes_decision_key()
	_test_input_descriptor_not_mutated()
	_test_output_not_aliased_to_input()
	_test_missing_fields_degrade_gracefully()
	_test_surface_family_mapping()
	_test_steep_slope_demotes_except_boulders()
	_test_moisture_suppresses_dry_branches()
	_test_ground_cover_promotes_stones()
	_test_ambience_and_decal_selection()
	_test_poi_eligibility_hints()
	_finish()


func _make_descriptor(seed_value: int) -> Dictionary:
	return {
		"surface_type": "regolith",
		"position": Vector3(12.5, 3.25, -7.75),
		"normal": Vector3(0.0, 1.0, 0.0),
		"altitude": 3.25,
		"moisture": 0.05,
		"temperature_c": -18.0,
		"ground_cover": "none",
		"biome_tags": ["open_plain", "crater_rim"],
		"seed": seed_value,
	}


func _family_band(output: Dictionary, family: String) -> String:
	for entry in output.get("prop_families", []):
		if String(entry.get("family", "")) == family:
			return String(entry.get("density_band", ""))
	return ""


func _test_determinism_same_inputs_same_outputs() -> void:
	var first := DressingScript.derive(_make_descriptor(7))
	var second := DressingScript.derive(_make_descriptor(7))
	_assert(_deep_equal(first, second), "Same inputs+seed produced different outputs.")
	_assert(String(first.get("schema", "")) == DressingScript.SCHEMA, "Output schema missing.")


func _test_seed_changes_decision_key() -> void:
	var first := DressingScript.derive(_make_descriptor(1))
	var second := DressingScript.derive(_make_descriptor(2))
	_assert(
		String(first.get("determinism_key", "")) != String(second.get("determinism_key", "")),
		"Different seeds produced identical determinism_key."
	)


func _test_input_descriptor_not_mutated() -> void:
	var descriptor := _make_descriptor(9)
	var snapshot := descriptor.duplicate(true)
	DressingScript.derive(descriptor)
	_assert(_deep_equal(descriptor, snapshot), "Derive mutated the input descriptor.")


func _test_output_not_aliased_to_input() -> void:
	var descriptor := _make_descriptor(11)
	var snapshot := descriptor.duplicate(true)
	var output := DressingScript.derive(descriptor)
	(output["prop_families"] as Array).append({"family": "corruption"})
	(output["decal_families"] as Array).append("corruption")
	_assert(_deep_equal(descriptor, snapshot), "Output shares mutable state with input descriptor.")


func _test_missing_fields_degrade_gracefully() -> void:
	var output := DressingScript.derive({})
	_assert(not (output.get("prop_families", []) as Array).is_empty(), "Empty descriptor produced no prop families.")
	_assert(String(output.get("ambience_selector", "")) != "", "Empty descriptor produced no ambience selector.")
	var degraded := output.get("degraded_inputs", []) as Array
	_assert(degraded.has("surface_type"), "Missing surface_type was not reported as degraded.")
	_assert(degraded.has("moisture"), "Missing moisture was not reported as degraded.")
	_assert(String(_family_band(output, "stones")) == "sparse", "Unknown surface did not fall back to sparse stones.")


func _test_surface_family_mapping() -> void:
	var metal := _make_descriptor(3)
	metal["surface_type"] = "metal"
	var metal_output := DressingScript.derive(metal)
	_assert(String(_family_band(metal_output, "industrial_scrap")) == "dense", "Metal surface did not map to dense industrial scrap.")

	var ice := _make_descriptor(4)
	ice["surface_type"] = "ice"
	var ice_output := DressingScript.derive(ice)
	_assert(not String(_family_band(ice_output, "crystals")).is_empty(), "Ice surface did not map to crystals.")


func _test_steep_slope_demotes_except_boulders() -> void:
	var steep := _make_descriptor(5)
	steep.erase("normal")
	steep["slope_deg"] = 60.0
	steep["surface_type"] = "rock"
	var output := DressingScript.derive(steep)
	_assert(String(_family_band(output, "boulders")) == "moderate", "Boulders lost their band on steep slope.")
	_assert(String(_family_band(output, "stones")) == "", "Stones were not demoted to none on steep slope.")


func _test_moisture_suppresses_dry_branches() -> void:
	var wet := _make_descriptor(6)
	wet["surface_type"] = "soil"
	wet["moisture"] = 0.9
	var wet_output := DressingScript.derive(wet)
	_assert(String(_family_band(wet_output, "dry_branches")) == "", "Wet soil still produced dry branches.")

	var dry := _make_descriptor(6)
	dry["surface_type"] = "soil"
	dry["moisture"] = 0.05
	var dry_output := DressingScript.derive(dry)
	_assert(String(_family_band(dry_output, "dry_branches")) == "moderate", "Dry soil did not raise dry branches to moderate.")


func _test_ground_cover_promotes_stones() -> void:
	var covered := _make_descriptor(8)
	covered["surface_type"] = "rock"
	covered["ground_cover"] = "lichen_patch"
	var output := DressingScript.derive(covered)
	_assert(String(_family_band(output, "stones")) == "moderate", "Ground cover did not promote stones to moderate.")


func _test_ambience_and_decal_selection() -> void:
	var base := DressingScript.derive(_make_descriptor(12))
	_assert(String(base.get("ambience_selector", "")) == "open_wind", "Open plain tag did not select open_wind ambience.")
	_assert((base.get("decal_families", []) as Array).has("surface_wear"), "Base decal surface_wear missing.")
	_assert((base.get("decal_families", []) as Array).has("impact_dust"), "Regolith decal impact_dust missing.")

	var wrecked := _make_descriptor(13)
	wrecked["biome_tags"] = ["wreckage"]
	var wrecked_output := DressingScript.derive(wrecked)
	_assert((wrecked_output.get("decal_families", []) as Array).count("impact_dust") == 1, "Wreckage decal dedup failed.")

	var cave := _make_descriptor(14)
	cave["biome_tags"] = ["cave"]
	var cave_output := DressingScript.derive(cave)
	_assert(String(cave_output.get("ambience_selector", "")) == "underground_echo", "Cave tag did not select underground_echo.")

	var high := _make_descriptor(15)
	high["altitude"] = 1200.0
	high["biome_tags"] = [] as Array[String]
	var high_output := DressingScript.derive(high)
	_assert(String(high_output.get("ambience_selector", "")) == "thin_air_loop", "High altitude did not select thin_air_loop.")


func _test_poi_eligibility_hints() -> void:
	var flat := DressingScript.derive(_make_descriptor(16))
	var poi := flat.get("poi_eligibility", {}) as Dictionary
	_assert(bool(poi.get("outpost", true)) == true, "Flat regolith rejected outpost eligibility.")
	_assert(bool(poi.get("cave_entrance", false)) == false, "Flat ground allowed cave_entrance eligibility.")
	_assert(bool(poi.get("beacon", false)) == true, "Beacon eligibility must always exist.")


func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			var dict_a: Dictionary = a
			var dict_b: Dictionary = b
			if dict_a.size() != dict_b.size():
				return false
			for key in dict_a:
				if not dict_b.has(key) or not _deep_equal(dict_a[key], dict_b[key]):
					return false
			return true
		TYPE_ARRAY:
			var array_a: Array = a
			var array_b: Array = b
			if array_a.size() != array_b.size():
				return false
			for index in array_a.size():
				if not _deep_equal(array_a[index], array_b[index]):
					return false
			return true
		_:
			return a == b


func _finish() -> void:
	if failures.is_empty():
		print("WF0.1 dressing contract tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.1 dressing contract tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

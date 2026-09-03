extends SceneTree

## WF0.4 Ambient World Clock / Atmosphere tests.
## Run: godot --headless --path <project> --script res://tests/world_fill/test_wf0_4_atmosphere.gd

const AtmosphereScript = preload("res://scripts/world_fill/ambience/world_fill_atmosphere.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_all_presets_apply()
	_test_clock_mapping_deterministic()
	_test_clock_derived_set_is_closed()
	_test_explicit_override_and_return()
	_test_fail_soft_unknown_preset_and_empty_clock()
	_test_report_is_presentation_only()
	_finish()


func _test_all_presets_apply() -> void:
	var atmosphere := AtmosphereScript.new()
	for preset_name in ["clear", "dust", "storm", "dawn", "night"]:
		var report: Dictionary = atmosphere.apply_preset(preset_name)
		_assert(
			String(report.get("preset", "")) == preset_name,
			"Preset %s did not apply." % preset_name
		)
		_assert(float(report.get("sun_energy", -1.0)) > 0.0, "Preset %s lost sun energy." % preset_name)
	var env_nodes := 0
	var sun_nodes := 0
	for child in atmosphere.get_children():
		if child is WorldEnvironment:
			env_nodes += 1
		if child is DirectionalLight3D:
			sun_nodes += 1
	_assert(env_nodes == 1, "Atmosphere must own exactly one WorldEnvironment.")
	_assert(sun_nodes == 1, "Atmosphere must own exactly one DirectionalLight3D.")
	atmosphere.free()


func _test_clock_mapping_deterministic() -> void:
	var expectations := {
		0.0: "night",
		0.1: "night",
		0.2: "dawn",
		0.25: "dawn",
		0.3: "clear",
		0.5: "clear",
		0.84: "clear",
		0.85: "night",
		0.99: "night",
		1.0: "night",
	}
	var atmosphere := AtmosphereScript.new()
	for day_fraction in expectations:
		var first: Dictionary = atmosphere.apply_clock({"day_fraction": day_fraction})
		var second: Dictionary = atmosphere.apply_clock({"day_fraction": day_fraction})
		_assert(_deep_equal(first, second), "Clock mapping is not deterministic at %s." % [day_fraction])
		_assert(
			String(first.get("preset", "")) == expectations[day_fraction],
			"day_fraction %s mapped to %s, expected %s." % [day_fraction, first.get("preset"), expectations[day_fraction]]
		)
	atmosphere.free()


func _test_clock_derived_set_is_closed() -> void:
	var atmosphere := AtmosphereScript.new()
	var derived := {}
	var fraction := 0.0
	while fraction <= 1.0:
		var report: Dictionary = atmosphere.apply_clock({"day_fraction": fraction})
		derived[String(report.get("preset", ""))] = true
		fraction += 0.01
	_assert(derived.size() <= AtmosphereScript.CLOCK_PRESETS.size(), "Clock derived more presets than the closed set.")
	for preset in derived:
		_assert(
			AtmosphereScript.CLOCK_PRESETS.has(preset),
			"Clock derived non-clock preset: %s" % preset
		)
	atmosphere.free()


func _test_explicit_override_and_return() -> void:
	var atmosphere := AtmosphereScript.new()
	var storm_report: Dictionary = atmosphere.apply_preset("storm")
	_assert(String(storm_report.get("preset", "")) == "storm", "Explicit storm preset did not apply.")
	var float_report: Dictionary = atmosphere.apply_preset("dust")
	_assert(String(float_report.get("preset", "")) == "dust", "Explicit dust preset did not apply.")
	var back_report: Dictionary = atmosphere.apply_clock({"day_fraction": 0.5})
	_assert(String(back_report.get("preset", "")) == "clear", "Clock did not retake control after explicit override.")
	atmosphere.free()


func _test_fail_soft_unknown_preset_and_empty_clock() -> void:
	var atmosphere := AtmosphereScript.new()
	var unknown_report: Dictionary = atmosphere.apply_preset("hurricane_of_bees")
	_assert(String(unknown_report.get("preset", "")) == "clear", "Unknown preset did not fall back to clear.")
	_assert(bool(unknown_report.get("fallback_used", false)), "Fallback was not reported.")
	var empty_report: Dictionary = atmosphere.apply_clock({})
	_assert(
		String(empty_report.get("preset", "")) == "clear",
		"Empty clock did not default to the mid-day clear preset."
	)
	_assert(not bool(empty_report.get("fallback_used", true)), "Default clock path must not flag fallback.")
	atmosphere.free()


func _test_report_is_presentation_only() -> void:
	var atmosphere := AtmosphereScript.new()
	var report: Dictionary = atmosphere.apply_preset("dawn")
	for key in report.keys():
		_assert(
			key in ["schema", "preset", "fallback_used", "presentation_only", "wind_audio", "sun_energy", "fog_density"],
			"Atmosphere report exposes unexpected key: %s" % String(key)
		)
	_assert(bool(report.get("presentation_only", false)), "Report must declare presentation_only.")
	_assert(String(report.get("schema", "")) == AtmosphereScript.SCHEMA, "Report schema missing.")
	atmosphere.free()


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
		print("WF0.4 atmosphere tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WF0.4 atmosphere tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

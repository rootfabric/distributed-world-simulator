extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Fixture = preload("res://tests/research/fabric1/fabric1_generalization_fixture_v1.gd")

var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	var width := 40
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--width="): width = int(arg.trim_prefix("--width="))
	_check([40, 56, 72].has(width), "width belongs to frozen scale ladder")
	var subject := Fixture.build(width)
	_check(not subject.is_empty(), "scale fixture constructs")
	if subject.is_empty(): _finish(width); return
	var t0 := Time.get_ticks_usec()
	var compiled := GenericCompiler.compile(subject["spec"])
	var compile_us := Time.get_ticks_usec() - t0
	_check(String(compiled.get("status", "")) == "BAKE_READY", "scale fixture auto-bakes")
	if String(compiled.get("status", "")) != "BAKE_READY": _finish(width); return
	var descriptor: Dictionary = compiled["compile_result"]["diagnostics"]["reduction"]
	var expected_full := 3 * width + 8
	_check(int(descriptor["full_equation_count"]) == expected_full, "full equation growth exact")
	_check(int(descriptor["reduced_equation_count"]) == 4, "boundary dimension stays constant")
	_check(float(descriptor["runtime_work_ratio"]) >= float(expected_full * expected_full) / 16.0 - 1.0e-9, "runtime work advantage follows equation reduction")
	var excitation: Array = subject["excitations"][0]
	var full := Reducer.evaluate_full(compiled["context"]["linear_system"], excitation, GenericCompiler.PIVOT_TOLERANCE)
	var reduced := Reducer.evaluate_reduced(descriptor, excitation)
	_check(bool(full.get("success", false)) and bool(reduced.get("success", false)), "scale full/reduced evaluation succeeds")
	if bool(full.get("success", false)) and bool(reduced.get("success", false)):
		_check(_max_delta(full["details"]["boundary_flow"], reduced["details"]["boundary_flow"]) <= 2.0e-8, "scale boundary parity")
		_check(absf(float(full["details"]["boundary_power"]) - float(reduced["details"]["boundary_power"])) <= 2.0e-8, "scale power parity")
	var deterministic := GenericCompiler.compile(subject["spec"])
	_check(String(deterministic.get("status", "")) == "BAKE_READY", "scale deterministic recompile succeeds")
	if String(deterministic.get("status", "")) == "BAKE_READY":
		_check(String(deterministic["compile_result"]["artifact"]["checksum"]) == String(compiled["compile_result"]["artifact"]["checksum"]), "scale artifact identity deterministic")
	var evidence := {
		"width": width,
		"full_equations": descriptor["full_equation_count"],
		"reduced_equations": descriptor["reduced_equation_count"],
		"work_ratio": descriptor["runtime_work_ratio"],
		"artifact_hash": compiled["compile_result"]["artifact"]["checksum"],
		"descriptor_hash": descriptor["checksum"],
	}
	print("FABRIC1_SCALE_EVIDENCE=", JSON.stringify(evidence, "", true))
	print("FABRIC1_SCALE_HASH=", Utils.canonical_hash(evidence))
	print("FABRIC1_SCALE_COMPILE_US_OBSERVED=", compile_us)
	_finish(width)

func _max_delta(a: Array, b: Array) -> float:
	if a.size() != b.size(): return INF
	var result := 0.0
	for index in range(a.size()): result = maxf(result, absf(float(a[index]) - float(b[index])))
	return result

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)

func _finish(width: int) -> void:
	if _failures.is_empty():
		print("FABRIC1 Scale %d: PASS (%d assertions)" % [width, _checks])
		quit(0); return
	for failure in _failures: push_error("FABRIC1 SCALE FAIL: " + failure)
	print("FABRIC1 Scale %d: FAIL (%d/%d)" % [width, _failures.size(), _checks])
	quit(1)

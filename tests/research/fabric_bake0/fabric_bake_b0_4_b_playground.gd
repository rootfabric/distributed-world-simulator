extends SceneTree

const CompilerA = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullValidation = preload("res://scripts/research/fabric_bake0/dynamic_rom_full_validation_reference_v1.gd")
const CompilerB = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const RomRuntime = preload("res://scripts/research/fabric_bake0/dynamic_rom_runtime_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build("ZERO")
	var full := CompilerA.compile(fixture["request"])
	assert(bool(full.get("success", false)))
	var reduced := CompilerB.compile(full["model"])
	assert(bool(reduced.get("success", false)))
	var descriptor: Dictionary = reduced["descriptor"]

	var full_prepared := FullValidation.prepare(full["model"], 0.005)
	var rom_initial := RomRuntime.initial_state(descriptor)
	assert(bool(full_prepared.get("success", false)))
	assert(bool(rom_initial.get("success", false)))

	var flows := Fixture.zero_flows(full["model"]["boundary_contract"])
	flows["port/electrical/000-left"] = 0.5
	var full_values: Array = FullValidation.zero_state(full_prepared)
	var rom_state: Dictionary = rom_initial["state"]
	var prepared := RomRuntime.prepare_step(descriptor, 0.005)
	var max_abs_error := 0.0
	for _index in range(400):
		var full_step := FullValidation.step(full_prepared, full_values, flows)
		var rom_step := RomRuntime.step_prepared(descriptor, rom_state, flows, 0.005, prepared)
		assert(bool(full_step.get("success", false)))
		assert(bool(rom_step.get("success", false)))
		full_values = full_step["values"]
		rom_state = rom_step["state"]
		for port_index in range(descriptor["port_ids"].size()):
			max_abs_error = maxf(
				max_abs_error,
				absf(float(full_step["boundary"][port_index]["effort"]) - float(rom_step["boundary"][port_index]["effort"]))
			)

	print("FABRIC-BAKE B0.4-B Playground: PASS descriptor=%s full=%d reduced=%d ratio=%.6f passivity=%s interpolation_abs=%s interpolation_rel=%s step_max_abs=%s execution_ready=%s" % [
		String(descriptor["descriptor_hash"]),
		int(descriptor["full_state_count"]),
		int(descriptor["reduced_state_count"]),
		float(descriptor["reduction_ratio"]),
		str(bool(descriptor["passivity_certificate"]["certified"])),
		String.num_scientific(float(descriptor["interpolation_certificate"]["max_abs_boundary_error"])),
		String.num_scientific(float(descriptor["interpolation_certificate"]["max_relative_boundary_error"])),
		String.num_scientific(max_abs_error),
		str(bool(reduced["artifact_binding"]["execution_ready"])),
	])
	quit(0)

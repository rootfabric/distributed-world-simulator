extends SceneTree

const FullCompiler = preload("res://scripts/research/fabric_bake0/dynamic_full_model_compiler_v1.gd")
const FullModel = preload("res://scripts/research/fabric_bake0/dynamic_full_model_descriptor_v1.gd")
const ROMCompiler = preload("res://scripts/research/fabric_bake0/dynamic_rom_compiler_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd")

func _init() -> void:
	var fixture := Fixture.build("ZERO")
	var full := FullCompiler.compile(fixture["request"])
	print("PROBE_FULL_SUCCESS=", bool(full.get("success", false)))
	print("PROBE_FULL_ERROR=", String(full.get("error_code", "")))
	if not bool(full.get("success", false)):
		quit(2)
	var validated := FullModel.validate(full["model"])
	print("PROBE_FULL_VALIDATE_SUCCESS=", bool(validated.get("success", false)))
	print("PROBE_FULL_VALIDATE_ERROR=", String(validated.get("error_code", "")))
	var reduced := ROMCompiler.compile(full["model"])
	print("PROBE_ROM_SUCCESS=", bool(reduced.get("success", false)))
	print("PROBE_ROM_ERROR=", String(reduced.get("error_code", "")))
	print("PROBE_ROM_DETAILS=", JSON.stringify(reduced.get("details", {}), "", true, true))
	quit(0 if bool(reduced.get("success", false)) else 3)

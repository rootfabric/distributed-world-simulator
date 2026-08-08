extends Node3D

const FixtureBuilder = preload("res://scripts/labs/t1/t1_complex_construct_fixture_builder.gd")

@export_enum("D0", "D1") var profile_id: String = "D0"

var fixture_descriptor: Dictionary = {}
var fixture_error: Dictionary = {}

func _ready() -> void:
	var result: Dictionary = build_fixture_descriptor()
	if bool(result.get("success", false)):
		fixture_descriptor = Dictionary(result["fixture"]).duplicate(true)
		fixture_error = {}
		set_meta("t1_fixture_profile_id", String(fixture_descriptor["profile_id"]))
		set_meta("t1_fixture_checksum", String(fixture_descriptor["fixture_checksum"]))
		set_meta("t1_fixture_part_count", int(fixture_descriptor["part_count"]))
	else:
		fixture_descriptor = {}
		fixture_error = result.duplicate(true)
		push_error("T1A.0 fixture initialization failed: %s" % result)

func build_fixture_descriptor(profile_override: String = "") -> Dictionary:
	var selected := profile_override if not profile_override.is_empty() else profile_id
	return FixtureBuilder.build_profile(selected)

func reset_fixture_preview() -> Dictionary:
	fixture_descriptor = {}
	fixture_error = {}
	var result: Dictionary = build_fixture_descriptor()
	if bool(result.get("success", false)):
		fixture_descriptor = Dictionary(result["fixture"]).duplicate(true)
	return result

func get_fixture_checksum() -> String:
	return String(fixture_descriptor.get("fixture_checksum", ""))

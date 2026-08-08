extends Node3D

const FixtureBuilder = preload("res://scripts/labs/t1/t1_complex_construct_fixture_builder.gd")
const VisualCatalog = preload("res://scripts/labs/t1/presentation/t1_part_visual_catalog.gd")
const VisualAdapter = preload("res://scripts/labs/t1/presentation/t1_part_visual_adapter.gd")

@export_enum("D0", "D1") var profile_id: String = "D0"
@export_enum("NEAR", "MID", "FAR") var detail_mode: String = "NEAR"

var fixture_descriptor: Dictionary = {}
var fixture_error: Dictionary = {}
var presentation_plan: Dictionary = {}
var presentation_error: Dictionary = {}

func _ready() -> void:
	var result: Dictionary = build_fixture_descriptor()
	if bool(result.get("success", false)):
		fixture_descriptor = Dictionary(result["fixture"]).duplicate(true)
		fixture_error = {}
		set_meta("t1_fixture_profile_id", String(fixture_descriptor["profile_id"]))
		set_meta("t1_fixture_checksum", String(fixture_descriptor["fixture_checksum"]))
		set_meta("t1_fixture_part_count", int(fixture_descriptor["part_count"]))
		var visual_result: Dictionary = build_presentation_plan("", detail_mode)
		if bool(visual_result.get("success", false)):
			presentation_plan = Dictionary(visual_result["plan"]).duplicate(true)
			presentation_error = {}
			set_meta("t1_visual_catalog_hash", String(presentation_plan["catalog_manifest_hash"]))
			set_meta("t1_presentation_checksum", String(presentation_plan["checksum"]))
			set_meta("t1_presentation_detail_mode", String(presentation_plan["detail_mode"]))
		else:
			presentation_plan = {}
			presentation_error = visual_result.duplicate(true)
			push_error("T1A.1 presentation initialization failed: %s" % visual_result)
	else:
		fixture_descriptor = {}
		fixture_error = result.duplicate(true)
		push_error("T1A.0 fixture initialization failed: %s" % result)

func build_fixture_descriptor(profile_override: String = "") -> Dictionary:
	var selected := profile_override if not profile_override.is_empty() else profile_id
	return FixtureBuilder.build_profile(selected)

func build_presentation_plan(profile_override: String = "", detail_override: String = "") -> Dictionary:
	var selected_profile := profile_override if not profile_override.is_empty() else profile_id
	var selected_detail := detail_override if not detail_override.is_empty() else detail_mode
	var fixture_result: Dictionary = FixtureBuilder.build_profile(selected_profile)
	if not bool(fixture_result.get("success", false)):
		return fixture_result
	var catalog = VisualCatalog.new()
	var catalog_result: Dictionary = catalog.load_catalog()
	if not bool(catalog_result.get("success", false)):
		return catalog_result
	return VisualAdapter.build_fixture_plan(Dictionary(fixture_result["fixture"]), catalog, selected_detail)

func reset_fixture_preview() -> Dictionary:
	fixture_descriptor = {}
	fixture_error = {}
	presentation_plan = {}
	presentation_error = {}
	var result: Dictionary = build_fixture_descriptor()
	if bool(result.get("success", false)):
		fixture_descriptor = Dictionary(result["fixture"]).duplicate(true)
		var visual_result: Dictionary = build_presentation_plan("", detail_mode)
		if bool(visual_result.get("success", false)):
			presentation_plan = Dictionary(visual_result["plan"]).duplicate(true)
		else:
			presentation_error = visual_result.duplicate(true)
	return result

func get_fixture_checksum() -> String:
	return String(fixture_descriptor.get("fixture_checksum", ""))

func get_presentation_checksum() -> String:
	return String(presentation_plan.get("checksum", ""))

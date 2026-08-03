extends RefCounted

const C3FixtureScript = preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const SnapshotBuilderScript = preload("res://scripts/construction/build/construction_stage_snapshot_builder.gd")
const ExtractorScript = preload("res://scripts/construction/composites/construction_composite_definition_extractor.gd")
const DefinitionScript = preload("res://scripts/construction/composites/construction_composite_definition.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ParameterScript = preload("res://scripts/construction/composites/composite_parameter_definition.gd")
const ExposedPortScript = preload("res://scripts/construction/composites/composite_exposed_port.gd")

const DEFINITION_ID: String = "composite-definition/furniture/reusable-table"
const CREATED_BY: String = "actor/c4-designer"


static func completed_source_snapshot() -> Dictionary:
	var result: Dictionary = SnapshotBuilderScript.build_for_stage(C3FixtureScript.build_plan(), 2)
	assert(bool(result.get("success", false)))
	return result["snapshot"]


static func extracted_definition() -> Dictionary:
	var result: Dictionary = ExtractorScript.extract_from_completed_build(
		DEFINITION_ID,
		1,
		"Reusable work table",
		"Reusable table",
		completed_source_snapshot(),
		C3FixtureScript.build_plan(),
		CREATED_BY
	)
	assert(bool(result.get("success", false)))
	return result["definition"]


static func definition() -> Dictionary:
	var value: Dictionary = extracted_definition().duplicate(true)
	for slot in value["part_slots"]:
		if String(slot["definition_id"]) == "wood_beam":
			slot["required_components"] = {"grade": {"class": "structural"}}
	value["parameters"] = [
		ParameterScript.create(
			"parameter/finish",
			ParameterScript.VALUE_TYPE_STRING,
			"natural",
			{"label": "Surface finish"}
		),
		ParameterScript.create(
			"parameter/load-rating-kg",
			ParameterScript.VALUE_TYPE_FLOAT,
			100.0,
			{"label": "Declared load rating", "unit": "kg"}
		),
	]
	value["exposed_ports"] = [
		ExposedPortScript.create(
			"port/service-anchor",
			"slot/leg-d",
			"MOUNT_POINT",
			[0.0, 0.0, 0.0],
			{"label": "Service anchor"}
		),
		ExposedPortScript.create(
			"port/work-surface",
			"slot/top",
			"SUPPORT_SURFACE",
			[0.0, 0.0, 0.0],
			{"label": "Work surface"}
		),
	]
	value["checksum"] = DefinitionScript.compute_checksum(value)
	assert(bool(DefinitionScript.validate(value).get("success", false)))
	return value


static func source_projections(instance_key: String) -> Array:
	var prefix: String = "item/c4-%s" % instance_key
	return [
		ProjectionScript.create("%s-cosmetic-beam" % prefix, "wood_beam", "Cosmetic beam", 1, ProjectionScript.container_relation("container/%s-parts" % instance_key, 0), {"grade": {"class": "cosmetic"}}, 0),
		ProjectionScript.create("%s-top" % prefix, "wood_panel", "Table top", 1, ProjectionScript.container_relation("container/%s-parts" % instance_key, 1), {}, 0),
		ProjectionScript.create("%s-leg-a" % prefix, "wood_beam", "Leg A", 1, ProjectionScript.container_relation("container/%s-parts" % instance_key, 2), {"grade": {"class": "structural", "batch": instance_key}}, 0),
		ProjectionScript.create("%s-leg-b" % prefix, "wood_beam", "Leg B", 1, ProjectionScript.container_relation("container/%s-parts" % instance_key, 3), {"grade": {"class": "structural", "batch": instance_key}}, 0),
		ProjectionScript.create("%s-leg-c" % prefix, "wood_beam", "Leg C", 1, ProjectionScript.container_relation("container/%s-parts" % instance_key, 4), {"grade": {"class": "structural", "batch": instance_key}}, 0),
		ProjectionScript.create("%s-leg-d" % prefix, "wood_beam", "Leg D", 1, ProjectionScript.container_relation("container/%s-parts" % instance_key, 5), {"grade": {"class": "structural", "batch": instance_key}}, 0),
		ProjectionScript.create("%s-fasteners-a" % prefix, "fastener", "Fasteners A", 3, ProjectionScript.container_relation("container/%s-tools" % instance_key, 0), {}, 0),
		ProjectionScript.create("%s-fasteners-b" % prefix, "fastener", "Fasteners B", 4, ProjectionScript.container_relation("container/%s-tools" % instance_key, 1), {}, 0),
		ProjectionScript.create("%s-sealant" % prefix, "sealant", "Sealant", 2, ProjectionScript.container_relation("container/%s-tools" % instance_key, 2), {}, 0),
		ProjectionScript.create("%s-unused-paint" % prefix, "paint", "Unused paint", 5, ProjectionScript.container_relation("container/%s-tools" % instance_key, 3), {}, 0),
	]


static func compile_ids(instance_key: String) -> Dictionary:
	return {
		"instantiation_id": "composite-instantiation/table/%s" % instance_key,
		"build_plan_id": "build-plan/table/c4-%s" % instance_key,
		"construct_id": "construct/table/c4-%s" % instance_key,
		"root_item_instance_id": "item/c4-%s-table-root" % instance_key,
	}

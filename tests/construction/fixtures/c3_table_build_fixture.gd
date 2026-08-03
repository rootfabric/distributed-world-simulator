extends RefCounted

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const StageScript = preload("res://scripts/construction/build/construction_build_stage.gd")
const BuildPlanScript = preload("res://scripts/construction/build/construction_build_plan.gd")

const BUILD_PLAN_ID: String = "build-plan/table/c3"
const CONSTRUCT_ID: String = "construct/table/c3"
const ROOT_ID: String = "item/c3-table-root"
const TOP_ID: String = "item/c3-table-top"
const LEG_A_ID: String = "item/c3-table-leg-a"
const LEG_B_ID: String = "item/c3-table-leg-b"
const LEG_C_ID: String = "item/c3-table-leg-c"
const LEG_D_ID: String = "item/c3-table-leg-d"
const FASTENER_ID: String = "item/c3-fasteners"
const SEALANT_ID: String = "item/c3-sealant"
const PART_ITEM_IDS: Array[String] = [TOP_ID, LEG_A_ID, LEG_B_ID, LEG_C_ID, LEG_D_ID]


static func source_projections() -> Array:
	return [
		ProjectionScript.create(TOP_ID, "wood_panel", "Table top", 1, ProjectionScript.container_relation("container/backpack", 0), {}, 0),
		ProjectionScript.create(LEG_A_ID, "wood_beam", "Leg A", 1, ProjectionScript.container_relation("container/backpack", 1), {}, 0),
		ProjectionScript.create(LEG_B_ID, "wood_beam", "Leg B", 1, ProjectionScript.container_relation("container/backpack", 2), {}, 0),
		ProjectionScript.create(LEG_C_ID, "wood_beam", "Leg C", 1, ProjectionScript.container_relation("container/backpack", 3), {}, 0),
		ProjectionScript.create(LEG_D_ID, "wood_beam", "Leg D", 1, ProjectionScript.container_relation("container/backpack", 4), {}, 0),
		ProjectionScript.create(FASTENER_ID, "fastener", "Fasteners", 10, ProjectionScript.container_relation("container/tools", 0), {}, 0),
		ProjectionScript.create(SEALANT_ID, "sealant", "Sealant", 3, ProjectionScript.container_relation("container/tools", 1), {}, 0),
	]


static func target_snapshot() -> Dictionary:
	var aggregate = AggregateScript.new()
	assert(bool(aggregate.setup(CONSTRUCT_ID, ROOT_ID).get("success", false)))
	var revision: int = 0
	for part in [
		PartScript.create("part/table/top", TOP_ID, "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		PartScript.create("part/table/leg-a", LEG_A_ID, "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-b", LEG_B_ID, "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-c", LEG_C_ID, "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		PartScript.create("part/table/leg-d", LEG_D_ID, "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]:
		assert(bool(aggregate.add_part("operation/c3/target/part/%d" % revision, revision, part).get("success", false)))
		revision += 1
	for bond in [
		BondScript.create("bond/table/leg-a", "part/table/top", "part/table/leg-a", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-b", "part/table/top", "part/table/leg-b", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-c", "part/table/top", "part/table/leg-c", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-d", "part/table/top", "part/table/leg-d", "BOLT", 2500.0),
	]:
		assert(bool(aggregate.add_bond("operation/c3/target/bond/%d" % revision, revision, bond).get("success", false)))
		revision += 1
	assert(bool(aggregate.set_build_state("operation/c3/target/operational", revision, "OPERATIONAL").get("success", false)))
	return aggregate.export_snapshot()


static func build_plan() -> Dictionary:
	var stages: Array = [
		StageScript.create(
			"stage/table/foundation",
			0,
			"Foundation and first supports",
			StageScript.SEMANTIC_FOUNDATION,
			["part/table/top", "part/table/leg-a", "part/table/leg-b"],
			["bond/table/leg-a", "bond/table/leg-b"],
			[{"item_instance_id": FASTENER_ID, "definition_id": "fastener", "quantity": 2}],
			["FASTEN"]
		),
		StageScript.create(
			"stage/table/frame",
			1,
			"Complete supporting frame",
			StageScript.SEMANTIC_FRAME,
			["part/table/top", "part/table/leg-a", "part/table/leg-b", "part/table/leg-c", "part/table/leg-d"],
			["bond/table/leg-a", "bond/table/leg-b", "bond/table/leg-c", "bond/table/leg-d"],
			[{"item_instance_id": FASTENER_ID, "definition_id": "fastener", "quantity": 2}],
			["FASTEN"]
		),
		StageScript.create(
			"stage/table/commissioning",
			2,
			"Seal and commission",
			StageScript.SEMANTIC_OPERATIONAL,
			["part/table/top", "part/table/leg-a", "part/table/leg-b", "part/table/leg-c", "part/table/leg-d"],
			["bond/table/leg-a", "bond/table/leg-b", "bond/table/leg-c", "bond/table/leg-d"],
			[{"item_instance_id": SEALANT_ID, "definition_id": "sealant", "quantity": 1}],
			["INSPECT"]
		),
	]
	return BuildPlanScript.create(
		BUILD_PLAN_ID,
		"C3 staged table",
		ProjectionScript.world_relation(),
		target_snapshot(),
		source_projections(),
		stages
	)

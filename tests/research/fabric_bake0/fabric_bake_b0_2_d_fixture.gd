extends RefCounted

const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const CCompiler = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")

const PLAN_ID := "unbake-plan/b0-2-d"
const TARGET_REGION_ID := CFixture.WEAK_REGION_ID
const MAX_FULL_PARTS := 64
const MIN_RETAINED_COMPONENT_PARTS := 100
const CONTINUITY_TOLERANCE := 1.0e-9
const CONSERVATION_TOLERANCE := 1.0e-8
const TRANSITION_VERSION := "FABRIC_BAKE_B0_2_D_R1"

static func build(reverse_input: bool = false) -> Dictionary:
	var c_fixture := CFixture.build(reverse_input, false)
	if not bool(c_fixture.get("success", false)):
		return {"success": false, "c_fixture": c_fixture}
	var c_compiled := CCompiler.compile(c_fixture["request"])
	if not bool(c_compiled.get("success", false)):
		return {"success": false, "c_fixture": c_fixture, "c_compiled": c_compiled}
	return {
		"success": true,
		"c_fixture": c_fixture,
		"c_compiled": c_compiled,
		"request": make_request(c_fixture, c_compiled, TARGET_REGION_ID),
	}

static func make_request(c_fixture: Dictionary, c_compiled: Dictionary, target_region_id: String) -> Dictionary:
	return {
		"plan_id": PLAN_ID,
		"source_frontier_hash": String(c_fixture["ab"]["frontier"]["frontier_hash"]),
		"structural_descriptor": c_fixture["aggregate"]["descriptor"],
		"reconstruction_mapping": c_fixture["aggregate"]["reconstruction_mapping"],
		"guard_field": c_compiled["guard_field"],
		"parts": c_fixture["ab"]["parts"].duplicate(true),
		"bonds": c_fixture["ab"]["bonds"].duplicate(true),
		"boundary_anchors": c_fixture["ab"]["anchors"].duplicate(true),
		"target_region_id": target_region_id,
		"max_full_parts": MAX_FULL_PARTS,
		"minimum_retained_component_parts": MIN_RETAINED_COMPONENT_PARTS,
		"continuity_tolerance": CONTINUITY_TOLERANCE,
		"conservation_tolerance": CONSERVATION_TOLERANCE,
		"transition_version": TRANSITION_VERSION,
	}

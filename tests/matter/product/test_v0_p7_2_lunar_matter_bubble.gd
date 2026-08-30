extends SceneTree

const MaterialCatalogScript = preload(
	"res://scripts/simulation/matter/catalog/matter_material_catalog.gd"
)
const MoonFeaturesScript = preload(
	"res://scripts/simulation/matter/generation/moon_surface_feature_catalog.gd"
)
const MoonSamplerScript = preload(
	"res://scripts/simulation/matter/generation/moon_geology_sampler.gd"
)
const BubbleScript = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const LegacyAdapterScript = preload(
	"res://scripts/world/matter/legacy_moon_surface_adapter.gd"
)

const SURFACE_RADIUS_M: float = 1737425.0
const ANCHOR := Vector3.UP
const HALF_EXTENT_M: float = 32.0
const ACTOR_ID := "player/p7-bubble-test"
const TOOL_ID := "item/tool/p7-bubble-test"

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_canonical_moon_sampler()
	_test_bounded_bubble_query_and_mutation()
	_test_legacy_route_contract()
	print("V0-P7.2 lunar Matter bubble: PASS (%d assertions, %d failures)" % [
		_assertions, _failures,
	])
	quit(0 if _failures == 0 else 1)


func _test_canonical_moon_sampler() -> void:
	var catalog := MaterialCatalogScript.default_catalog()
	var profile := MoonSamplerScript.create_profile({
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
	})
	var features := MoonFeaturesScript.default_catalog(MoonSamplerScript.DEFAULT_SEED)
	var body := MoonSamplerScript.default_body_definition(catalog, profile, features)
	_assert_success(
		MoonSamplerScript.validate_configuration(body, catalog, profile, features),
		"canonical Moon sampler configuration"
	)
	_assert_true(String(body.get("body_id", "")) == "body/moon", "Moon body identity")
	_assert_true(
		String(body.get("body_frame_id", "")) == "body/moon/fixed",
		"Moon body-fixed frame identity"
	)
	var above := ANCHOR * (SURFACE_RADIUS_M + 1.0)
	var shallow := ANCHOR * (SURFACE_RADIUS_M - 1.0)
	var compacted := ANCHOR * (SURFACE_RADIUS_M - 4.0)
	var fractured := ANCHOR * (SURFACE_RADIUS_M - 12.0)
	var deep := ANCHOR * (SURFACE_RADIUS_M - 40.0)
	var above_sample := MoonSamplerScript.sample(body, catalog, profile, features, above)
	var shallow_sample := MoonSamplerScript.sample(body, catalog, profile, features, shallow)
	var compacted_sample := MoonSamplerScript.sample(body, catalog, profile, features, compacted)
	var fractured_sample := MoonSamplerScript.sample(body, catalog, profile, features, fractured)
	var deep_sample := MoonSamplerScript.sample(body, catalog, profile, features, deep)
	_assert_true(float(above_sample.get("signed_distance_m", -1.0)) > 0.0, "vacuum above surface")
	_assert_true(float(above_sample.get("occupancy_ratio", 1.0)) == 0.0, "vacuum occupancy")
	_assert_material(shallow_sample, "matter/regolith-loose", "loose regolith shell")
	_assert_material(compacted_sample, "matter/regolith-compacted", "compacted regolith shell")
	_assert_material(fractured_sample, "matter/fractured-basalt", "fractured basalt shell")
	_assert_material(deep_sample, "matter/basalt", "deep basalt shell")
	var repeated := MoonSamplerScript.sample(body, catalog, profile, features, fractured)
	_assert_true(repeated == fractured_sample, "Moon sample is observer/order independent")


func _test_bounded_bubble_query_and_mutation() -> void:
	var bubble = BubbleScript.new()
	_assert_success(bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": HALF_EXTENT_M,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 3,
		"brick_interior_resolution": 8,
		"ghost_border_samples": 1,
	}), "bounded bubble configure")
	var report := bubble.contract_report()
	_assert_true(String(report.get("body_id", "")) == "body/moon", "bubble keeps Moon identity")
	_assert_true(
		String(report.get("body_frame_id", "")) == "body/moon/fixed",
		"bubble keeps Moon fixed frame"
	)
	_assert_true(String(report.get("canonical_geometry_owner", "")) == "MATTER", "Matter geometry owner")
	_assert_true(String(report.get("canonical_query_owner", "")) == "MATTER", "Matter query owner")
	_assert_true(not bool(report.get("canonical_state_owned_by_adapter", true)), "bubble adapter owns no canonical state")

	var center := bubble.anchor_body_fixed_m()
	var inside := center + Vector3(3.0, -0.5, 0.0)
	var outside := center + Vector3(HALF_EXTENT_M + 1.0, 0.0, 0.0)
	_assert_true(bubble.contains_body_fixed_position(inside), "inside root")
	_assert_true(not bubble.contains_body_fixed_position(outside), "outside root")
	_assert_true(bubble.route_for_body_fixed_position(inside) == "MATTER", "inside routes Matter")
	_assert_true(bubble.route_for_body_fixed_position(outside) == "LEGACY", "outside routes legacy")

	var before := bubble.sample_body_fixed(inside, 2)
	_assert_true(not before.is_empty(), "inside query uses canonical Matter sampler")
	_assert_true(float(before.get("signed_distance_m", 1.0)) < 0.0, "inside point begins in rock")

	var snapshots := bubble.materialize_presentation_level()
	_assert_true(snapshots.size() == 8, "bounded presentation materializes exactly level-1 cells")
	_assert_true(bubble.snapshot_store().size() == 8, "only bounded level-1 snapshots retained")
	var body_hash := String(bubble.body_definition().get("checksum", ""))
	for snapshot_value in snapshots:
		var snapshot: Dictionary = snapshot_value
		_assert_true(
			String(snapshot.get("body_definition_hash", "")) == body_hash,
			"materialized brick binds to the canonical Moon body definition"
		)

	var start := center + Vector3(2.5, -0.5, 0.0)
	var end := center + Vector3(3.5, -0.5, 0.0)
	var request := bubble.create_excavation_request(
		"operation/p7-2/moon-excavate",
		ACTOR_ID,
		TOOL_ID,
		start,
		end,
		0.75,
		1000000000.0,
		1
	)
	_assert_true(not request.is_empty(), "inside bounded excavation request exists")
	_assert_true(String(request.get("body_id", "")) == "body/moon", "mutation targets Moon body")
	var result := bubble.execute(request)
	_assert_true(String(result.get("status", "")) == "COMMITTED", "existing MW4 commits Moon mutation")
	_assert_true(float(result.get("removed_mass_kg", 0.0)) > 0.0, "Moon mutation removes positive mass")
	_assert_true(
		bubble.excavation_service().mutation_journal().size() == 1,
		"existing MW4 journal owns the operation"
	)
	var after := bubble.sample_body_fixed(inside, 2)
	_assert_true(not after.is_empty(), "mutated Matter remains queryable")
	_assert_true(
		float(after.get("signed_distance_m", -1.0)) > float(before.get("signed_distance_m", -1.0)),
		"query observes edited snapshot over procedural Moon base"
	)

	var outside_request := bubble.create_excavation_request(
		"operation/p7-2/outside",
		ACTOR_ID,
		TOOL_ID,
		outside,
		outside + Vector3.RIGHT,
		0.5,
		1000000000.0,
		2
	)
	_assert_true(outside_request.is_empty(), "mutation cannot escape bounded root")

	bubble.set_enabled(false)
	_assert_true(bubble.route_for_body_fixed_position(inside) == "LEGACY", "feature off routes legacy")
	_assert_true(bubble.sample_body_fixed(inside, 2).is_empty(), "feature off exposes no Matter query")


func _test_legacy_route_contract() -> void:
	var bubble = BubbleScript.new()
	_assert_success(bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": HALF_EXTENT_M,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 3,
	}), "adapter bubble configure")
	var adapter = LegacyAdapterScript.new()
	_assert_success(adapter.configure(bubble, 16.0, 2.0), "legacy adapter configure")
	_assert_true(
		absf(adapter.legacy_local_inner_radius_m(ANCHOR) - 16.0) < 0.000001,
		"legacy central cap receives Matter hole only at fixed bubble anchor"
	)
	var shifted_direction := (ANCHOR + Vector3.RIGHT * (4.0 / SURFACE_RADIUS_M)).normalized()
	_assert_true(
		adapter.legacy_local_inner_radius_m(shifted_direction) == 0.0,
		"off-center recenter does not create a false concentric hole"
	)
	var inside := bubble.anchor_body_fixed_m()
	var outside := inside + Vector3(HALF_EXTENT_M + 2.0, 0.0, 0.0)
	_assert_true(not adapter.legacy_collision_enabled_at(inside), "legacy collision disabled inside Matter")
	_assert_true(adapter.legacy_collision_enabled_at(outside), "legacy collision preserved outside")
	var contract := adapter.contract_report()
	_assert_true(not bool(contract.get("double_collision_allowed", true)), "double collision forbidden")
	_assert_true(not bool(contract.get("canonical_state_owned", true)), "legacy adapter owns no canonical state")


func _assert_material(sample: Dictionary, expected_id: String, message: String) -> void:
	var components: Array = sample.get("composition", {}).get("components", [])
	var actual := ""
	if components.size() == 1:
		actual = String(components[0].get("material_id", ""))
	_assert_true(actual == expected_id, "%s expected=%s actual=%s" % [
		message, expected_id, actual,
	])


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.2] %s" % message)

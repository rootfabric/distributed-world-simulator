extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticQuery = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SemanticBundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const CompositionReceipt = preload("res://scripts/simulation/procedural/contracts/semantic_field_composition_receipt.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Composer = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_composer_v1.gd")
const G3Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g3_surface_semantic_field_adapter_v1.gd")
const G5Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g5_feature_semantic_field_adapter_v1.gd")
const G6Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g6_fluid_semantic_field_adapter_v1.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const G5Fixture = preload("res://tests/procedural/fixtures/g5_feature_fixture_factory.gd")
const G6Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")
const RiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_g3_g5_composition()
	_test_g3_g6_composition()
	_test_strict_failure_policy()
	_finish()


func _test_g3_g5_composition() -> void:
	var graph = FeatureGraph.new()
	_assert(bool(graph.configure(G5Fixture.BODY_ID, G5Fixture.FRAME_ID).get("success", false)), "G7.2 G5 graph config succeeds")
	for feature in G5Fixture.all_features():
		_assert(bool(graph.add_feature(feature).get("success", false)), "G7.2 G5 fixture feature added")
	_assert(bool(graph.seal().get("success", false)), "G7.2 G5 graph seals")
	var valley: Dictionary = G5Fixture.valley()
	var position: Array = valley.get("bounds", {}).get("center_m", [])
	var query: Dictionary = SemanticQuery.create(
		G5Fixture.BODY_ID,
		G5Fixture.FRAME_ID,
		position,
		[Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE]
	)
	var provider = MacroProvider.new(20260810072, G5Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	var g3: Dictionary = G3Adapter.sample(query, provider)
	var g5: Dictionary = G5Adapter.sample(query, graph)
	_assert(bool(g3.get("success", false)), "G7.2 G3 partial succeeds")
	_assert(bool(g5.get("success", false)), "G7.2 G5 partial succeeds")
	var composed: Dictionary = Composer.compose(query, [g5, g3])
	_assert(bool(composed.get("success", false)), "G7.2 G3+G5 composition succeeds")
	if not bool(composed.get("success", false)):
		return
	var bundle: Dictionary = composed.get("details", {}).get("bundle", {})
	var receipt: Dictionary = composed.get("details", {}).get("receipt", {})
	_assert(bool(SemanticBundle.validate(bundle).get("success", false)), "G7.2 G3+G5 bundle validates")
	_assert(bool(CompositionReceipt.validate(receipt).get("success", false)), "G7.2 G3+G5 receipt validates")
	_assert(bundle.get("samples", {}).keys().size() == 2, "G7.2 G3+G5 exact bundle coverage")
	_assert(String(bundle["samples"][Registry.SURFACE_HEIGHT_M]["checksum"]) == String(g3["details"]["samples"][Registry.SURFACE_HEIGHT_M]["checksum"]), "G7.2 preserves G3 sample byte identity")
	_assert(String(bundle["samples"][Registry.VALLEY_INFLUENCE]["checksum"]) == String(g5["details"]["samples"][Registry.VALLEY_INFLUENCE]["checksum"]), "G7.2 preserves G5 sample byte identity")
	_assert(String(bundle["samples"][Registry.VALLEY_INFLUENCE]["provenance"]["metadata"].get("selected_feature_id", "")) == String(valley.get("feature_id", "")), "G7.2 preserves G5 FeatureId provenance")
	var contributions: Array = receipt.get("contributions", [])
	_assert(contributions.size() == 2, "G7.2 receipt has two contributions")
	_assert(contributions.size() == 2 and String(contributions[0].get("adapter_id", "")) == G3Adapter.ADAPTER_ID, "G7.2 receipt contributions sort by adapter id")
	var repeated: Dictionary = Composer.compose(query, [g3, g5])
	_assert(bool(repeated.get("success", false)), "G7.2 reversed input composition succeeds")
	_assert(String(repeated.get("details", {}).get("bundle", {}).get("checksum", "")) == String(bundle.get("checksum", "")), "G7.2 bundle independent of partial-result order")
	_assert(String(repeated.get("details", {}).get("receipt", {}).get("checksum", "")) == String(receipt.get("checksum", "")), "G7.2 receipt independent of partial-result order")


func _test_g3_g6_composition() -> void:
	var river: Dictionary = G6Fixture.river()
	var compiled: Dictionary = RiverProvider.compile(river)
	_assert(bool(compiled.get("success", false)), "G7.2 G6 river compile succeeds")
	if not bool(compiled.get("success", false)):
		return
	var points: Array = compiled.get("details", {}).get("river_spline", {}).get("points_m", [])
	_assert(points.size() >= 4, "G7.2 G6 spline has interior point")
	if points.size() < 4:
		return
	var position: Array = points[3]
	var query: Dictionary = SemanticQuery.create(
		G6Fixture.BODY_ID,
		G6Fixture.FRAME_ID,
		position,
		[
			Registry.SURFACE_HEIGHT_M,
			Registry.RIVER_DISTANCE_M,
			Registry.RIVER_WIDTH_M,
			Registry.FLUID_SURFACE_DISTANCE_M,
		]
	)
	var provider = MacroProvider.new(20260810073, G6Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	var g3: Dictionary = G3Adapter.sample(query, provider)
	var g6: Dictionary = G6Adapter.sample(query, [compiled])
	_assert(bool(g3.get("success", false)), "G7.2 G3 river-context partial succeeds")
	_assert(bool(g6.get("success", false)), "G7.2 G6 partial succeeds")
	var composed: Dictionary = Composer.compose(query, [g6, g3])
	_assert(bool(composed.get("success", false)), "G7.2 G3+G6 composition succeeds")
	if not bool(composed.get("success", false)):
		return
	var bundle: Dictionary = composed["details"]["bundle"]
	var receipt: Dictionary = composed["details"]["receipt"]
	_assert(bool(SemanticBundle.validate(bundle).get("success", false)), "G7.2 G3+G6 bundle validates")
	_assert(bool(CompositionReceipt.validate(receipt).get("success", false)), "G7.2 G3+G6 receipt validates")
	_assert(bundle["samples"].keys().size() == 4, "G7.2 G3+G6 exact bundle coverage")
	for field_id in [Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M]:
		_assert(String(bundle["samples"][field_id]["checksum"]) == String(g6["details"]["samples"][field_id]["checksum"]), "G7.2 preserves %s sample checksum" % field_id)
	var river_provenance: Dictionary = bundle["samples"][Registry.RIVER_DISTANCE_M]["provenance"]
	_assert(String(river_provenance.get("metadata", {}).get("source_feature_id", "")) == String(river.get("feature_id", "")), "G7.2 preserves upstream river FeatureId")
	_assert(String(river_provenance.get("metadata", {}).get("fluid_region_id", "")) == String(compiled.get("details", {}).get("fluid_region_id", "")), "G7.2 preserves upstream FluidRegionId")
	_assert(String(receipt.get("query_checksum", "")) == String(query.get("checksum", "")), "G7.2 receipt pins query checksum")
	_assert(String(receipt.get("bundle_checksum", "")) == String(bundle.get("checksum", "")), "G7.2 receipt pins bundle checksum")
	var receipt_contributions: Array = receipt.get("contributions", [])
	_assert(receipt_contributions.size() == 2, "G7.2 G3+G6 receipt has two contributions")
	for contribution in receipt_contributions:
		for field_id in contribution.get("field_ids", []):
			var expected_provenance_checksum: String = String(bundle["samples"][field_id]["provenance"]["checksum"])
			_assert(String(contribution.get("provenance_checksums", {}).get(field_id, "")) == expected_provenance_checksum, "G7.2 receipt pins %s provenance checksum" % field_id)


func _test_strict_failure_policy() -> void:
	var graph = FeatureGraph.new()
	_assert(bool(graph.configure(G5Fixture.BODY_ID, G5Fixture.FRAME_ID).get("success", false)), "G7.2 strict-policy graph config")
	for feature in G5Fixture.all_features():
		_assert(bool(graph.add_feature(feature).get("success", false)), "G7.2 strict-policy feature added")
	_assert(bool(graph.seal().get("success", false)), "G7.2 strict-policy graph seals")
	var position: Array = G5Fixture.valley().get("bounds", {}).get("center_m", [])
	var provider = MacroProvider.new(20260810074, G5Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	var full_query: Dictionary = SemanticQuery.create(G5Fixture.BODY_ID, G5Fixture.FRAME_ID, position, [Registry.SURFACE_HEIGHT_M, Registry.VALLEY_INFLUENCE])
	var g3: Dictionary = G3Adapter.sample(full_query, provider)
	var g5: Dictionary = G5Adapter.sample(full_query, graph)
	var missing: Dictionary = Composer.compose(full_query, [g3])
	_assert(String(missing.get("error_code", "")) == "G7_2_COMPOSITION_MISSING_FIELDS", "G7.2 rejects missing requested field")

	var surface_query: Dictionary = SemanticQuery.create(G5Fixture.BODY_ID, G5Fixture.FRAME_ID, position, [Registry.SURFACE_HEIGHT_M])
	var surface_g3: Dictionary = G3Adapter.sample(surface_query, provider)
	var surface_sample: Dictionary = surface_g3.get("details", {}).get("samples", {}).get(Registry.SURFACE_HEIGHT_M, {})
	var conflict_partial: Dictionary = GeoUtils.success({
		"adapter_id": "semantic-adapter/conflict-fixture-v1",
		"adapter_version": "1.0.0",
		"handled_field_ids": [Registry.SURFACE_HEIGHT_M],
		"samples": {Registry.SURFACE_HEIGHT_M: surface_sample},
	})
	var conflict: Dictionary = Composer.compose(surface_query, [surface_g3, conflict_partial])
	_assert(String(conflict.get("error_code", "")) == "G7_2_COMPOSITION_FIELD_CONFLICT", "G7.2 rejects duplicate field ownership")
	var duplicate_adapter: Dictionary = Composer.compose(surface_query, [surface_g3, surface_g3])
	_assert(String(duplicate_adapter.get("error_code", "")) == "G7_2_COMPOSITION_DUPLICATE_ADAPTER", "G7.2 rejects duplicate adapter contribution")
	var unrequested: Dictionary = Composer.compose(surface_query, [surface_g3, g5])
	_assert(String(unrequested.get("error_code", "")) == "G7_2_COMPOSITION_UNREQUESTED_FIELD", "G7.2 rejects unrequested contributed field")


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("G7.2 Composition / Provenance: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

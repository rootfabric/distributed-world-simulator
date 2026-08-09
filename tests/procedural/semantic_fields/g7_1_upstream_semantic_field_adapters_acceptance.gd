extends SceneTree

const SemanticQuery = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SemanticSample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const G3Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g3_surface_semantic_field_adapter_v1.gd")
const G5Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g5_feature_semantic_field_adapter_v1.gd")
const G6Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g6_fluid_semantic_field_adapter_v1.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const G5Fixture = preload("res://tests/procedural/fixtures/g5_feature_fixture_factory.gd")
const G6Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")
const RiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const WaterQuery = preload("res://scripts/simulation/procedural/contracts/water_surface_query.gd")
const WaterResolver = preload("res://scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd")

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_registry_activation()
	_test_g3_surface_adapter()
	_test_g5_feature_adapter()
	_test_g6_fluid_adapter()
	_finish()


func _test_registry_activation() -> void:
	_assert(bool(Registry.validate_registry().get("success", false)), "registry remains valid")
	for field_id in [Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M]:
		var descriptor: Dictionary = Registry.descriptor(field_id)
		_assert(String(descriptor.get("metadata", {}).get("availability", "")) == Registry.ADAPTER_AVAILABLE, "%s is G7.1 adapter-backed" % field_id)
	for field_id in [Registry.SLOPE, Registry.CURVATURE, Registry.DRAINAGE_POTENTIAL, Registry.CONTINENTALNESS, Registry.TEMPERATURE_BASELINE, Registry.MOISTURE_BASELINE]:
		var descriptor: Dictionary = Registry.descriptor(field_id)
		_assert(String(descriptor.get("metadata", {}).get("availability", "")) == Registry.VOCABULARY_ONLY, "%s remains vocabulary-only" % field_id)


func _test_g3_surface_adapter() -> void:
	var provider = MacroProvider.new(20260810071, 6000000.0, 900.0, 600000.0, 4, 0.5, 12.0)
	var position: Array = [6000000.0, 1250.0, -2500.0]
	var query: Dictionary = SemanticQuery.create(
		"body/g7-1-g3",
		"body/g7-1-g3/fixed",
		position,
		[Registry.SURFACE_HEIGHT_M]
	)
	var direct: Dictionary = provider.sample_surface({}, {"body_fixed_position_m": position}, {})
	_assert(bool(direct.get("success", false)), "G3 direct surface sample succeeds")
	var adapted: Dictionary = G3Adapter.sample(query, provider)
	_assert(bool(adapted.get("success", false)), "G3 semantic adapter succeeds")
	var details: Dictionary = adapted.get("details", {})
	_assert(details.get("handled_field_ids", []) == [Registry.SURFACE_HEIGHT_M], "G3 handles only requested surface height")
	var samples: Dictionary = details.get("samples", {})
	_assert(samples.has(Registry.SURFACE_HEIGHT_M), "G3 semantic surface sample present")
	var sample: Dictionary = samples.get(Registry.SURFACE_HEIGHT_M, {})
	_assert(bool(SemanticSample.validate_against_descriptor(sample, Registry.descriptor(Registry.SURFACE_HEIGHT_M)).get("success", false)), "G3 semantic sample validates")
	_assert(absf(float(sample.get("value", 0.0)) - float(direct.get("details", {}).get(Registry.SURFACE_HEIGHT_M, 0.0))) < 0.000000001, "G3 semantic value equals accepted provider value")
	var refs: Array = sample.get("provenance", {}).get("source_refs", [])
	_assert(refs.size() == 1, "G3 provenance has one provider source")
	_assert(String(refs[0].get("id", "")) == MacroProvider.PROVIDER_ID, "G3 provenance preserves provider id")
	var repeated: Dictionary = G3Adapter.sample(query, provider)
	_assert(String(repeated.get("details", {}).get("samples", {}).get(Registry.SURFACE_HEIGHT_M, {}).get("checksum", "")) == String(sample.get("checksum", "")), "G3 adapter is deterministic")
	var unrelated: Dictionary = SemanticQuery.create("body/g7-1-g3", "body/g7-1-g3/fixed", position, [Registry.VALLEY_INFLUENCE])
	var ignored: Dictionary = G3Adapter.sample(unrelated, provider)
	_assert(bool(ignored.get("success", false)) and Dictionary(ignored.get("details", {}).get("samples", {})).is_empty(), "G3 adapter ignores fields it does not own")


func _test_g5_feature_adapter() -> void:
	var graph = FeatureGraph.new()
	_assert(bool(graph.configure(G5Fixture.BODY_ID, G5Fixture.FRAME_ID).get("success", false)), "G5 graph config succeeds")
	for feature in G5Fixture.all_features():
		_assert(bool(graph.add_feature(feature).get("success", false)), "G5 fixture feature added")
	_assert(bool(graph.seal().get("success", false)), "G5 graph seals")
	var valley: Dictionary = G5Fixture.valley()
	var center: Array = valley.get("bounds", {}).get("center_m", [])
	var query: Dictionary = SemanticQuery.create(G5Fixture.BODY_ID, G5Fixture.FRAME_ID, center, [Registry.VALLEY_INFLUENCE])
	var adapted: Dictionary = G5Adapter.sample(query, graph)
	_assert(bool(adapted.get("success", false)), "G5 feature semantic adapter succeeds")
	var sample: Dictionary = adapted.get("details", {}).get("samples", {}).get(Registry.VALLEY_INFLUENCE, {})
	_assert(bool(SemanticSample.validate_against_descriptor(sample, Registry.descriptor(Registry.VALLEY_INFLUENCE)).get("success", false)), "G5 valley influence sample validates")
	_assert(absf(float(sample.get("value", -1.0)) - 1.0) < 0.000000001, "G5 valley center influence is one")
	var provenance: Dictionary = sample.get("provenance", {})
	_assert(String(provenance.get("configuration_hash", "")) == String(graph.manifest_hash()), "G5 provenance pins feature graph manifest")
	_assert(String(provenance.get("metadata", {}).get("selected_feature_id", "")) == String(valley.get("feature_id", "")), "G5 provenance preserves FeatureId")
	_assert(String(provenance.get("metadata", {}).get("influence_policy", "")) == G5Adapter.INFLUENCE_POLICY, "G5 influence policy explicit")
	_assert(not bool(provenance.get("metadata", {}).get("geomorphology_owned", true)), "G5 adapter does not claim geomorphology ownership")
	var repeated: Dictionary = G5Adapter.sample(query, graph)
	_assert(String(repeated.get("details", {}).get("samples", {}).get(Registry.VALLEY_INFLUENCE, {}).get("checksum", "")) == String(sample.get("checksum", "")), "G5 adapter is deterministic")
	var far_query: Dictionary = SemanticQuery.create(G5Fixture.BODY_ID, G5Fixture.FRAME_ID, [0.0, G5Fixture.RADIUS_M, 0.0], [Registry.VALLEY_INFLUENCE])
	var far_result: Dictionary = G5Adapter.sample(far_query, graph)
	_assert(bool(far_result.get("success", false)), "G5 zero-influence query succeeds")
	var far_sample: Dictionary = far_result.get("details", {}).get("samples", {}).get(Registry.VALLEY_INFLUENCE, {})
	_assert(absf(float(far_sample.get("value", -1.0))) < 0.000000001, "G5 outside valley influence is zero")
	_assert(Array(far_sample.get("provenance", {}).get("source_refs", [])).is_empty(), "G5 zero influence invents no FeatureId")


func _test_g6_fluid_adapter() -> void:
	var river: Dictionary = G6Fixture.river()
	var compiled: Dictionary = RiverProvider.compile(river)
	_assert(bool(compiled.get("success", false)), "G6 accepted river compile succeeds")
	var compiled_details: Dictionary = compiled.get("details", {})
	var points: Array = compiled_details.get("river_spline", {}).get("points_m", [])
	_assert(points.size() >= 4, "G6 compiled spline has interior control point")
	if points.size() < 4:
		return
	var position: Array = points[3]
	var requested: Array = [Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M]
	var query: Dictionary = SemanticQuery.create(G6Fixture.BODY_ID, G6Fixture.FRAME_ID, position, requested)
	var adapted: Dictionary = G6Adapter.sample(query, [compiled])
	_assert(bool(adapted.get("success", false)), "G6 fluid semantic adapter succeeds")
	var samples: Dictionary = adapted.get("details", {}).get("samples", {})
	_assert(samples.keys().size() == 3, "G6 adapter returns all requested fluid fields")

	var direct_query: Dictionary = WaterQuery.create(G6Fixture.BODY_ID, G6Fixture.FRAME_ID, position, G6Adapter.MAX_RESOLVE_DISTANCE_M, [])
	var direct: Dictionary = WaterResolver.resolve(direct_query, [compiled])
	_assert(bool(direct.get("success", false)) and bool(direct.get("details", {}).get("matched", false)), "G6 direct resolver matches")
	var water_sample: Dictionary = direct.get("details", {}).get("sample", {})
	_assert(absf(float(samples.get(Registry.RIVER_DISTANCE_M, {}).get("value", -1.0)) - float(water_sample.get("distance_to_centerline_m", -2.0))) < 0.000000001, "river-distance projects G6 centerline distance")
	_assert(absf(float(samples.get(Registry.RIVER_WIDTH_M, {}).get("value", -1.0)) - float(water_sample.get("width_m", -2.0))) < 0.000000001, "river-width projects G6 channel width")
	_assert(absf(float(samples.get(Registry.FLUID_SURFACE_DISTANCE_M, {}).get("value", -1.0)) - float(water_sample.get("distance_to_surface_m", -2.0))) < 0.000000001, "fluid-surface-distance projects G6 surface distance")
	for field_id in requested:
		_assert(bool(SemanticSample.validate_against_descriptor(samples.get(field_id, {}), Registry.descriptor(field_id)).get("success", false)), "%s sample validates" % field_id)
	var provenance: Dictionary = samples.get(Registry.RIVER_DISTANCE_M, {}).get("provenance", {})
	_assert(String(provenance.get("metadata", {}).get("source_feature_id", "")) == String(river.get("feature_id", "")), "G6 provenance preserves upstream FeatureId")
	_assert(String(provenance.get("metadata", {}).get("fluid_region_id", "")) == String(compiled_details.get("fluid_region_id", "")), "G6 provenance preserves FluidRegionId")
	_assert(String(provenance.get("metadata", {}).get("resolver_id", "")) == WaterResolver.RESOLVER_ID, "G6 provenance records accepted resolver")
	var repeated: Dictionary = G6Adapter.sample(query, [compiled])
	for field_id in requested:
		_assert(String(repeated.get("details", {}).get("samples", {}).get(field_id, {}).get("checksum", "")) == String(samples.get(field_id, {}).get("checksum", "")), "%s adapter result deterministic" % field_id)
	var unrelated: Dictionary = SemanticQuery.create(G6Fixture.BODY_ID, G6Fixture.FRAME_ID, position, [Registry.SLOPE])
	var ignored: Dictionary = G6Adapter.sample(unrelated, [compiled])
	_assert(bool(ignored.get("success", false)) and Dictionary(ignored.get("details", {}).get("samples", {})).is_empty(), "G6 adapter ignores fields it does not own")


func _assert(ok: bool, message: String) -> void:
	assertions += 1
	if ok:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("G7.1 Upstream Semantic Field Adapters: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

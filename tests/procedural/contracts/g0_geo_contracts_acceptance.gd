extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const Descriptor = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const VolumeQuery = preload("res://scripts/simulation/procedural/contracts/geo_volume_query.gd")
const FieldBundle = preload("res://scripts/simulation/procedural/contracts/geo_field_bundle.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const FlatProvider = preload("res://scripts/simulation/procedural/providers/flat_surface_provider.gd")
const StubProvider = preload("res://tests/procedural/fixtures/geo_provider_stub.gd")

const BODY_ID := "body/procedural-g0"
const RECIPE_ID := "planet-recipe/g0-flat"
const MANIFEST_VERSION := "1.0.0"
const HEIGHT_FIELD := "geo/surface-height-m"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest_and_contracts()
	_test_kernel_determinism()
	_test_graph_validation()
	_test_provider_binding_validation()
	_test_replacement_and_volume_boundary()
	_test_source_boundaries()
	_finish()


func _test_manifest_and_contracts() -> void:
	var path := "res://config/procedural/g0-geo-contracts.v1.json"
	_check(FileAccess.file_exists(path), "manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "manifest is JSON object")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g0-geo-contracts-v0", "manifest checkpoint")
		_check(String(parsed.get("implementation_branch", "")) == "feature/g0-geo-contracts", "manifest branch")
		_check(not bool(parsed.get("runtime_worlds_changed", true)), "runtime worlds unchanged")
		_check(not bool(parsed.get("production_terrain_changed", true)), "production terrain unchanged")

	var definition := _definition(RECIPE_ID)
	_ok(PlanetDefinition.validate(definition), "planet definition")
	_check(PlanetDefinition.normalize(definition) == definition, "definition normalization")
	var bad_radius := definition.duplicate(true)
	bad_radius["nominal_radius_m"] = 0.0
	bad_radius["checksum"] = GeoUtils.compute_checksum(bad_radius)
	_error(PlanetDefinition.validate(bad_radius), "INVALID_NOMINAL_RADIUS", "zero radius")

	var environment := _environment()
	_ok(PlanetEnvironment.validate(environment), "environment")
	var unsafe_environment := environment.duplicate(true)
	unsafe_environment["parameters"]["runtime"] = RefCounted.new()
	unsafe_environment["checksum"] = GeoUtils.compute_checksum(unsafe_environment)
	_error(PlanetEnvironment.validate(unsafe_environment), "NON_CANONICAL_JSON_VALUE", "unsafe environment")

	var flat := FlatProvider.new(0.0)
	var descriptor: Dictionary = flat.get_descriptor()
	_ok(Descriptor.validate(descriptor), "flat descriptor")
	_check(Array(descriptor["provides"]) == [HEIGHT_FIELD], "flat provides height")
	_check(float(descriptor["parameters"]["height_m"]) == 0.0, "provider parameters included")
	var changed_descriptor: Dictionary = FlatProvider.new(12.5).get_descriptor()
	_check(GeoUtils.payload_hash(changed_descriptor) != GeoUtils.payload_hash(descriptor), "parameter changes descriptor hash")
	var unsafe_descriptor := Descriptor.create("geo-provider/unsafe", "1.0.0", "1.0.0", [], ["geo/unsafe"], true, {"runtime": RefCounted.new()})
	_error(Descriptor.validate(unsafe_descriptor), "NON_CANONICAL_JSON_VALUE", "unsafe provider parameter")

	var context := _context()
	_ok(Context.validate(context), "generation context")
	var bad_budget := context.duplicate(true)
	bad_budget["detail_budget"] = 1.1
	bad_budget["checksum"] = GeoUtils.compute_checksum(bad_budget)
	_error(Context.validate(bad_budget), "INVALID_GEO_GENERATION_BUDGET", "invalid detail budget")

	var surface := SurfaceQuery.create(BODY_ID, [6000000.0, 0.0, 0.0], [HEIGHT_FIELD])
	_ok(SurfaceQuery.validate(surface), "surface query")
	var volume := VolumeQuery.create(BODY_ID, [6000000.0, 0.0, 0.0], ["geo/density"])
	_ok(VolumeQuery.validate(volume), "volume query")
	var ordered := SurfaceQuery.create(BODY_ID, [1.0, 2.0, 3.0], ["geo/z", HEIGHT_FIELD, "geo/z"])
	_check(Array(ordered["requested_fields"]) == [HEIGHT_FIELD, "geo/z"], "query fields canonicalized")

	var bundle := FieldBundle.create({HEIGHT_FIELD: 0.0}, {HEIGHT_FIELD: FlatProvider.PROVIDER_ID})
	_ok(FieldBundle.validate(bundle), "field bundle")
	_error(FieldBundle.validate(FieldBundle.create({HEIGHT_FIELD: 0.0}, {})), "GEO_FIELD_PROVENANCE_MISMATCH", "provenance mismatch")
	var sample := GeoSample.create(BODY_ID, GeoSample.QUERY_SURFACE, [0.0, 0.0, 0.0], bundle, "a".repeat(64))
	_ok(GeoSample.validate(sample), "geo sample")
	_check(float(GeoSample.field_value(sample, HEIGHT_FIELD, -1.0)) == 0.0, "sample field lookup")

	var a := Descriptor.create("geo-provider/a", "1.0.0", "1.0.0", [], ["geo/a"], true)
	var b := Descriptor.create("geo-provider/b", "1.0.0", "1.0.0", [], ["geo/b"], true)
	var recipe := PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, [b, a])
	_ok(PlanetRecipe.validate(recipe), "canonical recipe")
	_check(String(recipe["provider_descriptors"][0]["provider_id"]) == "geo-provider/a", "recipe sorts providers")


func _test_kernel_determinism() -> void:
	var fixture := _flat_fixture(3.5)
	var kernel = fixture["kernel"]
	var context: Dictionary = fixture["context"]
	var query_a := SurfaceQuery.create(BODY_ID, [6000000.0, 10.0, 20.0], [HEIGHT_FIELD])
	var query_b := SurfaceQuery.create(BODY_ID, [6000001.0, 30.0, 40.0], [HEIGHT_FIELD])
	var first_a: Dictionary = kernel.sample_surface(context, query_a)
	var first_b: Dictionary = kernel.sample_surface(context, query_b)
	_ok(first_a, "surface A")
	_ok(first_b, "surface B")
	var second_fixture := _flat_fixture(3.5)
	var second_kernel = second_fixture["kernel"]
	var second_b: Dictionary = second_kernel.sample_surface(second_fixture["context"], query_b)
	var second_a: Dictionary = second_kernel.sample_surface(second_fixture["context"], query_a)
	_ok(second_b, "surface B reverse order")
	_ok(second_a, "surface A reverse order")
	if _success(first_a) and _success(second_a):
		_check(first_a["details"]["sample"] == second_a["details"]["sample"], "A order independent")
	if _success(first_b) and _success(second_b):
		_check(first_b["details"]["sample"] == second_b["details"]["sample"], "B order independent")
	if _success(first_a):
		_check(float(GeoSample.field_value(first_a["details"]["sample"], HEIGHT_FIELD, NAN)) == 3.5, "configured flat height")
		_check(String(first_a["details"]["sample"]["provider_manifest_hash"]) == kernel.get_provider_manifest_hash(), "sample manifest provenance")


func _test_graph_validation() -> void:
	var missing := Descriptor.create("geo-provider/missing", "1.0.0", "1.0.0", ["geo/not-provided"], ["geo/out"], true)
	_config_error([missing], [StubProvider.new(missing, {"geo/out": 1.0})], "MISSING_GEO_PROVIDER_DEPENDENCY", "missing dependency")
	var dup_a := Descriptor.create("geo-provider/dup-a", "1.0.0", "1.0.0", [], ["geo/shared"], true)
	var dup_b := Descriptor.create("geo-provider/dup-b", "1.0.0", "1.0.0", [], ["geo/shared"], true)
	_config_error([dup_a, dup_b], [StubProvider.new(dup_a, {"geo/shared": 1.0}), StubProvider.new(dup_b, {"geo/shared": 2.0})], "DUPLICATE_GEO_PROVIDER_OUTPUT", "duplicate output")
	var cycle_a := Descriptor.create("geo-provider/cycle-a", "1.0.0", "1.0.0", ["geo/b"], ["geo/a"], true)
	var cycle_b := Descriptor.create("geo-provider/cycle-b", "1.0.0", "1.0.0", ["geo/a"], ["geo/b"], true)
	_config_error([cycle_a, cycle_b], [StubProvider.new(cycle_a, {"geo/a": 1.0}), StubProvider.new(cycle_b, {"geo/b": 2.0})], "GEO_PROVIDER_DEPENDENCY_CYCLE", "dependency cycle")
	var nondeterministic := Descriptor.create("geo-provider/random", "1.0.0", "1.0.0", [], ["geo/random"], false)
	_config_error([nondeterministic], [StubProvider.new(nondeterministic, {"geo/random": 1.0})], "NON_DETERMINISTIC_GEO_PROVIDER", "nondeterministic provider")
	var a := Descriptor.create("geo-provider/a", "1.0.0", "1.0.0", [], ["geo/a"], true)
	var b := Descriptor.create("geo-provider/b", "1.0.0", "1.0.0", [], ["geo/b"], true)
	var kernel = GeoKernel.new()
	_ok(kernel.configure(_definition(RECIPE_ID), _recipe([b, a]), [StubProvider.new(b, {"geo/b": 2.0}), StubProvider.new(a, {"geo/a": 1.0})]), "independent providers")
	_check(kernel.get_provider_order() == ["geo-provider/a", "geo-provider/b"], "provider order canonical")


func _test_provider_binding_validation() -> void:
	var flat := FlatProvider.new()
	var descriptor: Dictionary = flat.get_descriptor()
	var recipe := _recipe([descriptor])
	var definition := _definition(RECIPE_ID)
	var kernel = GeoKernel.new()
	_error(kernel.configure(definition, recipe, []), "UNKNOWN_GEO_PROVIDER", "missing implementation")
	var undeclared_descriptor := Descriptor.create("geo-provider/undeclared", "1.0.0", "1.0.0", [], ["geo/other"], true)
	_error(GeoKernel.new().configure(definition, recipe, [flat, StubProvider.new(undeclared_descriptor, {"geo/other": 1.0})]), "UNDECLARED_GEO_PROVIDER", "undeclared implementation")
	_error(GeoKernel.new().configure(definition, recipe, [flat, FlatProvider.new()]), "DUPLICATE_GEO_PROVIDER_IMPLEMENTATION", "duplicate implementation")
	var mismatched := FlatProvider.new(5.0)
	_error(GeoKernel.new().configure(definition, recipe, [mismatched]), "GEO_PROVIDER_DESCRIPTOR_MISMATCH", "parameter mismatch fenced")


func _test_replacement_and_volume_boundary() -> void:
	var flat := _flat_fixture(0.0)
	_check(_height(flat["kernel"], flat["context"], flat["query"]) == 0.0, "generic caller reads flat provider")
	var alternative_descriptor := Descriptor.create("geo-provider/alternative-flat", "1.0.0", "1.0.0", [], [HEIGHT_FIELD], true, {"profile": "test"})
	var alternative_provider = StubProvider.new(alternative_descriptor, {HEIGHT_FIELD: 17.5})
	var alternative_recipe_id := "planet-recipe/g0-alternative"
	var alternative_kernel = GeoKernel.new()
	_ok(alternative_kernel.configure(_definition(alternative_recipe_id), PlanetRecipe.create(alternative_recipe_id, "1.0.0", _environment(), [alternative_descriptor]), [alternative_provider]), "alternative provider")
	var alternative_context := Context.create(BODY_ID, "geo-scope/g0", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
	var alternative_query := SurfaceQuery.create(BODY_ID, [6000000.0, 0.0, 0.0], [HEIGHT_FIELD])
	_check(_height(alternative_kernel, alternative_context, alternative_query) == 17.5, "provider replacement preserves caller")
	var volume_query := VolumeQuery.create(BODY_ID, [6000000.0, 0.0, 0.0], [HEIGHT_FIELD])
	_error(flat["kernel"].sample_volume(flat["context"], volume_query), "GEO_PROVIDER_QUERY_KIND_UNSUPPORTED", "surface provider cannot answer volume")


func _test_source_boundaries() -> void:
	var paths: Array[String] = [
		"res://scripts/simulation/procedural/geo_contract_utils.gd", "res://scripts/simulation/procedural/geo_kernel.gd",
		"res://scripts/simulation/procedural/contracts/planet_definition.gd", "res://scripts/simulation/procedural/contracts/planet_environment.gd",
		"res://scripts/simulation/procedural/contracts/planet_recipe.gd", "res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd",
		"res://scripts/simulation/procedural/contracts/geo_generation_context.gd", "res://scripts/simulation/procedural/contracts/geo_surface_query.gd",
		"res://scripts/simulation/procedural/contracts/geo_volume_query.gd", "res://scripts/simulation/procedural/contracts/geo_field_bundle.gd",
		"res://scripts/simulation/procedural/contracts/geo_sample.gd", "res://scripts/simulation/procedural/providers/geo_provider.gd",
		"res://scripts/simulation/procedural/providers/flat_surface_provider.gd",
	]
	var forbidden := ["extends Node", "extends SceneTree", "MeshInstance3D", "ArrayMesh", "RenderingServer", "Terrain3D", "VoxelLodTerrain", "RandomNumberGenerator", "randf(", "randi("]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "source exists: %s" % path)
		for marker in forbidden:
			_check(not source.contains(marker), "no %s in %s" % [marker, path])


func _flat_fixture(height_m: float) -> Dictionary:
	var provider = FlatProvider.new(height_m)
	var kernel = GeoKernel.new()
	_ok(kernel.configure(_definition(RECIPE_ID), _recipe([provider.get_descriptor()]), [provider]), "flat kernel configure")
	return {"kernel": kernel, "context": _context(), "query": SurfaceQuery.create(BODY_ID, [6000000.0, 0.0, 0.0], [HEIGHT_FIELD])}


func _definition(recipe_id: String) -> Dictionary:
	return PlanetDefinition.create(BODY_ID, 2026080801, recipe_id, "body-shape/sphere-placeholder", 6000000.0, MANIFEST_VERSION)


func _environment() -> Dictionary:
	return PlanetEnvironment.create("planet-environment/g0-neutral", "gravity-model/unspecified", "atmosphere-model/unspecified", "temperature-model/unspecified", "fluid-catalog/none", "weathering-model/none", "material-catalog/unspecified", {})


func _recipe(descriptors: Array) -> Dictionary:
	return PlanetRecipe.create(RECIPE_ID, "1.0.0", _environment(), descriptors)


func _context() -> Dictionary:
	return Context.create(BODY_ID, "geo-scope/g0", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)


func _config_error(descriptors: Array, providers: Array, code: String, label: String) -> void:
	_error(GeoKernel.new().configure(_definition(RECIPE_ID), _recipe(descriptors), providers), code, label)


func _height(kernel, context: Dictionary, query: Dictionary) -> float:
	var result: Dictionary = kernel.sample_surface(context, query)
	if not _success(result):
		return NAN
	return float(GeoSample.field_value(result["details"]["sample"], HEIGHT_FIELD, NAN))


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s" % [label, String(result.get("error_code", ""))])


func _error(result: Dictionary, code: String, label: String) -> void:
	_check(not _success(result), "%s unexpectedly succeeded" % label)
	if not _success(result):
		_check(String(result.get("error_code", "")) == code, "%s expected %s got %s" % [label, code, String(result.get("error_code", ""))])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G0 Geo contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G0 Geo contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const PlanetDefinition = preload("res://scripts/simulation/procedural/contracts/planet_definition.gd")
const PlanetEnvironment = preload("res://scripts/simulation/procedural/contracts/planet_environment.gd")
const PlanetRecipe = preload("res://scripts/simulation/procedural/contracts/planet_recipe.gd")
const ProviderDescriptor = preload("res://scripts/simulation/procedural/contracts/geo_provider_descriptor.gd")
const Context = preload("res://scripts/simulation/procedural/contracts/geo_generation_context.gd")
const SurfaceQuery = preload("res://scripts/simulation/procedural/contracts/geo_surface_query.gd")
const GeoSample = preload("res://scripts/simulation/procedural/contracts/geo_sample.gd")
const GeoKernel = preload("res://scripts/simulation/procedural/geo_kernel.gd")
const Registry = preload("res://scripts/simulation/procedural/composition/geo_provider_registry.gd")
const Composer = preload("res://scripts/simulation/procedural/composition/geo_recipe_composer.gd")
const Catalog = preload("res://scripts/simulation/procedural/composition/g4_surface_provider_catalog.gd")
const BaseSurface = preload("res://scripts/simulation/procedural/providers/base_surface_provider_v1.gd")
const CasualMacroLayer = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_layer_provider_v1.gd")
const AlternativeMacro = preload("res://scripts/simulation/procedural/providers/alternative_macro_terrain_provider_v1.gd")
const ValleyModifier = preload("res://scripts/simulation/procedural/providers/casual_valley_modifier_provider_v1.gd")
const StubProvider = preload("res://tests/procedural/fixtures/g4_contract_provider_stub.gd")

const BODY_ID := "body/procedural-g4"
const RECIPE_ID := "world-recipe/g4-composed-surface"
const SHAPE_ID := "body-shape/sphere-v1"
const MANIFEST_VERSION := "1.0.0"
const RADIUS_M := 6000000.0
const SEED := 2026080801
const FINAL_FIELD := "geo/surface-height-m"
const MACRO_FIELD := "geo/macro-surface-height-m"

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_registry_and_recipe_driven_composition()
	_test_canonical_recipe_order_and_manifest()
	_test_valley_is_downstream_modifier()
	_test_base_surface_composes_without_caller_change()
	_test_invalid_graphs_rejected()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g4-provider-composition.v1.json"
	_check(FileAccess.file_exists(path), "G4 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G4 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g4-provider-composition-replacement-v0", "G4 checkpoint")
		_check(String(parsed.get("base_branch", "")) == "docs/universal-world-generation-roadmap-post-g3", "G4 docs base")
		_check(String(parsed.get("g3_accepted_head", "")) == "bc58f650ffb43775667bf0d07cb361a98a40d294", "G3 accepted baseline")
		_check(not bool(parsed.get("geo_kernel_changed", true)), "GeoKernel unchanged by G4")
		_check(not bool(parsed.get("surface_cell_key_changed", true)), "SurfaceCellKey unchanged by G4")
		_check(not bool(parsed.get("lod_selector_changed", true)), "LOD selector unchanged by G4")
		_check(String(parsed.get("final_surface_field", "")) == FINAL_FIELD, "final caller field stable")


func _test_registry_and_recipe_driven_composition() -> void:
	var catalog_result: Dictionary = Catalog.create_registry()
	_ok(catalog_result, "catalog registry")
	if not _success(catalog_result):
		return
	var registry = catalog_result["details"]["registry"]
	_check(registry.provider_ids() == [
		AlternativeMacro.PROVIDER_ID,
		BaseSurface.PROVIDER_ID,
		CasualMacroLayer.PROVIDER_ID,
		ValleyModifier.PROVIDER_ID,
	], "registry provider ids canonical")

	var environment := _environment()
	var casual_recipe := PlanetRecipe.create(RECIPE_ID, "1.0.0", environment, Catalog.casual_descriptors(SEED, RADIUS_M))
	var alternative_recipe := PlanetRecipe.create(RECIPE_ID, "2.0.0", environment, Catalog.alternative_descriptors(SEED, RADIUS_M))
	var definition := _definition()
	var composer = Composer.new()

	var casual_kernel = GeoKernel.new()
	var casual_config: Dictionary = composer.configure_kernel(casual_kernel, definition, casual_recipe, registry)
	_ok(casual_config, "casual recipe composition")
	var alternative_kernel = GeoKernel.new()
	var alternative_config: Dictionary = composer.configure_kernel(alternative_kernel, definition, alternative_recipe, registry)
	_ok(alternative_config, "alternative recipe composition")
	if not _success(casual_config) or not _success(alternative_config):
		return

	_check(casual_config["details"]["provider_order"] == [BaseSurface.PROVIDER_ID, CasualMacroLayer.PROVIDER_ID, ValleyModifier.PROVIDER_ID], "casual topological provider order")
	_check(alternative_config["details"]["provider_order"] == [BaseSurface.PROVIDER_ID, AlternativeMacro.PROVIDER_ID, ValleyModifier.PROVIDER_ID], "alternative topological provider order")
	_check(String(casual_config["details"]["provider_manifest_hash"]) != String(alternative_config["details"]["provider_manifest_hash"]), "macro replacement changes provenance hash")

	var changed_points: int = 0
	for lat in [-70.0, -35.0, -10.0, 0.0, 25.0, 52.0, 78.0]:
		for lon in [-160.0, -110.0, -45.0, 5.0, 70.0, 125.0, 175.0]:
			var direction := _direction(lat, lon)
			var casual_sample := _sample(casual_kernel, direction, [FINAL_FIELD])
			var alternative_sample := _sample(alternative_kernel, direction, [FINAL_FIELD])
			_check(casual_sample.has("sample"), "casual final surface query")
			_check(alternative_sample.has("sample"), "alternative final surface query")
			if casual_sample.has("sample") and alternative_sample.has("sample"):
				var ch: float = float(GeoSample.field_value(casual_sample["sample"], FINAL_FIELD, NAN))
				var ah: float = float(GeoSample.field_value(alternative_sample["sample"], FINAL_FIELD, NAN))
				_check(is_finite(ch) and is_finite(ah), "replacement heights finite")
				if absf(ch - ah) > 1.0:
					changed_points += 1
	_check(changed_points >= 35, "recipe-only macro replacement visibly changes world")
	_check(FINAL_FIELD == ValleyModifier.FIELD_SURFACE_HEIGHT_M, "renderer/downstream final field contract unchanged")


func _test_canonical_recipe_order_and_manifest() -> void:
	var descriptors: Array = Catalog.casual_descriptors(SEED, RADIUS_M)
	var shuffled: Array = [descriptors[2], descriptors[0], descriptors[1]]
	var recipe_a := PlanetRecipe.create(RECIPE_ID, "1.5.0", _environment(), descriptors)
	var recipe_b := PlanetRecipe.create(RECIPE_ID, "1.5.0", _environment(), shuffled)
	_check(recipe_a["provider_descriptors"] == recipe_b["provider_descriptors"], "recipe provider order canonicalized")
	_check(String(recipe_a["checksum"]) == String(recipe_b["checksum"]), "recipe checksum independent from descriptor input order")

	var catalog_result: Dictionary = Catalog.create_registry()
	_ok(catalog_result, "registry for canonical manifest")
	if not _success(catalog_result):
		return
	var composer = Composer.new()
	var kernel_a = GeoKernel.new()
	var kernel_b = GeoKernel.new()
	var config_a: Dictionary = composer.configure_kernel(kernel_a, _definition(), recipe_a, catalog_result["details"]["registry"])
	var config_b: Dictionary = composer.configure_kernel(kernel_b, _definition(), recipe_b, catalog_result["details"]["registry"])
	_ok(config_a, "canonical graph A")
	_ok(config_b, "canonical graph B")
	if _success(config_a) and _success(config_b):
		_check(String(config_a["details"]["provider_manifest_hash"]) == String(config_b["details"]["provider_manifest_hash"]), "same graph same provenance hash")
		_check(config_a["details"]["provider_order"] == config_b["details"]["provider_order"], "same graph same execution order")


func _test_valley_is_downstream_modifier() -> void:
	var catalog_result: Dictionary = Catalog.create_registry()
	_ok(catalog_result, "registry for valley")
	if not _success(catalog_result):
		return
	var recipe := PlanetRecipe.create(RECIPE_ID, "1.6.0", _environment(), Catalog.casual_descriptors(SEED, RADIUS_M, 0.0, 900.0, 600000.0, 80000.0, 350.0))
	var kernel = GeoKernel.new()
	_ok(Composer.new().configure_kernel(kernel, _definition(), recipe, catalog_result["details"]["registry"]), "valley graph configure")

	var normal := Vector3(0.35, 0.82, -0.45).normalized()
	var center_direction := normal.cross(Vector3.UP)
	if center_direction.length_squared() < 0.000001:
		center_direction = normal.cross(Vector3.RIGHT)
	center_direction = center_direction.normalized()
	var center := _sample(kernel, center_direction, [MACRO_FIELD, FINAL_FIELD])
	_check(center.has("sample"), "valley center sample")
	if center.has("sample"):
		var macro_h := float(GeoSample.field_value(center["sample"], MACRO_FIELD, NAN))
		var final_h := float(GeoSample.field_value(center["sample"], FINAL_FIELD, NAN))
		_check(_approx(macro_h - final_h, 350.0, 0.000001), "valley center carves configured depth")

	var off_direction := normal
	var off := _sample(kernel, off_direction, [MACRO_FIELD, FINAL_FIELD])
	_check(off.has("sample"), "off-valley sample")
	if off.has("sample"):
		var macro_h := float(GeoSample.field_value(off["sample"], MACRO_FIELD, NAN))
		var final_h := float(GeoSample.field_value(off["sample"], FINAL_FIELD, NAN))
		_check(_approx(macro_h, final_h, 0.000001), "outside valley final equals macro")


func _test_base_surface_composes_without_caller_change() -> void:
	var catalog_result: Dictionary = Catalog.create_registry()
	_ok(catalog_result, "registry for base composition")
	if not _success(catalog_result):
		return
	var registry = catalog_result["details"]["registry"]
	var recipe_zero := PlanetRecipe.create(RECIPE_ID, "1.7.0", _environment(), Catalog.casual_descriptors(SEED, RADIUS_M, 0.0))
	var recipe_raised := PlanetRecipe.create(RECIPE_ID, "1.8.0", _environment(), Catalog.casual_descriptors(SEED, RADIUS_M, 123.0))
	var kernel_zero = GeoKernel.new()
	var kernel_raised = GeoKernel.new()
	_ok(Composer.new().configure_kernel(kernel_zero, _definition(), recipe_zero, registry), "zero base graph")
	_ok(Composer.new().configure_kernel(kernel_raised, _definition(), recipe_raised, registry), "raised base graph")
	var direction := _direction(18.0, 44.0)
	var zero := _sample(kernel_zero, direction, [FINAL_FIELD])
	var raised := _sample(kernel_raised, direction, [FINAL_FIELD])
	_check(zero.has("sample") and raised.has("sample"), "base comparison samples")
	if zero.has("sample") and raised.has("sample"):
		var z := float(GeoSample.field_value(zero["sample"], FINAL_FIELD, NAN))
		var r := float(GeoSample.field_value(raised["sample"], FINAL_FIELD, NAN))
		_check(_approx(r - z, 123.0, 0.000001), "base layer propagates through macro and valley")


func _test_invalid_graphs_rejected() -> void:
	var definition := _definition()
	var composer = Composer.new()
	var missing_desc := ProviderDescriptor.create("geo-provider/g4-missing-stub", "1.0.0", "1.0.0", ["geo/missing-capability"], ["geo/output-a"], true, {})
	var missing_recipe := PlanetRecipe.create(RECIPE_ID, "3.0.0", _environment(), [missing_desc])
	var missing_registry = Registry.new()
	_ok(missing_registry.register_factory("geo-provider/g4-missing-stub", func(d): return StubProvider.new(d, {"geo/output-a": 1.0})), "register missing stub")
	var missing_result: Dictionary = composer.configure_kernel(GeoKernel.new(), definition, missing_recipe, missing_registry)
	_check(not _success(missing_result), "missing capability graph rejected")
	_check(_composition_cause(missing_result) == "MISSING_GEO_PROVIDER_DEPENDENCY", "missing capability precise cause")

	var cycle_a := ProviderDescriptor.create("geo-provider/g4-cycle-a", "1.0.0", "1.0.0", ["geo/cycle-b"], ["geo/cycle-a"], true, {})
	var cycle_b := ProviderDescriptor.create("geo-provider/g4-cycle-b", "1.0.0", "1.0.0", ["geo/cycle-a"], ["geo/cycle-b"], true, {})
	var cycle_recipe := PlanetRecipe.create(RECIPE_ID, "3.1.0", _environment(), [cycle_b, cycle_a])
	var cycle_registry = Registry.new()
	_ok(cycle_registry.register_factory("geo-provider/g4-cycle-a", func(d): return StubProvider.new(d, {"geo/cycle-a": 1.0})), "register cycle A")
	_ok(cycle_registry.register_factory("geo-provider/g4-cycle-b", func(d): return StubProvider.new(d, {"geo/cycle-b": 1.0})), "register cycle B")
	var cycle_result: Dictionary = composer.configure_kernel(GeoKernel.new(), definition, cycle_recipe, cycle_registry)
	_check(not _success(cycle_result), "cycle rejected")
	_check(_composition_cause(cycle_result) == "GEO_PROVIDER_DEPENDENCY_CYCLE", "cycle precise cause")

	var dup_a := ProviderDescriptor.create("geo-provider/g4-dup-a", "1.0.0", "1.0.0", [], ["geo/duplicate-output"], true, {})
	var dup_b := ProviderDescriptor.create("geo-provider/g4-dup-b", "1.0.0", "1.0.0", [], ["geo/duplicate-output"], true, {})
	var dup_recipe := PlanetRecipe.create(RECIPE_ID, "3.2.0", _environment(), [dup_b, dup_a])
	var dup_registry = Registry.new()
	_ok(dup_registry.register_factory("geo-provider/g4-dup-a", func(d): return StubProvider.new(d, {"geo/duplicate-output": 1.0})), "register duplicate A")
	_ok(dup_registry.register_factory("geo-provider/g4-dup-b", func(d): return StubProvider.new(d, {"geo/duplicate-output": 2.0})), "register duplicate B")
	var dup_result: Dictionary = composer.configure_kernel(GeoKernel.new(), definition, dup_recipe, dup_registry)
	_check(not _success(dup_result), "duplicate output graph rejected")
	_check(_composition_cause(dup_result) == "DUPLICATE_GEO_PROVIDER_OUTPUT", "duplicate output precise cause")

	var unknown_desc := ProviderDescriptor.create("geo-provider/g4-unregistered", "1.0.0", "1.0.0", [], ["geo/unregistered-output"], true, {})
	var unknown_recipe := PlanetRecipe.create(RECIPE_ID, "3.3.0", _environment(), [unknown_desc])
	var unknown_result: Dictionary = composer.configure_kernel(GeoKernel.new(), definition, unknown_recipe, Registry.new())
	_check(not _success(unknown_result), "unregistered provider rejected")
	_check(String(unknown_result.get("error_code", "")) == "GEO_RECIPE_PROVIDER_INSTANTIATION_FAILED", "unregistered provider rejected before kernel")
	_check(String(unknown_result.get("details", {}).get("cause", "")) == "UNREGISTERED_GEO_PROVIDER_FACTORY", "unregistered provider precise cause")

	var mismatch_registry = Registry.new()
	_ok(mismatch_registry.register_factory("geo-provider/g4-unregistered", func(_d): return StubProvider.new(ProviderDescriptor.create("geo-provider/g4-unregistered", "1.0.0", "1.0.1", [], ["geo/unregistered-output"], true, {}), {"geo/unregistered-output": 1.0})), "register mismatching factory")
	var mismatch_result: Dictionary = composer.configure_kernel(GeoKernel.new(), definition, unknown_recipe, mismatch_registry)
	_check(not _success(mismatch_result), "factory descriptor mismatch rejected")
	_check(String(mismatch_result.get("details", {}).get("cause", "")) == "GEO_PROVIDER_FACTORY_DESCRIPTOR_MISMATCH", "factory mismatch precise cause")


func _test_source_boundaries() -> void:
	var kernel_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geo_kernel.gd")
	_check(not kernel_source.is_empty(), "GeoKernel source available")
	for forbidden in ["casual_macro_terrain_layer_provider_v1", "alternative_macro_terrain_provider_v1", "casual_valley_modifier_provider_v1", "planet_type", "EARTH", "ASTEROID", "FLOATING_ISLAND"]:
		_check(not kernel_source.contains(forbidden), "GeoKernel has no G4/world-type special case: %s" % forbidden)

	var composer_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/composition/geo_recipe_composer.gd")
	var registry_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/composition/geo_provider_registry.gd")
	for source in [composer_source, registry_source]:
		for forbidden in ["SurfaceCellKey", "SurfaceLodSelector", "MeshInstance3D", "ImmediateMesh", "Camera3D", "RenderingServer", "EARTH", "MOON", "ASTEROID", "FLOATING_ISLAND", "OCEAN_PLANET"]:
			_check(not source.contains(forbidden), "generic composition core has no forbidden coupling: %s" % forbidden)

	var g3_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
	_check(g3_source.contains("const PROVIDER_ID: String = \"geo-provider/casual-macro-terrain-v1\""), "accepted G3 provider remains present")
	_check(g3_source.contains("const FIELD_SURFACE_HEIGHT_M: String = \"geo/surface-height-m\""), "accepted G3 provider contract not rewritten")


func _sample(kernel, direction: Vector3, fields: Array) -> Dictionary:
	var point := direction.normalized() * RADIUS_M
	var context := Context.create(BODY_ID, "geo-scope/g4", 1000.0, 100.0, 0.0, 0.0, 0.0, false, false, MANIFEST_VERSION)
	var query := SurfaceQuery.create(BODY_ID, [point.x, point.y, point.z], fields)
	var result: Dictionary = kernel.sample_surface(context, query)
	if not _success(result):
		failures.append("sample failed: %s %s" % [result.get("error_code", ""), result.get("details", {})])
		return {}
	return {"sample": result["details"]["sample"]}


func _definition() -> Dictionary:
	return PlanetDefinition.create(BODY_ID, SEED, RECIPE_ID, SHAPE_ID, RADIUS_M, MANIFEST_VERSION)


func _environment() -> Dictionary:
	return PlanetEnvironment.create("planet-environment/g4-neutral", "gravity-model/unspecified", "atmosphere-model/unspecified", "temperature-model/unspecified", "fluid-catalog/none", "weathering-model/none", "material-catalog/unspecified", {})


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _composition_cause(result: Dictionary) -> String:
	if String(result.get("error_code", "")) != "GEO_RECIPE_COMPOSITION_FAILED":
		return ""
	return String(result.get("details", {}).get("cause", ""))


func _approx(a: float, b: float, tolerance: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("G4 provider composition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G4 provider composition: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const GeoFieldBundle = preload("res://scripts/simulation/procedural/contracts/geo_field_bundle.gd")
const FieldId = preload("res://scripts/simulation/procedural/contracts/semantic_field_id.gd")
const ValueType = preload("res://scripts/simulation/procedural/contracts/semantic_field_value_type.gd")
const Domain = preload("res://scripts/simulation/procedural/contracts/semantic_field_domain.gd")
const Descriptor = preload("res://scripts/simulation/procedural/contracts/semantic_field_descriptor.gd")
const Provenance = preload("res://scripts/simulation/procedural/contracts/semantic_field_provenance.gd")
const Query = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const Sample = preload("res://scripts/simulation/procedural/contracts/semantic_field_sample.gd")
const Bundle = preload("res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")

const BODY_ID := "body/g7-fixture"
const FRAME_ID := "body/g7-fixture/fixed"
const POSITION := [6000000.0, 125.0, -250.0]

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_field_id()
	_test_value_types()
	_test_domains()
	_test_descriptor()
	_test_registry()
	_test_query()
	_test_provenance()
	_test_sample_and_bundle()
	_test_g0_field_bundle_compatibility()
	_test_p0_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g7-0-semantic-field-contracts.v1.json"
	_check(FileAccess.file_exists(path), "G7.0 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G7.0 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g7.0-semantic-field-contracts", "G7.0 checkpoint id")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G7.0 candidate status")
		_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G7.0 global revision")
		_check(String(parsed.get("base_branch", "")) == "feature/g6-hydrology-fluid-surface-v0", "G7.0 stacked on G6")
		_check(String(parsed.get("base_commit", "")) == "303d6830593cd3b4fbb20641daa90d6bef5d7ada", "G7.0 exact accepted/P0-clean G6 head")
		var compatibility: Dictionary = parsed.get("compatibility", {})
		_check(bool(compatibility.get("existing_geo_field_ids_preserved", false)), "existing geo field ids preserved")
		_check(not bool(compatibility.get("geo_field_bundle_replaced", true)), "G0 GeoFieldBundle is not replaced")
		_check(not bool(compatibility.get("geo_sample_replaced", true)), "G0 GeoSample is not replaced")
		_check(not bool(compatibility.get("geo_kernel_changed", true)), "GeoKernel not changed by G7.0")
		var invariants: Dictionary = parsed.get("invariants", {})
		for key in [
			"semantic_field_id_depends_on_surface_cell", "semantic_field_id_depends_on_lod",
			"semantic_field_id_depends_on_authority_region", "semantic_field_id_depends_on_interest_region",
			"semantic_field_query_is_universal_world_query", "semantic_field_query_has_renderer_state",
			"semantic_field_query_has_network_state", "g7_owns_material_ontology", "g7_owns_scheduler_cache",
			"g7_owns_persistence", "g7_owns_network_replication",
		]:
			_check(not bool(invariants.get(key, true)), "P0 invariant false: %s" % key)
		var deferred: Dictionary = parsed.get("deferred", {})
		_check(String(deferred.get("g3_g5_g6_adapters", "")) == "G7.1", "upstream adapters deferred to G7.1")
		_check(String(deferred.get("scheduler_cache_execution", "")) == "G12", "scheduler/cache remains G12")


func _test_field_id() -> void:
	for field_id in Registry.field_ids():
		_ok(FieldId.validate(field_id), "registered field id %s" % field_id)
	_check(not _success(FieldId.validate("surface-height-m")), "unqualified field id rejected")
	_check(not _success(FieldId.validate("world-feature/river/example")), "feature identity rejected as field id")
	_check(not _success(FieldId.validate("fluid-region/water/example")), "fluid identity rejected as field id")
	_check(not _success(FieldId.validate("authority-region/example")), "authority identity rejected as field id")
	var normalized := FieldId.normalize_many([Registry.SLOPE, Registry.SURFACE_HEIGHT_M, Registry.SLOPE])
	_ok(normalized, "field id set normalizes")
	if _success(normalized):
		_check(normalized["details"]["field_ids"] == [Registry.SLOPE, Registry.SURFACE_HEIGHT_M], "field id set sorted unique")


func _test_value_types() -> void:
	for value_type in ValueType.SUPPORTED:
		_ok(ValueType.validate(value_type), "value type %s" % value_type)
	_ok(ValueType.validate_value(ValueType.SCALAR_FLOAT, 12.5), "float accepts finite float")
	_ok(ValueType.validate_value(ValueType.SCALAR_FLOAT, 12), "float accepts integer numeric")
	_check(not _success(ValueType.validate_value(ValueType.SCALAR_FLOAT, INF)), "float rejects infinity")
	_ok(ValueType.validate_value(ValueType.SCALAR_INT, 12), "integer accepts JSON int")
	_check(not _success(ValueType.validate_value(ValueType.SCALAR_INT, 12.5)), "integer rejects fraction")
	_ok(ValueType.validate_value(ValueType.BOOLEAN, true), "boolean accepts bool")
	_check(not _success(ValueType.validate_value(ValueType.BOOLEAN, 1)), "boolean rejects numeric")
	_ok(ValueType.validate_value(ValueType.CANONICAL_ID, "world-feature/river/example"), "canonical id value accepted")
	_check(not _success(ValueType.validate_value(ValueType.CANONICAL_ID, "Example")), "canonical id value strict")
	_ok(ValueType.validate_value(ValueType.VECTOR3_FLOAT, [1.0, 2.0, 3.0]), "vector3 value accepted")
	_check(not _success(ValueType.validate_value(ValueType.VECTOR3_FLOAT, [1.0, 2.0])), "vector3 shape strict")


func _test_domains() -> void:
	_ok(Domain.validate(Domain.BODY_SURFACE_POINT), "surface semantic domain")
	_ok(Domain.validate(Domain.BODY_VOLUME_POINT), "volume semantic domain")
	_check(not _success(Domain.validate("surface-cell/lod")), "representation domain rejected")
	_check(not _success(Domain.validate("authority-region/owner")), "authority domain rejected")


func _test_descriptor() -> void:
	var descriptor := Descriptor.create(Registry.SURFACE_HEIGHT_M, ValueType.SCALAR_FLOAT, Domain.BODY_SURFACE_POINT, "m", "1.0.0", {"availability": Registry.UPSTREAM_ACCEPTED})
	_ok(Descriptor.validate(descriptor), "descriptor validates")
	var repeated := Descriptor.create(Registry.SURFACE_HEIGHT_M, ValueType.SCALAR_FLOAT, Domain.BODY_SURFACE_POINT, "m", "1.0.0", {"availability": Registry.UPSTREAM_ACCEPTED})
	_check(String(descriptor["checksum"]) == String(repeated["checksum"]), "descriptor deterministic")
	var tampered := descriptor.duplicate(true)
	tampered["unit"] = "km"
	_check(not _success(Descriptor.validate(tampered)), "descriptor checksum catches tamper")
	var extra := descriptor.duplicate(true)
	extra["lod"] = 3
	extra["checksum"] = GeoUtils.compute_checksum(extra)
	_check(String(Descriptor.validate(extra).get("error_code", "")) == "UNEXPECTED_FIELD", "descriptor rejects LOD field by exact schema")
	var wrong_namespace := Descriptor.create("material/rock", ValueType.SCALAR_FLOAT, Domain.BODY_SURFACE_POINT, "ratio")
	_check(not _success(Descriptor.validate(wrong_namespace)), "descriptor rejects material id as field identity")


func _test_registry() -> void:
	var validation := Registry.validate_registry()
	_ok(validation, "registry validates")
	_check(Registry.field_ids().size() == 13, "registry has 13 G7.0 vocabulary entries")
	_check(GeoUtils.is_lower_hex_64(Registry.manifest_hash()), "registry manifest hash canonical")
	_check(Registry.field_ids() == Registry.field_ids().duplicate(), "registry field ids stable")
	for field_id in Registry.field_ids():
		var descriptor := Registry.descriptor(field_id)
		_ok(Descriptor.validate(descriptor), "registry descriptor %s" % field_id)
		_check(String(descriptor["field_id"]) == field_id, "registry key matches descriptor %s" % field_id)
		_check(String(descriptor["domain"]) == Domain.BODY_SURFACE_POINT, "G7.0 registry field domain is surface point")
		_check(String(descriptor["value_type"]) == ValueType.SCALAR_FLOAT, "G7.0 registry field value type scalar float")
		_check(not bool(descriptor["metadata"].get("representation_owned", true)), "registry field not representation-owned")
		_check(not descriptor["metadata"].has("material_definition_id"), "registry does not invent MaterialDefinitionId")
	for field_id in [Registry.BASE_SURFACE_HEIGHT_M, Registry.MACRO_SURFACE_HEIGHT_M, Registry.SURFACE_HEIGHT_M]:
		_check(String(Registry.descriptor(field_id)["metadata"]["availability"]) == Registry.UPSTREAM_ACCEPTED, "upstream field marked accepted %s" % field_id)
	for field_id in [Registry.SLOPE, Registry.CURVATURE, Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M, Registry.DRAINAGE_POTENTIAL, Registry.CONTINENTALNESS, Registry.TEMPERATURE_BASELINE, Registry.MOISTURE_BASELINE]:
		_check(String(Registry.descriptor(field_id)["metadata"]["availability"]) == Registry.VOCABULARY_ONLY, "future field marked vocabulary-only %s" % field_id)


func _test_query() -> void:
	var query := Query.create(BODY_ID, FRAME_ID, POSITION, [Registry.RIVER_DISTANCE_M, Registry.SURFACE_HEIGHT_M, Registry.RIVER_DISTANCE_M])
	_ok(Query.validate(query), "semantic field query validates")
	_check(query["requested_field_ids"] == [Registry.RIVER_DISTANCE_M, Registry.SURFACE_HEIGHT_M], "query fields canonical sorted unique")
	_check(not query.has("surface_cell_key"), "query has no SurfaceCellKey")
	_check(not query.has("lod"), "query has no LOD")
	_check(not query.has("authority_region_id"), "query has no authority region")
	_check(not query.has("interest_region_id"), "query has no interest region")
	_check(not query.has("camera"), "query has no camera state")
	var extra := query.duplicate(true)
	extra["lod"] = 9
	extra["checksum"] = GeoUtils.compute_checksum(extra)
	_check(String(Query.validate(extra).get("error_code", "")) == "UNEXPECTED_FIELD", "query exact schema rejects LOD injection")
	var bad_field := Query.create(BODY_ID, FRAME_ID, POSITION, ["material/iron"])
	_check(not _success(Query.validate(bad_field)), "query rejects foreign field namespace")


func _test_provenance() -> void:
	var config_hash := GeoUtils.payload_hash({"seed": 7, "version": "fixture"})
	var refs := [
		Provenance.source_ref("source-kind/world-feature", "world-feature/river/fixture"),
		Provenance.source_ref("source-kind/fluid-region", "fluid-region/water/fixture"),
	]
	var provenance := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [Registry.SURFACE_HEIGHT_M], refs, config_hash, {"adapter": "fixture"})
	_ok(Provenance.validate(provenance), "provenance validates")
	_check(provenance["source_refs"].size() == 2, "provenance preserves generic upstream refs")
	_check(String(provenance["configuration_hash"]) == config_hash, "provenance pins config hash")
	var repeated := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [Registry.SURFACE_HEIGHT_M], refs, config_hash, {"adapter": "fixture"})
	_check(String(provenance["checksum"]) == String(repeated["checksum"]), "provenance deterministic")
	var bad := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", ["material/iron"], refs, config_hash)
	_check(not _success(Provenance.validate(bad)), "provenance rejects foreign source field namespace")
	var duplicate_refs := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [], [refs[0], refs[0]], config_hash)
	_check(not _success(Provenance.validate(duplicate_refs)), "provenance rejects duplicate source refs")


func _test_sample_and_bundle() -> void:
	var query := Query.create(BODY_ID, FRAME_ID, POSITION, [Registry.SLOPE, Registry.SURFACE_HEIGHT_M])
	var provenance := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [], [], GeoUtils.payload_hash({"fixture": 1}))
	var surface_sample := Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, 42.25, provenance)
	var slope_sample := Sample.create(Registry.SLOPE, BODY_ID, FRAME_ID, POSITION, 0.125, provenance)
	_ok(Sample.validate(surface_sample), "surface sample validates")
	_ok(Sample.validate_against_descriptor(surface_sample, Registry.descriptor(Registry.SURFACE_HEIGHT_M)), "surface sample matches descriptor")
	_ok(Sample.validate_against_descriptor(slope_sample, Registry.descriptor(Registry.SLOPE)), "slope sample matches descriptor")
	var wrong_type := Sample.create(Registry.SLOPE, BODY_ID, FRAME_ID, POSITION, "steep", provenance)
	_check(_success(Sample.validate(wrong_type)), "generic sample permits JSON-safe value before descriptor binding")
	_check(not _success(Sample.validate_against_descriptor(wrong_type, Registry.descriptor(Registry.SLOPE))), "descriptor binding rejects wrong value type")
	var bundle := Bundle.create(query, {Registry.SURFACE_HEIGHT_M: surface_sample, Registry.SLOPE: slope_sample})
	_ok(Bundle.validate(bundle), "semantic field bundle validates")
	var repeated := Bundle.create(query, {Registry.SLOPE: slope_sample, Registry.SURFACE_HEIGHT_M: surface_sample})
	_check(String(bundle["checksum"]) == String(repeated["checksum"]), "bundle deterministic independent of insertion order")
	var missing := Bundle.create(query, {Registry.SURFACE_HEIGHT_M: surface_sample})
	_check(String(Bundle.validate(missing).get("error_code", "")) == "SEMANTIC_FIELD_BUNDLE_COVERAGE_MISMATCH", "bundle requires exact requested coverage")
	var moved_sample := slope_sample.duplicate(true)
	moved_sample["body_fixed_position_m"] = [6000001.0, 125.0, -250.0]
	moved_sample["checksum"] = GeoUtils.compute_checksum(moved_sample)
	var moved := Bundle.create(query, {Registry.SURFACE_HEIGHT_M: surface_sample, Registry.SLOPE: moved_sample})
	_check(String(Bundle.validate(moved).get("error_code", "")) == "SEMANTIC_FIELD_BUNDLE_SAMPLE_POSITION_MISMATCH", "bundle enforces one canonical query position")


func _test_g0_field_bundle_compatibility() -> void:
	var old_bundle := GeoFieldBundle.create(
		{Registry.BASE_SURFACE_HEIGHT_M: 0.0, Registry.MACRO_SURFACE_HEIGHT_M: 250.0, Registry.SURFACE_HEIGHT_M: 245.0},
		{Registry.BASE_SURFACE_HEIGHT_M: "geo-provider/base-surface-v1", Registry.MACRO_SURFACE_HEIGHT_M: "geo-provider/casual-macro-terrain-layer-v1", Registry.SURFACE_HEIGHT_M: "geo-provider/casual-valley-modifier-v1"}
	)
	_ok(GeoFieldBundle.validate(old_bundle), "G0 GeoFieldBundle remains valid with registered field ids")
	_check(old_bundle["values"].has(Registry.SURFACE_HEIGHT_M), "G7 registry preserves existing G0/G3/G4 field key")


func _test_p0_source_boundaries() -> void:
	var contract_paths := [
		"res://scripts/simulation/procedural/contracts/semantic_field_id.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_descriptor.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_query.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_sample.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd",
		"res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd",
	]
	var joined := ""
	for path in contract_paths:
		_check(FileAccess.file_exists(path), "source exists %s" % path)
		joined += FileAccess.get_file_as_string(path)
	for forbidden in ["SurfaceCellKey", "surface_cell_key.gd", "SurfaceLodSelector", "AuthorityRegion", "InterestRegion", "WorldAddress", "MaterialDefinitionId", "material_definition_id", "Camera3D", "ImmediateMesh", "ENetMultiplayerPeer", "FileAccess.open("]:
		_check(joined.find(forbidden) < 0, "core G7.0 source excludes %s" % forbidden)
	_check(joined.find("WorldQuery") < 0, "G7.0 does not implement universal WorldQuery")


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s (%s)" % [label, String(result.get("error_code", ""))])


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("G7.0 Semantic Field Contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("G7.0 FAIL: %s" % failure)
	print("G7.0 Semantic Field Contracts: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)

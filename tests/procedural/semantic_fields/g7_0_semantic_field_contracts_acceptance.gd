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
	_test_manifest_and_registry()
	_test_contracts()
	_test_query_sample_bundle()
	_test_compatibility_and_p0()
	_finish()

func _test_manifest_and_registry() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g7-0-semantic-field-contracts.v1.json"))
	_check(parsed is Dictionary, "manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g7.0-semantic-field-contracts", "checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "candidate status")
		_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "global revision")
		_check(String(parsed.get("base_commit", "")) == "303d6830593cd3b4fbb20641daa90d6bef5d7ada", "exact G6 base")
		var compatibility: Dictionary = parsed.get("compatibility", {})
		_check(bool(compatibility.get("existing_geo_field_ids_preserved", false)), "existing field ids preserved")
		_check(not bool(compatibility.get("geo_field_bundle_replaced", true)), "GeoFieldBundle preserved")
		_check(not bool(compatibility.get("geo_sample_replaced", true)), "GeoSample preserved")
		_check(not bool(compatibility.get("geo_kernel_changed", true)), "GeoKernel unchanged")
		for key in parsed.get("invariants", {}).keys():
			_check(not bool(parsed["invariants"][key]), "P0 invariant false: %s" % key)
	_ok(Registry.validate_registry(), "registry validates")
	_check(Registry.field_ids().size() == 13, "13 registry fields")
	_check(GeoUtils.is_lower_hex_64(Registry.manifest_hash()), "registry manifest hash")
	for field_id in Registry.field_ids():
		_ok(FieldId.validate(field_id), "field id %s" % field_id)
		var descriptor := Registry.descriptor(field_id)
		_ok(Descriptor.validate(descriptor), "descriptor %s" % field_id)
		_check(String(descriptor["field_id"]) == field_id, "registry key binds descriptor")
		_check(String(descriptor["domain"]) == Domain.BODY_SURFACE_POINT, "surface-point domain")
		_check(String(descriptor["value_type"]) == ValueType.SCALAR_FLOAT, "scalar-float type")
		_check(not bool(descriptor["metadata"].get("representation_owned", true)), "not representation owned")
		_check(not descriptor["metadata"].has("material_definition_id"), "no invented material identity")
	for field_id in [Registry.BASE_SURFACE_HEIGHT_M, Registry.MACRO_SURFACE_HEIGHT_M, Registry.SURFACE_HEIGHT_M]:
		_check(String(Registry.descriptor(field_id)["metadata"]["availability"]) == Registry.UPSTREAM_ACCEPTED, "accepted upstream field")
	for field_id in [Registry.VALLEY_INFLUENCE, Registry.RIVER_DISTANCE_M, Registry.RIVER_WIDTH_M, Registry.FLUID_SURFACE_DISTANCE_M]:
		_check(String(Registry.descriptor(field_id)["metadata"]["availability"]) in ["VOCABULARY_ONLY_G7_0", "ADAPTER_AVAILABLE_G7_1"], "planned adapter field availability")
	for field_id in [Registry.SLOPE, Registry.CURVATURE, Registry.DRAINAGE_POTENTIAL, Registry.CONTINENTALNESS, Registry.TEMPERATURE_BASELINE, Registry.MOISTURE_BASELINE]:
		_check(String(Registry.descriptor(field_id)["metadata"]["availability"]) == Registry.VOCABULARY_ONLY, "vocabulary-only field")

func _test_contracts() -> void:
	_check(not _success(FieldId.validate("surface-height-m")), "unqualified field rejected")
	_check(not _success(FieldId.validate("world-feature/river/example")), "feature id is not field id")
	var normalized := FieldId.normalize_many([Registry.SLOPE, Registry.SURFACE_HEIGHT_M, Registry.SLOPE])
	_ok(normalized, "field set normalizes")
	if _success(normalized):
		_check(normalized["details"]["field_ids"] == [Registry.SLOPE, Registry.SURFACE_HEIGHT_M], "field set sorted unique")
	for value_type in ValueType.SUPPORTED:
		_ok(ValueType.validate(value_type), "supported value type")
	_ok(ValueType.validate_value(ValueType.SCALAR_FLOAT, 12.5), "float value")
	_check(not _success(ValueType.validate_value(ValueType.SCALAR_FLOAT, INF)), "non-finite rejected")
	_ok(ValueType.validate_value(ValueType.SCALAR_INT, 12), "int value")
	_check(not _success(ValueType.validate_value(ValueType.SCALAR_INT, 12.5)), "fraction rejected as int")
	_ok(ValueType.validate_value(ValueType.BOOLEAN, true), "bool value")
	_ok(ValueType.validate_value(ValueType.CANONICAL_ID, "world-feature/river/example"), "canonical-id value")
	_ok(ValueType.validate_value(ValueType.VECTOR3_FLOAT, [1.0, 2.0, 3.0]), "vector3 value")
	_ok(Domain.validate(Domain.BODY_SURFACE_POINT), "surface domain")
	_ok(Domain.validate(Domain.BODY_VOLUME_POINT), "volume domain")
	_check(not _success(Domain.validate("surface-cell/lod")), "representation domain rejected")
	var descriptor := Descriptor.create(Registry.SURFACE_HEIGHT_M, ValueType.SCALAR_FLOAT, Domain.BODY_SURFACE_POINT, "m")
	_ok(Descriptor.validate(descriptor), "descriptor validates")
	var extra := descriptor.duplicate(true)
	extra["lod"] = 3
	extra["checksum"] = GeoUtils.compute_checksum(extra)
	_check(String(Descriptor.validate(extra).get("error_code", "")) == "UNEXPECTED_FIELD", "descriptor exact schema")
	var config_hash := GeoUtils.payload_hash({"seed": 7})
	var refs := [Provenance.source_ref("source-kind/world-feature", "world-feature/river/fixture"), Provenance.source_ref("source-kind/fluid-region", "fluid-region/water/fixture")]
	var provenance := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [Registry.SURFACE_HEIGHT_M], refs, config_hash)
	_ok(Provenance.validate(provenance), "provenance validates")
	_check(String(provenance["configuration_hash"]) == config_hash, "provenance config hash")
	var duplicate_refs := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [], [refs[0], refs[0]], config_hash)
	_check(not _success(Provenance.validate(duplicate_refs)), "duplicate source refs rejected")

func _test_query_sample_bundle() -> void:
	var query := Query.create(BODY_ID, FRAME_ID, POSITION, [Registry.RIVER_DISTANCE_M, Registry.SURFACE_HEIGHT_M, Registry.RIVER_DISTANCE_M])
	_ok(Query.validate(query), "query validates")
	_check(query["requested_field_ids"] == [Registry.RIVER_DISTANCE_M, Registry.SURFACE_HEIGHT_M], "query fields sorted unique")
	for forbidden_field in ["surface_cell_key", "lod", "authority_region_id", "interest_region_id", "camera", "renderer", "network"]:
		_check(not query.has(forbidden_field), "query excludes %s" % forbidden_field)
	var with_lod := query.duplicate(true)
	with_lod["lod"] = 9
	with_lod["checksum"] = GeoUtils.compute_checksum(with_lod)
	_check(String(Query.validate(with_lod).get("error_code", "")) == "UNEXPECTED_FIELD", "LOD injection rejected")
	var provenance := Provenance.create("semantic-field-producer/g7-fixture", "1.0.0", [], [], GeoUtils.payload_hash({"fixture": 1}))
	var river_sample := Sample.create(Registry.RIVER_DISTANCE_M, BODY_ID, FRAME_ID, POSITION, 125.0, provenance)
	var height_sample := Sample.create(Registry.SURFACE_HEIGHT_M, BODY_ID, FRAME_ID, POSITION, 42.25, provenance)
	_ok(Sample.validate_against_descriptor(river_sample, Registry.descriptor(Registry.RIVER_DISTANCE_M)), "river sample typed")
	_ok(Sample.validate_against_descriptor(height_sample, Registry.descriptor(Registry.SURFACE_HEIGHT_M)), "height sample typed")
	var bundle := Bundle.create(query, {Registry.SURFACE_HEIGHT_M: height_sample, Registry.RIVER_DISTANCE_M: river_sample})
	_ok(Bundle.validate(bundle), "bundle validates")
	var repeated := Bundle.create(query, {Registry.RIVER_DISTANCE_M: river_sample, Registry.SURFACE_HEIGHT_M: height_sample})
	_check(String(bundle["checksum"]) == String(repeated["checksum"]), "bundle insertion-order deterministic")
	var missing := Bundle.create(query, {Registry.SURFACE_HEIGHT_M: height_sample})
	_check(String(Bundle.validate(missing).get("error_code", "")) == "SEMANTIC_FIELD_BUNDLE_COVERAGE_MISMATCH", "bundle exact coverage")

func _test_compatibility_and_p0() -> void:
	var old_bundle := GeoFieldBundle.create(
		{Registry.BASE_SURFACE_HEIGHT_M: 0.0, Registry.MACRO_SURFACE_HEIGHT_M: 250.0, Registry.SURFACE_HEIGHT_M: 245.0},
		{Registry.BASE_SURFACE_HEIGHT_M: "geo-provider/base-surface-v1", Registry.MACRO_SURFACE_HEIGHT_M: "geo-provider/casual-macro-terrain-layer-v1", Registry.SURFACE_HEIGHT_M: "geo-provider/casual-valley-modifier-v1"}
	)
	_ok(GeoFieldBundle.validate(old_bundle), "G0 GeoFieldBundle compatibility")
	var joined := ""
	for path in [
		"res://scripts/simulation/procedural/contracts/semantic_field_id.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_descriptor.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_query.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_sample.gd",
		"res://scripts/simulation/procedural/contracts/semantic_field_bundle.gd",
		"res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd",
	]:
		joined += FileAccess.get_file_as_string(path)
	for forbidden in ["SurfaceCellKey", "surface_cell_key.gd", "SurfaceLodSelector", "AuthorityRegion", "InterestRegion", "WorldAddress", "MaterialDefinitionId", "material_definition_id", "Camera3D", "ImmediateMesh", "ENetMultiplayerPeer", "FileAccess.open(", "WorldQuery"]:
		_check(joined.find(forbidden) < 0, "core source excludes %s" % forbidden)

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

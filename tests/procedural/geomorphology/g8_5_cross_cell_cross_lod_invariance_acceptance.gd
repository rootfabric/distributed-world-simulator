extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SemanticQuery = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Composer = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_composer_v1.gd")
const G3Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g3_surface_semantic_field_adapter_v1.gd")
const G5Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g5_feature_semantic_field_adapter_v1.gd")
const G6Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g6_fluid_semantic_field_adapter_v1.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchor = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const RiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")
const Profile = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_profile.gd")
const Deformation = preload("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
const ErosionDeposition = preload("res://scripts/simulation/procedural/geomorphology/erosion_deposition_baseline_v1.gd")

const LODS: Array[int] = [2, 4, 8, 12]
const INPUT_FIELDS: Array[String] = [
	Registry.SURFACE_HEIGHT_M,
	Registry.VALLEY_INFLUENCE,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
]
const PROOF_SEED := 20260811085
const VALLEY_STABLE_KEY := "feature-key/g8-5-invariance-valley"
const VALLEY_RADIUS_M := 1150000.0

var assertions := 0
var failures: Array[String] = []
var macro_provider
var feature_graph
var compiled_river: Dictionary = {}
var addressing
var profile: Dictionary = {}


func _init() -> void:
	_test_manifest_and_parent()
	if _prepare_sources():
		_test_query_boundary()
		_test_same_world_point_across_lod_and_cells()
		_test_query_order_invariance()
		_test_px_pz_seam_representation_boundary()
		_test_ownership_boundary()
	_finish()


func _test_manifest_and_parent() -> void:
	var g84 = JSON.parse_string(FileAccess.get_file_as_string("res://validation/g8-4-erosion-deposition-validation.json"))
	_check(g84 is Dictionary, "G8.4 validation parses")
	if g84 is Dictionary:
		_check(String(g84.get("decision", "")) == "ACCEPTED", "G8.4 parent accepted")
		_check(String(g84.get("automated_evidence", {}).get("tested_head", "")) == "82cc31429f2bf2ea419bf1b50159838eea51c727", "G8.4 accepted tested head")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://config/procedural/g8-5-cross-cell-cross-lod-geomorphology-invariance.v1.json"))
	_check(parsed is Dictionary, "G8.5 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g8.5-cross-cell-cross-lod-geomorphology-invariance", "G8.5 checkpoint")
		_check(String(parsed.get("status", "")) in ["IMPLEMENTED_CANDIDATE", "ACCEPTED"], "G8.5 status supports candidate to accepted transition")
		var lods: Array[int] = []
		for value in parsed.get("proof_lod_levels", []):
			lods.append(int(value))
		_check(lods == LODS, "G8.5 proof LOD levels pinned")
		var bounds: Dictionary = parsed.get("architecture_boundaries", {})
		_check(not bool(bounds.get("surface_cell_is_geomorphology_identity", true)), "SurfaceCellKey excluded from geomorphology identity")
		_check(not bool(bounds.get("lod_is_geomorphology_identity", true)), "LOD excluded from geomorphology identity")
		_check(not bool(bounds.get("cube_face_is_geomorphology_identity", true)), "cube face excluded from geomorphology identity")


func _prepare_sources() -> bool:
	macro_provider = MacroProvider.new(PROOF_SEED, Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	feature_graph = FeatureGraph.new()
	var configured: Dictionary = feature_graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID)
	_ok(configured, "G8.5 FeatureGraph config")
	if not _success(configured):
		return false
	var added: Dictionary = feature_graph.add_feature(_valley_feature())
	_ok(added, "G8.5 valley feature added")
	if not _success(added):
		return false
	var sealed: Dictionary = feature_graph.seal()
	_ok(sealed, "G8.5 FeatureGraph sealed")
	if not _success(sealed):
		return false
	compiled_river = RiverProvider.compile(Fixture.river())
	_ok(compiled_river, "G8.5 cross-cell river compile")
	if not _success(compiled_river):
		return false
	addressing = CubeSphereAddressing.new()
	profile = Profile.create("geomorphology-profile/g8-5-invariance")
	_ok(Profile.validate(profile), "G8.5 profile validates")
	var points: Array = compiled_river.get("details", {}).get("river_spline", {}).get("points_m", [])
	_check(points.size() >= 4, "G8.5 river spline has proof points")
	return points.size() >= 4


func _test_query_boundary() -> void:
	var point: Array = _proof_point()
	var query := SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, INPUT_FIELDS)
	_ok(SemanticQuery.validate(query), "G8.5 canonical semantic query validates")
	_check(not query.has("surface_cell"), "query has no surface_cell")
	_check(not query.has("surface_cell_key"), "query has no surface_cell_key")
	_check(not query.has("lod"), "query has no LOD")
	_check(not query.has("face"), "query has no cube face")
	_check(not query.has("representation"), "query has no representation identity")


func _test_same_world_point_across_lod_and_cells() -> void:
	var point: Array = _proof_point()
	var baseline_composed := _compose_at(point, INPUT_FIELDS)
	_ok(baseline_composed, "G8.5 baseline semantic composition")
	if not _success(baseline_composed):
		return
	var baseline_bundle: Dictionary = baseline_composed["details"]["bundle"]
	var baseline_geomorph := ErosionDeposition.apply(baseline_bundle, profile)
	_ok(baseline_geomorph, "G8.5 baseline geomorphology")
	if not _success(baseline_geomorph):
		return
	var baseline_deformation: Dictionary = baseline_geomorph["details"]["deformation"]
	var cell_tokens: Dictionary = {}

	for lod in LODS:
		var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, point, lod)
		_ok(addressed, "proof point addressed at LOD %d" % lod)
		if not _success(addressed):
			continue
		var cell: Dictionary = addressed["details"]["cell"]
		_ok(SurfaceCellKey.validate(cell), "SurfaceCellKey validates at LOD %d" % lod)
		cell_tokens[SurfaceCellKey.identity_token(cell)] = true

		var replay_composed := _compose_at(point, INPUT_FIELDS)
		_ok(replay_composed, "semantic replay at LOD %d" % lod)
		if not _success(replay_composed):
			continue
		var replay_bundle: Dictionary = replay_composed["details"]["bundle"]
		var replay_geomorph := ErosionDeposition.apply(replay_bundle, profile)
		_ok(replay_geomorph, "geomorphology replay at LOD %d" % lod)
		if not _success(replay_geomorph):
			continue
		var replay_deformation: Dictionary = replay_geomorph["details"]["deformation"]
		_check(String(replay_bundle["query"]["checksum"]) == String(baseline_bundle["query"]["checksum"]), "query checksum independent of LOD %d" % lod)
		_check(String(replay_bundle["checksum"]) == String(baseline_bundle["checksum"]), "bundle checksum independent of LOD %d" % lod)
		_check(String(replay_deformation["checksum"]) == String(baseline_deformation["checksum"]), "deformation checksum independent of LOD %d" % lod)
		_check(String(replay_deformation["source_semantic_bundle_checksum"]) == String(baseline_bundle["checksum"]), "deformation binds canonical bundle at LOD %d" % lod)
		_check(String(replay_deformation["profile_checksum"]) == String(profile["checksum"]), "deformation binds canonical profile at LOD %d" % lod)
		for component in Deformation.COMPONENT_FIELDS:
			_check(_near(float(replay_deformation["component_deltas_m"][component]), float(baseline_deformation["component_deltas_m"][component])), "%s independent of LOD %d" % [component, lod])

	_check(cell_tokens.size() == LODS.size(), "same world point maps to distinct representation cells across proof LODs")

	var actual: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, point, 8)
	_ok(actual, "actual LOD8 representation cell available")
	if _success(actual):
		var actual_cell: Dictionary = actual["details"]["cell"]
		var side := 1 << 8
		var alternate_cell := SurfaceCellKey.create(Fixture.BODY_ID, String(actual_cell["face"]), 8, (int(actual_cell["x"]) + 1) % side, int(actual_cell["y"]))
		_ok(SurfaceCellKey.validate(alternate_cell), "alternate external SurfaceCellKey validates")
		_check(SurfaceCellKey.identity_token(actual_cell) != SurfaceCellKey.identity_token(alternate_cell), "alternate cell identity differs")
		var alternate_face := "PZ" if String(actual_cell["face"]) != "PZ" else "PX"
		var alternate_face_cell := SurfaceCellKey.create(Fixture.BODY_ID, alternate_face, 8, int(actual_cell["x"]), int(actual_cell["y"]))
		_ok(SurfaceCellKey.validate(alternate_face_cell), "alternate external cube-face cell validates")
		_check(SurfaceCellKey.identity_token(actual_cell) != SurfaceCellKey.identity_token(alternate_face_cell), "alternate cube-face identity differs")
		var external_replay := _compose_at(point, INPUT_FIELDS)
		_ok(external_replay, "canonical semantics ignore external cell/face labels")
		if _success(external_replay):
			var external_geomorph := ErosionDeposition.apply(external_replay["details"]["bundle"], profile)
			_ok(external_geomorph, "geomorphology ignores external cell/face labels")
			if _success(external_geomorph):
				_check(String(external_geomorph["details"]["deformation"]["checksum"]) == String(baseline_deformation["checksum"]), "external SurfaceCellKey/cube face cannot perturb deformation")


func _test_query_order_invariance() -> void:
	var point: Array = _proof_point()
	var forward_fields: Array = INPUT_FIELDS.duplicate()
	var reverse_fields: Array = INPUT_FIELDS.duplicate()
	reverse_fields.reverse()
	var forward_query := SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, forward_fields)
	var reverse_query := SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, reverse_fields)
	_check(forward_query["requested_field_ids"] == reverse_query["requested_field_ids"], "query field order canonicalized")
	_check(String(forward_query["checksum"]) == String(reverse_query["checksum"]), "query checksum independent of input field order")
	var forward := _compose_query(forward_query)
	var reverse := _compose_query(reverse_query)
	_ok(forward, "forward-order composition")
	_ok(reverse, "reverse-order composition")
	if _success(forward) and _success(reverse):
		_check(String(forward["details"]["bundle"]["checksum"]) == String(reverse["details"]["bundle"]["checksum"]), "bundle independent of query field order")
		var forward_geomorph := ErosionDeposition.apply(forward["details"]["bundle"], profile)
		var reverse_geomorph := ErosionDeposition.apply(reverse["details"]["bundle"], profile)
		_ok(forward_geomorph, "forward geomorphology")
		_ok(reverse_geomorph, "reverse geomorphology")
		if _success(forward_geomorph) and _success(reverse_geomorph):
			_check(String(forward_geomorph["details"]["deformation"]["checksum"]) == String(reverse_geomorph["details"]["deformation"]["checksum"]), "deformation independent of query field order")


func _test_px_pz_seam_representation_boundary() -> void:
	var faces: Dictionary = {}
	var cells: Dictionary = {}
	for point_value in compiled_river["details"]["river_spline"]["points_m"]:
		var point: Array = point_value
		var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, point, 8)
		_ok(addressed, "river centerline point addressed at seam proof LOD")
		if not _success(addressed):
			continue
		var cell: Dictionary = addressed["details"]["cell"]
		faces[String(cell["face"])] = true
		cells[SurfaceCellKey.identity_token(cell)] = true
		var composed := _compose_at(point, INPUT_FIELDS)
		_ok(composed, "real upstream bundle across seam")
		if not _success(composed):
			continue
		var bundle: Dictionary = composed["details"]["bundle"]
		_check(absf(float(bundle["samples"][Registry.RIVER_DISTANCE_M]["value"])) <= 0.001, "centerline river distance remains zero across representation seam")
		var geomorph := ErosionDeposition.apply(bundle, profile)
		_ok(geomorph, "full geomorphology evaluates across seam")
		if _success(geomorph):
			_ok(Deformation.validate_against_profile(geomorph["details"]["deformation"], profile), "seam-side deformation validates")
	_check(cells.size() >= 2, "canonical river spans multiple representation cells")
	_check(faces.has("PX") and faces.has("PZ"), "canonical river crosses PX/PZ cube-sphere seam")


func _test_ownership_boundary() -> void:
	var geomorph_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/erosion_deposition_baseline_v1.gd")
	var deformation_source := FileAccess.get_file_as_string("res://scripts/simulation/procedural/geomorphology/geomorphology_deformation_sample.gd")
	for forbidden in ["SurfaceCellKey", "surface_cell_key", "CubeSphereAddressing", "Camera3D", "AuthorityRegion", "InterestRegion", "ENetMultiplayerPeer"]:
		_check(geomorph_source.find(forbidden) < 0, "G8.4 geomorphology source excludes %s" % forbidden)
		_check(deformation_source.find(forbidden) < 0, "deformation contract excludes %s" % forbidden)
	_check(geomorph_source.find("lod") < 0 and geomorph_source.find("LOD") < 0, "G8.4 geomorphology source excludes LOD")
	_check(deformation_source.find("lod") < 0 and deformation_source.find("LOD") < 0, "deformation contract excludes LOD")


func _compose_at(position: Array, field_ids: Array) -> Dictionary:
	var query := SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, position, field_ids)
	return _compose_query(query)


func _compose_query(query: Dictionary) -> Dictionary:
	var g3 := G3Adapter.sample(query, macro_provider)
	var g5 := G5Adapter.sample(query, feature_graph)
	var g6 := G6Adapter.sample(query, [compiled_river])
	return Composer.compose(query, [g3, g5, g6])


func _proof_point() -> Array:
	return compiled_river["details"]["river_spline"]["points_m"][3]


func _valley_feature() -> Dictionary:
	var center := _direction(5.0, 46.0) * Fixture.RADIUS_M
	return WorldFeature.create(
		Fixture.BODY_ID,
		FeatureType.VALLEY,
		PROOF_SEED + 1,
		"1.0.0",
		VALLEY_STABLE_KEY,
		Fixture.FRAME_ID,
		FeatureBounds.sphere(Fixture.FRAME_ID, _array3(center), VALLEY_RADIUS_M),
		[FeatureAnchor.create("feature-anchor/g8-5-invariance-valley-center", Fixture.FRAME_ID, "feature-anchor-role/center", _array3(center))],
		"",
		[],
		{"geometry_kind": "invariance-proof-bounds-projection", "production_canonical": false}
	)


func _direction(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var cos_lat := cos(lat)
	return Vector3(cos_lat * cos(lon), sin(lat), cos_lat * sin(lon)).normalized()


func _array3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _near(a: float, b: float) -> bool:
	return GeoUtils.approximately_equal(a, b, 0.0000001)


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
		push_error("G8.5 FAIL: %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

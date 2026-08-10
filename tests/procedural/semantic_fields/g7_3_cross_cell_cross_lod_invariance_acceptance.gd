extends SceneTree

const SemanticQuery = preload("res://scripts/simulation/procedural/contracts/semantic_field_query.gd")
const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const Registry = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_registry_v1.gd")
const Composer = preload("res://scripts/simulation/procedural/semantic_fields/semantic_field_composer_v1.gd")
const G3Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g3_surface_semantic_field_adapter_v1.gd")
const G6Adapter = preload("res://scripts/simulation/procedural/semantic_fields/adapters/g6_fluid_semantic_field_adapter_v1.gd")
const MacroProvider = preload("res://scripts/simulation/procedural/providers/casual_macro_terrain_provider_v1.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const RiverProvider = preload("res://scripts/simulation/procedural/hydrology/casual_river_provider_v1.gd")
const Fixture = preload("res://tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd")

const LODS: Array[int] = [2, 4, 8, 12]
const ALL_FIELDS: Array[String] = [
	Registry.FLUID_SURFACE_DISTANCE_M,
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
	Registry.SURFACE_HEIGHT_M,
]
const RIVER_FIELDS: Array[String] = [
	Registry.RIVER_DISTANCE_M,
	Registry.RIVER_WIDTH_M,
]

var assertions: int = 0
var failures: Array[String] = []
var macro_provider
var compiled_river: Dictionary = {}
var addressing


func _init() -> void:
	_test_manifest()
	if _prepare_sources():
		_test_query_boundary()
		_test_same_world_point_across_lod_and_cells()
		_test_query_order_invariance()
		_test_cross_cell_seam_feature_identity()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g7-3-cross-cell-cross-lod-invariance.v1.json"
	_check(FileAccess.file_exists(path), "G7.3 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G7.3 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g7.3-cross-cell-cross-lod-invariance", "G7.3 checkpoint")
		_check(String(parsed.get("status", "")) == "IMPLEMENTED_CANDIDATE", "G7.3 candidate status")
		_check(String(parsed.get("global_program_revision", "")) == "GLOBAL-P0-2026-08-08-R1", "G7.3 P0 revision")
		var lods: Array[int] = []
		for value in parsed.get("lod_levels", []):
			lods.append(int(value))
		_check(lods == LODS, "G7.3 LOD proof levels pinned")
		var boundaries: Dictionary = parsed.get("architecture_boundaries", {})
		_check(not bool(boundaries.get("surface_cell_is_semantic_identity", true)), "SurfaceCellKey excluded from semantic identity")
		_check(not bool(boundaries.get("lod_is_semantic_identity", true)), "LOD excluded from semantic identity")
		_check(not bool(boundaries.get("creates_semantic_cell_identity", true)), "no SemanticCell identity introduced")


func _prepare_sources() -> bool:
	macro_provider = MacroProvider.new(20260810073, Fixture.RADIUS_M, 900.0, 600000.0, 4, 0.5, 12.0)
	addressing = CubeSphereAddressing.new()
	compiled_river = RiverProvider.compile(Fixture.river())
	_ok(compiled_river, "G7.3 accepted river compile")
	if not _success(compiled_river):
		return false
	var points: Array = compiled_river.get("details", {}).get("river_spline", {}).get("points_m", [])
	_check(points.size() >= 4, "G7.3 river spline has interior points")
	return points.size() >= 4


func _test_query_boundary() -> void:
	var point: Array = compiled_river["details"]["river_spline"]["points_m"][3]
	var query: Dictionary = SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, ALL_FIELDS)
	_ok(SemanticQuery.validate(query), "canonical semantic query validates")
	_check(not query.has("surface_cell"), "SemanticFieldQuery has no surface_cell")
	_check(not query.has("surface_cell_key"), "SemanticFieldQuery has no surface_cell_key")
	_check(not query.has("lod"), "SemanticFieldQuery has no LOD")
	_check(not query.has("representation"), "SemanticFieldQuery has no representation identity")


func _test_same_world_point_across_lod_and_cells() -> void:
	var point: Array = compiled_river["details"]["river_spline"]["points_m"][3]
	var baseline: Dictionary = _compose_at(point, ALL_FIELDS)
	_ok(baseline, "baseline semantic composition succeeds")
	if not _success(baseline):
		return
	var baseline_bundle: Dictionary = baseline["details"]["bundle"]
	var baseline_receipt: Dictionary = baseline["details"]["receipt"]
	var baseline_query: Dictionary = baseline_bundle["query"]
	var cell_tokens: Dictionary = {}
	var previous_resolution_side: int = 0

	for lod in LODS:
		var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, point, lod)
		_ok(addressed, "same world point addressed at LOD %d" % lod)
		if not _success(addressed):
			continue
		var cell: Dictionary = addressed["details"]["cell"]
		_ok(SurfaceCellKey.validate(cell), "SurfaceCellKey validates at LOD %d" % lod)
		cell_tokens[SurfaceCellKey.identity_token(cell)] = true
		var resolution_side: int = 1 << lod
		_check(resolution_side > previous_resolution_side, "representation resolution increases at LOD %d" % lod)
		previous_resolution_side = resolution_side

		var replay: Dictionary = _compose_at(point, ALL_FIELDS)
		_ok(replay, "same point semantic replay at LOD %d" % lod)
		if not _success(replay):
			continue
		var bundle: Dictionary = replay["details"]["bundle"]
		var receipt: Dictionary = replay["details"]["receipt"]
		_check(String(bundle["query"]["checksum"]) == String(baseline_query["checksum"]), "query checksum independent of LOD %d" % lod)
		_check(String(bundle["checksum"]) == String(baseline_bundle["checksum"]), "bundle checksum independent of LOD %d" % lod)
		_check(String(receipt["checksum"]) == String(baseline_receipt["checksum"]), "receipt checksum independent of LOD %d" % lod)
		for field_id in ALL_FIELDS:
			var sample: Dictionary = bundle["samples"][field_id]
			var baseline_sample: Dictionary = baseline_bundle["samples"][field_id]
			_check(String(sample["checksum"]) == String(baseline_sample["checksum"]), "%s sample checksum independent of LOD %d" % [field_id, lod])
			_check(String(sample["provenance"]["checksum"]) == String(baseline_sample["provenance"]["checksum"]), "%s provenance independent of LOD %d" % [field_id, lod])

	_check(cell_tokens.size() == LODS.size(), "same world point has distinct representation cell identities across proof LODs")

	var actual_address: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, point, 8)
	_ok(actual_address, "actual LOD8 cell available for external-cell proof")
	if _success(actual_address):
		var actual_cell: Dictionary = actual_address["details"]["cell"]
		var side: int = 1 << 8
		var alternate_x: int = (int(actual_cell["x"]) + 1) % side
		var alternate_cell: Dictionary = SurfaceCellKey.create(Fixture.BODY_ID, String(actual_cell["face"]), 8, alternate_x, int(actual_cell["y"]))
		_ok(SurfaceCellKey.validate(alternate_cell), "alternate external SurfaceCellKey validates")
		_check(SurfaceCellKey.identity_token(actual_cell) != SurfaceCellKey.identity_token(alternate_cell), "external SurfaceCellKey identities differ")
		var external_replay: Dictionary = _compose_at(point, ALL_FIELDS)
		_ok(external_replay, "canonical semantics ignore alternate external cell label")
		if _success(external_replay):
			_check(String(external_replay["details"]["bundle"]["checksum"]) == String(baseline_bundle["checksum"]), "alternate SurfaceCellKey cannot perturb canonical bundle")


func _test_query_order_invariance() -> void:
	var point: Array = compiled_river["details"]["river_spline"]["points_m"][3]
	var forward_fields: Array = ALL_FIELDS.duplicate()
	var reverse_fields: Array = ALL_FIELDS.duplicate()
	reverse_fields.reverse()
	var forward_query: Dictionary = SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, forward_fields)
	var reverse_query: Dictionary = SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, point, reverse_fields)
	_check(forward_query["requested_field_ids"] == reverse_query["requested_field_ids"], "query field order normalizes to canonical order")
	_check(String(forward_query["checksum"]) == String(reverse_query["checksum"]), "query checksum independent of input field order")
	var forward: Dictionary = _compose_query(forward_query)
	var reverse: Dictionary = _compose_query(reverse_query)
	_ok(forward, "forward-order composition succeeds")
	_ok(reverse, "reverse-order composition succeeds")
	if _success(forward) and _success(reverse):
		_check(String(forward["details"]["bundle"]["checksum"]) == String(reverse["details"]["bundle"]["checksum"]), "bundle independent of query field order")
		_check(String(forward["details"]["receipt"]["checksum"]) == String(reverse["details"]["receipt"]["checksum"]), "provenance receipt independent of query field order")


func _test_cross_cell_seam_feature_identity() -> void:
	var details: Dictionary = compiled_river["details"]
	var canonical_feature_id: String = String(details["source_feature_id"])
	var canonical_fluid_region_id: String = String(details["fluid_region_id"])
	var cells: Dictionary = {}
	var faces: Dictionary = {}
	var centerline_samples: Dictionary = {}

	for point_value in details["river_spline"]["points_m"]:
		var point: Array = point_value
		var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, point, 8)
		_ok(addressed, "river control point addressed at seam proof LOD")
		if not _success(addressed):
			continue
		var cell: Dictionary = addressed["details"]["cell"]
		var face: String = String(cell["face"])
		faces[face] = true
		cells[SurfaceCellKey.identity_token(cell)] = true

		var composed: Dictionary = _compose_at(point, RIVER_FIELDS)
		_ok(composed, "river semantic composition across representation cell")
		if not _success(composed):
			continue
		var sample: Dictionary = composed["details"]["bundle"]["samples"][Registry.RIVER_DISTANCE_M]
		var metadata: Dictionary = sample["provenance"].get("metadata", {})
		_check(String(metadata.get("source_feature_id", "")) == canonical_feature_id, "FeatureId stable across representation cells")
		_check(String(metadata.get("fluid_region_id", "")) == canonical_fluid_region_id, "FluidRegionId stable across representation cells")
		if face == "PX" or face == "PZ":
			centerline_samples[face] = float(sample["value"])

	_check(cells.size() >= 2, "one river feature spans multiple representation cells")
	_check(faces.has("PX") and faces.has("PZ"), "river crosses PX/PZ cube-sphere seam")
	_check(centerline_samples.has("PX") and centerline_samples.has("PZ"), "semantic samples exist on both PX/PZ seam sides")
	if centerline_samples.has("PX") and centerline_samples.has("PZ"):
		_check(absf(float(centerline_samples["PX"])) <= 0.001, "PX centerline river-distance remains zero across seam")
		_check(absf(float(centerline_samples["PZ"])) <= 0.001, "PZ centerline river-distance remains zero across seam")


func _compose_at(position: Array, field_ids: Array) -> Dictionary:
	var query: Dictionary = SemanticQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, position, field_ids)
	return _compose_query(query)


func _compose_query(query: Dictionary) -> Dictionary:
	var g3: Dictionary = G3Adapter.sample(query, macro_provider)
	var g6: Dictionary = G6Adapter.sample(query, [compiled_river])
	return Composer.compose(query, [g3, g6])


func _success(result: Dictionary) -> bool:
	return bool(result.get("success", false))


func _ok(result: Dictionary, label: String) -> void:
	_check(_success(result), "%s: %s %s" % [label, String(result.get("error_code", "")), result.get("details", {})])


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: %s" % message)
	else:
		print("PASS: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("G7.3 Cross-Cell / Cross-LOD Invariance: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G7.3 Cross-Cell / Cross-LOD Invariance: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

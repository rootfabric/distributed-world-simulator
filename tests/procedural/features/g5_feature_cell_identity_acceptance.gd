extends SceneTree

const SurfaceCellKey = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")
const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const FeatureQuery = preload("res://scripts/simulation/procedural/contracts/feature_query.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const CubeSphereAddressing = preload("res://scripts/simulation/procedural/surface/cube_sphere_addressing.gd")
const Fixture = preload("res://tests/procedural/fixtures/g5_feature_fixture_factory.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	var fault := Fixture.seam_fault()
	var graph = FeatureGraph.new()
	_ok(graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID), "graph configure")
	_ok(graph.add_feature(fault), "fault add")
	_ok(graph.seal(), "graph seal")
	var addressing = CubeSphereAddressing.new()
	var canonical_feature_id: String = String(fault["feature_id"])

	var all_lod_cell_sets: Dictionary = {}
	for lod in [2, 4, 8, 12]:
		var cell_tokens: Dictionary = {}
		var faces: Dictionary = {}
		for anchor in fault["anchors"]:
			var position: Array = anchor["position_m"]
			var addressed: Dictionary = addressing.direction_to_cell(Fixture.BODY_ID, position, lod)
			_ok(addressed, "anchor addressed at LOD %d" % lod)
			if not _success(addressed):
				continue
			var cell: Dictionary = addressed["details"]["cell"]
			cell_tokens[SurfaceCellKey.identity_token(cell)] = true
			faces[String(cell["face"])] = true

			# Cell is only representation scope: spatial feature query still resolves
			# the same canonical feature identity at every anchor and every LOD.
			var query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, position, 1.0, [FeatureType.FAULT])
			var result: Dictionary = graph.query(query)
			_ok(result, "feature query at LOD %d anchor" % lod)
			if _success(result):
				_check(result["details"]["feature_ids"].has(canonical_feature_id), "same feature id visible through representation cell")
				_check(graph.manifest_hash() == result["details"]["manifest_hash"], "LOD query cannot alter feature graph")
		_check(cell_tokens.size() >= 2, "one feature spans multiple LOD %d cells" % lod)
		_check(faces.has("PX") and faces.has("PZ"), "feature crosses PX/PZ cube seam at LOD %d" % lod)
		all_lod_cell_sets[lod] = cell_tokens.keys()

	_check(String(Fixture.seam_fault()["feature_id"]) == canonical_feature_id, "feature regenerated with same id independent from cells")
	_check(all_lod_cell_sets[2] != all_lod_cell_sets[12], "representation cell set changes with LOD")
	_check(graph.feature_ids() == [canonical_feature_id], "canonical graph still has exactly one feature")

	_finish()


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
		print("G5 feature/cell identity: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G5 feature/cell identity: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

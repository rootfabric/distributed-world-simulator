extends SceneTree

const GeoUtils = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const FeatureType = preload("res://scripts/simulation/procedural/contracts/feature_type.gd")
const FeatureId = preload("res://scripts/simulation/procedural/contracts/feature_id.gd")
const FeatureBounds = preload("res://scripts/simulation/procedural/contracts/feature_bounds.gd")
const FeatureAnchor = preload("res://scripts/simulation/procedural/contracts/feature_anchor.gd")
const FeatureRelation = preload("res://scripts/simulation/procedural/contracts/feature_relation.gd")
const FeatureQuery = preload("res://scripts/simulation/procedural/contracts/feature_query.gd")
const WorldFeature = preload("res://scripts/simulation/procedural/contracts/world_feature.gd")
const FeatureGraph = preload("res://scripts/simulation/procedural/features/feature_graph.gd")
const Fixture = preload("res://tests/procedural/fixtures/g5_feature_fixture_factory.gd")

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_manifest()
	_test_feature_type_and_id()
	_test_bounds_and_contracts()
	_test_world_feature_identity_and_canonicalization()
	_test_graph_determinism_and_spatial_query()
	_test_relations_and_hierarchy()
	_test_volume_and_free_space_features()
	_test_invalid_graphs()
	_test_source_boundaries()
	_finish()


func _test_manifest() -> void:
	var path := "res://config/procedural/g5-world-feature-graph.v1.json"
	_check(FileAccess.file_exists(path), "G5 manifest exists")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "G5 manifest parses")
	if parsed is Dictionary:
		_check(String(parsed.get("checkpoint", "")) == "g5-world-feature-graph-v0", "G5 checkpoint")
		_check(String(parsed.get("base_branch", "")) == "feature/g4-provider-composition-replacement", "G5 stacked on G4")
		_check(String(parsed.get("world_feature_schema", "")) == WorldFeature.SCHEMA, "WorldFeature schema declared")
		_check(String(parsed.get("feature_query_schema", "")) == FeatureQuery.SCHEMA, "FeatureQuery schema declared")
		_check(not bool(parsed.get("surface_cell_owns_feature_identity", true)), "cell does not own feature identity")
		_check(not bool(parsed.get("lod_changes_feature_identity", true)), "LOD does not change feature identity")


func _test_feature_type_and_id() -> void:
	for type_id in [FeatureType.VALLEY, FeatureType.RIVER, FeatureType.CRATER, FeatureType.FAULT, FeatureType.CAVE_SYSTEM, FeatureType.ORE_VEIN, FeatureType.FLOATING_ISLAND, FeatureType.VOLCANIC_CONDUIT, FeatureType.REEF, FeatureType.STORM_CELL, FeatureType.ASTEROID_CLUSTER, FeatureType.ARTIFICIAL_RUIN_ZONE]:
		_ok(FeatureType.validate(type_id), "feature type %s" % type_id)
	_check(not _success(FeatureType.validate("valley")), "unqualified feature type rejected")

	var id_a: Dictionary = FeatureId.derive(Fixture.BODY_ID, FeatureType.FAULT, Fixture.SEED, Fixture.GENERATOR_VERSION, "feature-key/seam-fault-001")
	var id_b: Dictionary = FeatureId.derive(Fixture.BODY_ID, FeatureType.FAULT, Fixture.SEED, Fixture.GENERATOR_VERSION, "feature-key/seam-fault-001")
	_ok(id_a, "feature id A")
	_ok(id_b, "feature id B")
	if _success(id_a) and _success(id_b):
		_check(String(id_a["details"]["feature_id"]) == String(id_b["details"]["feature_id"]), "same semantic identity reproduces feature id")
		_ok(FeatureId.validate(id_a["details"]["feature_id"]), "derived id validates")
	var changed_key: Dictionary = FeatureId.derive(Fixture.BODY_ID, FeatureType.FAULT, Fixture.SEED, Fixture.GENERATOR_VERSION, "feature-key/seam-fault-002")
	if _success(id_a) and _success(changed_key):
		_check(String(id_a["details"]["feature_id"]) != String(changed_key["details"]["feature_id"]), "stable key changes identity")
	var changed_version: Dictionary = FeatureId.derive(Fixture.BODY_ID, FeatureType.FAULT, Fixture.SEED, "2.0.0", "feature-key/seam-fault-001")
	if _success(id_a) and _success(changed_version):
		_check(String(id_a["details"]["feature_id"]) != String(changed_version["details"]["feature_id"]), "generator version changes procedural identity")


func _test_bounds_and_contracts() -> void:
	var sphere := FeatureBounds.sphere(Fixture.FRAME_ID, [10.0, 20.0, 30.0], 50.0)
	_ok(FeatureBounds.validate(sphere), "sphere bounds")
	_check(FeatureBounds.contains_point(sphere, [10.0, 20.0, 79.0]), "sphere contains inside point")
	_check(not FeatureBounds.contains_point(sphere, [10.0, 20.0, 81.0]), "sphere rejects outside point")
	_check(FeatureBounds.intersects_sphere(sphere, [100.0, 20.0, 30.0], 40.0), "sphere broad-phase overlap")
	_check(not FeatureBounds.intersects_sphere(sphere, [101.0, 20.0, 30.0], 40.0), "sphere broad-phase separation")

	var box := FeatureBounds.aabb(Fixture.FRAME_ID, [0.0, 0.0, 0.0], [10.0, 20.0, 30.0])
	_ok(FeatureBounds.validate(box), "AABB bounds")
	_check(FeatureBounds.contains_point(box, [9.0, 19.0, 29.0]), "AABB contains point")
	_check(not FeatureBounds.contains_point(box, [11.0, 0.0, 0.0]), "AABB rejects point")
	_check(FeatureBounds.intersects_sphere(box, [15.0, 0.0, 0.0], 5.0), "AABB touches query sphere")
	_check(not FeatureBounds.intersects_sphere(box, [16.0, 0.0, 0.0], 5.0), "AABB separated from query sphere")

	var anchor := FeatureAnchor.create("feature-anchor/test", Fixture.FRAME_ID, "feature-anchor-role/core", [1.0, 2.0, 3.0])
	_ok(FeatureAnchor.validate(anchor), "anchor contract")
	var anchor_tampered := anchor.duplicate(true)
	anchor_tampered["position_m"] = [4.0, 5.0, 6.0]
	_check(not _success(FeatureAnchor.validate(anchor_tampered)), "anchor checksum catches tamper")

	var id_result: Dictionary = FeatureId.derive(Fixture.BODY_ID, FeatureType.CRATER, 1, "1.0.0", "feature-key/relation-target")
	_ok(id_result, "relation target id")
	if _success(id_result):
		var relation := FeatureRelation.create("feature-relation/intersects", String(id_result["details"]["feature_id"]), {"weight": 0.5})
		_ok(FeatureRelation.validate(relation), "relation contract")

	var query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, [0.0, 0.0, 0.0], 100.0, [FeatureType.RIVER, FeatureType.FAULT, FeatureType.RIVER])
	_ok(FeatureQuery.validate(query), "feature query contract")
	_check(query["feature_types"] == [FeatureType.FAULT, FeatureType.RIVER], "query types canonicalized sorted unique")


func _test_world_feature_identity_and_canonicalization() -> void:
	var fault := Fixture.seam_fault()
	_ok(WorldFeature.validate(fault), "seam fault feature")
	_check(String(fault["feature_type"]) == FeatureType.FAULT, "fault type")
	_check(fault["anchors"].size() == 5, "fault anchors")
	for index in range(1, fault["anchors"].size()):
		_check(String(fault["anchors"][index - 1]["anchor_id"]) < String(fault["anchors"][index]["anchor_id"]), "anchors canonical order")
	var repeated := Fixture.seam_fault()
	_check(String(fault["feature_id"]) == String(repeated["feature_id"]), "feature id repeat stable")
	_check(String(fault["checksum"]) == String(repeated["checksum"]), "feature DTO repeat exact")

	var tampered := fault.duplicate(true)
	tampered["stable_key"] = "feature-key/seam-fault-999"
	tampered["checksum"] = GeoUtils.compute_checksum(tampered)
	_check(not _success(WorldFeature.validate(tampered)), "feature id mismatch catches semantic identity tamper")


func _test_graph_determinism_and_spatial_query() -> void:
	var features: Array = Fixture.all_features()
	var graph_a = _build_graph(features)
	var reversed: Array = features.duplicate(true)
	reversed.reverse()
	var graph_b = _build_graph(reversed)
	_check(graph_a != null and graph_b != null, "graphs build")
	if graph_a == null or graph_b == null:
		return
	_check(graph_a.feature_ids() == graph_b.feature_ids(), "feature order independent from insertion order")
	_check(graph_a.manifest_hash() == graph_b.manifest_hash(), "graph manifest independent from insertion order")
	_check(graph_a.size() == 5, "graph feature count")

	var seam_fault := Fixture.seam_fault()
	var seam_center: Array = seam_fault["bounds"]["center_m"]
	var near_query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, seam_center, 1000.0, [FeatureType.FAULT])
	var near_result: Dictionary = graph_a.query(near_query)
	_ok(near_result, "fault spatial query")
	if _success(near_result):
		_check(near_result["details"]["feature_ids"] == [String(seam_fault["feature_id"])], "fault query returns canonical identity")
	var far_query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, [0.0, -12000000.0, 0.0], 1000.0, [])
	var far_result: Dictionary = graph_a.query(far_query)
	_ok(far_result, "far spatial query")
	if _success(far_result):
		_check(far_result["details"]["feature_ids"].is_empty(), "far query empty")

	# Query order is a consumer concern and cannot mutate canonical graph identity.
	for feature in features:
		var query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, feature["bounds"]["center_m"], 10.0, [])
		_ok(graph_a.query(query), "query canonical feature")
	_check(graph_a.manifest_hash() == graph_b.manifest_hash(), "queries do not mutate graph manifest")


func _test_relations_and_hierarchy() -> void:
	var features := Fixture.all_features()
	var graph = _build_graph(features)
	if graph == null:
		return
	var valley := Fixture.valley()
	var river := Fixture.river(String(valley["feature_id"]))
	var children: Dictionary = graph.children_of(String(valley["feature_id"]))
	_ok(children, "valley children")
	if _success(children):
		_check(children["details"]["feature_ids"] == [String(river["feature_id"])], "river parent hierarchy")
	var related: Dictionary = graph.related_features(String(river["feature_id"]), "feature-relation/flows-through")
	_ok(related, "river relation lookup")
	if _success(related):
		_check(related["details"]["relations"].size() == 1, "one flows-through relation")
		if related["details"]["relations"].size() == 1:
			_check(String(related["details"]["relations"][0]["feature"]["feature_id"]) == String(valley["feature_id"]), "relation resolves canonical valley")


func _test_volume_and_free_space_features() -> void:
	var graph = _build_graph(Fixture.all_features())
	if graph == null:
		return
	var cave := Fixture.cave_system()
	var cave_query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, cave["bounds"]["center_m"], 0.0, [FeatureType.CAVE_SYSTEM])
	var cave_result: Dictionary = graph.query(cave_query)
	_ok(cave_result, "subsurface cave query")
	if _success(cave_result):
		_check(cave_result["details"]["feature_ids"] == [String(cave["feature_id"])], "subsurface feature is first-class")

	var island := Fixture.floating_island()
	var island_query := FeatureQuery.create(Fixture.BODY_ID, Fixture.FRAME_ID, island["bounds"]["center_m"], 0.0, [FeatureType.FLOATING_ISLAND])
	var island_result: Dictionary = graph.query(island_query)
	_ok(island_result, "free-space feature query")
	if _success(island_result):
		_check(island_result["details"]["feature_ids"] == [String(island["feature_id"])], "floating island does not require enclosing surface")


func _test_invalid_graphs() -> void:
	var missing_parent_id := String(FeatureId.derive(Fixture.BODY_ID, FeatureType.VALLEY, 999, "1.0.0", "feature-key/missing-parent")["details"]["feature_id"])
	var orphan := WorldFeature.create(
		Fixture.BODY_ID, FeatureType.RIVER, 1000, "1.0.0", "feature-key/orphan-river", Fixture.FRAME_ID,
		FeatureBounds.sphere(Fixture.FRAME_ID, [Fixture.RADIUS_M, 0.0, 0.0], 1000.0), [], missing_parent_id, [], {}
	)
	var graph = FeatureGraph.new()
	_ok(graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID), "orphan graph configure")
	_ok(graph.add_feature(orphan), "orphan add allowed before seal")
	var orphan_seal: Dictionary = graph.seal()
	_check(not _success(orphan_seal), "missing parent rejected at seal")
	_check(String(orphan_seal.get("error_code", "")) == "MISSING_PARENT_FEATURE", "missing parent precise error")

	var missing_target_id := String(FeatureId.derive(Fixture.BODY_ID, FeatureType.CRATER, 1001, "1.0.0", "feature-key/missing-target")["details"]["feature_id"])
	var relation_feature := WorldFeature.create(
		Fixture.BODY_ID, FeatureType.FAULT, 1002, "1.0.0", "feature-key/missing-relation-target", Fixture.FRAME_ID,
		FeatureBounds.sphere(Fixture.FRAME_ID, [Fixture.RADIUS_M, 0.0, 0.0], 1000.0), [], "",
		[FeatureRelation.create("feature-relation/intersects", missing_target_id)], {}
	)
	var relation_graph = FeatureGraph.new()
	_ok(relation_graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID), "relation graph configure")
	_ok(relation_graph.add_feature(relation_feature), "relation feature add")
	var relation_seal: Dictionary = relation_graph.seal()
	_check(not _success(relation_seal), "missing relation target rejected")
	_check(String(relation_seal.get("error_code", "")) == "MISSING_FEATURE_RELATION_TARGET", "missing relation target precise error")

	var id_a := String(FeatureId.derive(Fixture.BODY_ID, FeatureType.VALLEY, 2001, "1.0.0", "feature-key/cycle-a")["details"]["feature_id"])
	var id_b := String(FeatureId.derive(Fixture.BODY_ID, FeatureType.VALLEY, 2002, "1.0.0", "feature-key/cycle-b")["details"]["feature_id"])
	var a := WorldFeature.create(Fixture.BODY_ID, FeatureType.VALLEY, 2001, "1.0.0", "feature-key/cycle-a", Fixture.FRAME_ID, FeatureBounds.sphere(Fixture.FRAME_ID, [Fixture.RADIUS_M, 0.0, 0.0], 1000.0), [], id_b)
	var b := WorldFeature.create(Fixture.BODY_ID, FeatureType.VALLEY, 2002, "1.0.0", "feature-key/cycle-b", Fixture.FRAME_ID, FeatureBounds.sphere(Fixture.FRAME_ID, [Fixture.RADIUS_M, 0.0, 0.0], 1000.0), [], id_a)
	var cycle_graph = FeatureGraph.new()
	_ok(cycle_graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID), "cycle graph configure")
	_ok(cycle_graph.add_feature(a), "cycle A add")
	_ok(cycle_graph.add_feature(b), "cycle B add")
	var cycle_seal: Dictionary = cycle_graph.seal()
	_check(not _success(cycle_seal), "parent cycle rejected")
	_check(String(cycle_seal.get("error_code", "")) == "FEATURE_PARENT_CYCLE", "parent cycle precise error")

	var duplicate_graph = FeatureGraph.new()
	_ok(duplicate_graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID), "duplicate graph configure")
	var fault := Fixture.seam_fault()
	_ok(duplicate_graph.add_feature(fault), "first duplicate feature add")
	var duplicate_result: Dictionary = duplicate_graph.add_feature(fault)
	_check(not _success(duplicate_result), "duplicate feature id rejected")
	_check(String(duplicate_result.get("error_code", "")) == "DUPLICATE_FEATURE_ID", "duplicate precise error")


func _test_source_boundaries() -> void:
	var paths := [
		"res://scripts/simulation/procedural/contracts/feature_type.gd",
		"res://scripts/simulation/procedural/contracts/feature_id.gd",
		"res://scripts/simulation/procedural/contracts/feature_bounds.gd",
		"res://scripts/simulation/procedural/contracts/feature_anchor.gd",
		"res://scripts/simulation/procedural/contracts/feature_relation.gd",
		"res://scripts/simulation/procedural/contracts/feature_query.gd",
		"res://scripts/simulation/procedural/contracts/world_feature.gd",
		"res://scripts/simulation/procedural/features/feature_graph.gd",
	]
	var forbidden := [
		"extends Node", "extends SceneTree", "MeshInstance3D", "ArrayMesh", "ImmediateMesh", "RenderingServer",
		"SurfaceCellKey", "surface_cell_key", "SurfaceLodSelector", "Camera3D", "MultiplayerPeer",
		"RandomNumberGenerator", "randf(", "randi(", "GeoKernel.new()",
	]
	for path in paths:
		var source := FileAccess.get_file_as_string(path)
		_check(not source.is_empty(), "core source readable %s" % path)
		for token in forbidden:
			_check(source.find(token) < 0, "feature core excludes %s in %s" % [token, path])


func _build_graph(features: Array):
	var graph = FeatureGraph.new()
	var configured: Dictionary = graph.configure(Fixture.BODY_ID, Fixture.FRAME_ID)
	_ok(configured, "graph configure")
	if not _success(configured):
		return null
	for feature in features:
		var added: Dictionary = graph.add_feature(feature)
		_ok(added, "graph add %s" % String(feature.get("feature_type", "")))
		if not _success(added):
			return null
	var sealed: Dictionary = graph.seal()
	_ok(sealed, "graph seal")
	if not _success(sealed):
		return null
	return graph


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
		print("G5 World Feature Graph: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("G5 World Feature Graph: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

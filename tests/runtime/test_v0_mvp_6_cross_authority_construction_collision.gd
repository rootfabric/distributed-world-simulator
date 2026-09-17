extends "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_seam.gd"

const RuntimeView = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd")

var collision_product: Dictionary = {}


func _physics_hits(position: Vector3, radius: float = 0.12) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_root().get_world_3d().direct_space_state.intersect_shape(query, 32)


func _hits_body(hits: Array, body) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var body_rid: RID = body.get_rid()
	for hit in hits:
		if not hit is Dictionary:
			continue
		if hit.get("collider") == body or hit.get("rid", RID()) == body_rid:
			return true
	return false


func exercise_derived_collision() -> bool:
	if not exercise_cross_authority_construction_seam():
		return false
	var added_snapshot: Dictionary = seam_product.get("added_snapshot", {})
	var removed_snapshot: Dictionary = seam_product.get("removed_snapshot", {})
	if not check(not added_snapshot.is_empty() and not removed_snapshot.is_empty(), "seam snapshots available for derived physics"):
		return false
	var view = RuntimeView.new()
	view.name = "MVP6DerivedConstructionRuntimeView"
	get_root().add_child(view)
	if not success(view.setup("client/mvp6/collision-proof"), "derived C13 runtime view setup"):
		view.queue_free()
		return false

	var added: Dictionary = view.apply_snapshot(added_snapshot)
	if not success(added, "derive 101-part canonical ADD snapshot into runtime geometry"):
		view.queue_free()
		return false
	await physics_frame
	var node = view.get_construct_node(SeamFactory.CONSTRUCT_ID)
	if not check(node != null and is_instance_valid(node), "derived runtime construct node exists after ADD"):
		view.queue_free()
		return false
	var body = node.get_body()
	if not check(body is StaticBody3D, "seam Construction derives a real StaticBody3D"):
		view.queue_free()
		return false
	if not check(int(added.get("part_count", 0)) == 101 and int(added.get("collision_part_count", 0)) == 101, "ADD projection has 101 colliding canonical parts"):
		view.queue_free()
		return false
	var leaf_part_id := SeamFactory.part_id(SeamFactory.ADD_PART_INDEX)
	if not check(node.get_part_collision_nodes(leaf_part_id).size() > 0, "101st east leaf owns a real CollisionShape3D"):
		view.queue_free()
		return false
	var leaf_center := Vector3(float(SeamFactory.ADD_PART_INDEX) - 49.5, 0.5, 0.0)
	var add_hits := _physics_hits(leaf_center)
	if not check(_hits_body(add_hits, body), "PhysicsDirectSpaceState3D hits the added east leaf"):
		view.queue_free()
		return false
	var added_body_rid: RID = body.get_rid()

	var removed: Dictionary = view.apply_snapshot(removed_snapshot)
	if not success(removed, "derive canonical C9 REMOVE snapshot into same runtime view"):
		view.queue_free()
		return false
	await physics_frame
	node = view.get_construct_node(SeamFactory.CONSTRUCT_ID)
	body = node.get_body() if node != null else null
	if not check(body is StaticBody3D and body.get_rid() == added_body_rid, "REMOVE updates the same derived StaticBody3D instead of creating authority"):
		view.queue_free()
		return false
	if not check(int(removed.get("part_count", 0)) == 100 and int(removed.get("collision_part_count", 0)) == 100, "REMOVE projection returns to 100 colliding canonical parts"):
		view.queue_free()
		return false
	if not check(node.get_part_node(leaf_part_id) == null and node.get_part_collision_nodes(leaf_part_id).is_empty(), "removed east leaf mesh and collision are absent"):
		view.queue_free()
		return false
	var removed_leaf_hits := _physics_hits(leaf_center)
	if not check(not _hits_body(removed_leaf_hits, body), "PhysicsDirectSpaceState3D no longer hits removed east leaf"):
		view.queue_free()
		return false
	var retained_part_id := SeamFactory.part_id(0)
	var retained_center := Vector3(-49.5, 0.5, 0.0)
	if not check(node.get_part_collision_nodes(retained_part_id).size() > 0, "retained west part keeps CollisionShape3D after REMOVE"):
		view.queue_free()
		return false
	var retained_hits := _physics_hits(retained_center)
	if not check(_hits_body(retained_hits, body), "PhysicsDirectSpaceState3D still hits retained 100-part Construction"):
		view.queue_free()
		return false
	var report: Dictionary = view.get_report()
	if not check(int(report.get("direct_authority_references", -1)) == 0 and not bool(report.get("canonical_truth_owner", true)), "derived physics view owns no canonical Construction truth"):
		view.queue_free()
		return false
	if not check(String(report.get("source_checksum", "")) == String(removed_snapshot.get("checksum", "")), "derived physics view is bound to exact post-REMOVE canonical checksum"):
		view.queue_free()
		return false
	collision_product = {
		"added_apply": added.duplicate(true),
		"removed_apply": removed.duplicate(true),
		"view_report": report.duplicate(true),
		"added_leaf_physics_hits": add_hits.size(),
		"removed_leaf_physics_hits": removed_leaf_hits.size(),
		"retained_part_physics_hits": retained_hits.size(),
		"static_body_rid_valid": body.get_rid().is_valid(),
		"same_runtime_body_across_remove": body.get_rid() == added_body_rid,
		"removed_leaf_body_hit": _hits_body(removed_leaf_hits, body),
		"retained_body_hit": _hits_body(retained_hits, body),
	}
	view.queue_free()
	await process_frame
	return true


func run() -> void:
	var okay := await exercise_derived_collision()
	var report := {
		"schema": "distributed_world_simulator.mvp6_cross_authority_construction_collision_test.v1",
		"subject_head": OS.get_environment("EXPECTED_HEAD"),
		"subject_tree": OS.get_environment("EXPECTED_TREE"),
		"passed": okay and failures.is_empty(),
		"assertions": assertions,
		"failures": failures,
		"collision": collision_product,
		"base_part_count": 100,
		"add_part_count": 101,
		"remove_part_count": 100,
		"cross_authority_seam_executed": seam_product.has("remove_result"),
		"derived_presentation_executed": collision_product.has("view_report"),
		"derived_collision_executed": collision_product.has("retained_body_hit") and bool(collision_product.get("retained_body_hit", false)),
		"physics_server_hit_executed": collision_product.has("added_leaf_physics_hits") and int(collision_product.get("added_leaf_physics_hits", 0)) > 0,
		"removed_leaf_collision_absent": collision_product.has("removed_leaf_body_hit") and not bool(collision_product.get("removed_leaf_body_hit", true)),
		"graphical_five_process_executed": false,
		"mvp6_cross_authority_construction_seam_verified": false,
		"mvp6_predicate_verified": false,
		"independent_verdict": false,
	}
	cleanup6()
	var output := OS.get_environment("MVP6_DERIVED_COLLISION_RESULT")
	var saved := output.is_empty()
	if not output.is_empty():
		saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_CROSS_AUTHORITY_CONSTRUCTION_COLLISION assertions=%d failures=%d passed=%s" % [assertions, failures.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

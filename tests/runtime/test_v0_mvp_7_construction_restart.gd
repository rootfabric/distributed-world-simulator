extends "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_persistence.gd"

# Three real OS processes over the EXISTING M0/C17/M4 persistence surfaces.
# The JSON cut is composed only from canonical owner exports produced by MVP6;
# it is evidence transport, not a second Construction owner or save engine.
var result7: Dictionary = {}
var cut_path7 := ""

func _write_cut7(value: Dictionary) -> bool:
	var directory := cut_path7.get_base_dir()
	var made := DirAccess.make_dir_recursive_absolute(directory)
	if made != OK and made != ERR_ALREADY_EXISTS:
		return check(false, "create construction restart evidence directory")
	var file := FileAccess.open(cut_path7, FileAccess.WRITE)
	if file == null:
		return check(false, "open construction canonical export cut")
	file.store_string(JSON.stringify(value, "", true, true) + "\n")
	file.flush()
	var okay := file.get_error() == OK
	file.close()
	return check(okay, "serialize canonical Construction owner exports to disk")

func _read_cut7() -> Dictionary:
	if not FileAccess.file_exists(cut_path7):
		check(false, "persisted construction cut exists")
		return {}
	var file := FileAccess.open(cut_path7, FileAccess.READ)
	if file == null:
		check(false, "open persisted construction cut")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		check(false, "construction cut parses as dictionary")
		return {}
	return Dictionary(parsed)

func produce7() -> bool:
	var roots_before := _process_repository_roots()
	if not exercise_cross_authority_construction_seam():
		return false
	var roots_after := _process_repository_roots()
	var new_roots: Array[String] = []
	for raw_name in roots_after.keys():
		var name := String(raw_name)
		if not roots_before.has(name):
			new_roots.append(name)
	new_roots.sort()
	if not check(new_roots.size() == 1, "producer creates exactly one durable M0 Construction repository"):
		return false
	var root_path := "user://mvp6-seam-construction/%s" % new_roots[0]
	var removed: Dictionary = seam_product.get("removed_snapshot", {})
	var durable_items: Dictionary = seam_product.get("durable_items", {})
	var durable_construction: Dictionary = seam_product.get("durable_construction", {})
	var durable_cluster: Dictionary = seam_product.get("durable_cluster", {})
	if not check(not removed.is_empty() and not durable_items.is_empty() and not durable_construction.is_empty() and not durable_cluster.is_empty(), "all canonical Construction recovery payloads exported"):
		return false
	var cut := {
		"schema": "distributed_world_simulator.mvp7_construction_restart_cut.v1",
		"repository_root": root_path,
		"durable_items": durable_items,
		"durable_construction": durable_construction,
		"durable_cluster": durable_cluster,
		"removed_snapshot": removed,
		"authority_record": seam_product.get("authority_record", {}),
		"item_graph_checksum": String(durable_items.get("snapshot", {}).get("checksum", "")),
		"construction_checksum": String(removed.get("checksum", "")),
	}
	if not _write_cut7(cut):
		return false
	result7 = {
		"cut_file": cut_path7,
		"repository_root": root_path,
		"item_graph_checksum": cut["item_graph_checksum"],
		"construction_checksum": cut["construction_checksum"],
		"part_count": seam_parts(removed),
		"bond_count": seam_bonds(removed),
		"terminal_command_count": Array(durable_cluster.get("replicas", [])).size(),
	}
	return check(seam_parts(removed) == 100 and seam_bonds(removed) == 99 and has_cross_seam_bond(removed), "producer cut is canonical final seam Construction")

func recover7() -> bool:
	var cut := _read_cut7()
	if cut.is_empty():
		return false
	if not check(cut.get("schema") == "distributed_world_simulator.mvp7_construction_restart_cut.v1", "construction restart cut schema"):
		return false
	var restored_graph = RestoredItemGraph.new()
	var item_result: Dictionary = restored_graph.restore_durable_state(Dictionary(cut.get("durable_items", {})))
	if not success(item_result, "new PID restores canonical M4 Item Graph for Construction"):
		return false
	var item_snapshot: Dictionary = restored_graph.create_snapshot()
	if not check(String(item_snapshot.get("checksum", "")) == String(cut.get("item_graph_checksum", "")), "Construction restart restores exact M4 checksum"):
		return false
	var created: Dictionary = Restorer.restore(
		restored_graph,
		String(item_snapshot.get("authority_owner_id", "authority/a")),
		int(item_snapshot.get("authority_epoch", 1)),
		String(cut.get("repository_root", ""))
	)
	if not success(created, "new PID reopens SAME canonical Construction M0 repository"):
		return false
	var detail: Dictionary = created.get("details", {})
	if not check(bool(detail.get("recovered_from_existing_m0", false)) and not bool(detail.get("build_plan_registered", true)) and bool(detail.get("single_item_graph_identity", false)), "restorer uses existing M0 and restored M4 without fresh build plan"):
		return false
	var construction_state: Dictionary = cut.get("durable_construction", {})
	if not success(detail["authoritative_adapter"].load_state(construction_state), "M0 state exactly matches persisted Construction adapter export"):
		return false
	var cluster_state: Dictionary = cut.get("durable_cluster", {})
	if not success(detail["cluster"].load_state(cluster_state), "restore C17 registry and read replica metadata"):
		return false
	var replica = detail["cluster"].get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B)
	if not check(replica != null and not replica.can_write(), "authority B remains read-only after process restart"):
		return false
	var replica_state: Dictionary = replica.get_state()
	var state_bundle: Dictionary = replica_state.get("state_bundle", {})
	if not check(not state_bundle.is_empty(), "persisted east replica carries canonical state bundle"):
		return false
	if not success(detail["transfer_backend"].import_construct_state(state_bundle), "restore gateway terminal command state from canonical replica bundle"):
		return false
	var expected_gateway: Dictionary = state_bundle.get("payload", {}).get("multiplayer_gateway", {})
	var actual_gateway: Dictionary = detail["gateway"].export_state()
	if not check(NetworkUtils.canonical_json(expected_gateway) == NetworkUtils.canonical_json(actual_gateway), "Construction gateway replay/session state round-trips exactly"):
		return false
	var terminal_commands: Array = expected_gateway.get("terminal_commands", [])
	if not check(terminal_commands.size() >= 3, "base ADD REMOVE terminal commands persisted"):
		return false
	for row_value in terminal_commands:
		var row: Dictionary = row_value
		if not check(detail["transfer_backend"].has_terminal_command(String(row.get("command_id", "")), String(row.get("command_checksum", ""))), "terminal command restored: " + String(row.get("command_id", ""))):
			return false
	var restored: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	var expected: Dictionary = cut.get("removed_snapshot", {})
	if not check(NetworkUtils.canonical_json(restored) == NetworkUtils.canonical_json(expected), "new PID restores exact post-REMOVE Construction snapshot"):
		return false
	if not check(String(restored.get("checksum", "")) == String(cut.get("construction_checksum", "")) and seam_parts(restored) == 100 and seam_bonds(restored) == 99 and has_cross_seam_bond(restored), "Construction identity topology and checksum survive restart"):
		return false
	if not check(not has_part(restored, SeamFactory.part_id(SeamFactory.ADD_PART_INDEX)), "removed east leaf stays absent after process restart"):
		return false
	var record: Dictionary = detail["cluster"].get_registry().get_record(SeamFactory.CONSTRUCT_ID)
	if not check(NetworkUtils.canonical_json(record) == NetworkUtils.canonical_json(cut.get("authority_record", {})), "single-writer C17 authority record survives restart"):
		return false
	if not check(String(replica_state.get("construct_checksum", "")) == String(restored.get("checksum", "")), "east replica checksum equals restored writer checksum"):
		return false

	var view = RestoredRuntimeView.new()
	view.name = "MVP7RestartedConstructionRuntimeView"
	get_root().add_child(view)
	if not success(view.setup("client/mvp7/construction-restart"), "derived recovered Construction view setup"):
		view.queue_free()
		return false
	var applied: Dictionary = view.apply_snapshot(restored)
	if not success(applied, "derive recovered Construction into physics/runtime view"):
		view.queue_free()
		return false
	await physics_frame
	var node = view.get_construct_node(SeamFactory.CONSTRUCT_ID)
	var body = node.get_body() if node != null else null
	if not check(body is StaticBody3D and int(applied.get("part_count", 0)) == 100 and int(applied.get("collision_part_count", 0)) == 100, "new PID derives one 100-part StaticBody3D with collision"):
		view.queue_free()
		return false
	var west_hits := _physics_hits(Vector3(-0.5, 0.5, 0.0))
	var east_hits := _physics_hits(Vector3(0.5, 0.5, 0.0))
	var boundary_hits := _physics_hits(Vector3(0.0, 0.5, 0.0), 0.08)
	if not check(_hits_body(west_hits, body) and _hits_body(east_hits, body) and _hits_body(boundary_hits, body), "recovered collision is continuous west east and directly at authority seam"):
		view.queue_free()
		return false
	var removed_leaf_center := Vector3(float(SeamFactory.ADD_PART_INDEX) - 49.5, 0.5, 0.0)
	var removed_hits := _physics_hits(removed_leaf_center)
	if not check(not _hits_body(removed_hits, body), "removed leaf collision does not reappear after process restart"):
		view.queue_free()
		return false
	var report: Dictionary = view.get_report()
	if not check(String(report.get("source_checksum", "")) == String(restored.get("checksum", "")) and int(report.get("direct_authority_references", -1)) == 0 and not bool(report.get("canonical_truth_owner", true)), "recovered collision stays a read-only derived view"):
		view.queue_free()
		return false
	result7 = {
		"repository_root": cut.get("repository_root", ""),
		"item_graph_checksum": item_snapshot.get("checksum", ""),
		"construction_checksum": restored.get("checksum", ""),
		"authority_record": record,
		"replica_checksum": replica_state.get("construct_checksum", ""),
		"terminal_command_count": terminal_commands.size(),
		"collision_part_count": applied.get("collision_part_count", 0),
		"west_hits": west_hits.size(),
		"east_hits": east_hits.size(),
		"boundary_hits": boundary_hits.size(),
		"removed_leaf_hits": removed_hits.size(),
	}
	view.queue_free()
	await process_frame
	return true

func run() -> void:
	var mode := OS.get_environment("MVP7_CONSTRUCTION_MODE")
	var root_path := OS.get_environment("MVP7_CONSTRUCTION_ROOT")
	cut_path7 = root_path.path_join("construction-cut.json")
	var completed := false
	if check(mode in ["produce", "recover1", "recover2"] and not root_path.is_empty(), "bounded Construction restart process configuration"):
		if mode == "produce":
			completed = produce7()
		else:
			completed = await recover7()
	check(completed, "Construction restart process completed")
	var report := {
		"schema": "distributed_world_simulator.mvp7_construction_restart_result.v1",
		"mode": mode,
		"process_id": OS.get_process_id(),
		"subject_head": OS.get_environment("EXPECTED_HEAD"),
		"subject_tree": OS.get_environment("EXPECTED_TREE"),
		"passed": failures.is_empty(),
		"assertions": assertions,
		"failures": failures,
		"evidence": result7,
		"construction_recovery_executed": mode != "produce" and not result7.is_empty(),
		"collision_recovery_executed": mode != "produce" and int(result7.get("collision_part_count", 0)) == 100,
		"graphical_five_process_executed": false,
		"enet_reconnect_executed": false,
		"mvp7_predicate_verified": false,
		"independent_verdict": false,
	}
	cleanup6()
	var output := OS.get_environment("MVP7_CONSTRUCTION_RESULT")
	var saved := output.is_empty()
	if not output.is_empty():
		saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP7_CONSTRUCTION_RESTART ", mode, " passed=", report["passed"] and saved, " assertions=", assertions, " failures=", failures.size())
	quit(0 if report["passed"] and saved else 1)

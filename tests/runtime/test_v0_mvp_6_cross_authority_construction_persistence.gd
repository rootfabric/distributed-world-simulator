extends "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_collision.gd"

const RestoredItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const RestoredRuntimeView = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd")
const Restorer = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_cross_authority_construction_restorer.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

var persistence_product: Dictionary = {}


func _process_repository_roots() -> Dictionary:
	var base := "user://mvp6-seam-construction"
	var absolute := ProjectSettings.globalize_path(base)
	var result: Dictionary = {}
	if not DirAccess.dir_exists_absolute(absolute):
		return result
	var prefix := "%d-" % OS.get_process_id()
	for raw_name in DirAccess.get_directories_at(base):
		var name := String(raw_name)
		if name.begins_with(prefix):
			result[name] = true
	return result


func exercise_persistence_rehydration() -> bool:
	# The seam product chooses a unique M0 repository beneath user://. Record
	# the current-process directory set before execution so the persistence proof
	# can reopen the exact repository created by this run, not a fresh empty one.
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
	if not check(new_roots.size() == 1, "exactly one durable Construction M0 repository is created by the seam scenario"):
		return false
	var root := "user://mvp6-seam-construction/%s" % new_roots[0]
	var removed_snapshot: Dictionary = seam_product.get("removed_snapshot", {})
	var durable_items: Dictionary = seam_product.get("durable_items", {})
	var durable_construction: Dictionary = seam_product.get("durable_construction", {})
	var durable_cluster: Dictionary = seam_product.get("durable_cluster", {})
	if not check(
		not removed_snapshot.is_empty()
		and not durable_items.is_empty()
		and not durable_construction.is_empty()
		and not durable_cluster.is_empty(),
		"canonical Item/Construction/C17 durable payloads are available"
	):
		return false

	# Fresh instance of the SAME canonical M4 service class. restore_durable_state
	# rehydrates owner/epoch/revision/items/inventories from its own payload; this
	# does not claim the separate MVP7 process-restart predicate.
	var restored_graph = RestoredItemGraph.new()
	var restored_items: Dictionary = restored_graph.restore_durable_state(durable_items)
	if not success(restored_items, "restore canonical M4 Item Graph durable state"):
		return false
	var restored_item_snapshot: Dictionary = restored_graph.create_snapshot()
	var durable_item_snapshot: Dictionary = durable_items.get("snapshot", {})
	# Durable export deliberately performs a JSON round-trip. Godot Dictionary
	# equality is Variant-type-sensitive ({"a":1} != {"a":1.0}) even though
	# canonical JSON normalizes integer-valued JSON numbers to the same value.
	var item_graph_canonical_equal := (
		NetworkUtils.canonical_json(restored_item_snapshot)
		== NetworkUtils.canonical_json(durable_item_snapshot)
	)
	if not check(item_graph_canonical_equal, "rehydrated Item Graph is exactly canonical-JSON equivalent to durable snapshot"):
		return false
	if not check(
		String(restored_item_snapshot.get("checksum", "")) == String(durable_item_snapshot.get("checksum", ""))
		and not String(restored_item_snapshot.get("checksum", "")).is_empty(),
		"rehydrated Item Graph preserves the exact canonical snapshot checksum"
	):
		return false
	if not check(
		String(restored_item_snapshot.get("authority_owner_id", "")) == String(durable_item_snapshot.get("authority_owner_id", ""))
		and int(restored_item_snapshot.get("authority_epoch", 0)) == int(durable_item_snapshot.get("authority_epoch", 0)),
		"Item Graph authority identity and epoch survive rehydration"
	):
		return false
	var migration: Dictionary = restored_items.get("details", {}).get("slot_migration", {})
	if not migration.is_empty() and not check(not bool(migration.get("migrated", true)), "current canonical Item Graph requires no compatibility migration on restore"):
		return false

	# Reopen the SAME durable M0 repository through bounded composition wiring.
	# The restorer intentionally does not register a new build plan because the
	# persisted structural items are already attached to the recovered construct.
	var created: Dictionary = Restorer.restore(
		restored_graph,
		String(restored_item_snapshot.get("authority_owner_id", "authority/a")),
		int(restored_item_snapshot.get("authority_epoch", 1)),
		root
	)
	if not success(created, "reopen persisted Construction M0 repository without rebuilding part sources"):
		return false
	var detail: Dictionary = created.get("details", {})
	if not check(
		bool(detail.get("single_item_graph_identity", false))
		and bool(detail.get("recovered_from_existing_m0", false))
		and not bool(detail.get("build_plan_registered", true)),
		"rehydrated Construction binds restored M4 graph without registering a fresh build plan"
	):
		return false
	var loaded_construction: Dictionary = detail["authoritative_adapter"].load_state(durable_construction)
	if not success(loaded_construction, "verify canonical Construction adapter state against reopened M0 repository"):
		return false
	var loaded_cluster: Dictionary = detail["cluster"].load_state(durable_cluster)
	if not success(loaded_cluster, "load C17 authority registry and east read replica state"):
		return false

	var replica = detail["cluster"].get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B)
	if not check(replica != null and not replica.can_write(), "rehydrated authority B replica remains read-only"):
		return false
	var restored_replica: Dictionary = replica.get_state()
	var state_bundle: Dictionary = restored_replica.get("state_bundle", {})
	if not check(
		not state_bundle.is_empty()
		and state_bundle.get("payload", {}) is Dictionary
		and state_bundle.get("payload", {}).get("multiplayer_gateway", {}) is Dictionary,
		"east replica preserves the final canonical Construction and gateway state bundle"
	):
		return false

	# C17 load_state restores registry/replica metadata. The final read replica
	# carries the owner-exported state_bundle, including terminal command replay.
	# Import it through the same transfer boundary so the fresh gateway recovers
	# dedup state instead of reconstructing it from test knowledge.
	var imported_bundle: Dictionary = detail["transfer_backend"].import_construct_state(state_bundle)
	if not success(imported_bundle, "restore final Construction and terminal command state from canonical replica bundle"):
		return false
	var expected_gateway_state: Dictionary = state_bundle.get("payload", {}).get("multiplayer_gateway", {})
	var restored_gateway_state: Dictionary = detail["gateway"].export_state()
	var gateway_state_canonical_equal := (
		NetworkUtils.canonical_json(restored_gateway_state)
		== NetworkUtils.canonical_json(expected_gateway_state)
	)
	if not check(gateway_state_canonical_equal, "multiplayer gateway terminal/session/permission state survives rehydration exactly"):
		return false
	var terminal_commands: Array = expected_gateway_state.get("terminal_commands", [])
	if not check(terminal_commands.size() >= 3, "persisted gateway retains base ADD and REMOVE terminal command history"):
		return false
	var terminal_ids: Dictionary = {}
	var terminal_replay_state_preserved := true
	for raw_row in terminal_commands:
		if not raw_row is Dictionary:
			terminal_replay_state_preserved = false
			continue
		var row: Dictionary = raw_row
		var command_id := String(row.get("command_id", ""))
		var command_checksum := String(row.get("command_checksum", ""))
		terminal_ids[command_id] = true
		terminal_replay_state_preserved = terminal_replay_state_preserved and detail["transfer_backend"].has_terminal_command(command_id, command_checksum)
	if not check(
		terminal_replay_state_preserved
		and terminal_ids.has("multiplayer-command/mvp6/seam/add-east-leaf")
		and terminal_ids.has("multiplayer-command/mvp6/seam/remove-east-leaf"),
		"canonical ADD/REMOVE terminal replay identities survive persistence rehydration"
	):
		return false

	var restored_snapshot: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	var construct_canonical_equal := (
		NetworkUtils.canonical_json(restored_snapshot)
		== NetworkUtils.canonical_json(removed_snapshot)
	)
	if not check(construct_canonical_equal, "rehydrated Construction exactly matches canonical post-REMOVE snapshot"):
		return false
	if not check(String(restored_snapshot.get("checksum", "")) == String(removed_snapshot.get("checksum", "")), "rehydrated Construction preserves exact canonical checksum"):
		return false
	if not check(seam_parts(restored_snapshot) == 100 and seam_bonds(restored_snapshot) == 99, "rehydrated Construction preserves 100 parts and 99 bonds"):
		return false
	if not check(has_cross_seam_bond(restored_snapshot), "rehydrated Construction preserves canonical A-to-B seam relationship"):
		return false
	if not check(not has_part(restored_snapshot, SeamFactory.part_id(SeamFactory.ADD_PART_INDEX)), "removed east leaf remains absent after rehydration"):
		return false

	var original_record: Dictionary = seam_product.get("authority_record", {})
	var restored_record: Dictionary = detail["cluster"].get_registry().get_record(SeamFactory.CONSTRUCT_ID)
	var authority_record_canonical_equal := (
		NetworkUtils.canonical_json(restored_record)
		== NetworkUtils.canonical_json(original_record)
	)
	if not check(authority_record_canonical_equal, "C17 owner/cell/epoch/replica mapping survives rehydration exactly"):
		return false
	if not check(
		String(restored_record.get("owner_server_id", "")) == SeamFactory.SERVER_A
		and int(restored_record.get("authority_epoch", 0)) == 1,
		"rehydrated C17 registry still has exactly writer A at epoch 1"
	):
		return false
	if not check(
		String(restored_replica.get("construct_checksum", "")) == String(restored_snapshot.get("checksum", "")),
		"rehydrated east replica checksum equals the canonical writer checksum"
	):
		return false

	# Derive a new presentation/physics instance from the rehydrated canonical
	# snapshot and prove real collision on both sides and directly at x=0 seam.
	var view = RestoredRuntimeView.new()
	view.name = "MVP6RehydratedConstructionRuntimeView"
	get_root().add_child(view)
	if not success(view.setup("client/mvp6/persistence-proof"), "rehydrated derived runtime view setup"):
		view.queue_free()
		return false
	var applied: Dictionary = view.apply_snapshot(restored_snapshot)
	if not success(applied, "derive rehydrated canonical snapshot into runtime geometry"):
		view.queue_free()
		return false
	await physics_frame
	var node = view.get_construct_node(SeamFactory.CONSTRUCT_ID)
	var body = node.get_body() if node != null else null
	if not check(body is StaticBody3D and int(applied.get("part_count", 0)) == 100 and int(applied.get("collision_part_count", 0)) == 100, "rehydrated snapshot derives one 100-part StaticBody3D"):
		view.queue_free()
		return false
	var west_id := SeamFactory.part_id(SeamFactory.SEAM_LEFT_INDEX)
	var east_id := SeamFactory.part_id(SeamFactory.SEAM_RIGHT_INDEX)
	if not check(node.get_part_collision_nodes(west_id).size() > 0 and node.get_part_collision_nodes(east_id).size() > 0, "rehydrated seam keeps collision shapes on both authority sides"):
		view.queue_free()
		return false
	var west_hits := _physics_hits(Vector3(-0.5, 0.5, 0.0))
	var east_hits := _physics_hits(Vector3(0.5, 0.5, 0.0))
	var boundary_hits := _physics_hits(Vector3(0.0, 0.5, 0.0), 0.08)
	if not check(_hits_body(west_hits, body) and _hits_body(east_hits, body), "PhysicsDirectSpaceState3D hits rehydrated Construction on both seam sides"):
		view.queue_free()
		return false
	if not check(_hits_body(boundary_hits, body), "PhysicsDirectSpaceState3D collision is continuous at the authority boundary"):
		view.queue_free()
		return false
	var removed_leaf_center := Vector3(float(SeamFactory.ADD_PART_INDEX) - 49.5, 0.5, 0.0)
	var removed_leaf_hits := _physics_hits(removed_leaf_center)
	if not check(not _hits_body(removed_leaf_hits, body), "removed leaf collision does not reappear after persistence rehydration"):
		view.queue_free()
		return false
	var view_report: Dictionary = view.get_report()
	if not check(
		String(view_report.get("source_checksum", "")) == String(restored_snapshot.get("checksum", ""))
		and int(view_report.get("direct_authority_references", -1)) == 0
		and not bool(view_report.get("canonical_truth_owner", true)),
		"rehydrated presentation remains an exact read-only derived view"
	):
		view.queue_free()
		return false

	persistence_product = {
		"repository_root": root,
		"restored_item_snapshot_checksum": String(restored_item_snapshot.get("checksum", "")),
		"restored_construct_checksum": String(restored_snapshot.get("checksum", "")),
		"restored_authority_record": restored_record.duplicate(true),
		"restored_replica_checksum": String(restored_replica.get("construct_checksum", "")),
		"slot_migration": migration.duplicate(true),
		"gateway_state_canonical_equal": gateway_state_canonical_equal,
		"terminal_command_count": terminal_commands.size(),
		"terminal_replay_state_preserved": terminal_replay_state_preserved,
		"derived_apply": applied.duplicate(true),
		"derived_report": view_report.duplicate(true),
		"west_seam_physics_hits": west_hits.size(),
		"east_seam_physics_hits": east_hits.size(),
		"boundary_physics_hits": boundary_hits.size(),
		"removed_leaf_physics_hits": removed_leaf_hits.size(),
		"same_snapshot_after_restore": construct_canonical_equal,
		"same_item_graph_after_restore": item_graph_canonical_equal,
		"same_authority_record_after_restore": authority_record_canonical_equal,
		"single_writer_preserved": String(restored_record.get("owner_server_id", "")) == SeamFactory.SERVER_A,
		"east_replica_read_only": not replica.can_write(),
		"canonical_truth_owner": false,
	}
	view.queue_free()
	await process_frame
	return true


func run() -> void:
	var okay := await exercise_persistence_rehydration()
	var report := {
		"schema": "distributed_world_simulator.mvp6_cross_authority_construction_persistence_test.v1",
		"subject_head": OS.get_environment("EXPECTED_HEAD"),
		"subject_tree": OS.get_environment("EXPECTED_TREE"),
		"passed": okay and failures.is_empty(),
		"assertions": assertions,
		"failures": failures,
		"persistence": persistence_product,
		"serialization_executed": seam_product.has("durable_items") and seam_product.has("durable_construction") and seam_product.has("durable_cluster"),
		"rehydration_executed": persistence_product.has("restored_construct_checksum"),
		"item_identity_preserved": bool(persistence_product.get("same_item_graph_after_restore", false)),
		"construction_identity_preserved": bool(persistence_product.get("same_snapshot_after_restore", false)),
		"authority_mapping_preserved": bool(persistence_product.get("same_authority_record_after_restore", false)) and bool(persistence_product.get("single_writer_preserved", false)) and bool(persistence_product.get("east_replica_read_only", false)),
		"relationships_preserved": bool(persistence_product.get("same_snapshot_after_restore", false)),
		"terminal_replay_state_preserved": bool(persistence_product.get("terminal_replay_state_preserved", false)) and bool(persistence_product.get("gateway_state_canonical_equal", false)),
		"collision_rehydrated": int(persistence_product.get("west_seam_physics_hits", 0)) > 0 and int(persistence_product.get("east_seam_physics_hits", 0)) > 0 and int(persistence_product.get("boundary_physics_hits", 0)) > 0,
		"removed_collision_stays_absent": int(persistence_product.get("removed_leaf_physics_hits", -1)) == 0,
		"full_process_restart_executed": false,
		"mvp7_restart_claimed": false,
		"mvp6_cross_authority_construction_seam_verified": false,
		"mvp6_predicate_verified": false,
		"independent_verdict": false,
	}
	cleanup6()
	var output := OS.get_environment("MVP6_PERSISTENCE_RESULT")
	var saved := output.is_empty()
	if not output.is_empty():
		saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_CROSS_AUTHORITY_CONSTRUCTION_PERSISTENCE assertions=%d failures=%d passed=%s" % [assertions, failures.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

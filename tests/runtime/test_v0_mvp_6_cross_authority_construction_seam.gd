extends "res://tests/runtime/test_v0_mvp_6_item_construction_composition.gd"

const SeamFactory = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_cross_authority_construction_factory.gd")
const SeamBridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const SeamCommand = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const SeamGrant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const DistributedCommand = preload("res://scripts/construction/distributed/construction_distributed_command.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const SalvagePolicy = preload("res://scripts/construction/damage/construction_salvage_policy.gd")
const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")

var seam_product: Dictionary = {}


func seam_construct_checksum(bundle: Dictionary) -> String:
	for row in bundle.get("constructs", []):
		if row is Dictionary and String(row.get("construct_id", "")) == SeamFactory.CONSTRUCT_ID:
			return String(row.get("checksum", ""))
	return ""


func seam_build_command(session: Dictionary, sequence: int, stage_index: int, suffix: String, bundle: Dictionary) -> Dictionary:
	return SeamCommand.create(
		"multiplayer-command/mvp6/seam/" + suffix,
		String(session.get("client_id", "")),
		String(session.get("session_id", "")),
		int(session.get("session_epoch", 0)),
		sequence,
		SeamGrant.ACTION_BUILD,
		SeamFactory.CONSTRUCT_ID,
		seam_construct_checksum(bundle),
		int(bundle.get("server_generation", 0)),
		int(session.get("permission_epoch", 0)),
		{
			"build_plan_id": SeamFactory.BUILD_PLAN_ID,
			"stage_index": stage_index,
			"operation_id": "operation/mvp6/seam/" + suffix,
			"provided_capabilities": ["FASTEN"],
			"options": {},
		}
	)


func stage_ore_for_build(graph) -> bool:
	var snapshot: Dictionary = graph.create_snapshot()
	var inventory: Dictionary = snapshot.get("inventories", {}).get("a", {})
	var hotbar: Array = Array(inventory.get("hotbar", [])).duplicate()
	for raw_id in hotbar:
		var item_id := String(raw_id)
		if item_id.is_empty(): continue
		var quantity := 0
		var definition := ""
		for row in graph.create_snapshot().get("items", []):
			if row is Dictionary and String(row.get("item_id", "")) == item_id:
				definition = String(row.get("definition_id", ""))
				quantity = int(row.get("quantity", 0))
				break
		if definition != "item/ore": continue
		if not success(native_command6("a", "seam-stage-%s" % item_id.sha256_text().left(10), "item.transfer", {
			"item_id": item_id,
			"quantity": quantity,
			"target_container_id": "inventory/a",
			"target_slot_index": -1,
		}), "stage seam ore stack into canonical inventory"): return false
	return true


func seam_parts(snapshot: Dictionary) -> int:
	return Array(snapshot.get("parts", [])).size()

func seam_bonds(snapshot: Dictionary) -> int:
	return Array(snapshot.get("bonds", [])).size()

func has_part(snapshot: Dictionary, part_id: String) -> bool:
	for row in snapshot.get("parts", []):
		if row is Dictionary and String(row.get("part_id", "")) == part_id: return true
	return false

func has_cross_seam_bond(snapshot: Dictionary) -> bool:
	for bond in snapshot.get("bonds", []):
		if not bond is Dictionary: continue
		if String(bond.get("bond_id", "")) == SeamFactory.bond_id(SeamFactory.SEAM_LEFT_INDEX):
			return String(bond.get("part_a_id", "")) == SeamFactory.part_id(SeamFactory.SEAM_LEFT_INDEX) and String(bond.get("part_b_id", "")) == SeamFactory.part_id(SeamFactory.SEAM_RIGHT_INDEX)
	return false


func exercise_cross_authority_construction_seam() -> bool:
	if not setup6(): return false
	if not seed6(): return false
	var owner = state["owners"]["authority/a"]
	var graph = owner.get_canonical_item_graph_port()
	if not success(owner.apply_canonical_server_output(
		"operation/mvp6/seam/ore-scale", "a", "item/ore", 96, "source/mvp6/seam/scale"
	), "issue exact additional native ore for 101-part seam build"): return false
	if not check(ore6(graph.create_snapshot(), "a") == 101, "seam build starts with exactly 101 canonical ore"): return false
	if not cross6("a", "authority/b", "transfer/mvp6/seam/ore-full-out", true): return false
	if not cross6("a", "authority/a", "transfer/mvp6/seam/ore-full-back", true): return false
	if not check(ore6(graph.create_snapshot(), "a") == 101, "101 ore survive nonempty A-B-A before seam build"): return false
	if not stage_ore_for_build(graph): return false
	if not check(ore6(graph.create_snapshot(), "a") == 101, "ore staging conserves all 101 canonical units"): return false

	var root := "user://mvp6-seam-construction/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var created: Dictionary = SeamFactory.create(graph, "authority/a", int(state["coordinators"]["a"].snapshot()["authority_epoch"]), root)
	if not success(created, "create single-writer 101-part seam Construction factory"): return false
	var detail: Dictionary = created.get("details", {})
	if not check(bool(detail.get("single_item_graph_identity", false)), "seam Construction uses same canonical M4 Item Graph"): return false
	if not check(bool(detail.get("damage_process_configured", false)), "seam Construction production factory configures C9 damage process"): return false
	if not check(not bool(detail.get("fixture_material_truth_present", true)), "seam Construction owns no private material truth"): return false

	var bridge = SeamBridge.new()
	if not success(bridge.setup(detail["gateway"]), "seam Construction M3 bridge setup"): return false
	var sessions: Dictionary = {}
	for actor in ["a", "b"]:
		var connected: Dictionary = bridge.connect_player(actor, int(state["coordinators"][actor].snapshot()["authority_epoch"]))
		if not success(connected, "seam Construction session " + actor): return false
		sessions[actor] = bridge.get_player_session(actor)
	if not success(detail["endpoint_a"].bind_authenticated_player("a", sessions["a"]), "bind writer endpoint actor"): return false
	if not success(detail["endpoint_b"].bind_authenticated_player("a", sessions["a"]), "bind east entry endpoint actor"): return false

	var initial_bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	var base_command := seam_build_command(sessions["a"], 0, 0, "build-base-100", initial_bundle)
	if not success(SeamCommand.validate(base_command), "base100 command validates"): return false
	var before_ore := ore6(graph.create_snapshot(), "a")
	var base_result: Dictionary = detail["endpoint_a"].submit(base_command)
	if not success(base_result, "single writer creates connected 100-part base"): return false
	if not check(before_ore - ore6(graph.create_snapshot(), "a") == 100, "base100 consumes exactly 100 real canonical ore"): return false
	var base_snapshot: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	if not check(seam_parts(base_snapshot) == 100 and seam_bonds(base_snapshot) == 99, "base Construction has exactly 100 parts and 99 bonds"): return false
	if not check(has_cross_seam_bond(base_snapshot), "base Construction has canonical bond crossing authority seam"): return false
	var base_facets: Dictionary = base_snapshot.get("compiled_facets", {})
	print("MVP6_BASE100_STATE build_state=%s semantic=%s operational=%s stage_id=%s stage_index=%s" % [String(base_snapshot.get("build_state", "")), String(base_facets.get("construction_semantic_state", "")), str(base_facets.get("operational", null)), String(base_facets.get("construction_stage_id", "")), str(base_facets.get("construction_stage_index", null))])
	if not check(String(base_snapshot.get("build_state", "")) == "PARTIAL" and String(base_facets.get("construction_semantic_state", "")) == "STRUCTURE" and not bool(base_facets.get("operational", true)), "base100 remains canonical PARTIAL/STRUCTURE pre-ADD stage"): return false

	var registered: Dictionary = SeamFactory.register_active_construct(detail)
	if not success(registered, "register one C17 canonical owner plus east read replica"): return false
	var cluster = detail["cluster"]
	var record: Dictionary = cluster.get_registry().get_record(SeamFactory.CONSTRUCT_ID)
	if not check(String(record.get("owner_server_id", "")) == SeamFactory.SERVER_A and int(record.get("authority_epoch", 0)) == 1, "C17 registry names exactly one writer A"): return false
	if not check(not cluster.get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B).can_write(), "authority B replica is read-only"): return false
	if not check(String(cluster.get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B).get_state().get("construct_checksum", "")) == String(record.get("construct_checksum", "")), "east replica starts at exact owner checksum"): return false

	var base_bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	var add_inner := seam_build_command(sessions["a"], 1, 1, "add-east-leaf", base_bundle)
	var add_route := DistributedCommand.create("authority-route/mvp6/seam/add-east", SeamFactory.SERVER_B, SeamFactory.SERVER_A, 1, add_inner, {"entry":"east", "operation":"ADD"})
	var before_add_items: Dictionary = graph.create_snapshot()
	var add_result: Dictionary = cluster.submit(SeamFactory.SERVER_B, add_route)
	if not success(add_result, "ADD enters through authority B and forwards to single writer A"): return false
	if not check(bool(add_result.get("forwarded", false)) and String(add_result.get("owner_server_id", "")) == SeamFactory.SERVER_A, "ADD route records B-entry/A-writer topology"): return false
	if not check(ore6(graph.create_snapshot(), "a") == 0, "ADD consumes final one real canonical ore exactly once"): return false
	var added_snapshot: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	if not check(seam_parts(added_snapshot) == 101 and seam_bonds(added_snapshot) == 100 and has_part(added_snapshot, SeamFactory.part_id(SeamFactory.ADD_PART_INDEX)), "ADD creates exact 101st east leaf and bond"): return false
	if not check(String(added_snapshot.get("build_state", "")) == "OPERATIONAL", "ADD transitions one canonical construct to OPERATIONAL"): return false
	if not check(String(cluster.get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B).get_state().get("construct_checksum", "")) == String(added_snapshot.get("checksum", "")), "ADD synchronizes east read replica to owner checksum"): return false
	var after_add_items: Dictionary = graph.create_snapshot()
	var add_replay: Dictionary = cluster.submit(SeamFactory.SERVER_B, add_route)
	if not success(add_replay, "exact routed ADD replay succeeds"): return false
	if not check(bool(add_replay.get("gateway_result", {}).get("replay", false)), "routed ADD replay is served terminally"): return false
	if not check(graph.create_snapshot() == after_add_items and detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID) == added_snapshot, "ADD replay duplicates neither material debit nor Construction"): return false

	var permissions = detail["gateway"].get_permission_store()
	var damage_grant := SeamGrant.create(
		"permission/mvp6/seam/damage", String(sessions["a"]["client_id"]), SeamFactory.CONSTRUCT_ID,
		[SeamGrant.ACTION_DAMAGE, SeamGrant.ACTION_READ], int(permissions.get_epoch())
	)
	if not success(permissions.publish(damage_grant), "publish explicit server DAMAGE permission"): return false
	var salvage_transform := Transform3D(Basis.IDENTITY, Vector3(float(SeamFactory.ADD_PART_INDEX) - 49.5, 0.5, 0.0))
	var damage_request := DamageRequest.create(
		"damage/mvp6/seam/remove-east-leaf", SeamFactory.CONSTRUCT_ID, String(added_snapshot["checksum"]),
		SeamFactory.part_id(0), [SeamFactory.bond_id(SeamFactory.ADD_PART_INDEX - 1)], [],
		{}, [], SalvagePolicy.create(2, ItemRelations.world(salvage_transform), false)
	)
	if not success(DamageRequest.validate(damage_request), "canonical REMOVE request validates"): return false
	var damage_bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	var remove_inner := SeamCommand.create(
		"multiplayer-command/mvp6/seam/remove-east-leaf",
		String(sessions["a"]["client_id"]), String(sessions["a"]["session_id"]), int(sessions["a"]["session_epoch"]), 2,
		SeamGrant.ACTION_DAMAGE, SeamFactory.CONSTRUCT_ID, String(added_snapshot["checksum"]), int(damage_bundle.get("server_generation", 0)), int(permissions.get_epoch()),
		{"plan_id":"plan/mvp6/seam/remove-east-leaf", "operation_id":"operation/mvp6/seam/remove-east-leaf", "request":damage_request, "failure_mode":""}
	)
	if not success(SeamCommand.validate(remove_inner), "canonical multiplayer REMOVE command validates"): return false
	var remove_route := DistributedCommand.create("authority-route/mvp6/seam/remove-east", SeamFactory.SERVER_B, SeamFactory.SERVER_A, 1, remove_inner, {"entry":"east", "operation":"REMOVE"})
	var before_remove_items: Dictionary = graph.create_snapshot()
	var remove_result: Dictionary = cluster.submit(SeamFactory.SERVER_B, remove_route)
	if not success(remove_result, "REMOVE enters through B and commits via configured C9 on writer A"): return false
	var removed_snapshot: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	if not check(seam_parts(removed_snapshot) == 100 and not has_part(removed_snapshot, SeamFactory.part_id(SeamFactory.ADD_PART_INDEX)), "REMOVE deletes only the east leaf and returns to 100 parts"): return false
	if not check(graph.create_snapshot() == before_remove_items, "REMOVE mutates structural Construction truth without touching canonical player Item Graph"): return false
	if not check(String(cluster.get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B).get_state().get("construct_checksum", "")) == String(removed_snapshot.get("checksum", "")), "REMOVE synchronizes east read replica to writer checksum"): return false
	var remove_replay: Dictionary = cluster.submit(SeamFactory.SERVER_B, remove_route)
	if not success(remove_replay, "exact routed REMOVE replay succeeds"): return false
	if not check(bool(remove_replay.get("gateway_result", {}).get("replay", false)), "REMOVE replay is terminal and does not reapply damage"): return false
	if not check(detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID) == removed_snapshot, "REMOVE replay preserves exact canonical checksum"): return false

	var stale_inner := remove_inner.duplicate(true)
	stale_inner["command_id"] = "multiplayer-command/mvp6/seam/stale-epoch-negative"
	stale_inner["sequence"] = 3
	stale_inner["checksum"] = SeamCommand.compute_checksum(stale_inner)
	var stale_route := DistributedCommand.create("authority-route/mvp6/seam/stale-epoch", SeamFactory.SERVER_B, SeamFactory.SERVER_A, 2, stale_inner, {"negative":"STALE_EPOCH"})
	var before_stale: Dictionary = detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID)
	var stale_result: Dictionary = cluster.submit(SeamFactory.SERVER_B, stale_route)
	if not check(not bool(stale_result.get("success", false)) and String(stale_result.get("error_code", "")) == "CONSTRUCTION_AUTHORITY_EPOCH_MISMATCH", "wrong authority epoch is rejected before writer mutation"): return false
	if not check(detail["authoritative_adapter"].get_construct_snapshot(SeamFactory.CONSTRUCT_ID) == before_stale, "wrong epoch cannot mutate Construction"): return false

	var durable_cluster: Dictionary = cluster.export_state()
	var durable_construction: Dictionary = detail["authoritative_adapter"].export_state()
	var durable_items: Dictionary = graph.export_durable_state()
	if not check(not durable_cluster.is_empty() and not durable_construction.is_empty() and not durable_items.is_empty(), "cluster, Construction and Item Graph all expose durable canonical payloads"): return false
	seam_product = {
		"base_snapshot": base_snapshot,
		"added_snapshot": added_snapshot,
		"removed_snapshot": removed_snapshot,
		"add_result": add_result,
		"add_replay": add_replay,
		"remove_result": remove_result,
		"remove_replay": remove_replay,
		"stale_epoch_result": stale_result,
		"authority_record": cluster.get_registry().get_record(SeamFactory.CONSTRUCT_ID),
		"east_replica": cluster.get_replica(SeamFactory.CONSTRUCT_ID, SeamFactory.SERVER_B).get_state(),
		"durable_cluster": durable_cluster,
		"durable_construction": durable_construction,
		"durable_items": durable_items,
		"item_graph_before_add": before_add_items,
	}
	return true


func run() -> void:
	var okay := exercise_cross_authority_construction_seam()
	var report := {
		"schema":"distributed_world_simulator.mvp6_cross_authority_construction_seam_test.v1",
		"subject_head":OS.get_environment("EXPECTED_HEAD"),
		"subject_tree":OS.get_environment("EXPECTED_TREE"),
		"passed":okay and failures.is_empty(),
		"assertions":assertions,
		"failures":failures,
		"product":seam_product,
		"base_part_count":100,
		"add_part_count":101,
		"remove_part_count":100,
		"single_writer_c17_executed":seam_product.has("authority_record"),
		"east_read_replica_executed":seam_product.has("east_replica"),
		"cross_authority_add_executed":seam_product.has("add_result"),
		"cross_authority_remove_executed":seam_product.has("remove_result"),
		"add_remove_replay_executed":seam_product.has("add_replay") and seam_product.has("remove_replay"),
		"wrong_epoch_negative_executed":seam_product.has("stale_epoch_result"),
		"nonempty_player_seam_carry_executed":cases6.size() == 2,
		"graphical_five_process_executed":false,
		"derived_collision_executed":false,
		"mvp6_cross_authority_construction_seam_verified":false,
		"mvp6_predicate_verified":false,
		"independent_verdict":false,
	}
	cleanup6()
	var output := OS.get_environment("MVP6_CROSS_AUTHORITY_SEAM_RESULT")
	var saved := output.is_empty()
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM assertions=%d failures=%d passed=%s" % [assertions, failures.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

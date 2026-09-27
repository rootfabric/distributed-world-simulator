extends "res://tests/runtime/test_v0_mvp_6_native_item_handoff.gd"

const ConstructionAuthority6 = preload("res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd")
const ConstructionBridge6 = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const ConstructionCommand6 = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const ConstructionGrant6 = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const ConstructionBundle6 = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")
const Presentation6 = preload("res://scripts/app/earth_construction_presentation.gd")

var construction6: Dictionary = {}

func ore6(graph: Dictionary, actor: String) -> int:
	var total := 0
	for row in graph.get("items", []):
		if row is Dictionary and String(row.get("definition_id", "")) == "item/ore":
			var loc: Dictionary = row.get("location", {})
			if String(loc.get("kind", "")) == "INVENTORY" and String(loc.get("player_id", "")) == actor:
				total += int(row.get("quantity", 0))
	return total

func construct_checksum6(bundle: Dictionary) -> String:
	for row in bundle.get("constructs", []):
		if row is Dictionary and String(row.get("construct_id", "")) == ConstructionAuthority6.CONSTRUCT_ID:
			return String(row.get("checksum", ""))
	return ""

func construction_command6(session: Dictionary, sequence: int, suffix: String, stage: int, bundle: Dictionary) -> Dictionary:
	return ConstructionCommand6.create(
		"multiplayer-command/mvp6/construction/" + suffix,
		String(session.get("client_id", "")),
		String(session.get("session_id", "")),
		int(session.get("session_epoch", 0)),
		sequence,
		ConstructionGrant6.ACTION_BUILD,
		ConstructionAuthority6.CONSTRUCT_ID,
		construct_checksum6(bundle),
		int(bundle.get("server_generation", 0)),
		int(session.get("permission_epoch", 0)),
		{
			"build_plan_id": ConstructionAuthority6.BUILD_PLAN_ID,
			"stage_index": stage,
			"operation_id": "operation/mvp6/construction/" + suffix,
			"provided_capabilities": ["INSPECT"] if stage == 2 else ["FASTEN"],
			"options": {},
		}
	)

func apply_two_presentations6(bundle: Dictionary) -> bool:
	var reports: Dictionary = {}
	for actor in ["a", "b"]:
		var adapter = Presentation6.new()
		adapter.name = "MVP6ConstructionPresentation_" + actor
		get_root().add_child(adapter)
		if not success(adapter.setup("client/mvp6/" + actor), "derived presentation setup " + actor):
			adapter.queue_free()
			return false
		var applied: Dictionary = adapter.apply_authoritative_bundle(bundle)
		if not success(applied, "authoritative Construction bundle presentation " + actor):
			adapter.queue_free()
			return false
		var details: Dictionary = applied.get("details", {})
		check(bool(details.get("outpost_present", false)), "client projection contains canonical outpost " + actor)
		check(int(details.get("proxy_mesh_count", 0)) > 0, "client has derived construction meshes " + actor)
		check(int(details.get("collision_proxy_count", 0)) > 0, "client has derived construction collision " + actor)
		check(int(details.get("collision_proxy_count", -1)) == int(details.get("proxy_mesh_count", -2)), "collision derives from exact proxy geometry " + actor)
		var report: Dictionary = adapter.get_report()
		check(int(report.get("direct_authority_references", -1)) == 0, "presentation owns no Construction authority " + actor)
		check(String(report.get("authoritative_bundle_checksum", "")) == String(bundle.get("checksum", "")), "client presents exact authoritative bundle " + actor)
		reports[actor] = {"apply": applied.duplicate(true), "report": report.duplicate(true)}
		adapter.queue_free()
	check(reports["a"]["report"]["source_checksum"] == reports["b"]["report"]["source_checksum"], "two client presentations derive same construct checksum")
	check(reports["a"]["report"]["authoritative_bundle_checksum"] == reports["b"]["report"]["authoritative_bundle_checksum"], "two client presentations derive same bundle checksum")
	construction6["presentations"] = reports
	return true

func build6() -> bool:
	var owner = state["owners"]["authority/a"]
	var graph = owner.get_canonical_item_graph_port()
	check(graph != null, "same canonical Item Graph available for Construction")
	check(ore6(graph.create_snapshot(), "a") == 8, "eight carried canonical ore units available after A-B-A")
	# The native carry fixture deliberately preserves a hotbar ore stack.
	# P4 spends inventory slots only: move that same stack through the native
	# command owner after both seam crossings, before preparing Construction.
	var carried_ore_id := String(receipts6["a"]["ore"]["details"]["output_item_id"])
	var before_storage: Dictionary = graph.create_snapshot()
	check(Array(before_storage["inventories"]["a"]["hotbar"]).has(carried_ore_id), "carried ore hotbar identity survives both seams")
	if not success(native_command6("a", "construction-storage", "item.transfer", {
		"item_id": carried_ore_id, "quantity": 5,
		"target_container_id": "inventory/a", "target_slot_index": -1,
	}), "canonical hotbar-to-inventory material staging"): return false
	var after_storage: Dictionary = graph.create_snapshot()
	check(ore6(after_storage, "a") == 8, "material staging conserves all eight canonical ore units")
	check(not Array(after_storage["inventories"]["a"]["hotbar"]).has(carried_ore_id), "native transfer clears only the moved ore hotbar alias")
	var storage_identity: Dictionary = {}
	for row in before_storage["items"]:
		storage_identity[String(row["item_id"])] = [row["definition_id"], row["quantity"]]
	var staged_identity: Dictionary = {}
	for row in after_storage["items"]:
		staged_identity[String(row["item_id"])] = [row["definition_id"], row["quantity"]]
	check(staged_identity == storage_identity, "material staging preserves every canonical item identity and quantity")
	var root := "user://mvp6-construction/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var created: Dictionary = ConstructionAuthority6.create_gateway(graph, "authority/a", int(state["coordinators"]["a"].snapshot()["authority_epoch"]), root)
	if not success(created, "accepted P4 Construction authority binds current Item Graph"): return false
	var details: Dictionary = created.get("details", {})
	check(bool(details.get("single_item_graph_identity", false)), "Construction uses same M4 Item Graph identity")
	check(not bool(details.get("fixture_material_truth_present", true)), "Construction owns no private material truth")
	var bridge = ConstructionBridge6.new()
	if not success(bridge.setup(details.get("gateway")), "accepted M3 Construction replication bridge"): return false
	var sessions: Dictionary = {}
	for actor in ["a", "b"]:
		var epoch := int(state["coordinators"][actor].snapshot()["authority_epoch"])
		var connected: Dictionary = bridge.connect_player(actor, epoch)
		if not success(connected, "Construction client session " + actor): return false
		sessions[actor] = connected.get("details", {}).get("session", {}).duplicate(true)
	var initial: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	if not success(ConstructionBundle6.validate(initial), "initial canonical Construction bundle"): return false
	check(construct_checksum6(initial).is_empty(), "no Construction exists before spending resources")
	var before_item: Dictionary = graph.create_snapshot()
	var staged: Array = []
	var consumed := [2, 4, 2]
	var a_session: Dictionary = sessions["a"]
	var last_command: Dictionary = {}
	for stage in range(3):
		var bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
		var cmd := construction_command6(a_session, stage, "stage-%d" % stage, stage, bundle)
		var before_qty := ore6(graph.create_snapshot(), "a")
		var result: Dictionary = bridge.submit_player_command("a", cmd)
		if not success(result, "real-resource Construction stage %d" % stage): return false
		var after_qty := ore6(graph.create_snapshot(), "a")
		check(before_qty - after_qty == consumed[stage], "stage %d consumes exact canonical ore" % stage)
		var replicated: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
		if not success(ConstructionBundle6.validate(replicated), "replicated canonical bundle stage %d" % stage): return false
		check(not construct_checksum6(replicated).is_empty(), "stage %d has canonical construct checksum" % stage)
		staged.append({"stage": stage, "before_ore": before_qty, "after_ore": after_qty, "command": cmd.duplicate(true), "result": result.duplicate(true), "bundle": replicated.duplicate(true)})
		last_command = cmd.duplicate(true)
	check(ore6(graph.create_snapshot(), "a") == 0, "Construction consumed exactly all eight carried ore units")
	var final_bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	var final_construct: Dictionary = details.get("live_port").get_construct_snapshot(ConstructionAuthority6.CONSTRUCT_ID)
	check(String(final_construct.get("build_state", "")) == "OPERATIONAL", "three canonical stages create one operational Construction")
	var ids: Array = []
	for row in final_bundle.get("constructs", []):
		if row is Dictionary: ids.append(String(row.get("construct_id", "")))
	check(ids.count(ConstructionAuthority6.CONSTRUCT_ID) == 1, "authoritative bundle has one Construction identity")
	var graph_after: Dictionary = graph.create_snapshot()
	var replay: Dictionary = bridge.submit_player_command("a", last_command)
	if not success(replay, "exact final Construction replay"): return false
	check(bool(replay.get("details", {}).get("result", {}).get("replay", false)), "Construction replay is served terminally")
	check(graph.create_snapshot() == graph_after, "Construction replay cannot spend resources twice")
	check(bridge.get_snapshot_packet().get("state_bundle", {}) == final_bundle, "Construction replay cannot create a second construct")
	var durable_items: Dictionary = graph.export_durable_state()
	var durable_construction: Dictionary = details.get("authoritative_adapter").export_state()
	check(not durable_items.is_empty(), "canonical Item Graph durable payload remains available")
	check(not durable_construction.is_empty(), "canonical Construction durable payload remains available")
	check(Array(durable_construction.get("construct_store", {}).get("constructs", [])).size() == 1, "Construction persistence payload contains one construct")
	construction6["authority"] = {
		"initial_bundle": initial,
		"stages": staged,
		"final_bundle": final_bundle,
		"final_construct": final_construct,
		"item_before": before_item,
		"item_after": graph_after,
		"replay": replay,
		"durable_item_graph": durable_items,
		"durable_construction": durable_construction,
	}
	return apply_two_presentations6(final_bundle)

func run() -> void:
	var okay := setup6()
	if okay: okay = seed6()
	if okay:
		var extra: Dictionary = state["owners"]["authority/a"].apply_canonical_server_output(
			"operation/mvp6/a/ore-construction-extra",
			"a",
			"item/ore",
			3,
			"source/mvp6/construction-focused"
		)
		okay = success(extra, "additional canonical ore for accepted 2/4/2 Construction recipe")
	if okay: check(ore6(graph6("authority/a"), "a") == 8, "pre-handoff canonical ore quantity is eight")
	if okay: okay = cross6("a", "authority/b", "transfer/mvp6/construction/full-out", true)
	if okay: okay = cross6("a", "authority/a", "transfer/mvp6/construction/full-back", true)
	if okay: check(ore6(graph6("authority/a"), "a") == 8, "ore identity and quantity survive nonempty A-B-A before build")
	if okay: okay = build6()
	var report := {
		"schema": "distributed_world_simulator.mvp6_item_construction_composition_test.v1",
		"subject_head": OS.get_environment("EXPECTED_HEAD"),
		"subject_tree": OS.get_environment("EXPECTED_TREE"),
		"passed": okay and failures.is_empty(),
		"assertions": assertions,
		"failures": failures,
		"handoff_cases": cases6,
		"construction": construction6,
		"native_nonempty_carry_executed": cases6.size() == 2,
		"real_resource_construction_executed": construction6.has("authority"),
		"two_client_derived_replication_executed": construction6.has("presentations"),
		"construction_collision_present": construction6.has("presentations"),
		"world_restart_executed": false,
		"graphical_network_clients_executed": false,
		"mvp6_predicate_verified": false,
		"independent_verdict": false,
	}
	cleanup6()
	var output := OS.get_environment("MVP6_CONSTRUCTION_RESULT")
	# Evidence output is optional in the canonical world/core regression runner.
	# Focused MVP6 CI provides the path and still fails closed if persistence of
	# that requested evidence fails. An absent optional path must not turn an
	# otherwise passing product test into process exit 1.
	var saved := true
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_ITEM_CONSTRUCTION_COMPOSITION assertions=%d failures=%d passed=%s" % [assertions, failures.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

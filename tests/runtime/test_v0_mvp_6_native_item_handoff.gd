extends "res://tests/runtime/test_v0_mvp3_live_owner_handoff.gd"

const Service6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_gameplay_service.gd")
var receipts6: Dictionary = {}
var cases6: Array = []

func setup6(spatial: bool = false) -> bool:
	var source = Service6.new()
	var target = Service6.new()
	services = [source, target]
	for entry in [[source, "a"], [target, "b"]]:
		if not success(entry[0].setup("authority/" + entry[1], 1, 0, {"fixed_tick_authority": true, "region_id": "region/mvp6/" + entry[1], "mvp6_spatial_validation": spatial, "mvp6_fixture_owner": entry[1] == "a"}), "MVP6 same native owners"): return false
	for actor in ["a", "b"]:
		if not success(source.join(actor, "transport-session/mvp3/" + actor, "operation/mvp6/join/" + actor), "native join"): return false
	var identity = Identity.new()
	var ledger = Ledger.new()
	var admission = Admission.new()
	var closure = Closure.new()
	if not success(ledger.configure(1024), "accepted P6 ledger"): return false
	for actor in ["a", "b"]:
		if not success(identity.bind("client-session/mvp3/" + actor, "player/mvp3/" + actor, "entity/mvp3/" + actor), "accepted P6 identity"): return false
	if not success(admission.configure(identity, ledger), "P6 admission") or not success(closure.configure(identity, ledger), "P6 closure"): return false
	var port_a = source.get_live_player_transfer_port()
	var port_b = target.get_live_player_transfer_port()
	if not check(port_a != null and port_b != null, "native combined ports"): return false
	if not success(port_a.register_peer("authority/b", port_b), "trusted B") or not success(port_b.register_peer("authority/a", port_a), "trusted A"): return false
	state = {"owners": {"authority/a": source, "authority/b": target}, "ports": {"authority/a": port_a, "authority/b": port_b}, "coordinators": {}, "carrying": {}, "pivots": {}, "ledger": ledger, "closure": closure, "identity": identity}
	for actor in ["a", "b"]:
		var coordinator = Coordinator.new()
		if not success(coordinator.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "same SM1 decision"): return false
		state["coordinators"][actor] = coordinator
		var carrying = Carry.new()
		if not success(carrying.configure(identity, ledger, closure, coordinator), "same SM1 carrying"): return false
		state["carrying"][actor] = carrying
		for port in [port_a, port_b]:
			if not success(port.bind_player(actor, "transport-session/mvp3/" + actor, 1, coordinator), "native player/item gate binding"): return false
		var by_authority: Dictionary = {}
		for authority in ["authority/a", "authority/b"]:
			var route = CommandRoute.new()
			if not success(route.configure(state["owners"][authority], actor, "transport-session/mvp3/" + actor, identity, ledger, admission, closure), "native gameplay route"): return false
			routes.append(route)
			by_authority[authority] = route
		var pivot = Pivot.new()
		if not success(pivot.configure(by_authority, coordinator, "gateway/mvp3", "client-session/mvp3/" + actor), "stable accepted pivot"): return false
		state["pivots"][actor] = pivot
	return move("a") and move("b")

func graph6(authority: String) -> Dictionary:
	return state["owners"][authority].create_canonical_item_graph_snapshot()

func owned6(snapshot: Dictionary, actor: String) -> Dictionary:
	var items: Array = []
	for row in snapshot.get("items", []):
		if row.get("location", {}).get("player_id") == actor: items.append(row)
	return {"items": items, "inventory": snapshot.get("inventories", {}).get(actor, {})}

func native_command6(actor: String, suffix: String, kind: String, payload: Dictionary) -> Dictionary:
	var decision: Dictionary = state["coordinators"][actor].snapshot()
	return state["owners"][decision["active_authority_id"]].handle_canonical_item_command(actor, "transport-session/mvp3/" + actor, 1, "operation/mvp6/" + actor + "/" + suffix, kind, payload)

func seed6() -> bool:
	for actor in ["a", "b"]:
		var owner = services[0]
		var ore: Dictionary = owner.apply_canonical_server_output("operation/mvp6/" + actor + "/ore", actor, "item/ore", 5, "source/mvp6/native-test")
		var tool: Dictionary = owner.apply_canonical_server_output("operation/mvp6/" + actor + "/tool", actor, "item/tool/mining", 1, "source/mvp6/native-test")
		if not success(ore, "real native ore") or not success(tool, "real native tool"): return false
		receipts6[actor] = {"ore": ore, "tool": tool}
		if not success(native_command6(actor, "equip", "item.equip", {"item_id": tool["details"]["output_item_id"], "slot_id": "tool/main"}), "native equipped relation"): return false
		if not success(native_command6(actor, "hotbar", "inventory.assign_hotbar", {"item_id": ore["details"]["output_item_id"], "slot_index": 2}), "real hotbar alias"): return false
	return true

func cross6(actor: String, target_id: String, transfer: String, expected_nonempty: bool) -> bool:
	var coordinator = state["coordinators"][actor]
	var decision: Dictionary = coordinator.snapshot()
	var source_id := String(decision["active_authority_id"])
	var epoch := int(decision["authority_epoch"])
	var source = state["owners"][source_id]
	var target = state["owners"][target_id]
	var source_port = state["ports"][source_id]
	var target_port = state["ports"][target_id]
	var before: Dictionary = source.get_player(actor)
	var before_items := owned6(graph6(source_id), actor)
	var other := "b" if actor == "a" else "a"
	var other_owner := String(state["coordinators"][other].snapshot()["active_authority_id"])
	var other_items := owned6(graph6(other_owner), other)
	var route_identity: Dictionary = state["pivots"][actor].get_client_route_identity()
	if not success(coordinator.begin_transfer(transfer, source_id, target_id, epoch), "SM1 freezes native source"): return false
	var frozen := graph6(source_id)
	check(not bool(source.handle_canonical_item_command(actor, "transport-session/mvp3/" + actor, 1, "operation/mvp6/" + actor + "/frozen", "inventory.select_hotbar", {"selected_hotbar_index": 0}).get("success", false)), "frozen native Service item mutation denied")
	check(not bool(source.get_canonical_item_graph_port().execute(actor, 1, "operation/mvp6/frozen-direct", "inventory.select_hotbar", {"selected_hotbar_index": 0}).get("success", false)), "direct graph cannot bypass source gate")
	check(not bool(source.apply_canonical_server_output("operation/mvp6/frozen-output", actor, "item/ore", 5, "source/mvp6/attack").get("success", false)), "frozen trusted output denied")
	check(not bool(source.get_canonical_item_graph_port().apply_server_construction_consume("operation/mvp6/frozen-consume", actor, [], 0, 0, "", "").get("success", false)), "frozen native construction debit denied")
	check(graph6(source_id) == frozen, "all rejected writes preserve source graph")
	var carry: Dictionary = state["carrying"][actor].prepare_transfer(transfer, "client-session/mvp3/" + actor, sequences[actor], last_commands[actor]["operation_id"])
	if not success(carry, "real latest input watermark"): return false
	var exported: Dictionary = source_port.prepare_export(actor, transfer, carry["details"]["manifest"])
	if not success(exported, "native nonempty item/player export"): return false
	var packet: Dictionary = exported["details"]["packet"]
	check(packet["item_payload_policy"] == "MVP6_NATIVE_ITEM_CLOSURE", "no misleading empty-carry policy")
	check((packet["item_carry"]["slice"]["items"].size() > 0) == expected_nonempty, "exact native payload has expected carrying scope")
	for item in packet["item_carry"]["slice"]["items"]:
		check(item.get("location", {}).get("player_id") == actor, "only actual actor inventory items exported")
	for record in packet["item_carry"]["slice"]["replay"].values():
		check(record.get("live_player_id") == actor and not record["result"].has("snapshot"), "native replay slice has no foreign full graph")
	# Another actor keeps using its actual owner while this one is frozen.
	if not move(other, -0.25): return false
	var outsider: Dictionary = state["owners"][other_owner].apply_canonical_server_output("operation/mvp6/" + other + "/during/" + transfer.sha256_text().left(12), other, "item/ore", 1, "source/mvp6/other")
	if not success(outsider, "other actor graph remains writable during source freeze"): return false
	var repeated_export: Dictionary = source_port.prepare_export(actor, transfer, carry["details"]["manifest"])
	if not success(repeated_export, "frozen actor export ignores unrelated graph clocks"): return false
	check(Utils.payload_hash(repeated_export["details"]["packet"]) == Utils.payload_hash(packet), "frozen item payload stable after foreign mutations")
	var target_before := graph6(target_id)
	for field in ["logical_player_id", "target_authority_id", "source_epoch", "position", "quantity"]:
		var forged := packet.duplicate(true)
		match field:
			"logical_player_id": forged[field] = other
			"target_authority_id": forged[field] = source_id
			"source_epoch": forged[field] = epoch + 10
			"position": forged["player"]["position"]["x"] = 999.0
			"quantity":
				if forged["item_carry"]["slice"]["items"].is_empty():
					forged["item_carry"]["slice"]["inventory"]["selected_hotbar_index"] = 7
				else: forged["item_carry"]["slice"]["items"][0]["quantity"] += 1
				forged["item_carry"] = Utils.finalize_json_checksum(forged["item_carry"])
		forged = Utils.finalize_json_checksum(forged)
		check(not bool(target_port.stage_export(actor, forged).get("success", false)), "rehashed tampering rejected: " + field)
		check(graph6(target_id) == target_before, "rejected packet leaves native target untouched")
	var wire = JSON.parse_string(JSON.stringify(packet, "", true, true))
	var staged: Dictionary = target_port.stage_export(actor, wire)
	if not success(staged, "real native target stage after JSON transport"): return false
	if not success(target_port.stage_export(actor, wire), "idempotent exact stage"): return false
	check(graph6(target_id) == target_before and target.get_player(actor).is_empty(), "staged items/player not published")
	check(not bool(target_port.activate_target(actor, transfer, "wrong-token").get("success", false)), "precommit activation rejected")
	var warm: Dictionary = state["carrying"][actor].build_composite_warm_report(transfer, staged["details"]["shadow_report"])
	if not success(warm, "existing composite WARM binds item slice") or not success(coordinator.validate_warm_target(transfer, target_id, warm["details"]["warm_report"]), "SM1 validates WARM"): return false
	var committed: Dictionary = coordinator.commit_ownership(transfer, source_id, target_id, epoch, epoch + 1)
	if not success(committed, "same SM1 commit"): return false
	var token := String(committed["details"]["commit_token"])
	check(not bool(target_port.activate_target(actor, transfer, token).get("success", false)), "no activation before native source retirement")
	check(not bool(source_port.retire_source(actor, transfer, "bad-token").get("success", false)), "wrong retirement proof rejected")
	if not success(source_port.retire_source(actor, transfer, token), "retire actual native player and item closure"): return false
	if not success(source_port.retire_source(actor, transfer, token), "exact retire replay"): return false
	check(owned6(graph6(source_id), actor)["items"].is_empty(), "source no longer owns carried items")
	check(not bool(source.apply_canonical_server_output("operation/mvp6/" + actor + "/ore", actor, "item/ore", 5, "source/mvp6/native-test").get("success", false)), "retired source cannot replay old issuance")
	if not success(coordinator.retire_source(transfer, source_id, token), "SM1 native retirement") or not success(coordinator.activate_target(transfer, target_id, epoch + 1, token), "SM1 target activation"): return false
	if not success(target_port.activate_target(actor, transfer, token), "native target installs ALL state then readiness"): return false
	var installed := graph6(target_id)
	if not success(target_port.activate_target(actor, transfer, token), "target activation exact replay"): return false
	check(graph6(target_id) == installed, "repeated activation causes no second native mutation")
	check(Utils.canonical_json(owned6(installed, actor)) == Utils.canonical_json(before_items), "IDs quantities slots hotbar and equipment preserved across seam")
	check(target.get_player(actor) == before and source.get_player(actor).is_empty(), "one live canonical player with unchanged identity")
	if expected_nonempty:
		var tool_id := String(receipts6[actor]["tool"]["details"]["output_item_id"])
		var tool_replay: Dictionary = target.handle_canonical_item_command(actor, "transport-session/mvp3/" + actor, 1, "operation/mvp6/" + actor + "/equip", "item.equip", {"item_id": tool_id, "slot_id": "tool/main"})
		check(tool_replay.get("success") == true and tool_replay.get("replay") == true, "native equipment replay follows actor")
		check(not bool(target.handle_canonical_item_command(actor, "transport-session/foreign", 1, "operation/mvp6/" + actor + "/equip", "item.equip", {"item_id": tool_id, "slot_id": "tool/main"}).get("success", false)), "stale session cannot exploit known native replay")
		var output_replay: Dictionary = target.apply_canonical_server_output("operation/mvp6/" + actor + "/ore", actor, "item/ore", 5, "source/mvp6/native-test")
		check(output_replay.get("success") == true and output_replay.get("replay") == true, "trusted output dedup follows actor without reissuance")
		check(graph6(target_id) == installed, "replays cannot recreate transferred output")
		check(target.get_canonical_item_graph_port().get_equipped_item(actor).get("item_id") == tool_id, "same tool is usable at target")
	if not move(actor, 0.25): return false
	check(state["pivots"][actor].get_client_route_identity() == route_identity, "gateway identity not rebound")
	if not success(state["carrying"][actor].validate_after_activation(transfer, "client-session/mvp3/" + actor, sequences[actor], last_commands[actor]["operation_id"], coordinator), "live input continues after combined activation"): return false
	var other_after := owned6(graph6(other_owner), other)
	for item in other_items["items"]:
		check(other_after["items"].has(item), "foreign original item unchanged by actor handoff")
	check(target.restore_durable_state({}).get("error_code") == "LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED", "whole gameplay restore still cannot bypass live authority")
	check(target.get_canonical_item_graph_port().restore_durable_state({}).get("error_code") == "LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED", "whole item graph restore cannot replace a bound owner")
	cases6.append({"actor": actor, "source": source_id, "target": target_id, "transfer": transfer, "token": token, "nonempty": expected_nonempty, "before": before_items, "installed": owned6(installed, actor), "packet": packet, "source_after": graph6(source_id), "target_after": graph6(target_id)})
	return true

func cleanup6() -> void:
	for route in routes: route.shutdown()
	for owner in services: owner.shutdown()
	routes.clear()
	services.clear()
	state.clear()

func run() -> void:
	var okay := setup6()
	if okay:
		check(graph6("authority/b")["items"].is_empty() and graph6("authority/b")["containers"].is_empty(), "second region does not duplicate first region fixtures")
		okay = cross6("a", "authority/b", "transfer/mvp6/empty-out", false)
	if okay: okay = cross6("a", "authority/a", "transfer/mvp6/empty-back", false)
	if okay: okay = seed6()
	if okay: okay = cross6("a", "authority/b", "transfer/mvp6/full-out", true)
	if okay: okay = cross6("a", "authority/a", "transfer/mvp6/full-back", true)
	if okay: okay = cross6("b", "authority/b", "transfer/mvp6/b-full-out", true)
	if okay: okay = cross6("b", "authority/a", "transfer/mvp6/b-full-back", true)
	if okay:
		check(not bool(state["ports"]["authority/b"].activate_target("a", "transfer/mvp6/full-out", cases6[2]["token"]).get("success", false)), "old completion cannot revive retired target")
		check(state["identity"].get_report()["counters"]["rebinds"] == 0, "no reconnect/session rebind")
	var report := {"schema": "distributed_world_simulator.mvp6_native_item_handoff_test.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "passed": okay and failures.is_empty() and cases6.size() == 6, "assertions": assertions, "failures": failures, "cases": cases6, "native_nonempty_carry_executed": true, "graphical_clients_executed": false, "world_restart_executed": false, "mvp6_predicate_verified": false, "independent_verdict": false}
	cleanup6()
	var output := OS.get_environment("MVP6_NATIVE_RESULT")
	var saved := true
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_NATIVE_ITEM_HANDOFF assertions=%d failures=%d cases=%d passed=%s" % [assertions, failures.size(), cases6.size(), str(report["passed"])])
	quit(0 if report["passed"] and saved else 1)

extends "res://tests/runtime/test_v0_mvp3_live_owner_handoff.gd"

# Diagnostic, NOT MVP6 acceptance. Exercise existing native owners without
# changing their write fences. A passing diagnostic proves the current blocker,
# not a successful nonempty transfer, graphical client or world restart.
const ItemGraph6 = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const Json6 = preload("res://scripts/network/contracts/network_contract_utils.gd")
var observed6: Dictionary = {}

func item_command6(actor: String, suffix: String, kind: String, payload: Dictionary) -> Dictionary:
	return services[0].handle_canonical_item_command(actor, "transport-session/mvp3/" + actor, 1, "operation/mvp6/prerequisite/" + suffix, kind, payload)

func item6(snapshot: Dictionary, identity: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value.get("item_id") == identity: return value
	return {}

func lifecycle6() -> bool:
	var owner6 = services[0]
	var ore: Dictionary = owner6.apply_canonical_server_output("operation/mvp6/prerequisite/ore", "a", "item/ore", 3, "source/mvp6/prerequisite-native-fixture")
	if not success(ore, "diagnostic native output, not graphical dig"): return false
	var ore_id := String(ore["details"]["output_item_id"])
	var tool: Dictionary = owner6.apply_canonical_server_output("operation/mvp6/prerequisite/tool", "a", "item/tool/mining", 1, "source/mvp6/prerequisite-native-fixture")
	if not success(tool, "diagnostic native tool"): return false
	var tool_id := String(tool["details"]["output_item_id"])
	if not success(item_command6("a", "equip", "item.equip", {"item_id": tool_id, "slot_id": "tool/main"}), "native equipment relation"): return false
	if not success(item_command6("a", "drop", "item.drop", {"item_id": ore_id, "quantity": 3}), "native full drop"): return false
	var dropped: Dictionary = owner6.create_canonical_item_graph_snapshot()
	if not check(item6(dropped, ore_id).get("location", {}).get("kind") == "WORLD", "dropped identity remains in canonical world"): return false
	var picked: Dictionary = item_command6("b", "pickup-b", "item.pickup", {"item_id": ore_id})
	if not success(picked, "other native actor picks up same identity"): return false
	var loser: Dictionary = item_command6("a", "pickup-a-loser", "item.pickup", {"item_id": ore_id})
	if not check(loser.get("success") == false and loser.get("error_code") == "ITEM_ALREADY_CLAIMED", "native serial contention has one winner"): return false
	var after_pickup: Dictionary = owner6.create_canonical_item_graph_snapshot()
	var duplicate: Dictionary = item_command6("b", "pickup-b", "item.pickup", {"item_id": ore_id})
	if not check(duplicate.get("success") == true and duplicate.get("replay") == true and owner6.create_canonical_item_graph_snapshot() == after_pickup, "exact native pickup replay cannot duplicate an item"): return false
	for actor in ["a", "b"]:
		if not success(item_command6(actor, "open-" + actor, "container.open", {"container_id": "container/shared/crate/1"}), "native shared container access " + actor): return false
	if not success(item_command6("b", "deposit-b", "item.transfer", {"item_id": ore_id, "quantity": 3, "target_container_id": "container/shared/crate/1", "target_slot_index": 0}), "native container deposit"): return false
	var deposited: Dictionary = owner6.create_canonical_item_graph_snapshot()
	if not check(item6(deposited, ore_id).get("location", {}).get("kind") == "CONTAINER", "same identity in canonical shared container"): return false
	if not success(item_command6("a", "withdraw-a", "item.transfer", {"item_id": ore_id, "quantity": 3, "target_container_id": "inventory/a", "target_slot_index": 0}), "other native actor withdraws shared item"): return false
	var final_graph: Dictionary = owner6.create_canonical_item_graph_snapshot()
	if not check(item6(final_graph, ore_id).get("quantity") == 3 and item6(final_graph, ore_id).get("location", {}).get("player_id") == "a", "quantity and identity conserved by owner lifecycle"): return false
	if not check(owner6.get_canonical_item_graph_port().get_equipped_item("a").get("item_id") == tool_id, "canonical tool stays equipped"): return false
	observed6["native_lifecycle"] = {"ore_id": ore_id, "tool_id": tool_id, "dropped": dropped, "picked": after_pickup, "deposited": deposited, "final": final_graph, "loser": loser, "serial_native_contention_only": true, "network_clients_executed": false, "spatial_gameplay_proven": false}
	return true

func persistence_payload6() -> bool:
	var graph6 = services[0].get_canonical_item_graph_port()
	var durable: Dictionary = graph6.export_durable_state()
	var replay: Dictionary = graph6.export_replay_state()
	var restored6 = ItemGraph6.new()
	if not success(restored6.setup("authority/a", 1), "isolated test-only native restoration target"): return false
	var transported = JSON.parse_string(JSON.stringify(durable, "", true, true))
	var transported_replay = JSON.parse_string(JSON.stringify(replay, "", true, true))
	if not check(transported is Dictionary and transported_replay is Dictionary, "real JSON payload roundtrip"): return false
	var restore_result: Dictionary = restored6.restore_durable_state(transported)
	if not success(restore_result, "existing native durable payload restores"): return false
	if not success(restored6.restore_replay_state(transported_replay), "existing native replay payload restores"): return false
	var restored_snapshot: Dictionary = restored6.create_snapshot()
	var restored_replay: Dictionary = restored6.export_replay_state()
	# Compare the complete existing canonical JSON contract. Do not strip the
	# checksum, clock, slot, equipment or any other field. JSON numeric type
	# normalization is owned by Json6, not a test-specific approximation.
	var expected_json := Json6.canonical_json(durable["snapshot"])
	var actual_json := Json6.canonical_json(restored_snapshot)
	observed6["persistence_payload"] = {"durable": durable, "replay": replay, "restored_snapshot": restored_snapshot, "restored_replay": restored_replay, "restore_result": restore_result, "raw_dictionary_equal": restored_snapshot == durable["snapshot"], "full_canonical_json_equal": actual_json == expected_json, "export_revision_type": type_string(typeof(durable["snapshot"]["revision"])), "restored_revision_type": type_string(typeof(restored_snapshot["revision"])), "payload_roundtrip_passed": false, "world_restart_executed": false}
	if not check(not expected_json.is_empty() and actual_json == expected_json, "full durable canonical JSON restored without any field loss"): return false
	if not check(restore_result.get("details", {}).get("slot_migration", {}).get("migrated") == false, "complete native slots need no legacy migration"): return false
	if not check(Json6.canonical_json(restored_replay) == Json6.canonical_json(replay), "full native replay payload preserved"): return false
	var corrupted: Dictionary = restored_snapshot.duplicate(true)
	corrupted["items"][0]["quantity"] = int(corrupted["items"][0]["quantity"]) + 1
	if not check(Json6.canonical_json(corrupted) != expected_json, "canonical comparison rejects changed quantity"): return false
	corrupted = restored_snapshot.duplicate(true)
	corrupted["items"][0]["location"]["slot_index"] = 31
	if not check(Json6.canonical_json(corrupted) != expected_json, "canonical comparison rejects changed slot"): return false
	var second_export: Dictionary = restored6.export_durable_state()
	if not check(Json6.canonical_json(second_export) == Json6.canonical_json(durable), "second durable export stays identical including checksums"): return false
	if not check(services[0].export_durable_state().is_empty(), "ordinary gameplay export is fenced while live bindings exist"): return false
	var rejected: Dictionary = services[0].restore_durable_state(evidence["legacy_restart_before_live"])
	observed6["persistence_payload"]["live_restore_rejection"] = rejected
	if not check(rejected.get("success") == false and rejected.get("error_code") == "LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED", "ordinary recovery cannot overwrite active live bindings"): return false
	observed6["persistence_payload"]["payload_roundtrip_passed"] = true
	return true

func nonempty_carry6() -> bool:
	var coordinator = state["coordinators"]["a"]
	var decision: Dictionary = coordinator.snapshot()
	var transfer_id := "transfer/mvp6/prerequisite/nonempty"
	var source_port = state["ports"]["authority/a"]
	var target_port = state["ports"]["authority/b"]
	var source_before: Dictionary = services[0].create_canonical_item_graph_snapshot()
	var target_before: Dictionary = services[1].create_canonical_item_graph_snapshot()
	var player_before: Dictionary = services[0].get_player("a")
	if not check(Array(source_before.get("inventories", {}).get("a", {}).get("inventory", [])).size() >= 2, "nonempty carry is real canonical ore plus equipped tool"): return false
	if not success(coordinator.begin_transfer(transfer_id, "authority/a", "authority/b", int(decision["authority_epoch"])), "actual SM1 freeze for nonempty diagnostic"): return false
	var carrying = state["carrying"]["a"]
	var prepared: Dictionary = carrying.prepare_transfer(transfer_id, "client-session/mvp3/a", sequences["a"], last_commands["a"]["operation_id"])
	if not success(prepared, "actual carrying watermark preparation"): return false
	var result: Dictionary = source_port.prepare_export("a", transfer_id, prepared["details"]["manifest"])
	var repeated: Dictionary = source_port.prepare_export("a", transfer_id, prepared["details"]["manifest"])
	# Native get_player is deliberately mutation-facing and hides a frozen
	# actor. get_players is the existing presentation read, retaining source
	# until actual retirement. Read owners only; never patch their stores.
	var source_presented: Dictionary = {}
	var target_presented: Dictionary = {}
	for row in source_port._registry.get_players():
		if row.get("logical_player_id") == "a": source_presented = row
	for row in target_port._registry.get_players():
		if row.get("logical_player_id") == "a": target_presented = row
	observed6["nonempty_carry"] = {"error_code": result.get("error_code", ""), "native_rejection": result, "repeated_rejection": repeated, "source_before": source_before, "target_before": target_before, "player_before": player_before, "source_presented_after": source_presented, "target_presented_after": target_presented, "source_mutation_view_after": services[0].get_player("a"), "empty_roundtrip_positive_control": evidence["transfers"].size() == 2, "nonempty_transfer_succeeded": false, "rejection_preserves_state": false}
	if not check(result.get("success") == false and result.get("error_code") == "MVP3_ITEM_CARRY_REQUIRES_MVP4", "current native empty-only boundary reproduced exactly"): return false
	if not check(repeated == result, "repeated diagnostic does not bypass native fence"): return false
	if not check(services[0].create_canonical_item_graph_snapshot() == source_before and services[1].create_canonical_item_graph_snapshot() == target_before, "rejected transfer loses or duplicates no item state"): return false
	if not check(source_presented == player_before and target_presented.is_empty(), "native presentation retains source identity and no target player appears"): return false
	if not check(services[0].get_player("a").is_empty() and services[1].get_player("a").is_empty(), "frozen source and unactivated target reject mutation-facing player reads"): return false
	if not check(source_port.get_prepared_export("a", transfer_id).is_empty(), "no false prepared packet escapes failed native export"): return false
	if not move("b", -0.25): return false
	observed6["nonempty_carry"]["rejection_preserves_state"] = true
	return true

func run() -> void:
	evidence = {"schema": "distributed_world_simulator.mvp6_native_prerequisite_diagnostic.v1", "transfers": []}
	var fixture_ok := setup_fixture()
	if fixture_ok: fixture_ok = move("a") and move("b")
	if fixture_ok: fixture_ok = cross("a", "authority/b", "transfer/mvp6/prerequisite/empty-out")
	if fixture_ok: fixture_ok = cross("a", "authority/a", "transfer/mvp6/prerequisite/empty-back")
	if fixture_ok: fixture_ok = lifecycle6()
	# The isolated payload comparison must not mask the separate live carry
	# diagnosis. Both results remain required for a diagnostic PASS.
	var persistence_ok := false
	var carry_ok := false
	if fixture_ok:
		persistence_ok = persistence_payload6()
		carry_ok = nonempty_carry6()
	var passed := fixture_ok and persistence_ok and carry_ok and failures.is_empty()
	var report := {"schema": "distributed_world_simulator.mvp6_native_prerequisite_diagnostic.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "diagnostic_passed": passed, "assertions": assertions, "failures": failures, "observations": observed6, "empty_transfers": evidence.get("transfers", []), "requires_native_scope_amendment": carry_ok, "mvp6_nonempty_carry_passed": false, "mvp6_predicate_verified": false, "independent_verdict": false, "network_clients_executed": false, "manual_input_executed": false, "world_restart_executed": false}
	for route in routes: route.shutdown()
	for service in services: service.shutdown()
	var output := OS.get_environment("MVP6_PREREQUISITE_RESULT")
	var saved := true
	if not output.is_empty(): saved = bool(AtomicJson.write_dictionary(output, report).get("success", false))
	print("MVP6_NATIVE_PREREQUISITE_DIAGNOSTIC assertions=%d failures=%d diagnostic_passed=%s mvp6_passed=false" % [assertions, failures.size(), str(passed)])
	quit(0 if passed and saved else 1)

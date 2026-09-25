extends SceneTree

# Native recovery prerequisite, deliberately NOT the graphical/world predicate.
# The Python parent runs produce -> recover1 -> recover2 as three actual PIDs.
const Service7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_gameplay_service.gd")
const Recovery7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_recovery_coordinator.gd")
const Repository7 = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Adapter7 = preload("res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd")
const Outbox7 = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const Decision7 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Checkpoint7 = preload("res://scripts/persistence/authoritative_checkpoint.gd")
const Utils7 = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ORE_OP7 := "operation/mvp7/native/a/ore"
const TOOL_OP7 := "operation/mvp7/native/a/tool"
const SOURCE7 := "source/mvp7/native-prerequisite-fixture"
var assertions7 := 0
var failures7: Array = []
var services7: Array = []
var coords7: Array = []
var evidence7: Dictionary = {}

func _initialize() -> void:
	call_deferred("run7")

func check7(ok: bool, label: String) -> bool:
	assertions7 += 1
	if not ok:
		failures7.append(label)
		push_error("MVP7_NATIVE_FAILURE: " + label)
	return ok

func success7(result: Dictionary, label: String) -> bool:
	return check7(bool(result.get("success", false)), label + ": " + String(result.get("error_code", "")))

func service7():
	var value = Service7.new()
	services7.append(value)
	if not success7(value.setup("authority/a", 1, 0, {"fixed_tick_authority": true, "region_id": "region/mvp7/native", "mvp6_spatial_validation": false, "mvp6_fixture_owner": true}), "native service setup"): return null
	return value

func bind7(value, generation: int) -> bool:
	var port = value.get_live_player_transfer_port()
	if not check7(port != null, "native MVP7 port available"): return false
	for actor in ["a", "b"]:
		var session := "transport-session/mvp7/native/%s/%d" % [actor, generation]
		var joined: Dictionary = value.join(actor, session, "operation/mvp7/native/join/%s/%d" % [actor, generation])
		if not success7(joined, "new native session " + actor): return false
		var decision = Decision7.new()
		coords7.append(decision)
		if not success7(decision.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "native SM1 fixture decision"): return false
		var epoch := int(value.get_player(actor).get("ownership_epoch", 0))
		if not check7(epoch == generation, "ownership epoch progression " + actor): return false
		if not success7(port.bind_player(actor, session, epoch, decision), "same native player/item owner binding"): return false
	return true

func recovery7(value, repository):
	var adapter = Adapter7.new()
	var outbox = Outbox7.new()
	var coordinator = Recovery7.new()
	if not success7(adapter.setup(value, "session/mvp7/native-world"), "native adapter setup"): return {}
	if not success7(outbox.setup(value), "native replay setup"): return {}
	if not success7(coordinator.configure(repository, adapter, outbox), "MVP7 coordinator setup"): return {}
	return {"coordinator": coordinator, "outbox": outbox, "adapter": adapter}

func item_command7(value, generation: int, operation: String, kind: String, payload: Dictionary) -> Dictionary:
	return value.handle_canonical_item_command("a", "transport-session/mvp7/native/a/%d" % generation, generation, operation, kind, payload)

func produce7(repository) -> void:
	var frozen = service7()
	if frozen == null or not bind7(frozen, 1): return
	check7(frozen.export_durable_state().is_empty(), "unsealed live export stays forbidden")
	var a_decision = coords7[coords7.size() - 2]
	if not success7(a_decision.begin_transfer("transfer/mvp7/pending", "authority/a", "authority/b", 1), "real SM1 source freeze"): return
	check7(frozen.seal_recovery_cut7().get("error_code") == "MVP7_HANDOFF_NOT_QUIESCENT", "pending handoff cannot be checkpointed")
	check7(frozen.export_durable_state().is_empty(), "rejected cut did not enable export")
	frozen.shutdown()
	var value = service7()
	if value == null or not bind7(value, 1): return
	var ore: Dictionary = value.apply_canonical_server_output(ORE_OP7, "a", "item/ore", 6, SOURCE7)
	var tool: Dictionary = value.apply_canonical_server_output(TOOL_OP7, "a", "item/tool/mining", 1, SOURCE7)
	if not success7(ore, "native fixture output") or not success7(tool, "native tool output"): return
	if not success7(item_command7(value, 1, "operation/mvp7/native/equip", "item.equip", {"item_id": tool["details"]["output_item_id"], "slot_id": "tool/main"}), "equip native relation"): return
	if not success7(item_command7(value, 1, "operation/mvp7/native/hotbar", "inventory.assign_hotbar", {"item_id": ore["details"]["output_item_id"], "slot_index": 2}), "native hotbar alias"): return
	if not success7(item_command7(value, 1, "operation/mvp7/native/container-open", "container.open", {"container_id": "container/shared/crate/1"}), "native shared container lease"): return
	var ports: Dictionary = recovery7(value, repository)
	if ports.is_empty(): return
	if not success7(ports["outbox"].stage_committed(ORE_OP7, "SERVER.OUTPUT", {"item_id": ore["details"]["output_item_id"]}), "undelivered native replay receipt"): return
	if not success7(value.seal_recovery_cut7(), "seal reconciled native cut"): return
	var durable: Dictionary = value.export_durable_state()
	if not check7(not durable.is_empty(), "sealed live snapshot exported") or not success7(value.validate_durable_state(durable), "native durable validator accepts cut"): return
	check7(durable.get("canonical_item_graph", {}).get("snapshot", {}).get("open_containers", {}).is_empty(), "transient lease is not durable")
	var before: Dictionary = value.create_canonical_item_graph_snapshot()
	check7(item_command7(value, 1, "operation/mvp7/native/after-seal", "inventory.select_hotbar", {"selected_hotbar_index": 3}).get("error_code") == "MVP7_RECOVERY_CUT_SEALED", "new client mutation fenced after seal")
	check7(value.apply_canonical_server_output("operation/mvp7/native/after-seal-output", "a", "item/ore", 1, SOURCE7).get("error_code") == "MVP7_RECOVERY_CUT_SEALED", "trusted output fenced after seal")
	check7(before == value.create_canonical_item_graph_snapshot(), "sealed graph unchanged")
	var saved: Dictionary = ports["coordinator"].persist_checkpoint("checkpoint/mvp7/native/1", 1, 0, ORE_OP7)
	if not success7(saved, "atomic native generation one checkpoint"): return
	var checkpoint: Dictionary = saved.get("details", {}).get("checkpoint", {})
	if not success7(ports["coordinator"].preflight_checkpoint7(checkpoint), "complete cut preflight"): return
	evidence7 = {"generation": 1, "checkpoint_checksum": checkpoint.get("checksum", ""), "durable_checksum": durable.get("checksum", ""), "replay_checksum": value.export_replay_state().get("checksum", ""), "item_graph_checksum": durable.get("canonical_item_graph", {}).get("snapshot", {}).get("checksum", ""), "ore_item_id": ore["details"]["output_item_id"], "tool_item_id": tool["details"]["output_item_id"], "binding": value.recovery_binding7()}

func recover7(repository, generation: int) -> void:
	var value = service7()
	if value == null: return
	var ports: Dictionary = recovery7(value, repository)
	if ports.is_empty(): return
	var loaded: Dictionary = repository.load_committed()
	if not success7(loaded, "new process reads committed native checkpoint"): return
	var checkpoint: Dictionary = loaded.get("details", {}).get("checkpoint", {})
	var durable: Dictionary = checkpoint.get("authority_state", {}).get("current_snapshot", {}).get("domain_components", {}).get("networked_gameplay_state", {})
	var original_graph: Dictionary = value.create_canonical_item_graph_snapshot()
	var bad_replay: Dictionary = checkpoint["replay_state"].duplicate(true)
	bad_replay["checksum"] = "0".repeat(64)
	var bad_checkpoint: Dictionary = Checkpoint7.create("checkpoint/mvp7/native/invalid", generation + 1, generation, checkpoint["authority_state"], bad_replay, "", int(checkpoint["server_tick"]))
	check7(not bool(ports["coordinator"].preflight_checkpoint7(bad_checkpoint).get("success", false)), "malformed replay rejected before restore")
	check7(value.create_canonical_item_graph_snapshot() == original_graph, "bad replay did not partially restore gameplay")
	if not success7(ports["coordinator"].require_minimum_generation7(generation), "bind expected committed generation"): return
	if not success7(ports["coordinator"].recover_latest(), "new process recovers native cut"): return
	check7(value.export_durable_state().get("checksum") == durable.get("checksum"), "durable state checksum exact after process restart")
	check7(value.export_replay_state().get("checksum") == checkpoint["replay_state"]["gameplay_replay"]["checksum"], "required native replay checksum exact")
	check7(ports["outbox"].get_pending_records().size() == 1, "undelivered receipt survives process restart")
	check7(ports["coordinator"].recover_latest().get("error_code") == "MVP7_RECOVERY_ALREADY_APPLIED", "no repeat recovery into running owner")
	var graph: Dictionary = value.create_canonical_item_graph_snapshot()
	check7(graph.get("checksum") == durable.get("canonical_item_graph", {}).get("snapshot", {}).get("checksum"), "world/inventory/equipment/container graph exact")
	var ids: Dictionary = {}
	for row in graph.get("items", []):
		check7(not ids.has(row["item_id"]), "unique restored item identity " + String(row["item_id"]))
		ids[row["item_id"]] = true
	check7(ids.has("item/shared/crate/1") and ids.has("item/shared/beacon/1"), "world fixture identities preserved")
	for actor in ["a", "b"]:
		var player: Dictionary = value.get_player(actor)
		check7(player.get("connected") == false and player.get("transport_session_id") == "", "stale session cleared " + actor)
	check7(not bool(item_command7(value, generation, "operation/mvp7/native/hotbar", "inventory.assign_hotbar", {"item_id": "item/not-trusted", "slot_index": 2}).get("success", false)), "historical operation cannot bypass disconnected authentication")
	evidence7 = {"generation_restored": generation, "recovered_checkpoint_checksum": checkpoint.get("checksum", ""), "recovered_durable_checksum": value.export_durable_state().get("checksum", ""), "recovered_replay_checksum": value.export_replay_state().get("checksum", ""), "recovered_item_graph_checksum": graph.get("checksum", ""), "recovered_inventory": graph.get("inventories", {}).get("a", {}), "recovered_container_count": graph.get("containers", []).size()}
	if generation == 2:
		check7(graph.get("inventories", {}).get("a", {}).get("selected_hotbar_index", -1) == 3, "second recovery gets post-reconnect current state")
		return
	if not bind7(value, 2): return
	var before_replay: Dictionary = value.create_canonical_item_graph_snapshot()
	var replay: Dictionary = value.apply_canonical_server_output(ORE_OP7, "a", "item/ore", 6, SOURCE7)
	if not success7(replay, "native output replay after reconnect"): return
	check7(bool(replay.get("replay", false)) or bool(replay.get("details", {}).get("replay", false)), "native output marked replay")
	check7(value.create_canonical_item_graph_snapshot() == before_replay, "no duplicate output after process restart")
	if not success7(item_command7(value, 2, "operation/mvp7/native/post-reconnect/hotbar", "inventory.select_hotbar", {"selected_hotbar_index": 3}), "new authenticated operation after recovery"): return
	check7(not bool(item_command7(value, 1, "operation/mvp7/native/stale-session/new", "inventory.select_hotbar", {"selected_hotbar_index": 0}).get("success", false)), "old session and epoch stay rejected")
	if not success7(value.seal_recovery_cut7(), "seal generation two"): return
	var saved: Dictionary = ports["coordinator"].persist_checkpoint("checkpoint/mvp7/native/2", 2, 1, "operation/mvp7/native/post-reconnect/hotbar")
	if not success7(saved, "post-reconnect generation two committed"): return
	evidence7["generation"] = 2
	evidence7["checkpoint_checksum"] = saved.get("details", {}).get("checkpoint", {}).get("checksum", "")
	evidence7["durable_checksum"] = value.export_durable_state().get("checksum", "")
	evidence7["replay_checksum"] = value.export_replay_state().get("checksum", "")
	evidence7["item_graph_checksum"] = value.export_durable_state().get("canonical_item_graph", {}).get("snapshot", {}).get("checksum", "")
	var floor = Recovery7.new()
	if not success7(floor.configure(repository, ports["adapter"], ports["outbox"]), "floor negative setup"): return
	if not success7(floor.require_minimum_generation7(2), "raise immutable generation floor"): return
	check7(floor.preflight_checkpoint7(checkpoint).get("error_code") == "MVP7_RECOVERY_GENERATION_ROLLBACK", "older valid checkpoint cannot satisfy newer required cut")

func run7() -> void:
	var mode := OS.get_environment("MVP7_NATIVE_MODE")
	var root := OS.get_environment("MVP7_NATIVE_ROOT")
	var target := OS.get_environment("MVP7_NATIVE_RESULT")
	var repository = Repository7.new()
	if check7(mode in ["produce", "recover1", "recover2"] and not root.is_empty() and not target.is_empty(), "bounded native process configuration") and success7(repository.configure(root), "existing M6 repository configured"):
		if mode == "produce": produce7(repository)
		elif mode == "recover1": recover7(repository, 1)
		else: recover7(repository, 2)
	check7(not evidence7.is_empty(), "process completed all required stages")
	for value in services7:
		value.shutdown()
	services7.clear()
	coords7.clear()
	var result := {"schema": "distributed_world_simulator.mvp7_native_recovery_result.v1", "mode": mode, "process_id": OS.get_process_id(), "subject_head": OS.get_environment("EXPECTED_HEAD"), "passed": failures7.is_empty(), "assertions": assertions7, "failures": failures7, "evidence": evidence7, "scope": "NATIVE_QUIESCENT_GAMEPLAY_PREREQUISITE", "fixture_material_source": SOURCE7, "graphical_world_predicate_executed": false, "mvp7_predicate_verified": false}
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		quit(2)
		return
	file.store_string(JSON.stringify(result, "\t", true, true) + "\n")
	file.close()
	print("MVP7_NATIVE_RECOVERY_", "PASS" if failures7.is_empty() else "FAIL", " mode=", mode, " assertions=", assertions7, " failures=", failures7.size())
	quit(0 if failures7.is_empty() else 1)

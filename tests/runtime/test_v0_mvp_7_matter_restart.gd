extends "res://tests/runtime/test_v0_mvp_5_exactly_once_material.gd"

# Three OS processes. Real P7/MW4 digging, MW5 disk persistence, M6 native Item
# owner and two independent MW6 surface nodes. This is not an ENet reconnect or
# the full graphical/Construction predicate; those remain separate gates.
const Gameplay7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_gameplay_service.gd")
const Shared7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_shared_dig_authority.gd")
const Adapter7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_matter_gameplay_authority_adapter.gd")
const Recovery7 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_recovery_coordinator.gd")
const Repository7 = preload("res://scripts/persistence/authoritative_recovery_repository.gd")
const Outbox7 = preload("res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd")
const MatterUtils7 = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Codec7 = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
var result7: Dictionary = {}
var adapter7 = null
var coordinator7 = null
var world_root7 := ""
var new_plan7: Dictionary = {}

func setup_world7(generation: int, recovering: bool) -> bool:
	owner = Gameplay7.new()
	if not success(owner.setup("authority/a", 1, 0, {"fixed_tick_authority": true, "region_id": "region/mvp7/matter", "mvp6_spatial_validation": false, "mvp6_fixture_owner": true}), "MVP7 canonical gameplay owner"): return false
	for actor in ["a", "b"]:
		sessions[actor] = "transport-session/mvp7/matter/%s/%d" % [actor, generation + 1 if recovering else 1]
		var decision = Coordinator.new()
		if not success(decision.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + actor, "player_entity_id": "entity/mvp3/" + actor, "last_input_sequence": 0, "last_operation_id": ""}), "existing SM1 decision"): return false
		decisions[actor] = decision
	bridge = Shared7.new()
	if not success(bridge.configure(owner, decisions, sessions), "same-owner Matter/P7 wiring"): return false
	var repository = Repository7.new()
	if not success(repository.configure(world_root7 + "/gameplay"), "native M6 repository"): return false
	adapter7 = Adapter7.new()
	if not success(adapter7.setup(owner, "session/mvp7/matter-world"), "native M6 adapter"): return false
	if not success(adapter7.configure_matter7(bridge, decisions, sessions, world_root7), "coupled M6/MW5 cut participant"): return false
	var replay = Outbox7.new()
	if not success(replay.setup(owner), "native required replay owner"): return false
	coordinator7 = Recovery7.new()
	if not success(coordinator7.configure(repository, adapter7, replay), "M6 commit record coordinator"): return false
	if recovering:
		if not success(coordinator7.require_minimum_generation7(generation), "bind required world generation"): return false
		var loaded: Dictionary = repository.load_committed()
		if not success(loaded, "native disk checkpoint in new PID"): return false
		var checkpoint: Dictionary = loaded["details"]["checkpoint"]
		var original: Dictionary = owner.create_canonical_item_graph_snapshot()
		var mixed: Dictionary = checkpoint["authority_state"].duplicate(true)
		var cut: Dictionary = mixed["current_snapshot"]["domain_components"][adapter7.CUT_FIELD7]
		cut["gameplay_checksum"] = "0".repeat(64)
		check(not bool(adapter7.validate_recovery_state(mixed).get("success", false)), "mixed cut rejected before canonical mutation")
		check(owner.create_canonical_item_graph_snapshot() == original, "failed preflight leaves Item owner untouched")
		if not success(coordinator7.recover_latest(), "restore native gameplay and committed MW5 reference"): return false
		bridge = adapter7.get_shared_matter7()
		check(adapter7.export_recovery_state()["current_snapshot"]["checksum"] == checkpoint["authority_state"]["current_snapshot"]["checksum"], "coupled checkpoint round-trip exact")
		var saved_graph: Dictionary = checkpoint["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]["canonical_item_graph"]["snapshot"]
		check(owner.create_canonical_item_graph_snapshot()["checksum"] == saved_graph["checksum"], "same persisted Item identities before session renewal")
		result7["recovered_checkpoint_checksum"] = checkpoint["checksum"]
		result7["recovered_item_graph_checksum"] = saved_graph["checksum"]
		result7["recovered_store_hash"] = bridge.report()["store_hash"]
		result7["recovered_state_hash"] = bridge.report()["state_hash"]
	var port = owner.get_live_player_transfer_port()
	if not check(port != null, "native live owner port"): return false
	for actor in ["a", "b"]:
		if not success(owner.join(actor, sessions[actor], "operation/mvp7/matter/join/%s/%d" % [actor, generation + 1 if recovering else 1]), "new native authenticated player session"): return false
		var epoch := int(owner.get_player(actor)["ownership_epoch"])
		check(epoch == (generation + 1 if recovering else 1), "ownership epoch advances after restart")
		if not success(port.bind_player(actor, sessions[actor], epoch, decisions[actor]), "same native ownership and Item gate"): return false
		var projection = Surface.new()
		root.add_child(projection)
		replicas[actor] = projection
		if not success(projection.configure_actor(actor, sessions[actor], false), "independent derived surface"): return false
		if not success(bridge.connect_replica(actor, sessions[actor], projection.create_sync_request()), "new current-state replica subscription") or not drain(actor): return false
		check(replicas[actor].contract_report()["store_hash"] == bridge.report()["store_hash"], "replica receives CURRENT persisted terrain " + actor)
		if not recovering and not success(bridge.equip_tool(actor, sessions[actor]), "initial tool only; never mint during recovery"): return false
	check(replicas["a"].contract_report()["geometry_hash"] == replicas["b"].contract_report()["geometry_hash"], "independent recovered geometry agrees")
	return true

func save_world7(generation: int) -> bool:
	if not success(adapter7.prepare_checkpoint7(generation), "freeze same native owners and stage immutable MW5 generation"): return false
	check(bridge.prepare_dig("a", sessions["a"], "operation/mvp4/a/after-seal", [0.0, -1.0, 0.0]).get("error_code") == "MVP7_MATTER_CUT_SEALED", "sealed terrain rejects new dig")
	var saved: Dictionary = coordinator7.persist_checkpoint("checkpoint/mvp7/matter/%d" % generation, generation, generation - 1, "")
	if not success(saved, "native M6 commit publishes matched gameplay and terrain cut"): return false
	result7["checkpoint_checksum"] = saved["details"]["checkpoint"]["checksum"]
	result7["item_graph_checksum"] = owner.create_canonical_item_graph_snapshot()["checksum"]
	result7["store_hash"] = bridge.report()["store_hash"]
	result7["state_hash"] = bridge.report()["state_hash"]
	result7["generation"] = generation
	result7["geometry_hash"] = replicas["a"].contract_report()["geometry_hash"]
	return true

func dig_new7(actor: String, suffix: String) -> bool:
	var prepared: Dictionary = {}
	for direction in [[0.0, -1.0, 0.0], [0.6, -0.8, 0.0], [-0.6, -0.8, 0.0], [0.0, -0.8, 0.6]]:
		prepared = bridge.prepare_dig(actor, sessions[actor], "operation/mvp4/" + actor + "/mvp7-" + suffix, direction)
		if bool(prepared.get("success", false)): break
	if not success(prepared, "canonical current-world aim"): return false
	new_plan7 = prepared["details"].duplicate(true)
	var before: Dictionary = bridge.report()
	var result: Dictionary = bridge.execute_prepared(actor, sessions[actor], new_plan7)
	if not success(result, "real canonical dig and native material delivery"): return false
	check(result["details"]["material_output"]["output_created_this_call"] == true, "new dig issues actual material once")
	check(int(result["details"]["material_output"]["output_quantity"]) > 0, "nonzero material is from terrain, not fixture top-up")
	check(bridge.report()["store_hash"] != before["store_hash"] and int(bridge.report()["stream_sequence"]) == int(before["stream_sequence"]) + 1, "one terrain commit and one stream advance")
	if not drain("a") or not drain("b"): return false
	check(replicas["a"].contract_report()["store_hash"] == bridge.report()["store_hash"] and replicas["b"].contract_report()["store_hash"] == bridge.report()["store_hash"], "both replicas receive post-recovery change")
	result7["new_output_receipt"] = result["details"]["material_output"]
	return true

func replay_old7() -> bool:
	var oracle_file := FileAccess.open(world_root7 + "/produce-oracle.json", FileAccess.READ)
	if not check(oracle_file != null, "test witness exists, never used as restored world state"): return false
	var oracle: Dictionary = JSON.parse_string(oracle_file.get_as_text())
	oracle_file.close()
	var old_plan: Dictionary = oracle["plan"]
	check(not bool(bridge.execute_prepared("a", sessions["a"], old_plan).get("success", false)), "old transient MAC invalid after process restart")
	check(not bool(bridge.authorize_committed_replay7("a", "transport-session/mvp7/matter/a/1", old_plan["request_transport"]).get("success", false)), "old credentials cannot renew known replay")
	check(not bool(bridge.authorize_committed_replay7("b", sessions["b"], old_plan["request_transport"]).get("success", false)), "foreign actor cannot renew replay")
	var request: Dictionary = Codec7.decode_persistence_json(old_plan["request_transport"])
	request["operation_id"] = "operation/mvp4/a/mvp7-never-committed"
	request["checksum"] = MatterUtils7.compute_checksum(request)
	check(not bool(bridge.authorize_committed_replay7("a", sessions["a"], Codec7.encode_persistence_json(request)).get("success", false)), "unknown operation cannot use replay path to bypass canonical aim")
	var graph_before := graph5()
	var matter_before: Dictionary = bridge.report()
	var attested: Dictionary = bridge.authorize_committed_replay7("a", sessions["a"], old_plan["request_transport"])
	if not success(attested, "reauthorize persisted request with CURRENT session"): return false
	var replayed: Dictionary = bridge.execute_prepared("a", sessions["a"], attested["details"])
	if not success(replayed, "native terminal Matter replay after restart"): return false
	var receipt: Dictionary = replayed["details"]["material_output"]
	check(receipt["output_item_id"] == oracle["receipt"]["output_item_id"] and receipt["output_quantity"] == oracle["receipt"]["output_quantity"], "original material identity and amount survive replay")
	check(receipt["matter_replay"] == true and receipt["item_graph_replay"] == true and receipt["output_created_this_call"] == false, "both canonical effects are replays")
	check(graph5() == graph_before and bridge.report()["store_hash"] == matter_before["store_hash"] and bridge.report()["stream_sequence"] == matter_before["stream_sequence"], "no extra item, carve, revision or stream advance")
	return true

func run() -> void:
	world_root7 = OS.get_environment("MVP7_WORLD_ROOT")
	var mode := OS.get_environment("MVP7_WORLD_MODE")
	var completed := false
	if check(not world_root7.is_empty() and mode in ["produce", "recover1", "recover2"], "bounded process configuration"):
		if mode == "produce" and setup_world7(1, false) and dig_new7("a", "initial"):
			var oracle := {"plan": new_plan7, "receipt": result7["new_output_receipt"], "test_only": true}
			if check(Support.write_json(world_root7 + "/produce-oracle.json", oracle), "write test-only request witness"):
				completed = save_world7(1)
		elif mode == "recover1" and setup_world7(1, true) and replay_old7() and dig_new7("b", "continued"):
			completed = save_world7(2)
		elif mode == "recover2" and setup_world7(2, true) and replay_old7():
			check(int(bridge.report()["stream_sequence"]) == 2, "second recovery includes post-reconnect dig")
			completed = true
	check(completed, "all process stages completed")
	result7["process_id"] = OS.get_process_id()
	result7["subject_head"] = OS.get_environment("EXPECTED_HEAD")
	result7["mode"] = mode
	result7["assertions"] = assertions
	result7["failures"] = failures
	result7["passed"] = failures.is_empty()
	result7["scope"] = "M6_MW5_THREE_PROCESS_RECOVERY_AND_TWO_MW6_PROJECTIONS"
	result7["mvp7_predicate_verified"] = false
	result7["enet_reconnect_executed"] = false
	result7["construction_recovery_executed"] = false
	var target := OS.get_environment("MVP7_WORLD_RESULT")
	var written := not target.is_empty() and Support.write_json(target, result7)
	cleanup5()
	adapter7 = null
	coordinator7 = null
	print("MVP7_WORLD_RECOVERY ", mode, " passed=", failures.is_empty() and written, " assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() and written else 1)

extends SceneTree

const FixtureScript = preload("res://tests/matter/handoff/mw8_test_fixture.gd")
const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const RegionScript = preload("res://scripts/simulation/matter/handoff/matter_authority_region.gd")
const LeaseScript = preload("res://scripts/simulation/matter/handoff/matter_authority_lease.gd")
const PackageScript = preload("res://scripts/simulation/matter/handoff/matter_handoff_package.gd")
const TicketScript = preload("res://scripts/simulation/matter/handoff/matter_client_handoff_ticket.gd")
const MW7FixtureScript = preload("res://tests/matter/interest/mw7_test_fixture.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")

var assertions: int = 0
var failures: Array[String] = []
var manifest: Dictionary = {}
var _root_path: String = ""
var _suite_started_usec: int = 0
var _clusters_to_shutdown: Array[Dictionary] = []


func _init() -> void:
	_suite_started_usec = Time.get_ticks_usec()
	_root_path = ProjectSettings.globalize_path(
		"user://mw8-handoff-%d" % Time.get_ticks_usec()
	)
	DirAccess.make_dir_recursive_absolute(_root_path)
	print("MW8 regional authority handoff: START")
	_load_manifest()
	_run_stage("contracts-freeze-abort", Callable(self, "_test_contracts_freeze_and_abort"))
	_run_stage("successful-handoff-reconnect", Callable(self, "_test_successful_handoff_and_reconnect"))
	_run_stage("split-brain-cross-region", Callable(self, "_test_split_brain_and_cross_region_fences"))
	_finish()


func _run_stage(label: String, test_case: Callable) -> void:
	var started_usec: int = Time.get_ticks_usec()
	print("MW8 stage %s: START" % label)
	test_case.call()
	print("MW8 stage %s: DONE (%.3f s)" % [
		label, float(Time.get_ticks_usec() - started_usec) / 1000000.0,
	])


func _load_manifest() -> void:
	var path: String = "res://config/matter/mw8-matter-authority-handoff.v1.json"
	var file = FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "MW8 manifest missing")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_assert(typeof(parsed) == TYPE_DICTIONARY, "MW8 manifest JSON invalid")
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed
		_assert(String(manifest.get("checkpoint", "")) == "v17.8.0-simulation-mw8-regional-authority-handoff", "MW8 manifest checkpoint changed")
		_assert(String(manifest.get("handoff_protocol", "")) == "FREEZE_PREPARE_COMMIT", "MW8 manifest protocol changed")


func _test_contracts_freeze_and_abort() -> void:
	var cluster: Dictionary = FixtureScript.create_cluster(_root_path.path_join("abort"))
	_assert_ok(cluster, "MW8 abort cluster setup failed")
	if not bool(cluster.get("success", false)):
		return
	_clusters_to_shutdown.append(cluster)
	var region: Dictionary = cluster["region"]
	_assert(bool(RegionScript.validate_for_grid(cluster["source_context"]["grid_profile"], region).get("success", false)), "MW8 region contract invalid")
	var lease: Dictionary = cluster["directory"].resolve_region(FixtureScript.REGION_ID)
	_assert(bool(LeaseScript.validate(lease).get("success", false)), "MW8 active lease contract invalid")
	_assert(String(lease.get("owner_id", "")) == FixtureScript.SOURCE_OWNER_ID, "MW8 initial owner changed")
	_assert(String(lease.get("status", "")) == "ACTIVE", "MW8 initial lease not active")
	var request: Dictionary = FixtureScript.request(
		cluster, "source", cluster["fixtures"][0],
		"operation/mw8/abort/probe", "actor/mw8/abort"
	)
	_assert(not request.is_empty(), "MW8 abort probe request missing")
	_assert_ok(cluster["source"]["gate"].authorize_mutation(request), "MW8 source gate rejected active lease")
	var target_before: Dictionary = cluster["target"]["gate"].authorize_mutation(request)
	_assert(not bool(target_before.get("success", false)), "MW8 target gate accepted region before handoff")
	_assert(String(target_before.get("error_code", "")) == "MATTER_REGION_NOT_OWNED_BY_SERVER", "MW8 target pre-handoff error changed")
	var begun: Dictionary = cluster["directory"].begin_handoff(
		"transfer/mw8/abort",
		FixtureScript.REGION_ID,
		FixtureScript.SOURCE_OWNER_ID,
		FixtureScript.SOURCE_EPOCH,
		FixtureScript.TARGET_OWNER_ID,
		FixtureScript.TARGET_EPOCH
	)
	_assert_ok(begun, "MW8 manual handoff begin failed")
	var conflicting_replay: Dictionary = cluster["directory"].begin_handoff(
		"transfer/mw8/abort",
		FixtureScript.REGION_ID,
		FixtureScript.SOURCE_OWNER_ID,
		FixtureScript.SOURCE_EPOCH,
		FixtureScript.TARGET_OWNER_ID,
		FixtureScript.TARGET_EPOCH + 1
	)
	_assert(not bool(conflicting_replay.get("success", false)), "MW8 transfer fingerprint conflict accepted")
	_assert(String(conflicting_replay.get("error_code", "")) == "MATTER_HANDOFF_TRANSFER_FINGERPRINT_CONFLICT", "MW8 transfer fingerprint error changed")
	var package_result: Dictionary = cluster["source"]["endpoint"].build_package(
		"transfer/mw8/abort", FixtureScript.REGION_ID,
		FixtureScript.TARGET_OWNER_ID, FixtureScript.TARGET_EPOCH
	)
	_assert_ok(package_result, "MW8 abort package build failed")
	if bool(package_result.get("success", false)):
		var wrong_world_package: Dictionary = Dictionary(package_result["details"]["package"]).duplicate(true)
		wrong_world_package["body_definition_hash"] = "0".repeat(64)
		wrong_world_package["checksum"] = MatterUtilsScript.compute_checksum(wrong_world_package)
		var wrong_world_result: Dictionary = cluster["target"]["endpoint"].prepare_import(wrong_world_package)
		_assert(not bool(wrong_world_result.get("success", false)), "MW8 wrong-world package accepted")
		_assert(String(wrong_world_result.get("error_code", "")) == "MATTER_HANDOFF_PACKAGE_WORLD_MISMATCH", "MW8 wrong-world package error changed")
		var stale_lease_package: Dictionary = Dictionary(package_result["details"]["package"]).duplicate(true)
		stale_lease_package["directory_revision"] = int(stale_lease_package["directory_revision"]) + 1
		stale_lease_package["checksum"] = MatterUtilsScript.compute_checksum(stale_lease_package)
		var stale_lease_result: Dictionary = cluster["target"]["endpoint"].prepare_import(stale_lease_package)
		_assert(not bool(stale_lease_result.get("success", false)), "MW8 stale-lease package accepted")
		_assert(String(stale_lease_result.get("error_code", "")) == "MATTER_HANDOFF_PACKAGE_LEASE_BINDING_MISMATCH", "MW8 stale-lease package error changed")
	var frozen: Dictionary = cluster["source"]["gate"].authorize_mutation(request)
	_assert(not bool(frozen.get("success", false)), "MW8 source accepted mutation while frozen")
	_assert(String(frozen.get("error_code", "")) == "MATTER_AUTHORITY_HANDOFF_IN_PROGRESS", "MW8 freeze error changed")
	var target_frozen: Dictionary = cluster["target"]["gate"].authorize_mutation(request)
	_assert(not bool(target_frozen.get("success", false)), "MW8 target accepted mutation before commit")
	_assert_ok(cluster["directory"].abort_handoff("transfer/mw8/abort"), "MW8 handoff abort failed")
	_assert_ok(cluster["source"]["gate"].authorize_mutation(request), "MW8 source did not resume after abort")
	_assert(not cluster["target"]["gate"].owns_region(FixtureScript.REGION_ID), "MW8 target owns aborted region")

	# A target with an active peer cannot rebase imported state. The coordinator must compensate.
	var blocker: Dictionary = cluster["target"]["authority"].connect_interest_peer(
		"peer/mw8/abort-blocker", "client/mw8/abort-blocker",
		"session/mw8/abort-blocker", "actor/mw8/abort-blocker"
	)
	_assert_ok(blocker, "MW8 target blocker peer failed")
	var failed_handoff: Dictionary = cluster["coordinator"].execute_handoff(
		"transfer/mw8/compensate",
		FixtureScript.REGION_ID,
		cluster["source"]["endpoint"],
		cluster["target"]["endpoint"],
		FixtureScript.TARGET_EPOCH,
		[]
	)
	_assert(not bool(failed_handoff.get("success", false)), "MW8 compensated handoff unexpectedly succeeded")
	_assert(String(failed_handoff.get("error_code", "")) == "MATTER_HANDOFF_TARGET_PREPARE_FAILED", "MW8 compensation error changed")
	var restored_lease: Dictionary = cluster["directory"].resolve_region(FixtureScript.REGION_ID)
	_assert(String(restored_lease.get("status", "")) == "ACTIVE", "MW8 compensation left lease frozen")
	_assert(String(restored_lease.get("owner_id", "")) == FixtureScript.SOURCE_OWNER_ID, "MW8 compensation changed owner")
	_assert(cluster["target_context"]["service"].snapshot_store().size() == 0, "MW8 compensation retained target snapshots")
	_assert(cluster["target_context"]["service"].mutation_journal().size() == 0, "MW8 compensation retained target journal")
	_assert(cluster["target_context"]["service"].material_receiver().batch_count() == 0, "MW8 compensation retained target batches")
	_assert(cluster["target"]["endpoint"].prepared_count() == 0, "MW8 compensation retained prepared transfer")


func _test_successful_handoff_and_reconnect() -> void:
	var cluster: Dictionary = FixtureScript.create_cluster(_root_path.path_join("success"))
	_assert_ok(cluster, "MW8 success cluster setup failed")
	if not bool(cluster.get("success", false)):
		return
	_clusters_to_shutdown.append(cluster)
	var source_client = FixtureScript.create_replica(cluster, "source", "client/mw8/miner")
	_assert(source_client != null, "MW8 source client setup failed")
	if source_client == null:
		return
	_assert_ok(source_client.set_interest(
		"subscription/mw8/miner", 1,
		cluster["region"]["center_cell_address"],
		int(cluster["region"]["radius_cells"])
	), "MW8 source interest failed")
	_assert_ok(FixtureScript.connect_replica(
		cluster, "source", source_client,
		"peer/mw8/source/miner", "session/mw8/source/miner", "actor/mw8/miner"
	), "MW8 source client connect failed")
	var first: Dictionary = FixtureScript.send_mutation(
		cluster, "source", source_client, cluster["fixtures"][0],
		"operation/mw8/miner/one", "actor/mw8/miner", "message/mw8/miner/one"
	)
	_assert_ok(first, "MW8 source mutation failed")
	_assert_ok(FixtureScript.dispatch_and_poll(
		cluster, "source", source_client, "peer/mw8/source/miner"
	), "MW8 source regional replication failed")
	_assert(source_client.snapshot_store().size() >= 1, "MW8 source client did not receive persistent brick")
	var original_request: Dictionary = first.get("request", {})
	var source_snapshot_hash: String = cluster["source_context"]["service"].snapshot_store().content_hash()
	var source_journal_hash: String = cluster["source_context"]["service"].mutation_journal().content_hash()
	var source_batch_count: int = cluster["source_context"]["service"].material_receiver().batch_count()

	cluster["source"]["interest_server"].disconnect_peer("peer/mw8/source/miner")
	cluster["source"]["authority"].disconnect_peer("peer/mw8/source/miner")
	var handoff: Dictionary = cluster["coordinator"].execute_handoff(
		"transfer/mw8/miner",
		FixtureScript.REGION_ID,
		cluster["source"]["endpoint"],
		cluster["target"]["endpoint"],
		FixtureScript.TARGET_EPOCH,
		["client/mw8/miner"]
	)
	_assert_ok(handoff, "MW8 successful handoff failed")
	if not bool(handoff.get("success", false)):
		return
	var package: Dictionary = handoff["details"]["package"]
	_assert(bool(PackageScript.validate_for_grid(package, cluster["source_context"]["grid_profile"]).get("success", false)), "MW8 transfer package invalid")
	_assert(package["snapshot_transports"].size() >= 1, "MW8 package omitted persistent snapshots")
	_assert(package["journal_records"].size() == 1, "MW8 package journal count changed")
	_assert(package["batch_transports"].size() == source_batch_count, "MW8 package batch count changed")
	var tickets: Array = handoff["details"]["tickets"]
	_assert(tickets.size() == 1, "MW8 client ticket count changed")
	var ticket: Dictionary = tickets[0] if not tickets.is_empty() else {}
	_assert(bool(TicketScript.validate(ticket).get("success", false)), "MW8 client handoff ticket invalid")
	_assert(String(ticket.get("target_owner_id", "")) == FixtureScript.TARGET_OWNER_ID, "MW8 ticket target owner changed")
	_assert(int(ticket.get("target_authority_epoch", 0)) == FixtureScript.TARGET_EPOCH, "MW8 ticket target epoch changed")
	var active_lease: Dictionary = cluster["directory"].resolve_region(FixtureScript.REGION_ID)
	_assert(String(active_lease.get("owner_id", "")) == FixtureScript.TARGET_OWNER_ID, "MW8 directory did not switch owner")
	_assert(int(active_lease.get("authority_epoch", 0)) == FixtureScript.TARGET_EPOCH, "MW8 directory did not switch epoch")
	_assert(String(active_lease.get("status", "")) == "ACTIVE", "MW8 committed lease not active")
	_assert(cluster["source"]["endpoint"].has_relinquished(FixtureScript.REGION_ID), "MW8 source did not record relinquish")
	_assert(cluster["target_context"]["service"].snapshot_store().content_hash() == source_snapshot_hash, "MW8 target snapshot state differs after handoff")
	_assert(cluster["target_context"]["service"].mutation_journal().content_hash() == source_journal_hash, "MW8 target journal differs after handoff")
	_assert(cluster["target_context"]["service"].material_receiver().batch_count() == source_batch_count, "MW8 target batches differ after handoff")
	_assert(cluster["target"]["authority"].stream_sequence() == 1, "MW8 target stream was not rebased to journal frontier")

	var source_gate_after: Dictionary = cluster["source"]["gate"].authorize_mutation(original_request)
	_assert(not bool(source_gate_after.get("success", false)), "MW8 source still authorizes transferred region")
	_assert(String(source_gate_after.get("error_code", "")) == "MATTER_REGION_NOT_OWNED_BY_SERVER", "MW8 old-owner error changed")
	_assert_ok(cluster["target"]["gate"].authorize_mutation(original_request), "MW8 target gate did not activate after commit")

	var target_client = FixtureScript.create_replica(cluster, "target", "client/mw8/miner")
	_assert(target_client != null, "MW8 target client setup failed")
	if target_client == null:
		return
	_assert_ok(target_client.set_interest(
		"subscription/mw8/miner", 2,
		cluster["region"]["center_cell_address"],
		int(cluster["region"]["radius_cells"])
	), "MW8 target interest failed")
	_assert_ok(FixtureScript.connect_replica(
		cluster, "target", target_client,
		"peer/mw8/target/miner", "session/mw8/target/miner", "actor/mw8/miner"
	), "MW8 target client connect failed")
	_assert_ok(FixtureScript.dispatch_and_poll(
		cluster, "target", target_client, "peer/mw8/target/miner"
	), "MW8 target handoff snapshot failed")
	_assert(target_client.snapshot_store().size() >= 1, "MW8 target client missed transferred region")
	_assert(target_client.snapshot_store().content_hash() == cluster["target_context"]["service"].snapshot_store().content_hash(), "MW8 target client projection differs")

	var replay_command: Dictionary = target_client.create_mutation_command(
		original_request, "message/mw8/miner/replay"
	)
	var replay_wire: Dictionary = cluster["target"]["command_transport"].send(replay_command)
	_assert(bool(replay_wire.get("success", false)), "MW8 target replay transport failed")
	var replay_result: Dictionary = target_client.accept_command_result(Dictionary(replay_wire.get("result", {})))
	_assert_ok(replay_result, "MW8 target exact replay failed")
	_assert(bool(replay_result.get("details", {}).get("replay", false)), "MW8 imported journal did not provide exact replay")
	_assert(cluster["target"]["authority"].stream_sequence() == 1, "MW8 exact replay advanced target stream")

	var second: Dictionary = FixtureScript.send_mutation(
		cluster, "target", target_client, cluster["fixtures"][1],
		"operation/mw8/miner/two", "actor/mw8/miner", "message/mw8/miner/two"
	)
	_assert_ok(second, "MW8 new target mutation failed")
	_assert(cluster["target"]["authority"].stream_sequence() == 2, "MW8 new target mutation sequence changed")
	_assert_ok(FixtureScript.dispatch_and_poll(
		cluster, "target", target_client, "peer/mw8/target/miner"
	), "MW8 post-handoff regional replication failed")
	_assert(target_client.snapshot_store().size() >= 2, "MW8 post-handoff client did not receive second brick")


func _test_split_brain_and_cross_region_fences() -> void:
	var cluster: Dictionary = FixtureScript.create_cluster(_root_path.path_join("fences"))
	_assert_ok(cluster, "MW8 fence cluster setup failed")
	if not bool(cluster.get("success", false)):
		return
	_clusters_to_shutdown.append(cluster)
	var overlap: Dictionary = RegionScript.create(
		"region/mw8-overlap",
		String(cluster["source_context"]["body"]["body_id"]),
		FixtureScript.CELL_LEVEL,
		cluster["region"]["center_cell_address"],
		0
	)
	var overlap_result: Dictionary = cluster["directory"].register_region(
		overlap, FixtureScript.SOURCE_OWNER_ID, FixtureScript.SOURCE_EPOCH
	)
	_assert(not bool(overlap_result.get("success", false)), "MW8 overlapping authority region accepted")
	_assert(String(overlap_result.get("error_code", "")) == "OVERLAPPING_MATTER_AUTHORITY_REGIONS", "MW8 overlap error changed")
	var parent_address: Dictionary = CellGridScript.parent(
		cluster["region"]["center_cell_address"], cluster["source_context"]["grid_profile"]
	)
	_assert(not parent_address.is_empty(), "MW8 mixed-level parent address missing")
	if not parent_address.is_empty():
		var mixed_level_region: Dictionary = RegionScript.create(
			"region/mw8-mixed-level",
			String(cluster["source_context"]["body"]["body_id"]),
			FixtureScript.CELL_LEVEL - 1,
			parent_address,
			0
		)
		var mixed_level_result: Dictionary = cluster["directory"].register_region(
			mixed_level_region, FixtureScript.SOURCE_OWNER_ID, FixtureScript.SOURCE_EPOCH
		)
		_assert(not bool(mixed_level_result.get("success", false)), "MW8 mixed-level authority region accepted")
		_assert(String(mixed_level_result.get("error_code", "")) == "MIXED_LEVEL_MATTER_AUTHORITY_REGIONS_UNSUPPORTED", "MW8 mixed-level error changed")
	var negative_candidates: Array[Dictionary] = MW7FixtureScript.surface_fixtures(
		{"context": cluster["source_context"]}, Vector3.LEFT, 4
	)
	_assert(not negative_candidates.is_empty(), "MW8 second-region fixture missing")
	if negative_candidates.is_empty():
		return
	var second_region: Dictionary = RegionScript.create(
		"region/mw8-negative",
		String(cluster["source_context"]["body"]["body_id"]),
		FixtureScript.CELL_LEVEL,
		negative_candidates[0]["address"]["cell_address"],
		0
	)
	_assert_ok(cluster["directory"].register_region(
		second_region, FixtureScript.SOURCE_OWNER_ID, FixtureScript.SOURCE_EPOCH
	), "MW8 second region registration failed")
	var inside_request: Dictionary = FixtureScript.request(
		cluster, "source", cluster["fixtures"][0],
		"operation/mw8/cross-region", "actor/mw8/cross-region"
	)
	var inside_address: Dictionary = inside_request["target_bricks"][0]
	var outside_address: Dictionary = negative_candidates[0]["address"]
	var sorted_targets: Array = [inside_address, outside_address]
	sorted_targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["address_id"]) < String(b["address_id"])
	)
	var expected_by_address: Dictionary = {}
	for address_value in sorted_targets:
		var address: Dictionary = address_value
		expected_by_address[String(address["address_id"])] = 0
	var cross_request: Dictionary = RequestScript.create({
		"operation_id": "operation/mw8/cross-region",
		"body_id": inside_request["body_id"],
		"actor_id": inside_request["actor_id"],
		"tool_id": inside_request["tool_id"],
		"operation_type": inside_request["operation_type"],
		"target_bricks": sorted_targets,
		"expected_revision_by_address": expected_by_address,
		"shape": inside_request["shape"],
		"source_container_id": inside_request["source_container_id"],
		"destination_container_id": inside_request["destination_container_id"],
		"requested_mass_kg": inside_request["requested_mass_kg"],
		"energy_budget_j": inside_request["energy_budget_j"],
		"client_tick": inside_request["client_tick"],
	})
	_assert(bool(RequestScript.validate(cross_request).get("success", false)), "MW8 cross-region request fixture invalid")
	var cross_result: Dictionary = cluster["source"]["gate"].authorize_mutation(cross_request)
	_assert(not bool(cross_result.get("success", false)), "MW8 cross-region mutation accepted")
	_assert(String(cross_result.get("error_code", "")) == "MATTER_CROSS_REGION_MUTATION_REQUIRES_COORDINATION", "MW8 cross-region error changed")

	var stale_begin: Dictionary = cluster["directory"].begin_handoff(
		"transfer/mw8/stale",
		FixtureScript.REGION_ID,
		FixtureScript.SOURCE_OWNER_ID,
		FixtureScript.SOURCE_EPOCH + 1,
		FixtureScript.TARGET_OWNER_ID,
		FixtureScript.TARGET_EPOCH + 1
	)
	_assert(not bool(stale_begin.get("success", false)), "MW8 stale source epoch began handoff")
	_assert(String(stale_begin.get("error_code", "")) == "STALE_MATTER_HANDOFF_SOURCE_LEASE", "MW8 stale lease error changed")
	var first_begin: Dictionary = cluster["directory"].begin_handoff(
		"transfer/mw8/split-a",
		FixtureScript.REGION_ID,
		FixtureScript.SOURCE_OWNER_ID,
		FixtureScript.SOURCE_EPOCH,
		FixtureScript.TARGET_OWNER_ID,
		FixtureScript.TARGET_EPOCH
	)
	_assert_ok(first_begin, "MW8 split-brain first prepare failed")
	var second_begin: Dictionary = cluster["directory"].begin_handoff(
		"transfer/mw8/split-b",
		FixtureScript.REGION_ID,
		FixtureScript.SOURCE_OWNER_ID,
		FixtureScript.SOURCE_EPOCH,
		"authority/mw8-third",
		FixtureScript.TARGET_EPOCH + 1
	)
	_assert(not bool(second_begin.get("success", false)), "MW8 concurrent handoff accepted")
	_assert(String(second_begin.get("error_code", "")) == "MATTER_AUTHORITY_REGION_HANDOFF_ALREADY_ACTIVE", "MW8 concurrent handoff error changed")
	_assert_ok(cluster["directory"].abort_handoff("transfer/mw8/split-a"), "MW8 split-brain cleanup abort failed")
	_assert(cluster["directory"].content_hash().length() == 64, "MW8 directory content hash invalid")


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, String(result.get("error_code", ""))])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	for cluster in _clusters_to_shutdown:
		_assert_ok(FixtureScript.shutdown_cluster(cluster), "MW8 cluster lifecycle shutdown failed")
	_clusters_to_shutdown.clear()
	var duration_seconds: float = float(Time.get_ticks_usec() - _suite_started_usec) / 1000000.0
	if failures.is_empty():
		print("MW8 regional authority handoff: PASS (%d assertions / %.3f s)" % [assertions, duration_seconds])
		quit(0)
		return
	print("MW8 regional authority handoff: FAIL (%d failures / %d assertions / %.3f s)" % [
		failures.size(), assertions, duration_seconds,
	])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

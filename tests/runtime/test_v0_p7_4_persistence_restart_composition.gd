extends SceneTree

const BubbleScript = preload("res://scripts/world/matter/lunar_matter_bubble.gd")
const CompositionScript = preload(
	"res://scripts/simulation/matter/contracts/matter_composition.gd"
)
const BatchScript = preload(
	"res://scripts/simulation/matter/contracts/matter_material_batch.gd"
)
const LedgerScript = preload(
	"res://scripts/simulation/matter/contracts/matter_mass_ledger.gd"
)
const ResultScript = preload(
	"res://scripts/simulation/matter/contracts/matter_mutation_result.gd"
)
const MatterRepositoryScript = preload(
	"res://scripts/simulation/matter/persistence/matter_state_repository.gd"
)
const MatterCoordinatorScript = preload(
	"res://scripts/simulation/matter/persistence/matter_state_coordinator.gd"
)
const GameplayServiceScript = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"
)
const GameplayRepositoryScript = preload(
	"res://scripts/persistence/authoritative_recovery_repository.gd"
)
const GameplayRecoveryScript = preload(
	"res://scripts/persistence/authoritative_recovery_coordinator.gd"
)
const GameplayAuthorityScript = preload(
	"res://scripts/runtime/networked_gameplay/m6/m6_dedicated_gameplay_authority_adapter.gd"
)
const ReplayOutboxScript = preload(
	"res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox.gd"
)
const RestartCompositionScript = preload(
	"res://scripts/runtime/networked_gameplay/p7/p7_persistence_restart_composition.gd"
)

const PLAYER := "miner"
const ACTOR_ID := "player/miner"
const SESSION_ID := "transport-session/p7-4/miner/1"
const AUTHORITY_ID := "simulation/p7-4/gameplay"
const OPERATION_ID := "operation/p7-4/restart/excavate/1"
const TOOL_ID := "item/tool/p7-4-test"
const MATTER_ROOT := "user://p7-4-persistence-restart/matter"
const GAMEPLAY_ROOT := "user://p7-4-persistence-restart/gameplay"
const SURFACE_RADIUS_M := 1737425.0

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var phase := _arg("phase", "")
	match phase:
		"seed":
			_seed()
		"recover-deliver":
			_recover_deliver()
		"recover-replay":
			_recover_replay()
		_:
			_assert_true(false, "phase must be seed, recover-deliver or recover-replay")
	_finish(phase)


func _seed() -> void:
	_remove_tree(ProjectSettings.globalize_path("user://p7-4-persistence-restart"))
	var matter := _new_matter_context()
	_assert_success(matter, "seed Matter context")
	if not bool(matter.get("success", false)):
		return
	var gameplay := _new_gameplay_context(true)
	_assert_success(gameplay, "seed gameplay recovery context")
	if not bool(gameplay.get("success", false)):
		return

	var request: Dictionary = _request(matter["bubble"])
	_assert_true(not request.is_empty(), "seed deterministic lunar request created")
	var committed: Dictionary = _seed_committed_mw5_fixture(matter, request)
	_assert_success(committed, "seed canonical committed Matter fixture")
	if not bool(committed.get("success", false)):
		return
	var result: Dictionary = committed["result"]
	_assert_true(String(result.get("status", "")) == "COMMITTED", "seed Matter journal contains committed result")
	_assert_true(Array(result.get("created_aggregate_ids", [])).size() == 1, "seed commit declares exactly one batch")
	var batch_id := String(Array(result.get("created_aggregate_ids", []))[0])
	var receiver = matter["bubble"].excavation_service().material_receiver()
	var batch: Dictionary = receiver.get_batch(batch_id)
	_assert_true(not batch.is_empty(), "seed batch exists in canonical MW4 receiver")
	_assert_true(String(batch.get("source_operation_id", "")) == OPERATION_ID, "seed batch provenance binds operation")
	_assert_true(receiver.batch_count() == 1, "seed receiver owns exactly one batch")

	var matter_saved: Dictionary = matter["coordinator"].save_next(1001)
	_assert_success(matter_saved, "seed MW5 checkpoint saved before Item Graph delivery")
	var gameplay_saved: Dictionary = gameplay["coordinator"].persist_checkpoint(
		"checkpoint/p7-4/gameplay/1", 1, 0, ""
	)
	_assert_success(gameplay_saved, "seed existing V0 gameplay checkpoint saved before delivery")
	var graph = gameplay["service"].get_canonical_item_graph_port()
	_assert_true(graph != null, "seed canonical Item Graph available")
	_assert_true(graph.get_replay_operation_count() == 0, "seed Item Graph has no P7 delivery replay before restart")
	_assert_true(_definition_quantity(graph.create_snapshot(), PLAYER, "item/ore") == 0, "seed inventory has no delivered P7 ore")
	var contract := RestartCompositionScript.new().contract_report()
	_assert_true(not bool(contract.get("canonical_state_owned", true)), "P7.4 owns no canonical state")
	_assert_true(not bool(contract.get("private_filesystem", true)), "P7.4 owns no filesystem")
	_assert_true(not bool(contract.get("private_save_format", true)), "P7.4 owns no save format")
	_assert_true(not bool(contract.get("delivery_receipt_store", true)), "P7.4 owns no delivery receipt store")
	_assert_true(String(contract.get("matter_persistence_owner", "")) == "MW5_MATTER_STATE_COORDINATOR", "P7.4 names MW5 as Matter persistence owner")
	_assert_true(String(contract.get("gameplay_persistence_owner", "")) == "M6_AUTHORITATIVE_RECOVERY_COORDINATOR", "P7.4 names existing V0 gameplay recovery owner")
	_assert_success(gameplay["service"].shutdown(), "seed gameplay service shutdown")


func _recover_deliver() -> void:
	var matter := _new_matter_context()
	_assert_success(matter, "fresh Matter process context")
	if not bool(matter.get("success", false)):
		return
	var gameplay := _new_gameplay_context(false)
	_assert_success(gameplay, "fresh gameplay process context")
	if not bool(gameplay.get("success", false)):
		return
	var request: Dictionary = _request(matter["bubble"])
	_assert_true(not request.is_empty(), "recovery recreates exact deterministic request")

	var composition = RestartCompositionScript.new()
	_assert_success(composition.configure(
		matter["coordinator"],
		matter["bubble"].excavation_service(),
		gameplay["coordinator"],
		gameplay["service"]
	), "P7.4 binds only existing recovery owners")
	var recovered: Dictionary = composition.recover_replay_and_deliver(request)
	_assert_success(recovered, "first restart recovers and delivers committed batch")
	if not bool(recovered.get("success", false)):
		return
	var details: Dictionary = recovered.get("details", {})
	var delivery: Dictionary = details.get("delivery", {})
	_assert_true(String(details.get("matter_recovery_source", "")) == "ACTIVE", "first restart uses active MW5 checkpoint")
	_assert_true(int(details.get("matter_checkpoint_generation", 0)) == 1, "first restart restores MW5 generation 1")
	_assert_true(String(details.get("gameplay_recovery_source", "")) == "ACTIVE", "first restart uses active gameplay checkpoint")
	_assert_true(int(details.get("gameplay_checkpoint_generation", 0)) == 1, "first restart restores gameplay generation 1")
	_assert_true(bool(details.get("matter_replay_exact", false)), "MW4 operation replay is exact after restart")
	_assert_true(int(details.get("matter_batch_count", 0)) == 1, "MW5 restore contains one and only one batch")
	_assert_true(not bool(delivery.get("replay", true)), "undelivered recovered batch performs one fresh Item Graph delivery")
	_assert_true(bool(delivery.get("item_graph_mutated", false)), "first post-restart delivery mutates Item Graph once")
	_assert_true(int(delivery.get("output_quantity", 0)) > 0, "first post-restart delivery produces canonical ore")
	_assert_true(String(details.get("item_graph_checksum_before_delivery", "")) != String(details.get("item_graph_checksum_after_delivery", "")), "fresh post-restart delivery changes Item Graph checksum")
	_assert_true(int(details.get("gameplay_revision_after_delivery", -1)) == int(details.get("gameplay_revision_before_delivery", -2)) + 1, "fresh Item Graph output advances aggregate gameplay revision exactly once")
	_assert_true(absf(float(delivery.get("total_mass_kg", 0.0)) - float(delivery.get("represented_mass_kg", 0.0)) - float(delivery.get("residual_mass_kg", 0.0))) < 0.000000001, "restart delivery preserves P7.3 mass conservation")
	var graph = gameplay["service"].get_canonical_item_graph_port()
	_assert_true(_definition_quantity(graph.create_snapshot(), PLAYER, "item/ore") == int(delivery.get("output_quantity", -1)), "canonical inventory accounting equals recovered delivery quantity")
	_assert_true(graph.get_replay_operation_count() >= 1, "canonical Item Graph replay ledger records delivery")
	_assert_true(matter["bubble"].excavation_service().material_receiver().batch_count() == 1, "delivery does not consume or duplicate Matter batch provenance")

	var matter_saved: Dictionary = matter["coordinator"].save_next(1002)
	_assert_success(matter_saved, "post-delivery MW5 generation 2 saved")
	_assert_true(int(matter_saved.get("details", {}).get("generation", 0)) == 2, "MW5 checkpoint generation advances")
	var gameplay_saved: Dictionary = gameplay["coordinator"].persist_checkpoint(
		"checkpoint/p7-4/gameplay/2", 2, 1, ""
	)
	_assert_success(gameplay_saved, "post-delivery existing gameplay checkpoint generation 2 saved")
	_assert_true(int(gameplay_saved.get("details", {}).get("checkpoint", {}).get("generation", 0)) == 2, "gameplay checkpoint generation advances")
	_assert_success(gameplay["service"].shutdown(), "first restart gameplay service shutdown")


func _recover_replay() -> void:
	var matter := _new_matter_context()
	_assert_success(matter, "second fresh Matter process context")
	if not bool(matter.get("success", false)):
		return
	var gameplay := _new_gameplay_context(false)
	_assert_success(gameplay, "second fresh gameplay process context")
	if not bool(gameplay.get("success", false)):
		return
	var request: Dictionary = _request(matter["bubble"])
	_assert_true(not request.is_empty(), "second restart recreates exact deterministic request")

	var composition = RestartCompositionScript.new()
	_assert_success(composition.configure(
		matter["coordinator"],
		matter["bubble"].excavation_service(),
		gameplay["coordinator"],
		gameplay["service"]
	), "second restart binds existing recovery owners")
	var recovered: Dictionary = composition.recover_replay_and_deliver(request)
	_assert_success(recovered, "second restart replays already delivered batch")
	if not bool(recovered.get("success", false)):
		return
	var details: Dictionary = recovered.get("details", {})
	var delivery: Dictionary = details.get("delivery", {})
	_assert_true(int(details.get("matter_checkpoint_generation", 0)) == 2, "second restart restores latest MW5 generation 2")
	_assert_true(int(details.get("gameplay_checkpoint_generation", 0)) == 2, "second restart restores latest gameplay generation 2")
	_assert_true(bool(details.get("matter_replay_exact", false)), "second restart still replays exact MW4 result")
	_assert_true(int(details.get("matter_batch_count", 0)) == 1, "second restart still has one Matter batch")
	_assert_true(bool(delivery.get("replay", false)), "second restart delivery is canonical Item Graph replay")
	_assert_true(not bool(delivery.get("item_graph_mutated", true)), "second restart replay does not mutate Item Graph")
	_assert_true(String(details.get("item_graph_checksum_before_delivery", "")) == String(details.get("item_graph_checksum_after_delivery", "")), "second restart replay leaves Item Graph byte-stable")
	_assert_true(int(details.get("gameplay_revision_after_delivery", -1)) == int(details.get("gameplay_revision_before_delivery", -2)), "Item Graph replay does not advance aggregate gameplay revision")
	var graph = gameplay["service"].get_canonical_item_graph_port()
	_assert_true(_definition_quantity(graph.create_snapshot(), PLAYER, "item/ore") == int(delivery.get("output_quantity", -1)), "second restart contains exactly one delivered ore quantity")
	_assert_true(graph.get_replay_operation_count() >= 1, "second restart restores Item Graph replay ledger")
	_assert_true(matter["bubble"].excavation_service().material_receiver().batch_count() == 1, "second restart does not duplicate MatterMaterialBatch")
	_assert_success(gameplay["service"].shutdown(), "second restart gameplay service shutdown")


# Build the smallest valid committed MW5 state through existing public Matter
# contracts. P7.4 is testing restart composition, not re-testing excavation
# geometry; the full gate keeps the real P7.3 lunar MW4 -> Item Graph regression.
func _seed_committed_mw5_fixture(matter: Dictionary, request: Dictionary) -> Dictionary:
	if request.is_empty() or Array(request.get("target_bricks", [])).is_empty():
		return _failure("P7_4_FIXTURE_REQUEST_TARGET_REQUIRED")
	var address: Dictionary = Dictionary(Array(request["target_bricks"])[0]).duplicate(true)
	var cell: Dictionary = Dictionary(address.get("cell_address", {})).duplicate(true)
	var snapshot: Dictionary = matter["bubble"].ensure_materialized_cell(cell, 1)
	if snapshot.is_empty() or int(snapshot.get("state_revision", -1)) != 1:
		return _failure("P7_4_FIXTURE_SNAPSHOT_BUILD_FAILED")
	if String(snapshot.get("address", {}).get("address_id", "")) != String(address.get("address_id", "")):
		return _failure("P7_4_FIXTURE_ADDRESS_MISMATCH")

	var mass_kg := 12.75
	var composition: Dictionary = CompositionScript.create([
		{"material_id": "matter/regolith-loose", "mass_fraction": 1.0},
	])
	if not bool(CompositionScript.validate(composition).get("success", false)):
		return _failure("P7_4_FIXTURE_COMPOSITION_FAILED")
	var receiver = matter["bubble"].excavation_service().material_receiver()
	var batch_id := "matter-batch/%s" % OPERATION_ID.sha256_text()
	var batch: Dictionary = BatchScript.create({
		"batch_id": batch_id,
		"container_id": receiver.container_id(),
		"source_body_id": matter["bubble"].body_definition()["body_id"],
		"source_operation_id": OPERATION_ID,
		"total_mass_kg": mass_kg,
		"bulk_volume_m3": mass_kg / 1500.0,
		"composition": composition,
		"temperature_k": 150.0,
	})
	if not bool(BatchScript.validate(batch).get("success", false)):
		return _failure("P7_4_FIXTURE_BATCH_FAILED")
	var reserved: Dictionary = receiver.reserve(
		OPERATION_ID, float(batch["total_mass_kg"]), float(batch["bulk_volume_m3"])
	)
	if not bool(reserved.get("success", false)):
		return _failure("P7_4_FIXTURE_RECEIVER_RESERVE_FAILED", {"cause": reserved})
	var committed_batch: Dictionary = receiver.commit_reserved(batch)
	if not bool(committed_batch.get("success", false)):
		return _failure("P7_4_FIXTURE_RECEIVER_COMMIT_FAILED", {"cause": committed_batch})

	var ledger: Dictionary = LedgerScript.create(
		OPERATION_ID,
		[{
			"account_id": "matter/body-moon",
			"material_id": "matter/regolith-loose",
			"mass_kg": mass_kg,
		}],
		[{
			"account_id": receiver.container_id(),
			"material_id": "matter/regolith-loose",
			"mass_kg": mass_kg,
		}]
	)
	var result: Dictionary = ResultScript.create({
		"operation_id": OPERATION_ID,
		"status": "COMMITTED",
		"changed_bricks": [{
			"address": address,
			"previous_revision": 0,
			"new_revision": 1,
			"snapshot_checksum": String(snapshot["checksum"]),
		}],
		"removed_mass_kg": mass_kg,
		"deposited_mass_kg": 0.0,
		"extracted_composition": composition,
		"generated_heat_j": 0.0,
		"consumed_energy_j": 0.0,
		"created_aggregate_ids": [batch_id],
		"mass_ledger": ledger,
		"error_code": "",
	})
	if not bool(ResultScript.validate(result).get("success", false)):
		return _failure("P7_4_FIXTURE_RESULT_FAILED")
	var recorded: Dictionary = matter["bubble"].excavation_service().mutation_journal().record(
		request, result
	)
	if not bool(recorded.get("success", false)):
		return _failure("P7_4_FIXTURE_JOURNAL_RECORD_FAILED", {"cause": recorded})
	return {
		"success": true,
		"error_code": "",
		"result": result,
		"batch": batch,
	}


func _new_matter_context() -> Dictionary:
	var bubble = BubbleScript.new()
	var bubble_setup: Dictionary = bubble.configure({
		"anchor_direction": [0.0, 1.0, 0.0],
		"canonical_surface_radius_m": SURFACE_RADIUS_M,
		"half_extent_m": 32.0,
		"mutation_level": 2,
		"presentation_level": 1,
		"max_level": 3,
		"brick_interior_resolution": 2,
		"ghost_border_samples": 1,
		"container_id": "container/p7-4/moon-output",
	})
	if not bool(bubble_setup.get("success", false)):
		return _failure("P7_4_BUBBLE_SETUP_FAILED", {"cause": bubble_setup})
	var repository = MatterRepositoryScript.new()
	var repository_setup: Dictionary = repository.configure(MATTER_ROOT)
	if not bool(repository_setup.get("success", false)):
		return _failure("P7_4_MATTER_REPOSITORY_SETUP_FAILED", {"cause": repository_setup})
	var service = bubble.excavation_service()
	var coordinator = MatterCoordinatorScript.new()
	var coordinator_setup: Dictionary = coordinator.configure(
		bubble.body_definition(),
		bubble.grid_profile(),
		bubble.mutation_level(),
		service.snapshot_store(),
		service.material_receiver(),
		service.mutation_journal(),
		repository
	)
	if not bool(coordinator_setup.get("success", false)):
		return _failure("P7_4_MATTER_COORDINATOR_SETUP_FAILED", {"cause": coordinator_setup})
	return {
		"success": true,
		"error_code": "",
		"bubble": bubble,
		"repository": repository,
		"coordinator": coordinator,
	}


func _new_gameplay_context(seed_player: bool) -> Dictionary:
	var service = GameplayServiceScript.new()
	var setup: Dictionary = service.setup(AUTHORITY_ID, 1, 0, {
		"profile": GameplayServiceScript.PROFILE_MULTIPLAYER_CORE,
		"topology_adapter": "ENET",
		"region_id": "region/p7-4/restart",
	})
	if not bool(setup.get("success", false)):
		return _failure("P7_4_GAMEPLAY_SETUP_FAILED", {"cause": setup})
	if seed_player:
		var joined: Dictionary = service.join(
			PLAYER, SESSION_ID, "operation/p7-4/gameplay/join/1"
		)
		if not bool(joined.get("success", false)):
			return _failure("P7_4_GAMEPLAY_PLAYER_SETUP_FAILED", {"cause": joined})
	var repository = GameplayRepositoryScript.new()
	var repository_setup: Dictionary = repository.configure(GAMEPLAY_ROOT)
	if not bool(repository_setup.get("success", false)):
		return _failure("P7_4_GAMEPLAY_REPOSITORY_SETUP_FAILED", {"cause": repository_setup})
	var authority = GameplayAuthorityScript.new()
	var authority_setup: Dictionary = authority.setup(service, "session/p7-4/restart")
	if not bool(authority_setup.get("success", false)):
		return _failure("P7_4_GAMEPLAY_AUTHORITY_SETUP_FAILED", {"cause": authority_setup})
	var outbox = ReplayOutboxScript.new()
	var outbox_setup: Dictionary = outbox.setup(service)
	if not bool(outbox_setup.get("success", false)):
		return _failure("P7_4_GAMEPLAY_REPLAY_SETUP_FAILED", {"cause": outbox_setup})
	var coordinator = GameplayRecoveryScript.new()
	var coordinator_setup: Dictionary = coordinator.configure(
		repository, authority, outbox
	)
	if not bool(coordinator_setup.get("success", false)):
		return _failure("P7_4_GAMEPLAY_RECOVERY_SETUP_FAILED", {"cause": coordinator_setup})
	return {
		"success": true,
		"error_code": "",
		"service": service,
		"repository": repository,
		"authority": authority,
		"outbox": outbox,
		"coordinator": coordinator,
	}


func _request(bubble) -> Dictionary:
	var center: Vector3 = bubble.anchor_body_fixed_m()
	return bubble.create_excavation_request(
		OPERATION_ID,
		ACTOR_ID,
		TOOL_ID,
		center + Vector3(2.5, -0.5, 0.0),
		center + Vector3(3.5, -0.5, 0.0),
		0.75,
		1000000000.0,
		1
	)


func _definition_quantity(snapshot: Dictionary, player_id: String, definition_id: String) -> int:
	var inventory: Dictionary = Dictionary(snapshot.get("inventories", {})).get(player_id, {})
	var item_ids: Array = inventory.get("inventory", [])
	var total := 0
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		if String(item.get("item_id", "")) in item_ids \
			and String(item.get("definition_id", "")) == definition_id:
			total += int(item.get("quantity", 0))
	return total


func _arg(name: String, fallback: String) -> String:
	var prefix := "--%s=" % name
	for value in OS.get_cmdline_user_args():
		var text := String(value)
		if text.begins_with(prefix):
			return text.substr(prefix.length())
	return fallback


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if name in [".", ".."]:
			continue
		var child := path.path_join(name)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}


func _assert_success(result: Dictionary, message: String) -> void:
	_assert_true(
		bool(result.get("success", false)),
		"%s: %s" % [message, String(result.get("error_code", ""))]
	)


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P7.4] %s" % message)


func _finish(phase: String) -> void:
	if _failures == 0:
		print("V0-P7.4 %s: PASS (%d assertions, 0 failures)" % [phase, _assertions])
		quit(0)
		return
	print("V0-P7.4 %s: FAIL (%d assertions, %d failures)" % [phase, _assertions, _failures])
	quit(1)

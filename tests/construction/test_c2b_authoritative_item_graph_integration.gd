extends SceneTree

const FactoryScript = preload("res://scripts/items/services/item_domain_factory.gd")
const DefinitionScript = preload("res://scripts/items/domain/item_definition.gd")
const ItemScript = preload("res://scripts/items/domain/item_instance.gd")
const ContainerScript = preload("res://scripts/containers/container_state.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const AdapterScript = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
const BridgeScript = preload("res://scripts/construction/authoritative/construction_m0_transaction_bridge.gd")
const PersistenceScript = preload("res://scripts/construction/authoritative/construction_authoritative_persistence.gd")

const CONSTRUCT_ID := "construct/table/c2b-integration"
const ROOT_ID := "item/00000000-0000-4000-8000-0000000000ff"
const TOP_ID := "item/00000000-0000-4000-8000-000000000001"
const LEG_A_ID := "item/00000000-0000-4000-8000-000000000002"
const LEG_B_ID := "item/00000000-0000-4000-8000-000000000003"
const LEG_C_ID := "item/00000000-0000-4000-8000-000000000004"
const LEG_D_ID := "item/00000000-0000-4000-8000-000000000005"
const FASTENER_ID := "item/00000000-0000-4000-8000-000000000006"
const PART_IDS := [TOP_ID, LEG_A_ID, LEG_B_ID, LEG_C_ID, LEG_D_ID]

var failures: Array[String] = []
var assertions: int = 0
var _sequence: int = 0


func _init() -> void:
	_test_authoritative_assembly_and_crash_recovery()
	_test_authoritative_deconstruction_and_rollback()
	_test_persistence_and_restart_replay()
	_finish()


func _test_authoritative_assembly_and_crash_recovery() -> void:
	var runtime: Dictionary = _runtime("assembly")
	var adapter = runtime.adapter
	var domain: Dictionary = runtime.domain
	var plan: Dictionary = _assembly_plan(adapter, "operation/c2b/assemble")
	var before: String = _canonical_json(adapter.export_state())
	var failed: Dictionary = adapter.apply_plan(plan, AdapterScript.FAILURE_AFTER_M0)
	_assert_error(failed, "INJECTED_FAILURE_AFTER_M0_COMMIT", "Failure after authoritative M0 commit not surfaced")
	_assert(String(failed.get("status", "")) == AdapterScript.STATUS_RETRYABLE, "Post-M0 failure must be retryable")
	_assert(_canonical_json(adapter.export_state()) == before, "Post-M0 failure changed local production state")
	_assert(domain.items.get_item(ROOT_ID) == null, "Post-M0 failure leaked construct root into ItemRegistry")
	_assert(not domain.operations.has_operation("operation/c2b/assemble"), "Post-M0 failure poisoned common Operation Ledger")
	var m0_after_failure: Dictionary = runtime.bridge.get_state_report()
	_assert_ok(m0_after_failure, "M0 report missing after committed failure")
	_assert(int(m0_after_failure.details.generation) == 2, "M0 did not commit exactly one assembly generation")
	var restarted: Dictionary = _runtime("assembly-restart", String(runtime.bridge_root))
	_assert(restarted.domain.items.get_item(ROOT_ID) != null, "Restart did not materialize committed M0 root into production ItemRegistry")
	_assert(restarted.adapter.get_construct_snapshot(CONSTRUCT_ID).size() > 0, "Restart did not materialize committed M0 construct")
	_assert(restarted.domain.operations.has_operation("operation/c2b/assemble"), "Restart did not restore common ledger from M0")
	_assert(int(restarted.adapter.get_authority_report().item_graph_revision) == 1, "Restart did not restore M0 Item Graph revision")
	var restart_replay: Dictionary = restarted.adapter.apply_plan(plan)
	_assert(bool(restart_replay.get("success", false)), "Restart could not replay committed construction operation")
	_assert(int(restarted.adapter.get_authority_report().server_tick) == 1, "Restart replay advanced authority tick")

	var committed: Dictionary = adapter.apply_plan(plan)
	_assert_ok(committed, "Assembly did not recover from authoritative M0 replay")
	_assert(String(committed.status) == AdapterScript.STATUS_SUCCEEDED, "Recovered assembly did not use common ledger success status")
	_assert(domain.operations.has_operation("operation/c2b/assemble"), "Assembly missing from common Operation Ledger")
	_assert(adapter.get_construct_snapshot(CONSTRUCT_ID).size() > 0, "Authoritative ConstructStore missing assembled table")
	_assert(domain.items.get_item(ROOT_ID) != null, "Production ItemRegistry missing construct root")
	_assert(String(domain.items.get_item(ROOT_ID).components.construction_root.construct_id) == CONSTRUCT_ID, "Construct root component mismatch")
	for item_id in PART_IDS:
		var item = domain.items.get_item(item_id)
		_assert(item != null, "Assembled part disappeared: %s" % item_id)
		_assert(RelationsScript.kind_of(item.relation) == RelationsScript.ATTACHMENT, "Part did not become canonical ATTACHMENT: %s" % item_id)
		_assert(String(item.relation.assembly_id) == CONSTRUCT_ID and String(item.relation.parent_item_id) == ROOT_ID, "Part attachment target mismatch: %s" % item_id)
		_assert(not domain.containers.get_container("container/backpack").item_ids.has(item_id), "Attached part remained in backpack: %s" % item_id)
	_assert(int(domain.items.get_item(FASTENER_ID).quantity) == 4, "Assembly did not consume four real fasteners")
	_assert(int(domain.items.get_item(FASTENER_ID).revision) == 1, "Fastener stack revision did not advance")
	_assert(int(domain.containers.get_container("container/backpack").revision) == 1, "Backpack revision did not advance once")
	_assert(int(domain.containers.get_container("container/tools").revision) == 1, "Tools container revision did not advance once")
	_assert_ok(domain.validator.validate_graph(), "Production Item Graph invalid after assembly")
	var report: Dictionary = adapter.get_authority_report()
	_assert(int(report.item_graph_revision) == 1 and int(report.ledger_revision) == 1 and int(report.server_tick) == 1, "Authoritative revisions did not advance together")
	_assert(int(report.construct_authority_revisions[CONSTRUCT_ID]) == 0, "Created construct must start at M0 authority revision zero")
	var m0_after_recovery: Dictionary = runtime.bridge.get_state_report()
	_assert(int(m0_after_recovery.details.generation) == 2, "Local recovery incorrectly advanced M0 generation")
	_assert(int(m0_after_recovery.details.aggregate_count) == 3, "M0 state must contain Item Graph, ledger and construct")
	var replay: Dictionary = adapter.apply_plan(plan)
	_assert(replay == committed, "Exact assembly replay did not return stored common-ledger result")
	_assert(int(adapter.get_authority_report().server_tick) == 1, "Exact replay advanced authority tick")

	var conflict: Dictionary = plan.duplicate(true)
	conflict.plan_id = "plan/c2b/assemble-conflict"
	conflict.checksum = PlanScript.compute_checksum(conflict)
	var conflict_result: Dictionary = adapter.apply_plan(conflict)
	_assert_error(conflict_result, "OPERATION_ID_CONFLICT", "Changed plan reused terminal operation ID")
	_assert(int(domain.items.get_item(FASTENER_ID).quantity) == 4, "Operation conflict consumed material")

	var stale: Dictionary = plan.duplicate(true)
	stale.plan_id = "plan/c2b/assemble-stale"
	stale.operation_id = "operation/c2b/assemble-stale"
	stale.checksum = PlanScript.compute_checksum(stale)
	var rejected: Dictionary = adapter.apply_plan(stale)
	_assert(not bool(rejected.success) and String(rejected.status) == AdapterScript.STATUS_REJECTED, "Stale assembly was not terminally rejected")
	var rejected_replay: Dictionary = adapter.apply_plan(stale)
	_assert(rejected_replay == rejected, "Terminal rejection did not replay exactly")
	_assert(domain.operations.has_operation("operation/c2b/assemble-stale"), "Terminal rejection not persisted in common ledger")


func _test_authoritative_deconstruction_and_rollback() -> void:
	var runtime: Dictionary = _runtime("deconstruction")
	var adapter = runtime.adapter
	var domain: Dictionary = runtime.domain
	var assembly: Dictionary = _assembly_plan(adapter, "operation/c2b/deconstruction-setup")
	_assert_ok(adapter.apply_plan(assembly), "Deconstruction fixture assembly failed")
	var deconstruction: Dictionary = _deconstruction_plan(adapter, "operation/c2b/deconstruct")
	var before: String = _canonical_json(adapter.export_state())
	var failed: Dictionary = adapter.apply_plan(deconstruction, AdapterScript.FAILURE_AFTER_ITEMS)
	_assert_error(failed, "INJECTED_FAILURE_AFTER_ITEM_COMMIT", "Failure after ItemRegistry commit not surfaced")
	_assert(String(failed.status) == AdapterScript.STATUS_RETRYABLE, "Partial local commit failure must be retryable")
	_assert(_canonical_json(adapter.export_state()) == before, "Partial local commit was not rolled back atomically")
	_assert(adapter.get_construct_snapshot(CONSTRUCT_ID).size() > 0, "Rollback removed construct")
	_assert(domain.items.get_item(ROOT_ID) != null, "Rollback removed root item")
	for item_id in PART_IDS:
		_assert(RelationsScript.kind_of(domain.items.get_item(item_id).relation) == RelationsScript.ATTACHMENT, "Rollback detached part: %s" % item_id)

	var committed: Dictionary = adapter.apply_plan(deconstruction)
	_assert_ok(committed, "Deconstruction did not recover from committed M0 replay")
	_assert(adapter.get_construct_snapshot(CONSTRUCT_ID).is_empty(), "Deconstruction retained construct snapshot")
	_assert(domain.items.get_item(ROOT_ID) == null, "Deconstruction retained construct root item")
	var salvage = domain.containers.get_container("container/salvage")
	for item_id in PART_IDS:
		var item = domain.items.get_item(item_id)
		_assert(RelationsScript.kind_of(item.relation) == RelationsScript.CONTAINER, "Deconstructed part not returned to container: %s" % item_id)
		_assert(String(item.relation.container_id) == "container/salvage", "Deconstructed part returned to wrong container")
		_assert(salvage.item_ids.has(item_id), "Salvage container missing deconstructed part")
	_assert(int(domain.items.get_item(FASTENER_ID).quantity) == 4, "Deconstruction incorrectly restored consumed fasteners")
	_assert_ok(domain.validator.validate_graph(), "Production Item Graph invalid after deconstruction")
	var report: Dictionary = adapter.get_authority_report()
	_assert(not report.construct_authority_revisions.has(CONSTRUCT_ID), "Deleted construct retained authority revision")
	_assert(int(report.item_graph_revision) == 2 and int(report.ledger_revision) == 2 and int(report.server_tick) == 2, "Deconstruction authority revisions mismatch")
	var m0: Dictionary = runtime.bridge.get_state_report()
	_assert(int(m0.details.generation) == 3, "Assembly and deconstruction should produce two M0 generations after bootstrap")
	_assert(int(m0.details.aggregate_count) == 2, "Deleted construct remained in M0 state")
	var replay: Dictionary = adapter.apply_plan(deconstruction)
	_assert(replay == committed, "Exact deconstruction replay changed result")


func _test_persistence_and_restart_replay() -> void:
	var runtime: Dictionary = _runtime("persistence")
	var adapter = runtime.adapter
	var plan: Dictionary = _assembly_plan(adapter, "operation/c2b/persisted-assemble")
	var original: Dictionary = adapter.apply_plan(plan)
	_assert_ok(original, "Persistence fixture assembly failed")
	var state_before: Dictionary = adapter.export_state()
	var store = FactoryScript.create_json_state_store("user://c2b-authoritative-persistence-%d" % Time.get_ticks_usec())
	var persistence = PersistenceScript.new()
	_assert_ok(persistence.setup(adapter, store, "c2b-state"), "C2B persistence setup failed")
	var saved: Dictionary = persistence.save()
	_assert_ok(saved, "C2B authoritative state save failed")
	_assert(String(saved.checksum) == String(state_before.checksum), "Persistence reported wrong checksum")
	var loaded_raw: Dictionary = store.load_state("c2b-state")
	_assert_ok(loaded_raw, "Saved C2B state could not be read")
	var state: Dictionary = loaded_raw.state

	var restored_domain: Dictionary = FactoryScript.create()
	_assert_ok(restored_domain.items.load_dict(state.item_registry), "Restart ItemRegistry preload failed")
	_assert_ok(restored_domain.containers.load_dict(state.container_registry), "Restart ContainerRegistry preload failed")
	_assert_ok(restored_domain.operations.load_dict(state.operation_ledger), "Restart common ledger preload failed")
	var restored_constructs = ConstructStoreScript.new()
	_assert_ok(restored_constructs.load_dict(state.construct_store), "Restart ConstructStore preload failed")
	var restored_bridge = BridgeScript.new()
	_assert_ok(restored_bridge.setup("user://c2b-m0-restored-%d" % Time.get_ticks_usec()), "Restart M0 bridge setup failed")
	var restored_adapter = AdapterScript.new()
	_assert_ok(restored_adapter.setup(
		restored_domain.items, restored_domain.containers, restored_domain.validator, restored_domain.mass,
		restored_domain.operations, restored_constructs, restored_bridge,
		String(state.authority_owner_id), int(state.authority_epoch), int(state.item_graph_revision),
		int(state.ledger_revision), int(state.server_tick), Dictionary(state.construct_authority_revisions)
	), "Restart authoritative adapter setup failed")
	_assert(_canonical_json(restored_adapter.export_state()) == _canonical_json(state_before), "Restart did not restore exact authoritative state")
	var restored_persistence = PersistenceScript.new()
	_assert_ok(restored_persistence.setup(restored_adapter, store, "c2b-state"), "Restart persistence setup failed")
	_assert_ok(restored_persistence.load(), "Restart persistence load failed")
	var replay: Dictionary = restored_adapter.apply_plan(plan)
	_assert(_canonical_json(replay) == _canonical_json(original), "Persisted common-ledger replay changed semantic result after restart")
	_assert(int(restored_adapter.get_authority_report().server_tick) == 1, "Restart replay advanced server tick")

	var tampered: Dictionary = state.duplicate(true)
	tampered.server_tick = int(tampered.server_tick) + 1
	var before_tamper: String = _canonical_json(restored_adapter.export_state())
	var rejected: Dictionary = restored_adapter.load_state(tampered)
	_assert_error(rejected, "AUTHORITATIVE_CONSTRUCTION_STATE_CHECKSUM_MISMATCH", "Tampered persisted state accepted")
	_assert(_canonical_json(restored_adapter.export_state()) == before_tamper, "Rejected persisted state mutated live domain")


func _runtime(suffix: String, existing_bridge_root: String = "") -> Dictionary:
	_sequence += 1
	var domain: Dictionary = FactoryScript.create()
	_register_definitions(domain)
	_add_containers(domain)
	_add_source_items(domain)
	_assert_ok(domain.validator.validate_graph(), "Initial production Item Graph invalid")
	var constructs = ConstructStoreScript.new()
	var bridge = BridgeScript.new()
	var bridge_root: String = existing_bridge_root if not existing_bridge_root.is_empty() else "user://c2b-m0-%s-%d-%d" % [suffix, Time.get_ticks_usec(), _sequence]
	_assert_ok(bridge.setup(bridge_root), "M0 bridge setup failed")
	var adapter = AdapterScript.new()
	_assert_ok(adapter.setup(
		domain.items, domain.containers, domain.validator, domain.mass, domain.operations,
		constructs, bridge, "authority/construction-test", 3, 0, 0, 0, {}
	), "Authoritative adapter setup failed")
	return {"domain": domain, "constructs": constructs, "bridge": bridge, "adapter": adapter, "bridge_root": bridge_root}


func _register_definitions(domain: Dictionary) -> void:
	for row in [
		{"id": "construct_root", "display_name": "Construct root", "max_stack": 1, "unit_mass_kg": 0.1, "external_volume_l": 0.1, "tags": ["construction"]},
		{"id": "wood_panel", "display_name": "Wood panel", "max_stack": 1, "unit_mass_kg": 12.0, "external_volume_l": 40.0, "tags": ["construction_part"]},
		{"id": "wood_beam", "display_name": "Wood beam", "max_stack": 1, "unit_mass_kg": 2.0, "external_volume_l": 8.0, "tags": ["construction_part"]},
		{"id": "fastener", "display_name": "Fastener", "max_stack": 100, "unit_mass_kg": 0.05, "external_volume_l": 0.02, "tags": ["material"]},
	]:
		domain.items.register_definition(DefinitionScript.new(row))


func _add_containers(domain: Dictionary) -> void:
	for container in [
		ContainerScript.new({"container_id": "container/backpack", "owner_kind": "ACTOR", "owner_id": "player", "storage_mode": ContainerScript.STORAGE_SLOTS, "slot_count": 8, "maximum_mass_kg": 1000.0, "maximum_volume_l": 1000.0}),
		ContainerScript.new({"container_id": "container/tools", "owner_kind": "ACTOR", "owner_id": "player", "storage_mode": ContainerScript.STORAGE_SLOTS, "slot_count": 4, "maximum_mass_kg": 1000.0, "maximum_volume_l": 1000.0}),
		ContainerScript.new({"container_id": "container/salvage", "owner_kind": "SYSTEM", "owner_id": "test", "storage_mode": ContainerScript.STORAGE_BULK, "slot_count": 16, "maximum_mass_kg": 1000.0, "maximum_volume_l": 1000.0}),
	]:
		_assert(domain.containers.add_container(container), "Could not add container %s" % container.container_id)


func _add_source_items(domain: Dictionary) -> void:
	var rows: Array = [
		[TOP_ID, "wood_panel", "Top", 1, "container/backpack", 0],
		[LEG_A_ID, "wood_beam", "Leg A", 1, "container/backpack", 1],
		[LEG_B_ID, "wood_beam", "Leg B", 1, "container/backpack", 2],
		[LEG_C_ID, "wood_beam", "Leg C", 1, "container/backpack", 3],
		[LEG_D_ID, "wood_beam", "Leg D", 1, "container/backpack", 4],
		[FASTENER_ID, "fastener", "Fasteners", 8, "container/tools", 0],
	]
	for row in rows:
		var item = ItemScript.new({"instance_id": row[0], "definition_id": row[1], "display_name": row[2], "quantity": row[3], "relation": RelationsScript.container(row[4], row[5]), "components": {}, "revision": 0})
		_assert(domain.items.add_item(item), "Could not add production item %s" % row[0])
		var container = domain.containers.get_container(row[4])
		container.item_ids.append(row[0])
		container.slot_assignments[int(row[5])] = row[0]


func _assembly_plan(adapter, operation_id: String) -> Dictionary:
	var root: Dictionary = PlannerScript.create_root_projection(ROOT_ID, CONSTRUCT_ID, "Authoritative table", RelationsScript.world())
	var sources: Array = []
	for item_id in PART_IDS + [FASTENER_ID]:
		sources.append(adapter.get_item_projection(item_id))
	var result: Dictionary = PlannerScript.build_assembly_plan(
		"plan/%s" % operation_id.trim_prefix("operation/"), operation_id, _table_snapshot(), root, sources, {FASTENER_ID: 4}
	)
	_assert_ok(result, "Assembly plan creation failed")
	return result.plan


func _deconstruction_plan(adapter, operation_id: String) -> Dictionary:
	var root: Dictionary = adapter.get_item_projection(ROOT_ID)
	var parts: Array = []
	for item_id in PART_IDS:
		parts.append(adapter.get_item_projection(item_id))
	var result: Dictionary = PlannerScript.build_deconstruction_plan(
		"plan/%s" % operation_id.trim_prefix("operation/"), operation_id,
		adapter.get_construct_snapshot(CONSTRUCT_ID), root, parts, RelationsScript.container("container/salvage", -1)
	)
	_assert_ok(result, "Deconstruction plan creation failed")
	return result.plan


func _table_snapshot() -> Dictionary:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup(CONSTRUCT_ID, ROOT_ID), "Table aggregate setup failed")
	var revision: int = 0
	for part in [
		PartScript.create("part/table/top", TOP_ID, "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		PartScript.create("part/table/leg-a", LEG_A_ID, "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-b", LEG_B_ID, "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-c", LEG_C_ID, "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		PartScript.create("part/table/leg-d", LEG_D_ID, "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]:
		_assert_ok(aggregate.add_part("operation/c2b/table/%d" % revision, revision, part), "Table part add failed")
		revision += 1
	for bond in [
		BondScript.create("bond/table/leg-a", "part/table/top", "part/table/leg-a", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-b", "part/table/top", "part/table/leg-b", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-c", "part/table/top", "part/table/leg-c", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-d", "part/table/top", "part/table/leg-d", "BOLT", 2500.0),
	]:
		_assert_ok(aggregate.add_bond("operation/c2b/table/%d" % revision, revision, bond), "Table bond add failed")
		revision += 1
	_assert_ok(aggregate.set_build_state("operation/c2b/table/operational", revision, "OPERATIONAL"), "Table did not become operational")
	return aggregate.export_snapshot()


func _canonical_json(value) -> String:
	return preload("res://scripts/network/contracts/network_contract_utils.gd").canonical_json(value)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, code: String, message: String) -> void:
	_assert(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [message, result])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("C2B authoritative Item Graph integration: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C2B authoritative Item Graph integration: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

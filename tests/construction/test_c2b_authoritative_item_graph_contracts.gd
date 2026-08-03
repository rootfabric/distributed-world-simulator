extends SceneTree

const AggregateScript = preload("res://scripts/construction/domain/construct_aggregate.gd")
const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const PlannerScript = preload("res://scripts/construction/item_graph/construction_item_transaction_planner.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const StateScript = preload("res://scripts/construction/authoritative/construction_authoritative_state.gd")
const TranslatorScript = preload("res://scripts/construction/authoritative/construction_m0_batch_translator.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")
const PortScript = preload("res://scripts/construction/item_graph/construction_item_graph_transaction_port.gd")
const AdapterScript = preload("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_construct_store_contract()
	_test_authoritative_state_contract()
	_test_m0_translation_contract()
	_test_adapter_and_documentation_contracts()
	_finish()


func _test_construct_store_contract() -> void:
	var snapshot: Dictionary = _table_snapshot()
	var store = ConstructStoreScript.new()
	var create_mutation: Dictionary = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd").create(
		"CREATE", "construct/table/c2b", {}, snapshot
	)
	_assert_ok(store.apply_mutation(create_mutation), "Construct store rejected valid create")
	_assert(store.size() == 1, "Construct store size did not advance")
	_assert(_canonical_json(store.get_snapshot("construct/table/c2b")) == _canonical_json(snapshot), "Construct store did not preserve snapshot")
	var persisted: Dictionary = store.to_dict()
	_assert_ok(ConstructStoreScript.validate_state(persisted), "Construct store state rejected")
	_assert(String(persisted.get("checksum", "")).length() == 64, "Construct store checksum is not SHA-256 sized")
	var restored = ConstructStoreScript.new()
	_assert_ok(restored.load_dict(JSON.parse_string(JSON.stringify(persisted, "", true, true))), "Construct store JSON load failed")
	_assert(_canonical_json(restored.to_dict()) == _canonical_json(persisted), "Construct store JSON round-trip changed state")
	var tampered: Dictionary = persisted.duplicate(true)
	tampered["constructs"].clear()
	_assert_error(ConstructStoreScript.validate_state(tampered), "CONSTRUCT_STORE_CHECKSUM_MISMATCH", "Tampered construct store accepted")
	var delete_mutation: Dictionary = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd").create(
		"DELETE", "construct/table/c2b", snapshot, {}
	)
	_assert_ok(store.apply_mutation(delete_mutation), "Construct store rejected valid delete")
	_assert(store.size() == 0, "Construct store retained deleted construct")


func _test_authoritative_state_contract() -> void:
	var store = ConstructStoreScript.new()
	var state: Dictionary = StateScript.create(
		"authority/construction-test",
		3,
		4,
		5,
		20,
		{},
		{"schema": "planet_simulator.item_registry.v2", "schema_version": 2, "definitions": [], "items": []},
		{"schema": "planet_simulator.container_registry.v2", "schema_version": 2, "containers": []},
		store.to_dict(),
		{"schema": "planet_simulator.item_operation_ledger.v1", "schema_version": 1, "maximum_entries": 10, "next_sequence": 1, "records": []}
	)
	_assert_ok(StateScript.validate(state), "Authoritative state rejected")
	_assert(String(state["checksum"]).length() == 64, "Authoritative state checksum is not SHA-256 sized")
	var roundtrip = JSON.parse_string(JSON.stringify(state, "", true, true))
	_assert(roundtrip is Dictionary, "Authoritative state did not survive JSON")
	_assert_ok(StateScript.validate(Dictionary(roundtrip)), "Authoritative state JSON round-trip rejected")
	_assert(_canonical_json(Dictionary(roundtrip)) == _canonical_json(state), "Authoritative state JSON round-trip changed values")
	var tampered: Dictionary = state.duplicate(true)
	tampered["server_tick"] = 21
	_assert_error(StateScript.validate(tampered), "AUTHORITATIVE_CONSTRUCTION_STATE_CHECKSUM_MISMATCH", "Tampered authoritative state accepted")
	var future: Dictionary = state.duplicate(true)
	future["schema"] = "planet_simulator.authoritative_construction_state.v2"
	future["checksum"] = StateScript.compute_checksum(future)
	_assert_error(StateScript.validate(future), "UNSUPPORTED_AUTHORITATIVE_CONSTRUCTION_STATE_SCHEMA", "Future authoritative state schema accepted")
	var mismatched_revisions: Dictionary = state.duplicate(true)
	mismatched_revisions["construct_authority_revisions"] = {"construct/table/ghost": 0}
	mismatched_revisions["checksum"] = StateScript.compute_checksum(mismatched_revisions)
	_assert_error(StateScript.validate(mismatched_revisions), "CONSTRUCT_AUTHORITY_REVISION_SET_MISMATCH", "Authority revision map accepted a construct absent from store")
	var invalid_item_schema: Dictionary = state.duplicate(true)
	invalid_item_schema["item_registry"]["schema"] = "planet_simulator.item_registry.v999"
	invalid_item_schema["checksum"] = StateScript.compute_checksum(invalid_item_schema)
	_assert_error(StateScript.validate(invalid_item_schema), "INVALID_AUTHORITATIVE_ITEM_REGISTRY_SCHEMA", "Invalid ItemRegistry schema accepted")


func _test_m0_translation_contract() -> void:
	var snapshot: Dictionary = _table_snapshot()
	var root: Dictionary = PlannerScript.create_root_projection(
		"item/00000000-0000-4000-8000-0000000000ff",
		"construct/table/c2b",
		"C2B table",
		ProjectionScript.world_relation()
	)
	var source: Array = _source_projections()
	var planned: Dictionary = PlannerScript.build_assembly_plan(
		"plan/c2b/contracts/assemble",
		"operation/c2b/contracts/assemble",
		snapshot,
		root,
		source,
		{"item/00000000-0000-4000-8000-000000000006": 4}
	)
	_assert_ok(planned, "Assembly plan fixture failed")
	var item_graph_before: Dictionary = _wrapped_item_graph("before")
	var item_graph_after: Dictionary = _wrapped_item_graph("after")
	var ledger_before: Dictionary = _wrapped_ledger("before")
	var ledger_after: Dictionary = _wrapped_ledger("after")
	var translated: Dictionary = TranslatorScript.build_batch(
		planned["plan"],
		item_graph_before,
		item_graph_after,
		ledger_before,
		ledger_after,
		"authority/construction-test",
		3,
		7,
		8,
		40
	)
	_assert_ok(translated, "C2B plan did not translate to M0 batch")
	var batch: Dictionary = translated["batch"]
	_assert_ok(BatchScript.validate(batch), "Translated M0 batch rejected by canonical M0 contract")
	_assert(batch["preconditions"].size() == 3 and batch["operations"].size() == 3, "M0 batch does not cover item graph, ledger and construct")
	var aggregate_ids: Array[String] = []
	for operation in batch["operations"]:
		aggregate_ids.append(String(operation["aggregate_id"]))
	var sorted_ids: Array[String] = aggregate_ids.duplicate()
	sorted_ids.sort()
	_assert(aggregate_ids == sorted_ids, "M0 aggregate operations are not canonical")
	_assert(aggregate_ids.has(TranslatorScript.ITEM_GRAPH_AGGREGATE_ID), "M0 batch omits production Item Graph aggregate")
	_assert(aggregate_ids.has(TranslatorScript.LEDGER_AGGREGATE_ID), "M0 batch omits shared Operation Ledger aggregate")
	_assert(aggregate_ids.has(TranslatorScript.aggregate_id_for_construct("construct/table/c2b")), "M0 batch omits ConstructAggregate")
	_assert(String(batch["batch_id"]) == TranslatorScript.batch_id_for_plan(planned["plan"]), "M0 batch ID is not deterministic")
	var empty_store = ConstructStoreScript.new()
	var bootstrapped: Dictionary = TranslatorScript.build_bootstrap_snapshots(
		item_graph_before, ledger_before, empty_store.to_dict(),
		"authority/construction-test", 3, 7, 8, 39
	)
	_assert_ok(bootstrapped, "M0 bootstrap snapshot generation failed")
	_assert(bootstrapped["snapshots"].size() == 2, "Empty construction runtime must bootstrap two canonical aggregates")


func _test_adapter_and_documentation_contracts() -> void:
	var adapter = AdapterScript.new()
	_assert_ok(PortScript.validate_adapter(adapter), "C2B adapter no longer satisfies construction transaction port")
	var adapter_text: String = FileAccess.get_file_as_string("res://scripts/construction/authoritative/authoritative_construction_item_graph_adapter.gd")
	for production_path in [
		"res://scripts/items/services/item_registry.gd",
		"res://scripts/containers/container_registry.gd",
		"res://scripts/items/services/item_relationship_validator.gd",
		"res://scripts/items/services/item_mass_service.gd",
		"res://scripts/items/services/item_operation_ledger.gd",
	]:
		_assert(adapter_text.contains(production_path), "C2B adapter does not import production dependency: %s" % production_path)
	var map_text: String = FileAccess.get_file_as_string("res://docs/plans/CONSTRUCTION_MAP_RU.md")
	_assert(map_text.contains("C2B") and map_text.contains("Authoritative Item Graph Integration"), "Construction map does not expose C2B")
	var powershell_runner: String = FileAccess.get_file_as_string("res://RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.ps1")
	var shell_runner: String = FileAccess.get_file_as_string("res://RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.sh")
	_assert(powershell_runner.contains("test_c2b_authoritative_item_graph_contracts.gd") and powershell_runner.contains("test_c2b_authoritative_item_graph_integration.gd"), "C2B PowerShell runner omits a focused scenario")
	_assert(shell_runner.contains("test_c2b_authoritative_item_graph_contracts.gd") and shell_runner.contains("test_c2b_authoritative_item_graph_integration.gd"), "C2B shell runner omits a focused scenario")
	_assert(TranslatorScript.PACKAGE_HASH.length() == 64, "C2B dynamic package hash is not 64 hexadecimal characters")
	var world_runner: String = FileAccess.get_file_as_string("res://RUN_WORLD_REGRESSION_TESTS.ps1")
	_assert(world_runner.contains("test_c2b_authoritative_item_graph_contracts.gd"), "World regression omits C2B contract test")
	_assert(world_runner.contains("test_c2b_authoritative_item_graph_integration.gd"), "World regression omits C2B integration test")


func _table_snapshot() -> Dictionary:
	var aggregate = AggregateScript.new()
	_assert_ok(aggregate.setup("construct/table/c2b", "item/00000000-0000-4000-8000-0000000000ff"), "C2B table setup failed")
	var revision: int = 0
	for part in _parts():
		_assert_ok(aggregate.add_part("op/c2b/contracts/%s" % part["part_id"], revision, part), "C2B part add failed")
		revision += 1
	for bond in _bonds():
		_assert_ok(aggregate.add_bond("op/c2b/contracts/%s" % bond["bond_id"], revision, bond), "C2B bond add failed")
		revision += 1
	_assert_ok(aggregate.set_build_state("op/c2b/contracts/operational", revision, "OPERATIONAL"), "C2B table did not become operational")
	return aggregate.export_snapshot()


func _source_projections() -> Array:
	return [
		ProjectionScript.create("item/00000000-0000-4000-8000-000000000001", "wood_panel", "Top", 1, ProjectionScript.container_relation("container/backpack", 0), {}, 0),
		ProjectionScript.create("item/00000000-0000-4000-8000-000000000002", "wood_beam", "Leg A", 1, ProjectionScript.container_relation("container/backpack", 1), {}, 0),
		ProjectionScript.create("item/00000000-0000-4000-8000-000000000003", "wood_beam", "Leg B", 1, ProjectionScript.container_relation("container/backpack", 2), {}, 0),
		ProjectionScript.create("item/00000000-0000-4000-8000-000000000004", "wood_beam", "Leg C", 1, ProjectionScript.container_relation("container/backpack", 3), {}, 0),
		ProjectionScript.create("item/00000000-0000-4000-8000-000000000005", "wood_beam", "Leg D", 1, ProjectionScript.container_relation("container/backpack", 4), {}, 0),
		ProjectionScript.create("item/00000000-0000-4000-8000-000000000006", "fastener", "Fasteners", 8, ProjectionScript.container_relation("container/tools", 0), {}, 0),
	]


func _parts() -> Array:
	return [
		PartScript.create("part/table/top", "item/00000000-0000-4000-8000-000000000001", "PANEL", "surface", 12.0, [0.0, 0.75, 0.0]),
		PartScript.create("part/table/leg-a", "item/00000000-0000-4000-8000-000000000002", "BEAM", "support", 2.0, [-0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-b", "item/00000000-0000-4000-8000-000000000003", "BEAM", "support", 2.0, [0.5, 0.375, -0.3]),
		PartScript.create("part/table/leg-c", "item/00000000-0000-4000-8000-000000000004", "BEAM", "support", 2.0, [0.5, 0.375, 0.3]),
		PartScript.create("part/table/leg-d", "item/00000000-0000-4000-8000-000000000005", "BEAM", "support", 2.0, [-0.5, 0.375, 0.3]),
	]


func _bonds() -> Array:
	return [
		BondScript.create("bond/table/leg-a", "part/table/top", "part/table/leg-a", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-b", "part/table/top", "part/table/leg-b", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-c", "part/table/top", "part/table/leg-c", "BOLT", 2500.0),
		BondScript.create("bond/table/leg-d", "part/table/top", "part/table/leg-d", "BOLT", 2500.0),
	]


func _wrapped_item_graph(marker: String) -> Dictionary:
	var state: Dictionary = {"schema": TranslatorScript.ITEM_GRAPH_STATE_SCHEMA, "item_registry": {"marker": marker}, "container_registry": {"marker": marker}, "checksum": ""}
	state["checksum"] = _checksum(state)
	return state


func _wrapped_ledger(marker: String) -> Dictionary:
	var state: Dictionary = {"schema": TranslatorScript.LEDGER_STATE_SCHEMA, "operation_ledger": {"marker": marker}, "checksum": ""}
	state["checksum"] = _checksum(state)
	return state


func _canonical_json(value) -> String:
	return preload("res://scripts/network/contracts/network_contract_utils.gd").canonical_json(value)


func _checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return preload("res://scripts/network/contracts/network_contract_utils.gd").payload_hash(payload)


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
		print("C2B authoritative Item Graph contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("C2B authoritative Item Graph contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

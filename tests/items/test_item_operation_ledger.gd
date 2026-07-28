extends SceneTree

const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const Definition = preload("res://scripts/items/domain/item_definition.gd")
const ContainerState = preload("res://scripts/containers/container_state.gd")
const Relations = preload("res://scripts/items/domain/item_relations.gd")
const OperationFingerprint = preload("res://scripts/items/services/item_operation_fingerprint.gd")
const OperationLedger = preload("res://scripts/items/services/item_operation_ledger.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_canonical_payload_fingerprint()
	_test_exact_replay_and_payload_conflict()
	_test_revision_conflict_contract()
	_test_split_revision_and_replay()
	_test_retryable_failure_can_be_retried()
	_test_ledger_schema_and_bounded_history()
	_test_transient_content_generation()
	_test_persistent_ledger_replay_after_restart()
	_finish()


func _test_canonical_payload_fingerprint() -> void:
	var first_payload: Dictionary = {
		"z": 3,
		"relation": {
			"kind": "CONTAINER",
			"slot": 2,
			"container_id": "backpack",
		},
		"a": [1, 2, 3],
	}
	var second_payload: Dictionary = {
		"a": [1, 2, 3],
		"relation": {
			"container_id": "backpack",
			"slot": 2,
			"kind": "CONTAINER",
		},
		"z": 3,
	}
	var first: Dictionary = OperationFingerprint.build(
		"MOVE_ITEM",
		"item/example",
		7,
		first_payload
	)
	var second: Dictionary = OperationFingerprint.build(
		"MOVE_ITEM",
		"item/example",
		7,
		second_payload
	)
	_assert_success(first, "First payload fingerprint must be created")
	_assert_success(second, "Second payload fingerprint must be created")
	_assert(
		String(first.get("payload_hash", "")) == String(second.get("payload_hash", "")),
		"Dictionary insertion order must not change payload hash"
	)
	_assert(
		OperationFingerprint.is_sha256_hex(String(first.get("payload_hash", ""))),
		"Payload fingerprint must be lowercase SHA-256"
	)
	var changed_revision: Dictionary = OperationFingerprint.build(
		"MOVE_ITEM",
		"item/example",
		8,
		second_payload
	)
	_assert(
		String(changed_revision.get("payload_hash", "")) != String(first.get("payload_hash", "")),
		"expected_revision must participate in payload fingerprint"
	)
	var changed_command: Dictionary = OperationFingerprint.build(
		"SPLIT_AND_MOVE",
		"item/example",
		7,
		second_payload
	)
	_assert(
		String(changed_command.get("payload_hash", "")) != String(first.get("payload_hash", "")),
		"command_type must participate in payload fingerprint"
	)


func _test_exact_replay_and_payload_conflict() -> void:
	var fixture: Dictionary = _fixture()
	var rock = fixture.items.create_item("rock", 1, {}, Relations.world())
	var target: Dictionary = Relations.container("backpack")
	var first: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		target,
		"move-exact-replay",
		0
	)
	_assert_success(first, "Revision-guarded move must succeed")
	_assert(String(first.get("status", "")) == OperationLedger.STATUS_SUCCEEDED, "Successful operation must expose SUCCEEDED status")
	_assert(int(first.get("expected_revision", -2)) == 0, "Result must preserve expected revision")
	_assert(int(first.get("result_revision", -2)) == 1, "Successful move must expose result revision")
	_assert(String(first.get("command_type", "")) == "MOVE_ITEM", "Result must expose command type")
	_assert(OperationFingerprint.is_sha256_hex(String(first.get("payload_hash", ""))), "Result must expose payload hash")
	_assert(fixture.operations.size() == 1, "Successful operation must be recorded once")

	var replay: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		target,
		"move-exact-replay",
		0
	)
	_assert(first == replay, "Exact replay must return byte-equivalent stored result")
	_assert(rock.revision == 1, "Exact replay must not increment item revision")
	_assert(fixture.operations.size() == 1, "Exact replay must not append another ledger record")
	_assert(fixture.containers.get_container("backpack").item_ids.count(rock.instance_id) == 1, "Exact replay must not duplicate container membership")

	var conflict: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.world(),
		"move-exact-replay",
		1
	)
	_assert_error(conflict, "OPERATION_ID_CONFLICT", "Same operation ID with another payload must fail")
	_assert(String(conflict.get("status", "")) == OperationLedger.STATUS_REJECTED, "Operation ID conflict must be terminal rejection")
	_assert(Relations.kind_of(rock.relation) == Relations.CONTAINER, "Payload conflict must not mutate aggregate")
	_assert(rock.revision == 1, "Payload conflict must preserve revision")
	_assert(fixture.operations.size() == 1, "Payload conflict must not replace stored operation")


func _test_revision_conflict_contract() -> void:
	var fixture: Dictionary = _fixture()
	var rock = fixture.items.create_item("rock", 1, {}, Relations.world())
	var invalid_expected: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.container("backpack"),
		"invalid-expected-revision",
		-2
	)
	_assert_error(invalid_expected, "INVALID_EXPECTED_REVISION", "Expected revision below compatibility sentinel must fail")
	_assert(fixture.operations.size() == 0, "Invalid command envelope must not enter operation ledger")
	var rejected: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.container("backpack"),
		"revision-conflict-original",
		4
	)
	_assert_error(rejected, "REVISION_CONFLICT", "Wrong expected revision must be rejected")
	_assert(String(rejected.get("status", "")) == OperationLedger.STATUS_REJECTED, "Revision conflict must be terminal rejection")
	_assert(int(rejected.get("result_revision", -2)) == 0, "Revision conflict must report current revision")
	_assert(fixture.operations.has_operation("revision-conflict-original"), "Revision conflict must be remembered")
	_assert(rock.revision == 0, "Rejected command must not mutate revision")

	var valid: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.container("backpack"),
		"revision-valid",
		0
	)
	_assert_success(valid, "Fresh expected revision must succeed")
	_assert(rock.revision == 1, "Successful command must increment revision exactly once")

	var rejected_replay: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.container("backpack"),
		"revision-conflict-original",
		4
	)
	_assert(rejected == rejected_replay, "Terminal rejection must replay unchanged after aggregate changes")
	var stale: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		Relations.world(),
		"revision-stale-new-command",
		0
	)
	_assert_error(stale, "REVISION_CONFLICT", "New command with stale revision must fail")
	_assert(int(stale.get("result_revision", -2)) == 1, "Stale command must report latest aggregate revision")
	_assert(Relations.kind_of(rock.relation) == Relations.CONTAINER, "Stale command must not change relation")


func _test_split_revision_and_replay() -> void:
	var fixture: Dictionary = _fixture()
	var source = fixture.items.create_item("rock", 10, {}, Relations.world(), "Lunar sample")
	var first: Dictionary = fixture.transfer.split_and_move(
		source.instance_id,
		3,
		Relations.container("backpack"),
		"split-replay",
		0
	)
	_assert_success(first, "Revision-guarded split must succeed")
	_assert(source.quantity == 7, "Split must decrement source quantity once")
	_assert(source.revision == 1, "Split must increment source revision once")
	_assert(int(first.get("result_revision", -2)) == 1, "Split result revision must belong to source aggregate")
	var new_item_id: String = String(first.get("new_item_id", ""))
	_assert(not new_item_id.is_empty(), "Split must expose created item ID")
	_assert(fixture.items.get_item(new_item_id) != null, "Split output must exist")
	var item_count_after_first: int = fixture.items.all_items().size()

	var replay: Dictionary = fixture.transfer.split_and_move(
		source.instance_id,
		3,
		Relations.container("backpack"),
		"split-replay",
		0
	)
	_assert(first == replay, "Exact split replay must return stored result")
	_assert(source.quantity == 7, "Split replay must not decrement source again")
	_assert(source.revision == 1, "Split replay must not increment source revision")
	_assert(fixture.items.all_items().size() == item_count_after_first, "Split replay must not create another item")

	var conflict: Dictionary = fixture.transfer.split_and_move(
		source.instance_id,
		4,
		Relations.container("backpack"),
		"split-replay",
		1
	)
	_assert_error(conflict, "OPERATION_ID_CONFLICT", "Split operation ID must bind quantity and expected revision")
	_assert(source.quantity == 7, "Conflicting split payload must not mutate source")


func _test_retryable_failure_can_be_retried() -> void:
	var fixture: Dictionary = _fixture()
	var rock = fixture.items.create_item("rock", 1, {}, Relations.world())
	var relation: Dictionary = Relations.container("late-container")
	var unavailable: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		relation,
		"retryable-container",
		0
	)
	_assert_error(unavailable, "CONTAINER_NOT_FOUND", "Missing container must fail")
	_assert(String(unavailable.get("status", "")) == OperationLedger.STATUS_RETRYABLE, "Unavailable dependency must be retryable")
	_assert(not fixture.operations.has_operation("retryable-container"), "Retryable failure must not poison persistent ledger")
	_assert(rock.revision == 0, "Retryable failure must not mutate item")

	fixture.containers.add_container(ContainerState.new({
		"container_id": "late-container",
		"owner_kind": "SYSTEM",
		"owner_id": "test",
		"slot_count": 4,
		"maximum_mass_kg": 100.0,
		"maximum_volume_l": 100.0,
	}))
	var retry: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		relation,
		"retryable-container",
		0
	)
	_assert_success(retry, "Same operation ID must succeed after retryable dependency appears")
	_assert(String(retry.get("status", "")) == OperationLedger.STATUS_SUCCEEDED, "Successful retry must become terminal")
	_assert(fixture.operations.has_operation("retryable-container"), "Successful retry must be persisted")
	_assert(rock.revision == 1, "Successful retry must increment revision once")


func _test_ledger_schema_and_bounded_history() -> void:
	var fixture: Dictionary = _fixture(2)
	for index in range(3):
		var item = fixture.items.create_item(
			"rock",
			1,
			{},
			Relations.world(),
			"Bounded %d" % index
		)
		var result: Dictionary = fixture.transfer.move_item(
			item.instance_id,
			Relations.container("backpack"),
			"bounded-%d" % index,
			0
		)
		_assert_success(result, "Bounded ledger operation %d must succeed" % index)
	_assert(fixture.operations.size() == 2, "Ledger must prune entries above configured maximum")
	_assert(not fixture.operations.has_operation("bounded-0"), "Ledger must prune oldest sequence first")
	_assert(fixture.operations.has_operation("bounded-1"), "Ledger must preserve newer entry")
	_assert(fixture.operations.has_operation("bounded-2"), "Ledger must preserve newest entry")

	var snapshot: Dictionary = fixture.operations.to_dict()
	var encoded: String = JSON.stringify(snapshot, "", true, true)
	var decoded = JSON.parse_string(encoded)
	var restored = OperationLedger.new()
	var load_result: Dictionary = restored.load_dict(Dictionary(decoded))
	_assert_success(load_result, "Operation ledger must survive JSON round-trip")
	_assert(restored.to_dict() == snapshot, "Operation ledger JSON round-trip must preserve complete payload")

	var before_invalid: Dictionary = restored.to_dict()
	var invalid: Dictionary = before_invalid.duplicate(true)
	invalid["schema_version"] = 999
	var invalid_result: Dictionary = restored.load_dict(invalid)
	_assert_error(invalid_result, "UNSUPPORTED_OPERATION_LEDGER_VERSION", "Future ledger version must fail closed")
	_assert(restored.to_dict() == before_invalid, "Failed ledger load must not mutate active records")


func _test_transient_content_generation() -> void:
	var ledger := OperationLedger.new()
	var initial_generation := int(ledger.get_content_generation())
	ledger.remember_terminal(
		"generation-terminal",
		"TEST",
		"%064d" % 3,
		"item/generation",
		0,
		1,
		OperationLedger.STATUS_SUCCEEDED,
		{"success": true, "item_id": "item/generation"}
	)
	var remembered_generation := int(ledger.get_content_generation())
	_assert(remembered_generation > initial_generation, "remember_terminal must advance transient ledger generation")
	var snapshot := ledger.to_dict()
	ledger.clear()
	var cleared_generation := int(ledger.get_content_generation())
	_assert(cleared_generation > remembered_generation, "clear must advance transient ledger generation")
	_assert_success(ledger.load_dict(snapshot), "Generation fixture must reload valid ledger snapshot")
	var loaded_generation := int(ledger.get_content_generation())
	_assert(loaded_generation > cleared_generation, "load_dict must advance transient ledger generation")
	var before_invalid_generation := loaded_generation
	var invalid_snapshot := snapshot.duplicate(true)
	invalid_snapshot["schema_version"] = 999
	_assert_error(ledger.load_dict(invalid_snapshot), "UNSUPPORTED_OPERATION_LEDGER_VERSION", "Invalid load must fail")
	_assert(int(ledger.get_content_generation()) == before_invalid_generation, "Failed load_dict must not advance transient ledger generation")
	_assert(not ledger.to_dict().has("content_generation"), "Transient generation must not enter persisted ledger schema")


func _test_persistent_ledger_replay_after_restart() -> void:
	var fixture: Dictionary = _fixture()
	var rock = fixture.items.create_item("rock", 1, {}, Relations.world(), "Persistent sample")
	var target: Dictionary = Relations.container("backpack")
	var original: Dictionary = fixture.transfer.move_item(
		rock.instance_id,
		target,
		"persistent-operation",
		0
	)
	_assert_success(original, "Operation must succeed before persistence")

	var root_path: String = "user://r12-operation-ledger-%d" % Time.get_ticks_msec()
	var store = Factory.create_json_state_store(root_path)
	_assert_success(store.save_state("items", fixture.items.to_dict()), "Item registry must save for restart fixture")
	_assert_success(store.save_state("containers", fixture.containers.to_dict()), "Container registry must save for restart fixture")
	_assert_success(fixture.operations.save_to_store(store, "operations"), "Operation ledger must save through ItemStateStore")

	var restored_fixture: Dictionary = _fixture()
	var item_state: Dictionary = store.load_state("items")
	var container_state: Dictionary = store.load_state("containers")
	_assert_success(item_state, "Saved item registry must load")
	_assert_success(container_state, "Saved container registry must load")
	_assert_success(restored_fixture.items.load_dict(Dictionary(item_state.get("state", {}))), "Restored item registry must accept saved state")
	restored_fixture.containers.load_dict(Dictionary(container_state.get("state", {})))
	_assert_success(restored_fixture.operations.load_from_store(store, "operations"), "Restored operation ledger must load")
	_assert_success(restored_fixture.validator.validate_graph(), "Restarted aggregate graph must remain valid")

	var restored_rock = restored_fixture.items.get_item(rock.instance_id)
	_assert(restored_rock != null, "Restart must preserve aggregate identity")
	_assert(restored_rock.revision == 1, "Restart must preserve result revision")
	var replay: Dictionary = restored_fixture.transfer.move_item(
		rock.instance_id,
		target,
		"persistent-operation",
		0
	)
	_assert(original == replay, "Operation replay after restart must return persisted result")
	_assert(restored_rock.revision == 1, "Persistent replay must not mutate aggregate")
	_assert(restored_fixture.containers.get_container("backpack").item_ids.count(rock.instance_id) == 1, "Persistent replay must not duplicate membership")

	var conflict: Dictionary = restored_fixture.transfer.move_item(
		rock.instance_id,
		Relations.world(),
		"persistent-operation",
		1
	)
	_assert_error(conflict, "OPERATION_ID_CONFLICT", "Persisted operation ID must reject another payload after restart")
	_assert(restored_rock.revision == 1, "Persistent payload conflict must not mutate aggregate")

	store.delete_state("items")
	store.delete_state("containers")
	store.delete_state("operations")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root_path))


func _fixture(operation_limit: int = 2048) -> Dictionary:
	var fixture: Dictionary = Factory.create(operation_limit)
	fixture.items.register_definition(Definition.new({
		"id": "rock",
		"display_name": "Rock",
		"max_stack": 50,
		"unit_mass_kg": 2.0,
		"external_volume_l": 0.8,
		"tags": ["rock", "resource"],
	}))
	fixture.containers.add_container(ContainerState.new({
		"container_id": "backpack",
		"owner_kind": "ACTOR",
		"owner_id": "player",
		"slot_count": 16,
		"maximum_mass_kg": 200.0,
		"maximum_volume_l": 200.0,
		"allow_nested_containers": true,
		"maximum_nested_depth": 4,
	}))
	return fixture


func _assert_success(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s; result=%s" % [message, str(result)])


func _assert_error(result: Dictionary, expected_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false))
		and String(result.get("error_code", "")) == expected_code,
		"%s; expected=%s result=%s" % [message, expected_code, str(result)]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Item operation ledger: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Item operation ledger: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

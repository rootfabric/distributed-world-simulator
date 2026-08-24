extends SceneTree

const CanonicalItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const MAIN_SCENE_PATH := "res://main.tscn"
const V0_BOOTSTRAP_PATH := "res://scripts/app/v0_simulator_app.gd"
const P1_BOOTSTRAP_PATH := "res://scripts/app/v0_p1_simulator_app.gd"
const SHARED_BEACON_ID := "item/shared/beacon/1"
const SHARED_CRATE_ID := "container/shared/crate/1"
const PLAYER_BATTERY_ID := "item/player/a/battery"

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	_test_snapshot_and_export_are_pure()
	_test_legacy_slotless_restore_migrates_once()
	_test_current_restore_preserves_clock()
	_test_restore_validation_uses_incoming_mode()
	_test_generic_v0_bootstrap()
	_finish()


func _test_snapshot_and_export_are_pure() -> void:
	var graph = CanonicalItemGraph.new()
	_assert(
		bool(graph.setup("authority/v0-p2/purity", 1, {"playable_sandbox": true}).get("success", false)),
		"P2 purity graph configures"
	)
	graph.ensure_player("a")
	var first: Dictionary = graph.create_snapshot()
	var second: Dictionary = graph.create_snapshot()
	_assert(
		String(first.get("checksum", "")) == String(second.get("checksum", "")),
		"repeated create_snapshot is checksum-idempotent"
	)
	_assert(
		int(first.get("revision", -1)) == int(second.get("revision", -1))
		and int(first.get("tick", -1)) == int(second.get("tick", -1)),
		"repeated create_snapshot does not advance canonical revision/tick"
	)

	var durable_first: Dictionary = graph.export_durable_state()
	var after_first_export: Dictionary = graph.create_snapshot()
	var durable_second: Dictionary = graph.export_durable_state()
	var after_second_export: Dictionary = graph.create_snapshot()
	_assert(
		String(durable_first.get("checksum", "")) == String(durable_second.get("checksum", "")),
		"repeated export_durable_state is checksum-idempotent"
	)
	_assert(
		String(after_first_export.get("checksum", "")) == String(after_second_export.get("checksum", ""))
		and int(after_first_export.get("revision", -1)) == int(first.get("revision", -1))
		and int(after_first_export.get("tick", -1)) == int(first.get("tick", -1)),
		"durable export does not mutate canonical Item Graph"
	)


func _test_legacy_slotless_restore_migrates_once() -> void:
	var fixture := _build_legacy_slotless_fixture()
	_assert(not fixture.is_empty(), "legacy slotless durable fixture builds")
	if fixture.is_empty():
		return
	var stored_snapshot: Dictionary = Dictionary(fixture.get("snapshot", {}))
	var stored_revision := int(stored_snapshot.get("revision", -1))
	var stored_tick := int(stored_snapshot.get("tick", -1))

	var restored_graph = CanonicalItemGraph.new()
	_assert(
		bool(restored_graph.validate_durable_state(fixture).get("success", false)),
		"fresh target validates legacy sandbox durable state from incoming mode"
	)
	var restored: Dictionary = restored_graph.restore_durable_state(fixture)
	_assert(bool(restored.get("success", false)), "fresh target restores legacy slotless durable state")
	if not bool(restored.get("success", false)):
		return
	var migration: Dictionary = Dictionary(
		Dictionary(restored.get("details", {})).get("slot_migration", {})
	)
	_assert(bool(migration.get("migrated", false)), "legacy restore reports explicit slot migration")
	_assert(
		int(migration.get("before_revision", -1)) == stored_revision
		and int(migration.get("after_revision", -1)) == stored_revision + 1,
		"legacy slot migration advances revision exactly once"
	)
	_assert(
		int(migration.get("before_tick", -1)) == stored_tick
		and int(migration.get("after_tick", -1)) == stored_tick + 1,
		"legacy slot migration advances tick exactly once"
	)
	_assert(
		int(migration.get("changed_item_count", 0)) >= 2,
		"legacy migration reports changed inventory/container item locations"
	)
	_assert(
		int(migration.get("changed_owner_count", 0)) >= 2,
		"legacy migration reports both inventory and external-container owners"
	)

	var migrated: Dictionary = restored_graph.create_snapshot()
	_assert(
		bool(migrated.get("playable_sandbox", false)),
		"fresh legacy restore applies playable sandbox mode from durable state"
	)
	_assert(
		_item_slot_index(migrated, PLAYER_BATTERY_ID) == 2,
		"legacy player inventory receives deterministic battery slot 2"
	)
	_assert(
		_item_location_kind(migrated, SHARED_BEACON_ID) == "CONTAINER"
		and _item_container_id(migrated, SHARED_BEACON_ID) == SHARED_CRATE_ID
		and _item_slot_index(migrated, SHARED_BEACON_ID) == 0,
		"legacy external-container item receives deterministic canonical slot 0"
	)
	_assert(
		_container_has_item(migrated, SHARED_CRATE_ID, SHARED_BEACON_ID),
		"legacy migration preserves canonical external-container membership"
	)

	var repeated: Dictionary = restored_graph.create_snapshot()
	_assert(
		String(repeated.get("checksum", "")) == String(migrated.get("checksum", ""))
		and int(repeated.get("revision", -1)) == stored_revision + 1
		and int(repeated.get("tick", -1)) == stored_tick + 1,
		"post-migration snapshot is pure and does not migrate twice"
	)
	var durable_first: Dictionary = restored_graph.export_durable_state()
	var durable_second: Dictionary = restored_graph.export_durable_state()
	_assert(
		String(durable_first.get("checksum", "")) == String(durable_second.get("checksum", "")),
		"post-migration durable export is stable"
	)
	var after_exports: Dictionary = restored_graph.create_snapshot()
	_assert(
		String(after_exports.get("checksum", "")) == String(migrated.get("checksum", ""))
		and int(after_exports.get("revision", -1)) == stored_revision + 1
		and int(after_exports.get("tick", -1)) == stored_tick + 1,
		"post-migration exports do not advance canonical state"
	)


func _test_current_restore_preserves_clock() -> void:
	var source = CanonicalItemGraph.new()
	_assert(
		bool(source.setup("authority/v0-p2/current-source", 1, {"playable_sandbox": true}).get("success", false)),
		"current-format source graph configures"
	)
	source.ensure_player("a")
	var current: Dictionary = source.export_durable_state()
	_assert(not current.is_empty(), "current slot-aware durable state exports")
	if current.is_empty():
		return
	var stored_snapshot: Dictionary = Dictionary(current.get("snapshot", {}))
	var stored_revision := int(stored_snapshot.get("revision", -1))
	var stored_tick := int(stored_snapshot.get("tick", -1))

	var restored_graph = CanonicalItemGraph.new()
	_assert(
		bool(restored_graph.validate_durable_state(current).get("success", false)),
		"fresh target validates current sandbox durable state from incoming mode"
	)
	var restored: Dictionary = restored_graph.restore_durable_state(current)
	_assert(bool(restored.get("success", false)), "fresh target restores current slot-aware durable state")
	if not bool(restored.get("success", false)):
		return
	var migration: Dictionary = Dictionary(
		Dictionary(restored.get("details", {})).get("slot_migration", {})
	)
	_assert(not bool(migration.get("migrated", true)), "current slot-aware restore does not report migration")
	_assert(
		int(migration.get("after_revision", -1)) == stored_revision
		and int(migration.get("after_tick", -1)) == stored_tick,
		"current slot-aware restore preserves stored revision/tick exactly"
	)
	_assert(
		int(migration.get("changed_item_count", -1)) == 0
		and int(migration.get("changed_owner_count", -1)) == 0,
		"current slot-aware restore has zero migration changes"
	)
	var restored_snapshot: Dictionary = restored_graph.create_snapshot()
	_assert(
		bool(restored_snapshot.get("playable_sandbox", false)),
		"fresh current restore applies playable sandbox mode from durable state"
	)
	_assert(
		String(restored_snapshot.get("checksum", "")) == String(stored_snapshot.get("checksum", "")),
		"current slot-aware restore preserves canonical snapshot checksum"
	)


func _test_restore_validation_uses_incoming_mode() -> void:
	var source = CanonicalItemGraph.new()
	_assert(
		bool(source.setup("authority/v0-p2/mode-source", 1, {"playable_sandbox": true}).get("success", false)),
		"mode-independence source graph configures"
	)
	source.ensure_player("a")
	var current: Dictionary = source.export_durable_state()
	_assert(not current.is_empty(), "mode-independence durable state exports")
	if current.is_empty():
		return

	var mismatched_target = CanonicalItemGraph.new()
	_assert(
		bool(mismatched_target.setup("authority/v0-p2/mismatched-target", 1, {"playable_sandbox": false}).get("success", false)),
		"mismatched restore target configures non-sandbox"
	)
	_assert(
		bool(mismatched_target.validate_durable_state(current).get("success", false)),
		"durable validation ignores prior target mode and uses incoming sandbox mode"
	)
	var restored: Dictionary = mismatched_target.restore_durable_state(current)
	_assert(bool(restored.get("success", false)), "sandbox durable state restores over mismatched prior target mode")
	if not bool(restored.get("success", false)):
		return
	var expected_snapshot: Dictionary = Dictionary(current.get("snapshot", {}))
	var actual_snapshot: Dictionary = mismatched_target.create_snapshot()
	_assert(
		bool(actual_snapshot.get("playable_sandbox", false))
		and String(actual_snapshot.get("checksum", "")) == String(expected_snapshot.get("checksum", "")),
		"incoming durable mode and canonical checksum replace mismatched target configuration"
	)


func _test_generic_v0_bootstrap() -> void:
	_assert(FileAccess.file_exists(MAIN_SCENE_PATH), "P2 main scene exists")
	_assert(FileAccess.file_exists(V0_BOOTSTRAP_PATH), "generic V0 bootstrap exists")
	_assert(FileAccess.file_exists(P1_BOOTSTRAP_PATH), "historical P1 bootstrap remains available")
	if not FileAccess.file_exists(MAIN_SCENE_PATH) or not FileAccess.file_exists(V0_BOOTSTRAP_PATH):
		return
	var main_scene := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	var bootstrap := FileAccess.get_file_as_string(V0_BOOTSTRAP_PATH)
	_assert(
		main_scene.contains("res://scripts/app/v0_simulator_app.gd")
		and not main_scene.contains("res://scripts/app/v0_p1_simulator_app.gd"),
		"main scene routes through generic V0 product bootstrap"
	)
	_assert(
		bootstrap.contains('bool(options.get("network_mvp", false))')
		and bootstrap.contains('launch_option_errors.is_empty()'),
		"generic V0 bootstrap bridges product mode only after launch validation"
	)
	_assert(
		bootstrap.contains('options["network_playground"] = true'),
		"generic V0 bootstrap preserves inherited playable-sandbox capability"
	)


func _build_legacy_slotless_fixture() -> Dictionary:
	var source = CanonicalItemGraph.new()
	if not bool(source.setup("authority/v0-p2/legacy-source", 1, {"playable_sandbox": true}).get("success", false)):
		return {}
	source.ensure_player("a")
	var durable: Dictionary = source.export_durable_state()
	if durable.is_empty():
		return {}
	var snapshot: Dictionary = Dictionary(durable.get("snapshot", {})).duplicate(true)
	var items: Array = Array(snapshot.get("items", [])).duplicate(true)
	for index in range(items.size()):
		if not items[index] is Dictionary:
			continue
		var item: Dictionary = Dictionary(items[index]).duplicate(true)
		var item_id := String(item.get("item_id", ""))
		var location: Dictionary = Dictionary(item.get("location", {})).duplicate(true)
		if item_id == SHARED_BEACON_ID:
			location = {"kind": "CONTAINER", "container_id": SHARED_CRATE_ID}
		elif String(location.get("kind", "")) in ["INVENTORY", "CONTAINER"]:
			location.erase("slot_index")
		item["location"] = location
		items[index] = item
	snapshot["items"] = items

	var containers: Array = Array(snapshot.get("containers", [])).duplicate(true)
	for index in range(containers.size()):
		if not containers[index] is Dictionary:
			continue
		var container: Dictionary = Dictionary(containers[index]).duplicate(true)
		if String(container.get("container_id", "")) == SHARED_CRATE_ID:
			container["slots"] = [SHARED_BEACON_ID]
		containers[index] = container
	snapshot["containers"] = containers
	snapshot["checksum"] = ""
	snapshot = NetworkUtils.finalize_json_checksum(snapshot)
	if snapshot.is_empty():
		return {}
	durable["snapshot"] = snapshot
	durable["checksum"] = ""
	return NetworkUtils.finalize_json_checksum(durable)


func _item_record(snapshot: Dictionary, item_id: String) -> Dictionary:
	for item_value in snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value)
	return {}


func _item_location_kind(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_record(snapshot, item_id).get("location", {}).get("kind", ""))


func _item_container_id(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_record(snapshot, item_id).get("location", {}).get("container_id", ""))


func _item_slot_index(snapshot: Dictionary, item_id: String) -> int:
	return int(_item_record(snapshot, item_id).get("location", {}).get("slot_index", -1))


func _container_has_item(snapshot: Dictionary, container_id: String, item_id: String) -> bool:
	for container_value in snapshot.get("containers", []):
		if not container_value is Dictionary:
			continue
		var container: Dictionary = container_value
		if String(container.get("container_id", "")) == container_id:
			return item_id in Array(container.get("slots", []))
	return false


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
		return
	failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("V0-P2 Item Graph restore purity: %d assertions, 0 failures" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-P2 Item Graph restore purity: %d assertions, %d failures" % [assertions, failures.size()])
	quit(1)

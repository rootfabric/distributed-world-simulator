extends SceneTree

const OwnerService = preload(
	"res://scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd"
)
const PlayableStateCodec = preload(
	"res://scripts/runtime/listen_host/playable_state_codec.gd"
)
const PredictionJournal = preload(
	"res://scripts/network/prediction/predicted_item_interaction_journal.gd"
)

var assertions: int = 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_same_revision_pickup_and_drop_rollback()
	_test_owner_locomotion_keeps_item_drop_server_authoritative()
	_finish()


func _test_same_revision_pickup_and_drop_rollback() -> void:
	var service = _configured_owner_service()
	var transport := "transport-session/test/nx-c1/items"
	_assert(bool(service.join("b", transport, "operation/test/nx-c1/items/join").get("success", false)), "item fixture joins")
	var probe := service.handle_canonical_item_command(
		"b", transport, 1,
		"operation/test/nx-c1/items/probe",
		"inventory.permission_probe",
		{"target_player_id":"b"}
	)
	_assert(bool(probe.get("success", false)), "canonical item graph materializes player inventory")
	var canonical := service.create_canonical_item_graph_snapshot()
	var revision := int(canonical.get("revision", -1))
	_assert(revision >= 0, "canonical revision available")
	_assert(_location(canonical, "item/shared/ore/1") == "WORLD", "ore starts in canonical world")
	_assert(_location(canonical, "item/player/b/battery") == "INVENTORY", "battery starts in canonical inventory")

	var pickup_journal = PredictionJournal.new()
	_assert(bool(pickup_journal.setup("b", {"timeout_ms":8000, "max_pending":8}).get("success", false)), "pickup journal configures")
	_assert(bool(pickup_journal.adopt_authoritative(canonical, 1000).get("success", false)), "pickup journal adopts authority")
	var pickup := pickup_journal.begin_prediction(
		"item.pickup", {"item_id":"item/shared/ore/1"},
		"prediction/nx-c1/pickup", 1010
	)
	_assert(bool(pickup.get("success", false)), "optimistic pickup begins")
	_assert(_location(pickup_journal.get_authoritative_snapshot(), "item/shared/ore/1") == "WORLD", "pickup does not mutate authoritative snapshot")
	_assert(_location(pickup_journal.get_presentation_snapshot(), "item/shared/ore/1") == "INVENTORY", "pickup changes presentation only")
	var pickup_rollback := pickup_journal.resolve_prediction(
		"prediction/nx-c1/pickup",
		{"success":false, "error_code":"ITEM_ALREADY_CLAIMED"},
		canonical,
		1020
	)
	_assert(bool(pickup_rollback.get("success", false)), "rejected pickup resolves")
	var pickup_view := pickup_journal.get_presentation_snapshot()
	_assert(int(pickup_view.get("revision", -2)) == revision, "pickup rollback preserves same authority revision")
	_assert(_location(pickup_view, "item/shared/ore/1") == "WORLD", "pickup rollback restores canonical world placement")

	var drop_journal = PredictionJournal.new()
	_assert(bool(drop_journal.setup("b", {"timeout_ms":8000, "max_pending":8}).get("success", false)), "drop journal configures")
	_assert(bool(drop_journal.adopt_authoritative(canonical, 2000).get("success", false)), "drop journal adopts authority")
	var drop := drop_journal.begin_prediction(
		"item.drop",
		{"item_id":"item/player/b/battery", "quantity":1, "transform":{"basis":[1,0,0,0,1,0,0,0,1], "origin":[2,0,-1]}},
		"prediction/nx-c1/drop",
		2010
	)
	_assert(bool(drop.get("success", false)), "optimistic drop begins")
	_assert(_quantity(drop_journal.get_presentation_snapshot(), "item/player/b/battery") == 1, "partial drop decrements presentation source")
	_assert(_count_prefix(drop_journal.get_presentation_snapshot(), "item/predicted/") == 1, "optimistic drop creates presentation-only spawn")
	_assert(_quantity(drop_journal.get_authoritative_snapshot(), "item/player/b/battery") == 2, "drop leaves authority untouched")
	var drop_rollback := drop_journal.resolve_prediction(
		"prediction/nx-c1/drop",
		{"success":false, "error_code":"DROP_REJECTED"},
		canonical,
		2020
	)
	_assert(bool(drop_rollback.get("success", false)), "rejected drop resolves")
	var drop_view := drop_journal.get_presentation_snapshot()
	_assert(int(drop_view.get("revision", -2)) == revision, "drop rollback preserves same authority revision")
	_assert(_quantity(drop_view, "item/player/b/battery") == 2, "drop rollback restores authoritative quantity")
	_assert(_count_prefix(drop_view, "item/predicted/") == 0, "drop rollback removes predicted spawn")
	_assert(int(pickup_journal.get_report().get("rolled_back", 0)) == 1, "pickup rollback counted")
	_assert(int(drop_journal.get_report().get("rolled_back", 0)) == 1, "drop rollback counted")
	_assert(int(pickup_journal.get_report().get("same_revision_reprojections", 0)) >= 1, "same-revision pickup reprojection observable")
	_assert(int(drop_journal.get_report().get("same_revision_reprojections", 0)) >= 1, "same-revision drop reprojection observable")
	service.shutdown()


func _test_owner_locomotion_keeps_item_drop_server_authoritative() -> void:
	var service = _configured_owner_service()
	var transport := "transport-session/test/nx-c1/drop"
	_assert(bool(service.join("b", transport, "operation/test/nx-c1/drop/join").get("success", false)), "drop fixture joins")
	var player := service.get_player("b")
	var epoch := int(player.get("ownership_epoch", 0))
	var state := PlayableStateCodec.create_player_state(
		Vector3(2.1, 0.0, 0.0), Basis.IDENTITY, Vector3(3.0, 0.0, 0.0),
		Vector3(2.1, 0.9, 0.0), "flat_humanoid", "first_person", false, 1,
		"scenario/playground/local", "main", "playground", "scenario-playground", 0.1
	)
	var state_result := service.submit_player_state(
		"b", transport, epoch, 1, state, 1.0 / 30.0,
		"operation/test/nx-c1/drop/state"
	)
	_assert(bool(state_result.get("success", false)), "owner locomotion accepted before item action")
	_assert(absf(float(service.get_player("b").get("orientation_yaw", 99.0))) < 0.000001, "identity owner basis remains yaw zero")

	var drop := service.handle_canonical_item_command(
		"b", transport, epoch,
		"operation/test/nx-c1/drop/battery",
		"item.drop",
		{"item_id":"item/player/b/battery", "quantity":1}
	)
	_assert(bool(drop.get("success", false)), "server accepts B-owned battery drop")
	var snapshot := service.create_canonical_item_graph_snapshot()
	_assert(_location(snapshot, "item/player/b/battery") == "WORLD", "server canonical graph moves dropped battery to world")
	_assert(not _inventory_contains(snapshot, "b", "item/player/b/battery"), "server canonical inventory removes dropped battery")
	var origin := _item_transform_origin(snapshot, "item/player/b/battery")
	_assert(origin.distance_to(Vector3(2.1, 0.35, -1.35)) < 0.05, "drop transform derives from validated owner pose")
	service.shutdown()


func _configured_owner_service():
	var service = OwnerService.new()
	var setup := service.setup(
		"authority/test/nx-c1/items", 1, 0,
		{"profile":"MULTIPLAYER_CORE", "topology_adapter":"TEST", "region_id":"region/test/nx-c1/items", "playable_sandbox":true, "fixed_tick_authority":true}
	)
	_assert(bool(setup.get("success", false)), "owner item service configures")
	return service


func _item_row(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value)
	return {}


func _location(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_row(snapshot, item_id).get("location", {}).get("kind", ""))


func _quantity(snapshot: Dictionary, item_id: String) -> int:
	return int(_item_row(snapshot, item_id).get("quantity", 0))


func _count_prefix(snapshot: Dictionary, prefix: String) -> int:
	var count := 0
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")).begins_with(prefix):
			count += 1
	return count


func _inventory_contains(snapshot: Dictionary, player_id: String, item_id: String) -> bool:
	var inventories := Dictionary(snapshot.get("inventories", {}))
	var inventory := Dictionary(inventories.get(player_id, {}))
	return item_id in Array(inventory.get("inventory", []))


func _item_transform_origin(snapshot: Dictionary, item_id: String) -> Vector3:
	var transform := Dictionary(_item_row(snapshot, item_id).get("transform", {}))
	return PlayableStateCodec.transform_from_dto(transform).origin


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("NX.C1 item rollback: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("NX.C1 owner item projection rollback: PASS (%d assertions)" % assertions)
		quit(0)
		return
	print("NX.C1 owner item projection rollback: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(1)

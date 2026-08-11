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
const PlaygroundRuntime = preload(
	"res://scripts/world/testing/playground_view_relative_runtime_fix10_item_projection.gd"
)

var assertions: int = 0
var failures: Array[String] = []


class FakeAdapter:
	extends RefCounted
	var conversions: int = 0

	func convert(snapshot: Dictionary) -> Dictionary:
		conversions += 1
		return {
			"success": true,
			"error_code": "",
			"details": {
				"graph_snapshot": {
					"marker": String(snapshot.get("marker", "")),
				},
			},
		}


class FakeItemGameplay:
	extends RefCounted
	var applied: Array[Dictionary] = []

	func apply_network_graph_snapshot(
		graph_snapshot: Dictionary,
		replica_revision: int = -1,
		replica_checksum: String = ""
	) -> Dictionary:
		applied.append({
			"graph": graph_snapshot.duplicate(true),
			"revision": replica_revision,
			"checksum": replica_checksum,
		})
		return {"success": true, "error_code": ""}


func _init() -> void:
	_test_same_revision_projection_callback_is_not_suppressed()
	_test_prediction_rejection_rebuilds_same_revision_authority()
	_test_owner_authority_keeps_item_drop_server_authoritative()
	_finish()


func _test_same_revision_projection_callback_is_not_suppressed() -> void:
	var runtime = PlaygroundRuntime.new()
	var adapter = FakeAdapter.new()
	var gameplay = FakeItemGameplay.new()
	runtime._network_playground_enabled = true
	runtime._m7_item_adapter = adapter
	runtime.item_gameplay = gameplay
	runtime._m7_last_item_revision = 2

	runtime._on_m4_item_graph_updated({
		"revision": 2,
		"checksum": "same-authority-checksum",
		"marker": "PREDICTED",
	})
	runtime._on_m4_item_graph_updated({
		"revision": 2,
		"checksum": "same-authority-checksum",
		"marker": "ROLLED_BACK",
	})

	_assert(adapter.conversions == 2, "same revision projected events are both converted")
	_assert(gameplay.applied.size() == 2, "same revision projected events are both applied")
	_assert(
		String(gameplay.applied[0].get("graph", {}).get("marker", "")) == "PREDICTED",
		"first same-revision projection reaches item controller"
	)
	_assert(
		String(gameplay.applied[1].get("graph", {}).get("marker", "")) == "ROLLED_BACK",
		"same-revision rollback reaches item controller"
	)
	_assert(runtime._fix10_item_same_revision_reapplies == 2, "same revision reapplies are observable")
	_assert(runtime._fix10_item_projection_failures == 0, "same revision projection has no apply failures")
	runtime.free()


func _test_prediction_rejection_rebuilds_same_revision_authority() -> void:
	var service = _configured_owner_service()
	var transport := "transport-session/test/b"
	var join_result: Dictionary = service.join("b", transport, "operation/test/join/b/journal")
	_assert(bool(join_result.get("success", false)), "journal fixture player joins")

	# Materialize B's sandbox inventory without changing the shared ore.
	var probe: Dictionary = service.handle_canonical_item_command(
		"b", transport, 1,
		"operation/test/item/probe/b",
		"inventory.permission_probe",
		{"target_player_id": "b"}
	)
	_assert(bool(probe.get("success", false)), "journal fixture item graph materializes B")
	var canonical: Dictionary = service.create_canonical_item_graph_snapshot()
	var canonical_revision := int(canonical.get("revision", -1))
	_assert(_item_location_kind(canonical, "item/shared/ore/1") == "WORLD", "authority starts with ore in world")

	var journal = PredictionJournal.new()
	var setup: Dictionary = journal.setup("b", {"timeout_ms": 8000, "max_pending": 8})
	_assert(bool(setup.get("success", false)), "prediction journal configures")
	var adopt: Dictionary = journal.adopt_authoritative(canonical, 1000)
	_assert(bool(adopt.get("success", false)), "prediction journal adopts canonical graph")
	var prediction: Dictionary = journal.begin_prediction(
		"item.pickup",
		{"item_id": "item/shared/ore/1"},
		"prediction/test/ore-pickup",
		1010
	)
	_assert(bool(prediction.get("success", false)), "optimistic ore pickup begins")
	var predicted_snapshot: Dictionary = journal.get_presentation_snapshot()
	_assert(int(predicted_snapshot.get("revision", -1)) == canonical_revision, "prediction preserves authority revision")
	_assert(_item_location_player(predicted_snapshot, "item/shared/ore/1") == "b", "optimistic pickup presents ore in B inventory")

	var rollback: Dictionary = journal.resolve_prediction(
		"prediction/test/ore-pickup",
		{"success": false, "error_code": "PLAYER_PERMISSION_DENIED"},
		canonical,
		1020
	)
	_assert(bool(rollback.get("success", false)), "rejected prediction resolves")
	var rolled_back_snapshot: Dictionary = journal.get_presentation_snapshot()
	_assert(int(rolled_back_snapshot.get("revision", -1)) == canonical_revision, "rollback keeps same authority revision")
	_assert(_item_location_kind(rolled_back_snapshot, "item/shared/ore/1") == "WORLD", "same-revision rollback restores ore to world")
	_assert(int(journal.get_report().get("rolled_back", 0)) == 1, "rollback is counted")
	_assert(int(journal.get_report().get("same_revision_reprojections", 0)) >= 1, "same-revision reprojection is counted")
	service.shutdown()


func _test_owner_authority_keeps_item_drop_server_authoritative() -> void:
	var service = _configured_owner_service()
	var transport := "transport-session/test/b/drop"
	var join_result: Dictionary = service.join("b", transport, "operation/test/join/b/drop")
	_assert(bool(join_result.get("success", false)), "owner drop fixture player joins")

	var state := PlayableStateCodec.create_player_state(
		Vector3(2.1, 0.0, 0.0),
		Basis.IDENTITY,
		Vector3(3.0, 0.0, 0.0),
		Vector3(2.1, 0.9, 0.0),
		"flat_humanoid",
		"first_person",
		false,
		1,
		"scenario/playground/local",
		"main",
		"playground",
		"scenario-playground",
		0.1
	)
	var state_result: Dictionary = service.submit_player_state(
		"b", transport, 1, 1, state, 1.0 / 30.0,
		"operation/test/owner-state/b/1"
	)
	_assert(bool(state_result.get("success", false)), "owner-authored locomotion state is accepted before item action")
	var accepted_player: Dictionary = Dictionary(state_result.get("details", {}).get("player", {}))
	_assert(absf(float(accepted_player.get("orientation_yaw", 99.0))) < 0.000001, "identity owner basis round-trips to yaw zero")
	_assert(
		String(service.get_report().get("owner_basis_yaw_roundtrip_policy", "")) == "GODOT_FORWARD_MINUS_Z_BASIS_TO_YAW_V1",
		"owner service reports Godot -Z basis/yaw roundtrip policy"
	)

	var drop: Dictionary = service.handle_canonical_item_command(
		"b", transport, 1,
		"operation/test/item/drop/battery",
		"item.drop",
		{"item_id": "item/player/b/battery", "quantity": 1}
	)
	_assert(bool(drop.get("success", false)), "B can drop B-owned battery under owner locomotion authority")
	_assert(String(drop.get("error_code", "")) != "PLAYER_PERMISSION_DENIED", "owner movement does not break item ownership")
	var snapshot: Dictionary = service.create_canonical_item_graph_snapshot()
	_assert(_item_location_kind(snapshot, "item/player/b/battery") == "WORLD", "server-authoritative drop moves B battery to world")
	_assert(not _inventory_contains(snapshot, "b", "item/player/b/battery"), "server removes dropped battery from B inventory")
	var dropped_transform := _item_transform_origin(snapshot, "item/player/b/battery")
	_assert(dropped_transform.distance_to(Vector3(2.1, 0.35, -1.35)) < 0.05, "drop transform is derived from validated owner position/yaw")
	service.shutdown()


func _configured_owner_service():
	var service = OwnerService.new()
	var setup: Dictionary = service.setup(
		"test-authority",
		1,
		0,
		{
			"profile": "MULTIPLAYER_CORE",
			"topology_adapter": "TEST",
			"region_id": "region/test/owner-items",
			"playable_sandbox": true,
			"fixed_tick_authority": true,
		}
	)
	_assert(bool(setup.get("success", false)), "owner item service configures")
	return service


func _item_row(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(Dictionary(value).get("item_id", "")) == item_id:
			return Dictionary(value)
	return {}


func _item_location_kind(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_row(snapshot, item_id).get("location", {}).get("kind", ""))


func _item_location_player(snapshot: Dictionary, item_id: String) -> String:
	return String(_item_row(snapshot, item_id).get("location", {}).get("player_id", ""))


func _inventory_contains(snapshot: Dictionary, player_id: String, item_id: String) -> bool:
	var inventories: Dictionary = Dictionary(snapshot.get("inventories", {}))
	var inventory: Dictionary = Dictionary(inventories.get(player_id, {}))
	return item_id in Array(inventory.get("inventory", []))


func _item_transform_origin(snapshot: Dictionary, item_id: String) -> Vector3:
	var transform: Dictionary = Dictionary(_item_row(snapshot, item_id).get("transform", {}))
	return PlayableStateCodec.transform_from_dto(transform).origin


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	print("M7 owner-authority item drop/projection: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)

extends SceneTree

const Journal = preload("res://scripts/network/prediction/predicted_item_interaction_journal.gd")
const PlaygroundRuntime = preload("res://scripts/world/testing/playground_runtime.gd")
const Adapter = preload("res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter.gd")
const Factory = preload("res://scripts/items/services/item_domain_factory.gd")
const GraphPersistence = preload("res://scripts/items/persistence/item_graph_persistence.gd")
const Presenter = preload("res://scripts/items/presentation/item_representation_system.gd")
const PlayableStateCodec = preload("res://scripts/runtime/listen_host/playable_state_codec.gd")

const WORLD_ITEM_ID := "item/shared/beacon/fix5"

class FakeReplicaController:
	extends RefCounted
	var runtime_mode: String = "replica"


class FakeProjectionAdapter:
	extends RefCounted
	var conversions: int = 0

	func convert(snapshot: Dictionary) -> Dictionary:
		conversions += 1
		return {
			"success": true,
			"error_code": "",
			"details": {
				"graph_snapshot": {
					"probe_revision": int(snapshot.get("revision", -1)),
					"probe_marker": String(snapshot.get("marker", "")),
				},
			},
		}


class FakeItemGameplay:
	extends RefCounted
	var applies: Array[Dictionary] = []

	func apply_network_graph_snapshot(
		graph_snapshot: Dictionary,
		replica_revision: int = -1,
		replica_checksum: String = ""
	) -> Dictionary:
		applies.append({
			"graph_snapshot": graph_snapshot.duplicate(true),
			"revision": replica_revision,
			"checksum": replica_checksum,
		})
		return {"success": true}


var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_same_revision_rejection_reprojects_world_item()
	_test_same_revision_presentation_is_not_filtered()
	_test_two_replica_presenters_share_authoritative_transform()
	_finish()


func _test_same_revision_rejection_reprojects_world_item() -> void:
	var journal = Journal.new()
	_assert(bool(journal.setup("a").get("success", false)), "journal setup failed")
	var authority := _canonical_snapshot(17)
	_assert(bool(journal.adopt_authoritative(authority, 100).get("success", false)), "base authority adopt failed")
	var predicted: Dictionary = journal.begin_prediction(
		"item.pickup",
		{"item_id": WORLD_ITEM_ID},
		"prediction/fix5/rejected-pickup",
		110
	)
	_assert(bool(predicted.get("success", false)), "pickup prediction was not accepted")
	_assert(_location(journal.get_presentation_snapshot(), WORLD_ITEM_ID) == "INVENTORY", "predicted pickup did not remove WORLD presentation")
	_assert(_location(journal.get_authoritative_snapshot(), WORLD_ITEM_ID) == "WORLD", "prediction mutated authority")

	# This is the production failure shape: server rejects the pickup and returns
	# the exact pre-prediction Item Graph revision/checksum because authority did
	# not mutate. FIX5 must rebuild presentation even though authority is a
	# duplicate.
	var rejected: Dictionary = journal.resolve_prediction(
		"prediction/fix5/rejected-pickup",
		{"success": false, "error_code": "ITEM_NOT_VISIBLE_TO_PLAYER"},
		authority,
		120
	)
	_assert(bool(rejected.get("success", false)), "same-revision rejection failed to resolve")
	var rollback := journal.get_presentation_snapshot()
	_assert(_location(rollback, WORLD_ITEM_ID) == "WORLD", "rejected pickup did not restore WORLD item")
	_assert(not rollback.has("prediction_overlay"), "rejected pickup left stale prediction overlay")
	_assert(_transform_dto(rollback, WORLD_ITEM_ID) == _transform_dto(authority, WORLD_ITEM_ID), "rollback did not restore authoritative transform")
	_assert(journal.get_pending_predictions().is_empty(), "rejected pickup remained pending")
	var report: Dictionary = journal.get_report()
	_assert(String(report.get("duplicate_authority_policy", "")) == "REPROJECT_SAME_REVISION_AFTER_PENDING_CHANGE_V1", "FIX5 duplicate authority policy missing")
	_assert(int(report.get("same_revision_reprojections", 0)) >= 1, "same-revision reproject was not counted")


func _test_same_revision_presentation_is_not_filtered() -> void:
	var runtime = PlaygroundRuntime.new()
	var adapter = FakeProjectionAdapter.new()
	var gameplay = FakeItemGameplay.new()
	runtime._network_playground_enabled = true
	runtime._m7_item_adapter = adapter
	runtime.item_gameplay = gameplay
	runtime._m7_last_item_revision = 9

	runtime._on_m4_item_graph_updated({
		"revision": 9,
		"checksum": "1".repeat(64),
		"marker": "predicted",
	})
	runtime._on_m4_item_graph_updated({
		"revision": 9,
		"checksum": "1".repeat(64),
		"marker": "rollback",
	})
	_assert(gameplay.applies.size() == 2, "same-revision prediction/rollback projection was filtered")
	_assert(String(gameplay.applies[0].get("graph_snapshot", {}).get("probe_marker", "")) == "predicted", "first same-revision projection missing")
	_assert(String(gameplay.applies[1].get("graph_snapshot", {}).get("probe_marker", "")) == "rollback", "rollback same-revision projection missing")
	var report: Dictionary = runtime.get_fix5_item_consistency_report()
	_assert(String(report.get("projection_policy", "")) == "APPLY_ALL_NONSTALE_SAME_REVISION_PROJECTIONS_V1", "FIX5 projection policy missing")
	_assert(int(report.get("same_revision_projection_applies", 0)) == 2, "same-revision projection applies not counted")

	runtime._on_m4_item_graph_updated({
		"revision": 8,
		"checksum": "2".repeat(64),
		"marker": "stale",
	})
	_assert(gameplay.applies.size() == 2, "strictly stale Item Graph projection was applied")
	_assert(int(runtime.get_fix5_item_consistency_report().get("stale_projection_suppressions", 0)) == 1, "stale suppression not counted")
	runtime.free()


func _test_two_replica_presenters_share_authoritative_transform() -> void:
	var expected := Transform3D(
		Basis(Vector3(0.2, 1.0, -0.15).normalized(), 0.73),
		Vector3(2.75, 0.63, -4.125)
	)
	var authority := _canonical_snapshot(23, expected)
	var replica_a := _build_replica_presenter("a", authority, "a")
	var replica_b := _build_replica_presenter("b", authority, "b")
	if replica_a.is_empty() or replica_b.is_empty():
		return
	var body_a: RigidBody3D = replica_a.get("body")
	var body_b: RigidBody3D = replica_b.get("body")
	var presenter_a = replica_a.get("presenter")
	var presenter_b = replica_b.get("presenter")
	_assert(body_a != null and body_b != null, "replica world bodies were not materialized")
	if body_a == null or body_b == null:
		_cleanup_replica(replica_a)
		_cleanup_replica(replica_b)
		return
	_assert(body_a.freeze and body_b.freeze, "replica WORLD bodies are still local physics authorities")
	_assert_transform_close(body_a.transform, expected, "client A did not receive authoritative transform")
	_assert_transform_close(body_b.transform, expected, "client B did not receive authoritative transform")
	_assert_transform_close(body_a.transform, body_b.transform, "clients disagree on initial WORLD transform")

	# Simulate the old failure mode: each client locally diverges to a different
	# position/rotation. A synchronization pass must snap both frozen replicas
	# back to the same projected server transform, even without changing item
	# revision.
	body_a.freeze = false
	body_b.freeze = false
	body_a.transform = Transform3D(Basis(Vector3.UP, 1.2), Vector3(40.0, 3.0, -8.0))
	body_b.transform = Transform3D(Basis(Vector3.RIGHT, -0.8), Vector3(-31.0, 9.0, 12.0))
	presenter_a.synchronize_all()
	presenter_b.synchronize_all()
	_assert(body_a.freeze and body_b.freeze, "authoritative sync did not re-freeze replica bodies")
	_assert_transform_close(body_a.transform, expected, "client A local physics divergence survived authoritative sync")
	_assert_transform_close(body_b.transform, expected, "client B local physics divergence survived authoritative sync")
	_assert_transform_close(body_a.transform, body_b.transform, "clients still disagree after authoritative reapply")
	_assert(not bool(presenter_a.capture_world_state(String(replica_a.get("item_id", "")))), "replica A was allowed to capture local world state")
	_assert(not bool(presenter_b.capture_world_state(String(replica_b.get("item_id", "")))), "replica B was allowed to capture local world state")
	var report_a: Dictionary = presenter_a.get_fix5_world_authority_report()
	var report_b: Dictionary = presenter_b.get_fix5_world_authority_report()
	_assert(bool(report_a.get("authoritative_replica_mode", false)), "client A FIX5 replica authority mode disabled")
	_assert(bool(report_b.get("authoritative_replica_mode", false)), "client B FIX5 replica authority mode disabled")
	_assert(String(report_a.get("policy", "")) == "SERVER_ITEM_GRAPH_TRANSFORM_FROZEN_REPLICA_V1", "client A world authority policy missing")
	_assert(int(report_a.get("authoritative_state_reapplies", 0)) >= 2, "client A did not reapply authoritative state")
	_assert(int(report_b.get("authoritative_state_reapplies", 0)) >= 2, "client B did not reapply authoritative state")
	_cleanup_replica(replica_a)
	_cleanup_replica(replica_b)


func _build_replica_presenter(player_id: String, canonical: Dictionary, suffix: String) -> Dictionary:
	var adapter = Adapter.new()
	var setup: Dictionary = adapter.setup(player_id)
	_assert(bool(setup.get("success", false)), "adapter setup failed for %s" % player_id)
	if not bool(setup.get("success", false)):
		return {}
	var converted: Dictionary = adapter.convert(canonical)
	_assert(bool(converted.get("success", false)), "canonical conversion failed for %s: %s" % [player_id, converted])
	if not bool(converted.get("success", false)):
		return {}
	var graph: Dictionary = Dictionary(converted.get("details", {}).get("graph_snapshot", {}))
	var domain: Dictionary = Factory.create()
	domain.world_entities.setup({"authority_owner_id": "authority/fix5", "authority_epoch": 1})
	var persistence = GraphPersistence.new()
	persistence.setup(domain, null, "fix5-%s" % suffix)
	var loaded: Dictionary = persistence.load_snapshot(graph)
	_assert(bool(loaded.get("success", false)), "replica graph load failed for %s: %s" % [player_id, loaded])
	if not bool(loaded.get("success", false)):
		return {}

	var host := Node3D.new()
	host.name = "Fix5ReplicaHost_%s" % suffix
	get_root().add_child(host)
	var world_root := Node3D.new()
	world_root.name = "World"
	host.add_child(world_root)
	var attachment_root := Node3D.new()
	attachment_root.name = "Attachments"
	host.add_child(attachment_root)
	var presenter = Presenter.new()
	presenter.name = "Presenter"
	host.add_child(presenter)
	presenter.setup(
		domain.items,
		world_root,
		attachment_root,
		false,
		domain.mass,
		null,
		"scenario/playground/local",
		"",
		domain.world_entities
	)
	presenter.set_interaction_controller(FakeReplicaController.new())
	presenter.synchronize_all()
	var replica_item_id := adapter.to_replica_item_id(WORLD_ITEM_ID)
	var body = presenter.get_world_node(replica_item_id)
	_assert(body != null, "WORLD body missing for %s" % player_id)
	return {
		"host": host,
		"presenter": presenter,
		"body": body,
		"item_id": replica_item_id,
		"domain": domain,
	}


func _cleanup_replica(replica: Dictionary) -> void:
	var host = replica.get("host")
	if host != null and is_instance_valid(host):
		host.free()


func _canonical_snapshot(revision: int, world_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var transform := world_transform
	if transform == Transform3D.IDENTITY:
		transform = Transform3D(Basis(Vector3.UP, 0.35), Vector3(1.25, 0.55, -2.75))
	return {
		"schema": "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1",
		"authority_owner_id": "authority/fix5",
		"authority_epoch": 1,
		"revision": revision,
		"tick": revision,
		"items": [
			{
				"item_id": WORLD_ITEM_ID,
				"definition_id": "item/beacon",
				"quantity": 1,
				"location": {"kind": "WORLD"},
				"mounted": false,
				"transform": PlayableStateCodec.create_transform_dto(transform),
			},
		],
		"inventories": {
			"a": {"inventory": [], "hotbar": ["", "", "", "", "", "", "", "", "", ""], "selected_hotbar_index": 0},
			"b": {"inventory": [], "hotbar": ["", "", "", "", "", "", "", "", "", ""], "selected_hotbar_index": 0},
		},
		"containers": [],
		"mounts": [],
		"open_containers": {},
		"checksum": ("%064d" % revision),
	}


func _location(snapshot: Dictionary, item_id: String) -> String:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return String(value.get("location", {}).get("kind", ""))
	return ""


func _transform_dto(snapshot: Dictionary, item_id: String) -> Dictionary:
	for value in snapshot.get("items", []):
		if value is Dictionary and String(value.get("item_id", "")) == item_id:
			return Dictionary(value.get("transform", {})).duplicate(true)
	return {}


func _assert_transform_close(actual: Transform3D, expected: Transform3D, message: String) -> void:
	_assert(actual.origin.distance_to(expected.origin) <= 0.0000001, "%s position actual=%s expected=%s" % [message, actual.origin, expected.origin])
	var actual_q := actual.basis.get_rotation_quaternion().normalized()
	var expected_q := expected.basis.get_rotation_quaternion().normalized()
	_assert(absf(actual_q.dot(expected_q)) >= 0.9999999, "%s rotation actual=%s expected=%s" % [message, actual_q, expected_q])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error("FIX5 ASSERT: %s" % message)


func _finish() -> void:
	print("M7 world item consistency FIX5: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures:
		print(" - %s" % failure)
	quit(0 if failures.is_empty() else 1)

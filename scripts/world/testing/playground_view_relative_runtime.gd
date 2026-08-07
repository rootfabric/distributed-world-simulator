extends "res://scripts/world/testing/playground_runtime.gd"

const ProjectionHashUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SlotAwareM7ItemGraphReplicaAdapterScript = preload(
	"res://scripts/runtime/networked_gameplay/m7/m7_item_graph_replica_adapter_slot_aware.gd"
)
const SlotAwarePredictionJournalScript = preload(
	"res://scripts/network/prediction/predicted_item_interaction_journal_slot_aware.gd"
)
const InventoryRev6EnhancerScript = preload(
	"res://scripts/ui/inventory/inventory_network_rev6_enhancer.gd"
)

const SLOT_AWARE_PREDICTION_TIMEOUT_MS := 8000
const SLOT_AWARE_PREDICTION_MAX_PENDING := 32

# Network-playground specialization that keeps local camera input independent
# from the authoritative avatar-facing yaw and keeps client prediction on the
# physics clock. The shared movement kernel consumes an absolute world-space
# yaw, so derive it from the active camera's real view basis instead of reusing
# an accumulated local camera_yaw value.

var _pending_prediction_presentation: Dictionary = {}
var _pending_prediction_presentation_dirty: bool = false
var _physics_prediction_steps: int = 0
var _render_prediction_steps_suppressed: int = 0
var _m7_last_item_projection_hash: String = ""
var _m7_same_revision_projection_updates: int = 0
var _inventory_rev6_enhancer


func _process(delta: float) -> void:
	if runtime_role != "game-client":
		return
	if _m3_attached:
		if _network_playground_enabled:
			# Prediction owns a 60 Hz fixed physics clock. Advancing it from render
			# frames makes the CharacterBody and interpolated Camera3D fight the
			# physics interpolation path and produces visible micro-stutter.
			_render_prediction_steps_suppressed += 1
			return
		_apply_m3_network_input(delta)
	elif _m2_attached:
		_apply_m2_flat_input(delta)
		_sync_m2_player_state(delta)


func _physics_process(delta: float) -> void:
	if (
		runtime_role != "game-client"
		or not _m3_attached
		or not _network_playground_enabled
	):
		_flush_pending_prediction_presentation()
		return
	_sync_m7_predicted_player_state(delta)
	_flush_pending_prediction_presentation()
	_physics_prediction_steps += 1


func _setup_m7_networked_item_gameplay(runtime) -> Dictionary:
	var setup_result: Dictionary = super._setup_m7_networked_item_gameplay(runtime)
	if not bool(setup_result.get("success", false)):
		return setup_result
	if _m7_item_bridge == null:
		return {"success": false, "error_code": "M7_ITEM_BRIDGE_NOT_CONFIGURED", "details": {}}

	var adapter = SlotAwareM7ItemGraphReplicaAdapterScript.new()
	var adapter_setup: Dictionary = adapter.setup(runtime.get_local_player_id())
	if not bool(adapter_setup.get("success", false)):
		return adapter_setup

	var journal = SlotAwarePredictionJournalScript.new()
	var journal_setup: Dictionary = journal.setup(runtime.get_local_player_id(), {
		"timeout_ms": SLOT_AWARE_PREDICTION_TIMEOUT_MS,
		"max_pending": SLOT_AWARE_PREDICTION_MAX_PENDING,
	})
	if not bool(journal_setup.get("success", false)):
		return journal_setup
	var canonical: Dictionary = runtime.get_item_graph_snapshot()
	if not canonical.is_empty():
		var adopted: Dictionary = journal.adopt_authoritative(canonical)
		if not bool(adopted.get("success", false)):
			return adopted

	# Keep the already-configured bridge/pump/signals, but replace the two
	# projection components before attach_m3_multiplayer_client performs its
	# first authoritative item_graph_updated application.
	_m7_item_adapter = adapter
	_m7_item_bridge._adapter = adapter
	_m7_item_bridge._prediction_journal = journal

	# Rev6 UI hardening remains a presentation/composition layer. All actual
	# item mutations still travel through the existing M7 bridge and rev5
	# slot-aware authority, including automatic pickup stacking and sorting.
	if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer):
		_inventory_rev6_enhancer.queue_free()
	_inventory_rev6_enhancer = InventoryRev6EnhancerScript.new()
	_inventory_rev6_enhancer.name = "InventoryNetworkRev6Enhancer"
	add_child(_inventory_rev6_enhancer)
	var enhancer_setup: Dictionary = _inventory_rev6_enhancer.setup(
		item_gameplay,
		_m7_item_bridge
	)
	if not bool(enhancer_setup.get("success", false)):
		return enhancer_setup
	return setup_result


func _create_m7_movement_intent(
	delta_seconds: float,
	input_override: Vector2 = Vector2(INF, INF),
	jump_override: int = -1,
	sprint_override: int = -1
) -> Dictionary:
	var input_vector := input_override
	if is_inf(input_vector.x) or is_inf(input_vector.y):
		input_vector = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()
	return {
		"move_x": input_vector.x,
		"move_z": -input_vector.y,
		"look_yaw": _network_view_yaw(),
		"look_pitch": clampf(player.camera_pitch, -1.45, 1.45),
		"jump_pressed": (
			Input.is_action_pressed("jump") if jump_override < 0 else jump_override > 0
		),
		"sprint": (
			Input.is_action_pressed("boost") if sprint_override < 0 else sprint_override > 0
		),
		"delta_seconds": clampf(delta_seconds, 0.000001, 0.25),
	}


func _network_view_yaw() -> float:
	if player == null:
		return 0.0
	var view_basis: Basis = player.get_view_basis()
	var camera_forward: Vector3 = (-view_basis.z).slide(Vector3.UP)
	if camera_forward.length_squared() < 0.000001:
		return wrapf(float(player.camera_yaw), -PI, PI)
	camera_forward = camera_forward.normalized()
	return atan2(-camera_forward.x, -camera_forward.z)


func _apply_m7_prediction_presentation(state: Dictionary) -> void:
	if state.is_empty() or player == null:
		return
	# Reconciliation arrives from the transport/render process, while local
	# prediction is advanced from the physics process. Never mutate the
	# CharacterBody transform directly from the transport callback: queue the
	# newest presentation and apply it once on the next physics tick.
	_pending_prediction_presentation = state.duplicate(true)
	_pending_prediction_presentation_dirty = true


func _flush_pending_prediction_presentation() -> void:
	if not _pending_prediction_presentation_dirty or player == null:
		return
	var state: Dictionary = _pending_prediction_presentation
	_pending_prediction_presentation = {}
	_pending_prediction_presentation_dirty = false
	var position: Dictionary = Dictionary(state.get("position", {}))
	var velocity: Dictionary = Dictionary(state.get("velocity", {}))
	player.set_world_position(Vector3(
		float(position.get("x", 0.0)),
		float(position.get("y", 0.0)),
		float(position.get("z", 0.0))
	))
	player.velocity = Vector3(
		float(velocity.get("x", 0.0)),
		float(velocity.get("y", 0.0)),
		float(velocity.get("z", 0.0))
	)
	var yaw: float = float(state.get("orientation_yaw", 0.0))
	# Rotate only the visible astronaut. Rotating the CharacterBody root would
	# rotate CameraAnchor as well and apply yaw twice for the local player.
	if player.visual_root != null:
		player.visual_root.rotation.y = yaw


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_m4_item_graph_snapshot = snapshot.duplicate(true)
	_m4_item_snapshot_updates += 1
	if not _network_playground_enabled or item_gameplay == null or _m7_item_adapter == null:
		return
	# NX6 prediction can produce two different presentation snapshots at the
	# same canonical revision: optimistic state and rollback/rebase. Revision-
	# only dedupe loses the rollback and leaves the UI ahead of authority.
	var projection_hash := ProjectionHashUtils.payload_hash(snapshot)
	if not projection_hash.is_empty() and projection_hash == _m7_last_item_projection_hash:
		return
	var revision := int(snapshot.get("revision", -1))
	var previous_revision := _m7_last_item_revision
	var converted: Dictionary = _m7_item_adapter.convert(snapshot)
	if not bool(converted.get("success", false)):
		_m7_last_sync_error = String(converted.get("error_code", "M7_ITEM_REPLICA_CONVERSION_FAILED"))
		return
	var details: Dictionary = Dictionary(converted.get("details", {}))
	var apply_result: Dictionary = item_gameplay.apply_network_graph_snapshot(
		Dictionary(details.get("graph_snapshot", {})),
		revision,
		String(snapshot.get("checksum", ""))
	)
	if bool(apply_result.get("success", false)):
		if revision == previous_revision and not _m7_last_item_projection_hash.is_empty():
			_m7_same_revision_projection_updates += 1
		_m7_last_item_revision = revision
		_m7_last_item_projection_hash = projection_hash
		_m7_last_sync_error = ""
	else:
		_m7_last_sync_error = String(apply_result.get("error_code", "M7_ITEM_REPLICA_APPLY_FAILED"))


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["view_relative_prediction"] = {
		"clock": "PHYSICS_60HZ",
		"physics_prediction_steps": _physics_prediction_steps,
		"render_prediction_steps_suppressed": _render_prediction_steps_suppressed,
		"presentation_pending": _pending_prediction_presentation_dirty,
	}
	report["item_projection"] = {
		"last_projection_hash": _m7_last_item_projection_hash,
		"same_revision_projection_updates": _m7_same_revision_projection_updates,
	}
	report["inventory_rev6"] = (
		_inventory_rev6_enhancer.get_report()
		if _inventory_rev6_enhancer != null and is_instance_valid(_inventory_rev6_enhancer)
		else {}
	)
	return report

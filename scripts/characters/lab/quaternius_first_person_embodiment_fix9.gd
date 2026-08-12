class_name QuaterniusFirstPersonEmbodimentFix9
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix8.gd"

const HeldStateType = preload("res://scripts/characters/presentation/held_item_presentation_state.gd")
const ThirdPersonPresenterType = preload("res://scripts/characters/presentation/third_person_held_item_presenter.gd")
const HELD_SOURCE_HOTBAR := "HOTBAR_LOCAL_SELECTION"

var held_item_presentation_state
var third_person_held_item_presenter
var _held_item_setup_result: Dictionary = {}
var _last_held_apply_result: Dictionary = {}
var _held_state_changes: int = 0
var _third_person_updates: int = 0
var _third_person_clears: int = 0


func _ready() -> void:
	super._ready()
	_setup_shared_held_item_presentation()


func _setup_shared_held_item_presentation() -> void:
	if base_lab == null or base_lab.player == null or base_lab.avatar == null:
		_held_item_setup_result = _failure("FPE_R2_BASE_PRESENTATION_NOT_READY")
		return

	held_item_presentation_state = HeldStateType.new()
	held_item_presentation_state.changed.connect(_on_held_item_presentation_changed)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	third_person_held_item_presenter = ThirdPersonPresenterType.new()
	third_person_held_item_presenter.name = "FpeR2ThirdPersonHeldItemPresenter"
	base_lab.player.add_child(third_person_held_item_presenter)
	var world_layer_index := 20
	if base_lab.presentation_profile != null:
		world_layer_index = int(base_lab.presentation_profile.world_render_layer_index)
	_held_item_setup_result = third_person_held_item_presenter.setup(
		base_lab.avatar,
		source_skeleton,
		world_layer_index
	)
	if not bool(_held_item_setup_result.get("success", false)):
		_last_fpe_status_code = String(_held_item_setup_result.get("error_code", "FPE_R2_THIRD_PERSON_SETUP_FAILED"))
		return

	# Seed both first- and third-person presentation from the already installed
	# canonical hotbar contents plus the local transient selected-slot state.
	if base_lab.character_gameplay_controller != null:
		_apply_hotbar_presentation_for_index(int(base_lab.character_gameplay_controller.selected_hotbar_index))


func _apply_hotbar_presentation_for_index(index: int) -> Dictionary:
	var started_us := Time.get_ticks_usec()
	if base_lab == null or base_lab.character_gameplay_controller == null:
		return _failure("FPE_HOTBAR_CONTROLLER_NOT_READY")
	if first_person_embodiment == null:
		return _failure("FPE_EMBODIMENT_NOT_READY")
	if held_item_presentation_state == null:
		# During the base _ready() path Fix9 state is not constructed yet. Preserve
		# Fix8 behavior until R2 setup completes, then seed the shared state once.
		return super._apply_hotbar_presentation_for_index(index)

	var controller = base_lab.character_gameplay_controller
	var hotbar = controller.get_container(controller.player_hotbar_id)
	if hotbar == null or index < 0 or index >= int(hotbar.slot_count):
		return _failure("FPE_HOTBAR_SLOT_UNAVAILABLE", {"index": index})

	var selected_item_id := String(hotbar.get_item_at_slot(index))
	var previous_state: Dictionary = held_item_presentation_state.get_hand_snapshot("right")
	if (
		selected_item_id == _last_hotbar_item_id
		and String(previous_state.get("item_id", "")) == selected_item_id
		and int(previous_state.get("selected_slot_index", -2)) == index
	):
		_record_hotbar_prediction_cost(started_us)
		return {
			"success": true,
			"code": "OK",
			"details": {
				"changed": false,
				"item_id": selected_item_id,
				"index": index,
				"shared_held_state": true,
			},
		}

	var previous_item_id := _last_hotbar_item_id
	_last_hotbar_item_id = selected_item_id
	_hotbar_sync_runs += 1
	_hotbar_local_prediction_applies += 1

	if selected_item_id.is_empty():
		var cleared: Dictionary = held_item_presentation_state.clear_hand(
			"right",
			index,
			HELD_SOURCE_HOTBAR
		)
		if bool(cleared.get("success", false)) and bool(cleared.get("details", {}).get("changed", false)):
			_hotbar_local_prediction_clears += 1
		_record_hotbar_prediction_cost(started_us)
		return _merge_state_and_apply_result(cleared)

	var item: Variant = controller.get_item(selected_item_id)
	if item == null:
		_last_hotbar_item_id = ""
		held_item_presentation_state.clear_hand("right", index, HELD_SOURCE_HOTBAR)
		_hotbar_local_prediction_clears += 1
		_record_hotbar_prediction_cost(started_us)
		return _failure("FPE_SELECTED_HOTBAR_ITEM_MISSING", {
			"index": index,
			"item_id": selected_item_id,
			"previous_item_id": previous_item_id,
		})

	var definition: Variant = controller.get_definition(String(item.definition_id))
	var display_name := String(item.definition_id)
	var item_color := Color(0.65, 0.68, 0.72, 1.0)
	if definition != null:
		display_name = String(definition.display_name)
		item_color = _metadata_color(definition.metadata, item_color)

	var state_result: Dictionary = held_item_presentation_state.set_hand_item(
		"right",
		selected_item_id,
		display_name,
		item_color,
		index,
		HELD_SOURCE_HOTBAR
	)
	_record_hotbar_prediction_cost(started_us)
	return _merge_state_and_apply_result(state_result)


func _on_held_item_presentation_changed(hand_id: String, snapshot: Dictionary) -> void:
	_held_state_changes += 1
	_last_held_apply_result = _apply_held_item_snapshot(hand_id, snapshot)


func _apply_held_item_snapshot(hand_id: String, snapshot: Dictionary) -> Dictionary:
	if hand_id != "right":
		return _failure("FPE_R2_UNSUPPORTED_HELD_HAND", {"hand_id": hand_id})
	if first_person_embodiment == null:
		return _failure("FPE_R2_FIRST_PERSON_EMBODIMENT_REQUIRED")
	if third_person_held_item_presenter == null:
		return _failure("FPE_R2_THIRD_PERSON_PRESENTER_REQUIRED")

	var item_id := String(snapshot.get("item_id", ""))
	if item_id.is_empty():
		var first_clear: Dictionary = first_person_embodiment.clear_authoritative_hand_item("right")
		var third_clear: Dictionary = third_person_held_item_presenter.clear_item()
		if bool(third_clear.get("success", false)):
			_third_person_clears += 1
		if not bool(first_clear.get("success", false)):
			return first_clear
		if not bool(third_clear.get("success", false)):
			return third_clear
		return {
			"success": true,
			"error_code": "",
			"details": {
				"item_id": "",
				"first_person_applied": true,
				"third_person_applied": true,
			},
		}

	var display_name := String(snapshot.get("display_name", item_id))
	var color := _snapshot_color(snapshot, Color(0.65, 0.68, 0.72, 1.0))
	var first_result: Dictionary = first_person_embodiment.set_authoritative_hand_item(
		"right",
		item_id,
		display_name,
		color
	)
	var third_result: Dictionary = third_person_held_item_presenter.present_item(
		item_id,
		display_name,
		color
	)
	if bool(third_result.get("success", false)):
		_third_person_updates += 1
	if not bool(first_result.get("success", false)):
		return first_result
	if not bool(third_result.get("success", false)):
		return third_result
	return {
		"success": true,
		"error_code": "",
		"details": {
			"item_id": item_id,
			"first_person_applied": true,
			"third_person_applied": true,
			"third_person_attachment": third_result.get("details", {}).get("attachment_mode", ""),
		},
	}


func _merge_state_and_apply_result(state_result: Dictionary) -> Dictionary:
	if not bool(state_result.get("success", false)):
		return state_result
	var changed := bool(state_result.get("details", {}).get("changed", false))
	if changed and not _last_held_apply_result.is_empty() and not bool(_last_held_apply_result.get("success", false)):
		return _last_held_apply_result.duplicate(true)
	var result := state_result.duplicate(true)
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["shared_held_state"] = true
	details["first_person_and_third_person"] = true
	result["details"] = details
	return result


func _snapshot_color(snapshot: Dictionary, fallback: Color) -> Color:
	var value: Variant = snapshot.get("color", [])
	if value is Array:
		var components: Array = value
		if components.size() >= 4:
			return Color(
				float(components[0]),
				float(components[1]),
				float(components[2]),
				float(components[3])
			)
	return fallback


func get_held_item_presentation_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_r2_held_item_composition.v1",
		"setup": _held_item_setup_result.duplicate(true),
		"state": held_item_presentation_state.create_report() if held_item_presentation_state != null else {},
		"third_person": third_person_held_item_presenter.create_report() if third_person_held_item_presenter != null else {},
		"held_state_changes": _held_state_changes,
		"third_person_updates": _third_person_updates,
		"third_person_clears": _third_person_clears,
		"last_apply_result": _last_held_apply_result.duplicate(true),
		"shared_transient_state": true,
		"durable_selection": false,
		"concrete_item_actions_server_authoritative": true,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2"] = get_held_item_presentation_report()
	return snapshot

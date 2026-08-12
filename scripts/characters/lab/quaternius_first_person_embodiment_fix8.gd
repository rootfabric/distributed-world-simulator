class_name QuaterniusFirstPersonEmbodimentFix8
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix7.gd"

# Hotbar selection is input/presentation state, not an Item Graph mutation.
# The accepted CH9.6 path sends inventory.select_hotbar through the durable item
# command pipeline. That pipeline persists a full recovery checkpoint before the
# command completes. Because the CH9.6 server and client live in the same
# SceneTree for this lab, the synchronous disk checkpoint stalls the entire game.
#
# Fix8 deliberately does not send a server hotbar command. Item actions still
# carry an explicit canonical item_id through the accepted network bridge and
# remain server-authoritative. Only the local selected slot / viewmodel ownership
# moves out of the durable Item Graph path.

const HOTBAR_SELECTION_MODE := "CLIENT_LOCAL_PRESENTATION"

var _local_hotbar_index: int = -1
var _local_hotbar_switches: int = 0
var _local_hotbar_noops: int = 0
var _server_hotbar_commands_suppressed: int = 0
var _local_hotbar_switch_total_us: int = 0
var _local_hotbar_switch_max_us: int = 0
var _canonical_selection_overrides_ignored: int = 0


func _ensure_hotbar_network_adapter() -> bool:
	# Intentionally do not construct FirstPersonHotbarNetworkAdapter. The base
	# process calls this port every frame, so return readiness without introducing
	# an ITEM_COMMAND path for selection-only input.
	return (
		base_lab != null
		and bool(base_lab.network_ready)
		and base_lab.character_gameplay_controller != null
	)


func _poll_hotbar_authority() -> void:
	# No authority round-trip exists for slot selection in Fix8. Server authority
	# is exercised when a concrete item action is submitted with an explicit id.
	pass


func _select_hotbar_nonblocking(index: int) -> Dictionary:
	var started_us: int = Time.get_ticks_usec()
	if base_lab == null or not bool(base_lab.network_ready):
		return _failure("FPE_HOTBAR_RUNTIME_NOT_READY")
	var controller = base_lab.character_gameplay_controller
	if controller == null:
		return _failure("FPE_HOTBAR_CONTROLLER_NOT_READY")
	if index < 0 or index >= 10:
		return _failure("FPE_HOTBAR_INDEX_INVALID", {"index": index})

	if int(controller.selected_hotbar_index) == index and _local_hotbar_index == index:
		_local_hotbar_noops += 1
		_record_local_hotbar_switch_cost(started_us)
		return {
			"success": true,
			"code": "HOTBAR_LOCAL_PRESENTATION_NOOP",
			"details": {
				"changed": false,
				"selected_hotbar_index": index,
				"selection_mode": HOTBAR_SELECTION_MODE,
				"network_command_sent": false,
				"durable_checkpoint_requested": false,
			},
		}

	_local_hotbar_index = index
	controller.selected_hotbar_index = index
	_hotbar_prediction_index = -1
	_local_hotbar_switches += 1
	_server_hotbar_commands_suppressed += 1

	# The right-hand viewmodel changes synchronously in the input callback. This
	# path does not poll ENet, wait for an authority result, or touch persistence.
	var presentation_result: Dictionary = _apply_hotbar_presentation_for_index(index)
	if not bool(presentation_result.get("success", false)):
		_record_local_hotbar_switch_cost(started_us)
		return presentation_result

	# Ten persistent cells are cheap compared with the former checkpoint, but UI
	# rendering is still kept outside Item Graph/network work. It uses only the
	# already installed local replica.
	_refresh_persistent_hotbar_only()
	_hotbar_presentation_dirty = false
	_record_local_hotbar_switch_cost(started_us)
	return {
		"success": true,
		"code": "HOTBAR_LOCAL_PRESENTATION",
		"details": {
			"changed": true,
			"selected_hotbar_index": index,
			"selected_item_id": _last_hotbar_item_id,
			"selection_mode": HOTBAR_SELECTION_MODE,
			"network_command_sent": false,
			"durable_checkpoint_requested": false,
			"server_authority_deferred_to_item_action": true,
		},
	}


func _on_fpe_canonical_projection_applied(classification: String, snapshot: Dictionary) -> void:
	super._on_fpe_canonical_projection_applied(classification, snapshot)
	if _local_hotbar_index < 0 or base_lab == null:
		return
	var controller = base_lab.character_gameplay_controller
	if controller == null:
		return

	# A later structural Item Graph projection may contain the old durable
	# selected_hotbar_index. Do not let that presentation-only field overwrite the
	# user's current local selection. All actual item/container contents from the
	# canonical projection remain accepted and authoritative.
	if int(controller.selected_hotbar_index) != _local_hotbar_index:
		_canonical_selection_overrides_ignored += 1
		controller.selected_hotbar_index = _local_hotbar_index
		_refresh_persistent_hotbar_only()
	_hotbar_presentation_dirty = true


func _record_local_hotbar_switch_cost(started_us: int) -> void:
	var elapsed_us: int = maxi(Time.get_ticks_usec() - started_us, 0)
	_local_hotbar_switch_total_us += elapsed_us
	_local_hotbar_switch_max_us = maxi(_local_hotbar_switch_max_us, elapsed_us)


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null:
		return
	fpe_status_label.text = fpe_status_label.text.replace(
		"hotbar: NONBLOCKING/BOOTSTRAP",
		"hotbar: LOCAL/INSTANT"
	)
	fpe_status_label.text += (
		"\nhotbar local: %d switches | max %.3f ms | server commands: 0 | durable checkpoint: NO"
		% [_local_hotbar_switches, float(_local_hotbar_switch_max_us) / 1000.0]
	)


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["fix8"] = {
		"selection_mode": HOTBAR_SELECTION_MODE,
		"local_hotbar_index": _local_hotbar_index,
		"local_hotbar_switches": _local_hotbar_switches,
		"local_hotbar_noops": _local_hotbar_noops,
		"server_hotbar_commands_suppressed": _server_hotbar_commands_suppressed,
		"server_hotbar_commands_sent": 0,
		"durable_hotbar_checkpoints_requested": 0,
		"local_hotbar_switch_average_us": (
			float(_local_hotbar_switch_total_us) / float(_local_hotbar_switches + _local_hotbar_noops)
			if _local_hotbar_switches + _local_hotbar_noops > 0 else 0.0
		),
		"local_hotbar_switch_max_us": _local_hotbar_switch_max_us,
		"canonical_selection_overrides_ignored": _canonical_selection_overrides_ignored,
		"item_actions_remain_server_authoritative": true,
		"third_person_item_presentation": "FOLLOWUP_NOT_IN_FIX8",
	}
	return snapshot

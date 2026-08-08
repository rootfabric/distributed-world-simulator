extends "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix8.gd"

# FIX9 keeps the accepted rev6 inventory behavior but removes presentation-only
# property writes that were occurring on nearly every client frame. The prior
# enhancer recomputed sort-button and interaction-hint geometry every _process()
# iteration even when nothing moved. In graphical FIX8 evidence those counters
# tracked client process iterations almost one-for-one. FIX9 still checks the
# current target geometry every frame, but writes Control layout properties only
# when the target actually differs, preserving resize/reflow behavior.

const FIX9_SCHEMA: String = "planet_simulator.inventory_network_rev6_enhancer.fix9.v1"
const FIX9_LAYOUT_POLICY: String = "WRITE_CONTROL_GEOMETRY_ONLY_WHEN_CHANGED_V1"
const FIX9_LAYOUT_EPSILON: float = 0.001

var _fix9_sort_layout_skips: int = 0
var _fix9_hint_layout_skips: int = 0
var _fix9_visibility_updates: int = 0
var _fix9_visibility_skips: int = 0


func setup(controller, network_bridge) -> Dictionary:
	var result: Dictionary = super.setup(controller, network_bridge)
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["schema"] = FIX9_SCHEMA
	details["layout_policy"] = FIX9_LAYOUT_POLICY
	result["details"] = details
	return result


func _layout_sort_buttons() -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var eligible: int = 0
	var changed: bool = false
	var player_panel = screen.get("player_panel")
	var external_panel = screen.get("external_panel")
	var player_result: int = _fix9_layout_sort_button_if_needed(player_sort_button, player_panel)
	var external_result: int = _fix9_layout_sort_button_if_needed(external_sort_button, external_panel)
	for result in [player_result, external_result]:
		if result >= 0:
			eligible += 1
		if result > 0:
			changed = true
	if eligible <= 0:
		return
	if changed:
		_sort_layout_updates += 1
	else:
		_fix9_sort_layout_skips += 1


func _fix9_layout_sort_button_if_needed(button: Button, panel) -> int:
	if button == null or panel == null:
		return -1
	if not is_instance_valid(button) or not is_instance_valid(panel) or not panel is Control:
		return -1
	var panel_rect: Rect2 = (panel as Control).get_global_rect()
	# Control clamps `size` to its combined minimum size. The accepted button
	# factory asks for 112x30, while Godot 4.7.1's default Button theme is already
	# at least 31 px high (and the real Russian caption can require >112 px width).
	# Comparing against the unattainable nominal size makes every frame look
	# changed and recreates the exact hot-path churn FIX9 is meant to remove.
	var minimum_size: Vector2 = button.get_combined_minimum_size()
	var target_size := Vector2(
		maxf(SORT_BUTTON_SIZE.x, minimum_size.x),
		maxf(SORT_BUTTON_SIZE.y, minimum_size.y)
	)
	var target_position := Vector2(
		panel_rect.end.x - target_size.x - SORT_BUTTON_MARGIN.x,
		panel_rect.position.y + SORT_BUTTON_MARGIN.y
	)
	var size_changed: bool = button.size.distance_to(target_size) > FIX9_LAYOUT_EPSILON
	var position_changed: bool = button.global_position.distance_to(target_position) > FIX9_LAYOUT_EPSILON
	if not size_changed and not position_changed:
		return 0
	if size_changed:
		button.size = target_size
	if position_changed:
		button.global_position = target_position
	return 1


func _layout_interaction_hint() -> void:
	var runtime = get_parent()
	if runtime == null:
		return
	var hint = runtime.get("interaction_label")
	if hint == null or not is_instance_valid(hint) or not hint is Control:
		return
	var hint_control := hint as Control
	var position_changed: bool = (
		hint_control.position.distance_to(INTERACTION_HINT_POSITION) > FIX9_LAYOUT_EPSILON
	)
	var size_changed: bool = hint_control.size.distance_to(INTERACTION_HINT_SIZE) > FIX9_LAYOUT_EPSILON
	if not position_changed and not size_changed:
		_fix9_hint_layout_skips += 1
		return
	if position_changed:
		hint_control.position = INTERACTION_HINT_POSITION
	if size_changed:
		hint_control.size = INTERACTION_HINT_SIZE
	_interaction_hint_layout_updates += 1


func _update_sort_button_visibility(inventory_visible: bool, carry_active: bool) -> void:
	var seven_days: bool = false
	var profile = screen.get("active_interaction_profile") if screen != null else null
	if profile != null:
		seven_days = String(profile.get("profile_id")) == "seven_days_like"
	var allow_sort: bool = inventory_visible and seven_days and not carry_active and not _sort_in_progress
	_fix9_set_button_visibility(player_sort_button, allow_sort)
	var external_visible: bool = (
		allow_sort
		and screen != null
		and not String(screen.get("external_container_id")).is_empty()
	)
	_fix9_set_button_visibility(external_sort_button, external_visible)


func _fix9_set_button_visibility(button: Button, target_visible: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	if button.visible == target_visible:
		_fix9_visibility_skips += 1
		return
	button.visible = target_visible
	_fix9_visibility_updates += 1


func get_report() -> Dictionary:
	var result: Dictionary = super.get_report()
	result["schema"] = FIX9_SCHEMA
	result["layout_policy"] = FIX9_LAYOUT_POLICY
	result["sort_layout_skips"] = _fix9_sort_layout_skips
	result["interaction_hint_layout_skips"] = _fix9_hint_layout_skips
	result["visibility_updates"] = _fix9_visibility_updates
	result["visibility_skips"] = _fix9_visibility_skips
	return result

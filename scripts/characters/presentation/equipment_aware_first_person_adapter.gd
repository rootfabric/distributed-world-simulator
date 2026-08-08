class_name EquipmentAwareFirstPersonAdapter
extends "res://scripts/characters/presentation/full_body_first_person_adapter.gd"


func refresh_presentation_visuals() -> Dictionary:
	if presentation == null:
		return {"success": false, "error_code": "NO_PRESENTATION_BOUND", "details": {}}

	_clear_shadow_proxy()
	_restore_visual_layers()
	world_visual_root = _resolve_world_visual_root(presentation)
	viewmodel_visual_root = _resolve_viewmodel_visual_root(presentation)
	custom_shadow_proxy_root = _resolve_custom_shadow_proxy_root(presentation)
	_capture_and_move_visuals(world_visual_root, _world_render_layer_mask(), _world_visual_states)
	if viewmodel_visual_root != null and viewmodel_visual_root != world_visual_root:
		_capture_and_move_visuals(viewmodel_visual_root, _viewmodel_render_layer_mask(), _viewmodel_visual_states)
	_build_shadow_proxy()
	_apply_camera_policy()
	_apply_viewmodel_visibility()
	_apply_shadow_visibility()
	return _success(create_report())

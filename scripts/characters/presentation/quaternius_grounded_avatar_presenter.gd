class_name QuaterniusGroundedAvatarPresenter
extends "res://scripts/characters/presentation/quaternius_avatar_presenter.gd"

const DEFAULT_CROUCH_GROUND_OFFSET_M := 0.35
const DEFAULT_GROUND_OFFSET_RESPONSE := 12.0

var crouch_ground_offset_m := DEFAULT_CROUCH_GROUND_OFFSET_M
var ground_offset_response := DEFAULT_GROUND_OFFSET_RESPONSE
var _presentation_ground_offset_y := 0.0
var _presentation_ground_target_y := 0.0


func setup(options: Dictionary = {}) -> Dictionary:
	crouch_ground_offset_m = maxf(
		0.0,
		float(options.get("crouch_ground_offset_m", DEFAULT_CROUCH_GROUND_OFFSET_M))
	)
	ground_offset_response = maxf(
		0.1,
		float(options.get("ground_offset_response", DEFAULT_GROUND_OFFSET_RESPONSE))
	)
	return super.setup(options)


func _process(delta: float) -> void:
	super._process(delta)
	_update_ground_compensation(delta)


func _update_ground_compensation(delta: float) -> void:
	# Quaternius UAL1 crouch clips bend the legs around the model origin without
	# lowering the whole rendered body enough to keep the feet on the gameplay
	# foot plane. Correct that as presentation-only motion. CharacterBody3D,
	# collision, network position and root-motion authority remain untouched.
	var is_quaternius_asset := asset_mode.begins_with("QUATERNIUS")
	var is_crouch := current_semantic in ["crouch_idle", "crouch_walk"]
	_presentation_ground_target_y = -crouch_ground_offset_m if is_quaternius_asset and is_crouch else 0.0
	_presentation_ground_offset_y = lerpf(
		_presentation_ground_offset_y,
		_presentation_ground_target_y,
		clampf(delta * ground_offset_response, 0.0, 1.0)
	)
	if absf(_presentation_ground_offset_y - _presentation_ground_target_y) < 0.0005:
		_presentation_ground_offset_y = _presentation_ground_target_y
	if _model_yaw_root != null:
		_model_yaw_root.position.y = _presentation_ground_offset_y


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["ground_compensation"] = {
		"mode": "QUATERNIUS_CROUCH_VISUAL_ROOT_OFFSET",
		"configured_offset_m": crouch_ground_offset_m,
		"current_offset_y": _presentation_ground_offset_y,
		"target_offset_y": _presentation_ground_target_y,
		"response": ground_offset_response,
		"gameplay_body_moved": false,
		"root_motion_applied": false,
	}
	return report

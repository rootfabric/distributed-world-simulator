class_name SemanticAnimationDriver
extends RefCounted

const Utils = preload("res://scripts/characters/contracts/character_contract_utils.gd")

const IDLE_SPEED := 0.08
const RUN_SPEED := 4.5
const JUMP_SPEED := 0.35

var previous_grounded := true
var last_motion_semantic := "locomotion/idle"
var last_action_sequence := -1

func resolve_motion(state) -> StringName:
	if state == null:
		return &"locomotion/idle"
	if not state.grounded:
		previous_grounded = false
		last_motion_semantic = "locomotion/jump_start" if state.velocity.y > JUMP_SPEED else "locomotion/fall"
		return StringName(last_motion_semantic)
	if not previous_grounded:
		previous_grounded = true
		last_motion_semantic = "locomotion/land"
		return &"locomotion/land"
	previous_grounded = true
	var speed: float = float(state.horizontal_speed())
	if speed <= IDLE_SPEED:
		last_motion_semantic = "locomotion/idle"
		return &"locomotion/idle"
	var local_velocity: Vector3 = Basis(Vector3.UP, -float(state.facing_yaw)) * Vector3(state.velocity)
	if absf(local_velocity.x) > absf(local_velocity.z) * 1.15:
		last_motion_semantic = "locomotion/strafe_right" if local_velocity.x > 0.0 else "locomotion/strafe_left"
		return StringName(last_motion_semantic)
	last_motion_semantic = "locomotion/run" if speed >= RUN_SPEED else "locomotion/walk"
	return StringName(last_motion_semantic)

func resolve_action(state) -> StringName:
	if state == null or not state.active:
		return &""
	if state.action_sequence == last_action_sequence:
		return &""
	last_action_sequence = state.action_sequence
	var action_id := Utils.normalized_id(state.action_id)
	if action_id == "action/none":
		return &""
	return StringName(action_id)

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.semantic_animation_driver.v1",
		"previous_grounded": previous_grounded,
		"last_motion_semantic": last_motion_semantic,
		"last_action_sequence": last_action_sequence,
	}

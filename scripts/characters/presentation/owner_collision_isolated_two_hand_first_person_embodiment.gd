class_name OwnerCollisionIsolatedTwoHandFirstPersonEmbodiment
extends "res://scripts/characters/presentation/two_hand_posed_first_person_embodiment.gd"

const OWNER_COLLISION_RELEASE_GRACE_SEC := 0.20

var _owner_collision_isolation_by_body_id: Dictionary = {}
var _owner_collision_isolation_activations := 0
var _owner_collision_isolation_release_schedules := 0
var _owner_collision_isolation_restores := 0


func _attach_local_sandbox_target(hand: String, target: Node) -> Dictionary:
	var result: Dictionary = super._attach_local_sandbox_target(hand, target)
	if not bool(result.get("success", false)):
		return result
	if not target is RigidBody3D or player == null:
		return result

	var body := target as RigidBody3D
	var body_id := body.get_instance_id()
	var body_had_owner_exception := _has_collision_exception(body, player)
	var owner_had_body_exception := _has_collision_exception(player, body)
	if not body_had_owner_exception:
		body.add_collision_exception_with(player)
	if not owner_had_body_exception:
		player.add_collision_exception_with(body)

	_owner_collision_isolation_by_body_id[body_id] = {
		"body_id": body_id,
		"body": body,
		"body_had_owner_exception": body_had_owner_exception,
		"owner_had_body_exception": owner_had_body_exception,
	}
	_owner_collision_isolation_activations += 1

	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["owner_collision_isolated"] = true
	details["owner_collision_grace_ms"] = int(round(OWNER_COLLISION_RELEASE_GRACE_SEC * 1000.0))
	result["details"] = details
	return result


func _release_local_sandbox_target(hand: String) -> Dictionary:
	var body: RigidBody3D = null
	if _sandbox_state_by_hand.has(hand):
		var state: Dictionary = Dictionary(_sandbox_state_by_hand[hand])
		var target: Variant = state.get("target")
		if target is RigidBody3D and is_instance_valid(target):
			body = target as RigidBody3D

	var isolation: Dictionary = {}
	if body != null:
		isolation = Dictionary(_owner_collision_isolation_by_body_id.get(body.get_instance_id(), {})).duplicate(true)

	var result: Dictionary = super._release_local_sandbox_target(hand)
	if not bool(result.get("success", false)):
		return result
	if body != null and not isolation.is_empty():
		_schedule_owner_collision_restore(body, isolation)
		var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
		details["owner_collision_restore_scheduled"] = true
		details["owner_collision_grace_ms"] = int(round(OWNER_COLLISION_RELEASE_GRACE_SEC * 1000.0))
		result["details"] = details
	return result


func get_owner_collision_isolation_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_owner_collision_isolation.v1",
		"active": _owner_collision_isolation_by_body_id.size(),
		"activations": _owner_collision_isolation_activations,
		"release_schedules": _owner_collision_isolation_release_schedules,
		"restores": _owner_collision_isolation_restores,
		"release_grace_ms": int(round(OWNER_COLLISION_RELEASE_GRACE_SEC * 1000.0)),
		"owner_only_exception": true,
		"world_collisions_preserved": true,
		"presentation_sandbox_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["owner_collision_isolation"] = get_owner_collision_isolation_report()
	return report


func _schedule_owner_collision_restore(body: RigidBody3D, isolation: Dictionary) -> void:
	_owner_collision_isolation_release_schedules += 1
	if get_tree() == null:
		_finish_owner_collision_restore(body, isolation)
		return
	var timer := get_tree().create_timer(OWNER_COLLISION_RELEASE_GRACE_SEC)
	timer.timeout.connect(_finish_owner_collision_restore.bind(body, isolation))


func _finish_owner_collision_restore(body: RigidBody3D, isolation: Dictionary) -> void:
	var body_id := int(isolation.get("body_id", 0))
	if body != null and is_instance_valid(body) and player != null and is_instance_valid(player):
		if not bool(isolation.get("body_had_owner_exception", false)):
			body.remove_collision_exception_with(player)
		if not bool(isolation.get("owner_had_body_exception", false)):
			player.remove_collision_exception_with(body)
	if body_id > 0:
		_owner_collision_isolation_by_body_id.erase(body_id)
	_owner_collision_isolation_restores += 1


func _has_collision_exception(source: PhysicsBody3D, other: PhysicsBody3D) -> bool:
	if source == null or other == null:
		return false
	for exception in source.get_collision_exceptions():
		if exception == other:
			return true
	return false

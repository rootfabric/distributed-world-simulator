extends "res://scripts/items/presentation/item_representation_system_base.gd"

const Fix5Relations = preload("res://scripts/items/domain/item_relations.gd")
const Fix5SpatialRef = preload("res://scripts/simulation/spatial/spatial_ref.gd")

# FIX5 boundary: a graphical replica is a presentation of server Item Graph
# state. It must never become an independent physics authority for WORLD items.
const FIX5_WORLD_AUTHORITY_POLICY := "SERVER_ITEM_GRAPH_TRANSFORM_FROZEN_REPLICA_V1"

var _fix5_authoritative_replica_mode: bool = false
var _fix5_authoritative_state_reapplies: int = 0
var _fix5_capture_suppressions: int = 0


func set_interaction_controller(controller) -> void:
	super.set_interaction_controller(controller)
	var was_replica := _fix5_authoritative_replica_mode
	_fix5_authoritative_replica_mode = (
		controller != null
		and String(controller.get("runtime_mode")) == "replica"
	)
	if _fix5_authoritative_replica_mode:
		world_applied_revisions.clear()
		world_applied_spatial_states.clear()
		if not world_nodes.is_empty():
			synchronize_all()
	elif was_replica:
		for body_value in world_nodes.values():
			if not body_value is RigidBody3D or not is_instance_valid(body_value):
				continue
			var body: RigidBody3D = body_value
			var item_id := String(body.get_meta("item_instance_id", ""))
			var item = item_registry.get_item(item_id)
			var definition = (
				item_registry.get_definition(item.definition_id)
				if item != null
				else null
			)
			body.freeze = (
				bool(definition.metadata.get("freeze_world_body", false))
				if definition != null
				else false
			)
			var gravity_driver = body.get_node_or_null("GravityBodyDriver")
			if gravity_driver != null:
				gravity_driver.process_mode = Node.PROCESS_MODE_INHERIT


func _ensure_world_node(item) -> void:
	super._ensure_world_node(item)
	if not _fix5_authoritative_replica_mode:
		return
	var body_value = world_nodes.get(item.instance_id)
	if not body_value is RigidBody3D or not is_instance_valid(body_value):
		return
	var body: RigidBody3D = body_value
	var spatial_ref: Dictionary = {}
	var aggregate = _get_world_aggregate(item)
	if aggregate != null:
		spatial_ref = Dictionary(aggregate.spatial_ref).duplicate(true)
		world_applied_spatial_states[item.instance_id] = _aggregate_presentation_state(aggregate)
	else:
		spatial_ref = Fix5Relations.spatial_ref_from_relation(item.relation)
		world_applied_revisions[item.instance_id] = int(item.revision)
	if spatial_ref.is_empty():
		return
	# Always restore pose from the currently projected Item Graph. This is
	# intentionally stronger than the legacy revision cache because a prediction
	# rollback may change presentation while authoritative revision is unchanged.
	body.freeze = true
	body.transform = Transform3D(
		Fix5SpatialRef.get_basis(spatial_ref),
		Fix5SpatialRef.get_position(spatial_ref)
	)
	body.linear_velocity = Fix5SpatialRef.get_linear_velocity(spatial_ref)
	body.angular_velocity = Fix5SpatialRef.get_angular_velocity(spatial_ref)
	if aggregate != null:
		body.sleeping = bool(aggregate.physics_state.get("sleeping", false))
	var gravity_driver = body.get_node_or_null("GravityBodyDriver")
	if gravity_driver != null:
		gravity_driver.process_mode = Node.PROCESS_MODE_DISABLED
	_fix5_authoritative_state_reapplies += 1


func capture_world_state(item_id: String) -> bool:
	if _fix5_authoritative_replica_mode:
		_fix5_capture_suppressions += 1
		return false
	return super.capture_world_state(item_id)


func is_fix5_authoritative_replica_mode() -> bool:
	return _fix5_authoritative_replica_mode


func get_fix5_world_authority_report() -> Dictionary:
	return {
		"policy": FIX5_WORLD_AUTHORITY_POLICY,
		"authoritative_replica_mode": _fix5_authoritative_replica_mode,
		"authoritative_state_reapplies": _fix5_authoritative_state_reapplies,
		"capture_suppressions": _fix5_capture_suppressions,
		"world_node_count": world_nodes.size(),
	}

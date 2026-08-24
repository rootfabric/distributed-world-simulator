extends "res://scripts/runtime/networked_gameplay/m6/m6_durable_replay_outbox_p2.gd"

# V0-P3 additive replay aggregate adapter.
# The exact accepted P2 outbox remains the compatibility parent. P3 only adds
# recognition of resource_replay.records to the existing durable replay lookup.

func _replay_state_has_operation(replay_state: Dictionary, operation_id: String) -> bool:
	if super._replay_state_has_operation(replay_state, operation_id):
		return true
	var resource_replay_value = replay_state.get("resource_replay", {})
	if not resource_replay_value is Dictionary:
		return false
	var resource_records_value = Dictionary(resource_replay_value).get("records", {})
	return (
		resource_records_value is Dictionary
		and Dictionary(resource_records_value).has(operation_id)
	)

extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_live_player_gate.gd"

# USER1-SEM1 adapts the accepted MVP3 local gate to normal product player
# identity. The coordinator still owns every authority/epoch decision; this
# adapter only validates that its player snapshot belongs to the product row.


func decision_snapshot() -> Dictionary:
	if _coordinator == null:
		return {}
	var state_value = _coordinator.snapshot()
	if not state_value is Dictionary:
		return {}
	var state: Dictionary = state_value
	var player_value = state.get("player_snapshot", {})
	if not player_value is Dictionary:
		return {}
	var player: Dictionary = player_value
	var epoch_value = state.get("authority_epoch")
	if (
		typeof(epoch_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(epoch_value))
		or float(epoch_value) != floorf(float(epoch_value))
		or float(epoch_value) < 1.0
		or float(epoch_value) > 9007199254740991.0
	):
		return {}
	var epoch := int(epoch_value)
	if epoch < _highest_observed_epoch:
		return {}
	if (
		String(player.get("logical_player_id", "")) != _player
		or String(player.get("player_entity_id", "")) != "player/%s" % _player
	):
		return {}
	_highest_observed_epoch = epoch
	return state


static func normalize_live_record(record: Dictionary) -> Dictionary:
	var normalized := record.duplicate(true)
	for field in [
		"ownership_epoch",
		"last_input_sequence",
		"state_revision",
		"joined_tick",
		"left_tick",
	]:
		if normalized.has(field):
			normalized[field] = int(normalized[field])
	return normalized

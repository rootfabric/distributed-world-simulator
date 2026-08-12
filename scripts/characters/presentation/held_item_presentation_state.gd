class_name HeldItemPresentationState
extends RefCounted

signal changed(hand_id: String, snapshot: Dictionary)

const HAND_LEFT := "left"
const HAND_RIGHT := "right"
const VALID_HANDS: Array[String] = [HAND_LEFT, HAND_RIGHT]

var _revision: int = 0
var _state_by_hand: Dictionary = {
	HAND_LEFT: {},
	HAND_RIGHT: {},
}


func set_hand_item(
	hand_id: String,
	item_id: String,
	display_name: String = "",
	item_color: Color = Color(0.65, 0.68, 0.72, 1.0),
	selected_slot_index: int = -1,
	source: String = "PRESENTATION"
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("HELD_PRESENTATION_INVALID_HAND", {"hand_id": hand_id})
	var normalized_item_id := item_id.strip_edges()
	if normalized_item_id.is_empty():
		return clear_hand(hand, selected_slot_index, source)

	var candidate := {
		"hand_id": hand,
		"item_id": normalized_item_id,
		"display_name": display_name,
		"color": [item_color.r, item_color.g, item_color.b, item_color.a],
		"selected_slot_index": selected_slot_index,
		"source": source,
	}
	var previous: Dictionary = get_hand_snapshot(hand)
	if _stable_fields(previous) == _stable_fields(candidate):
		return _success({
			"changed": false,
			"hand_id": hand,
			"snapshot": previous,
		})

	_revision += 1
	candidate["revision"] = _revision
	_state_by_hand[hand] = candidate.duplicate(true)
	changed.emit(hand, candidate.duplicate(true))
	return _success({
		"changed": true,
		"hand_id": hand,
		"snapshot": candidate,
	})


func clear_hand(
	hand_id: String,
	selected_slot_index: int = -1,
	source: String = "PRESENTATION"
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("HELD_PRESENTATION_INVALID_HAND", {"hand_id": hand_id})
	var candidate := {
		"hand_id": hand,
		"item_id": "",
		"display_name": "",
		"color": [0.0, 0.0, 0.0, 0.0],
		"selected_slot_index": selected_slot_index,
		"source": source,
	}
	var previous: Dictionary = get_hand_snapshot(hand)
	if _stable_fields(previous) == _stable_fields(candidate):
		return _success({
			"changed": false,
			"hand_id": hand,
			"snapshot": previous,
		})

	_revision += 1
	candidate["revision"] = _revision
	_state_by_hand[hand] = candidate.duplicate(true)
	changed.emit(hand, candidate.duplicate(true))
	return _success({
		"changed": true,
		"hand_id": hand,
		"snapshot": candidate,
	})


func get_hand_snapshot(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return {}
	var value: Variant = _state_by_hand.get(hand, {})
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.held_item_presentation_state.v1",
		"revision": _revision,
		"left": get_hand_snapshot(HAND_LEFT),
		"right": get_hand_snapshot(HAND_RIGHT),
		"transient": true,
		"durable": false,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _stable_fields(snapshot: Dictionary) -> Dictionary:
	var stable := snapshot.duplicate(true)
	stable.erase("revision")
	return stable


func _normalize_hand(hand_id: String) -> String:
	var normalized := hand_id.strip_edges().to_lower()
	return normalized if normalized in VALID_HANDS else ""


func _success(details: Dictionary = {}) -> Dictionary:
	return {
		"success": true,
		"error_code": "",
		"details": details.duplicate(true),
	}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": false,
		"error_code": error_code,
		"details": details.duplicate(true),
	}

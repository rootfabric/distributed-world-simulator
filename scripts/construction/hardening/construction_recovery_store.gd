extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const StateEnvelope = preload("res://scripts/construction/hardening/construction_state_envelope.gd")

const SLOT_SCHEMA := "planet_simulator.construction_recovery_slot.v1"
const MAX_SLOTS := 2

var _slots: Array = []
var _next_sequence := 0
var _quarantine: Array = []

func commit(envelope: Dictionary) -> Dictionary:
	var checked := StateEnvelope.validate(envelope)
	if not bool(checked.get("success", false)):
		return checked
	var slot := {
		"schema": SLOT_SCHEMA,
		"sequence": _next_sequence,
		"envelope": envelope.duplicate(true),
		"checksum": "",
	}
	slot["checksum"] = H.checksum(slot)
	_slots.append(slot)
	_next_sequence += 1
	while _slots.size() > MAX_SLOTS:
		_slots.pop_front()
	return H.success({"sequence": int(slot["sequence"])})

func recover() -> Dictionary:
	_quarantine.clear()
	for index in range(_slots.size() - 1, -1, -1):
		var slot: Dictionary = _slots[index]
		var checked := _validate_slot(slot)
		if bool(checked.get("success", false)):
			return H.success({
				"envelope": Dictionary(slot["envelope"]).duplicate(true),
				"sequence": int(slot["sequence"]),
				"fallback_used": index != _slots.size() - 1,
				"quarantined": _quarantine.size(),
			})
		_quarantine.append({"sequence": int(slot.get("sequence", -1)), "error_code": String(checked.get("error_code", "INVALID_SLOT"))})
	return H.failure("NO_VALID_CONSTRUCTION_PRODUCTION_CHECKPOINT", {"quarantined": _quarantine.size()})

func replace_slots(slots: Array, next_sequence: int) -> Dictionary:
	if slots.size() > MAX_SLOTS or not H.is_non_negative_integer(next_sequence):
		return H.failure("INVALID_CONSTRUCTION_RECOVERY_STATE")
	var previous_sequence := -1
	for raw_slot in slots:
		if typeof(raw_slot) != TYPE_DICTIONARY:
			return H.failure("INVALID_CONSTRUCTION_RECOVERY_STATE")
		var slot: Dictionary = raw_slot
		var checked := _validate_slot(slot)
		if not bool(checked.get("success", false)):
			return checked
		var sequence := int(slot["sequence"])
		if sequence <= previous_sequence or sequence >= next_sequence:
			return H.failure("INVALID_CONSTRUCTION_RECOVERY_SEQUENCE")
		previous_sequence = sequence
	_slots = slots.duplicate(true)
	_next_sequence = next_sequence
	_quarantine.clear()
	return H.success()

func get_slots() -> Array:
	return _slots.duplicate(true)

func get_quarantine() -> Array:
	return _quarantine.duplicate(true)

func corrupt_latest_for_test(field: String, value) -> Dictionary:
	if _slots.is_empty():
		return H.failure("NO_CONSTRUCTION_RECOVERY_SLOT")
	var index := _slots.size() - 1
	var slot: Dictionary = _slots[index]
	slot[field] = value
	_slots[index] = slot
	return H.success()

static func _validate_slot(slot: Dictionary) -> Dictionary:
	if slot.keys().size() != 4 or slot.get("schema") != SLOT_SCHEMA:
		return H.failure("INVALID_CONSTRUCTION_RECOVERY_SLOT")
	if not H.is_non_negative_integer(slot.get("sequence")) or typeof(slot.get("envelope")) != TYPE_DICTIONARY:
		return H.failure("INVALID_CONSTRUCTION_RECOVERY_SLOT")
	if String(slot.get("checksum", "")) != H.checksum(slot):
		return H.failure("CONSTRUCTION_RECOVERY_SLOT_CHECKSUM_MISMATCH")
	return StateEnvelope.validate(slot["envelope"])

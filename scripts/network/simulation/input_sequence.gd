extends RefCounted

const SCHEMA: String = "planet_simulator.input_sequence.v1"
const MIN_SEQUENCE: int = 1
const MAX_SEQUENCE: int = 2147483647
const HALF_RANGE: int = 1073741823

static func next(value: int) -> int:
	if value < MIN_SEQUENCE or value >= MAX_SEQUENCE:
		return MIN_SEQUENCE
	return value + 1

static func is_valid(value: int) -> bool:
	return value >= MIN_SEQUENCE and value <= MAX_SEQUENCE

static func is_newer(candidate: int, reference: int) -> bool:
	if not is_valid(candidate):
		return false
	if reference == 0:
		return true
	if not is_valid(reference) or candidate == reference:
		return false
	var forward: int = forward_distance(reference, candidate)
	return forward > 0 and forward <= HALF_RANGE

static func forward_distance(reference: int, candidate: int) -> int:
	if not is_valid(candidate):
		return -1
	if reference == 0:
		return candidate
	if not is_valid(reference):
		return -1
	if candidate >= reference:
		return candidate - reference
	return (MAX_SEQUENCE - reference) + candidate

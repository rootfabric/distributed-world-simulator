extends RefCounted

const MODULUS: int = 2147483647
const MULTIPLIER: int = 48271

var _state: int = 1
var _draw_count: int = 0


func configure(seed: int) -> Dictionary:
	if seed < 1 or seed >= MODULUS:
		return _failure("INVALID_RANDOM_SEED")
	_state = seed
	_draw_count = 0
	return _success()


func next_unit() -> float:
	_state = int((_state * MULTIPLIER) % MODULUS)
	_draw_count += 1
	return float(_state) / float(MODULUS)


func next_percent() -> float:
	return next_unit() * 100.0


func next_int(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	var span: int = maximum - minimum + 1
	return minimum + mini(int(floor(next_unit() * float(span))), span - 1)


func snapshot() -> Dictionary:
	return {
		"state": _state,
		"draw_count": _draw_count,
	}


static func derive_seed(base_seed: int, stream_key: String) -> int:
	var value: int = maxi(base_seed, 1) % MODULUS
	for index in range(stream_key.length()):
		value = int((value * 131 + stream_key.unicode_at(index) + 17) % MODULUS)
	return maxi(value, 1)


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}

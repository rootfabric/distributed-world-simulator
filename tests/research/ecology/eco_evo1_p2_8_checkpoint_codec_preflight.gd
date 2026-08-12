extends SceneTree

const Persistence = preload("res://scripts/research/ecology/plant_world_persistence_v1.gd")

var assertions := 0

func _init() -> void:
	var probe := {
		"current_year": 14,
		"total_years": 30,
		"seed_count": 160,
		"zero": 0,
		"negative": -7,
		"biomass": 0.08,
		"transport": Vector2(-1.0, 0.0),
		"bounds": Rect2(-10.0, -10.0, 20.0, 20.0),
		"history": PackedStringArray(["0", "14"]),
		"nested": [
			{"year": 18, "count": 87, "ratio": 0.5},
			{"year": 30, "count": 0, "ratio": 1.0},
		],
	}
	var before_hash := Persistence.value_hash(probe)
	var encoded = Persistence._encode_value(probe)
	_check(encoded != null, "codec encodes representative plant-world value")
	if encoded == null:
		_finish(false)
		return
	var text := JSON.stringify(encoded, "", true, true)
	var parsed = JSON.parse_string(text)
	_check(typeof(parsed) == TYPE_DICTIONARY, "encoded checkpoint fragment parses as JSON dictionary")
	var decoded = Persistence._decode_value(parsed)
	_check(typeof(decoded) == TYPE_DICTIONARY, "codec restores representative plant-world dictionary")
	if typeof(decoded) != TYPE_DICTIONARY:
		_finish(false)
		return
	var restored: Dictionary = decoded
	_check(typeof(restored.get("current_year")) == TYPE_INT, "current_year remains int after JSON round-trip")
	_check(typeof(restored.get("total_years")) == TYPE_INT, "total_years remains int after JSON round-trip")
	_check(typeof(restored.get("seed_count")) == TYPE_INT, "seed_count remains int after JSON round-trip")
	_check(typeof(restored.get("zero")) == TYPE_INT, "zero remains int after JSON round-trip")
	_check(typeof(restored.get("negative")) == TYPE_INT, "negative remains int after JSON round-trip")
	_check(typeof(restored.get("biomass")) == TYPE_FLOAT, "biomass remains float after JSON round-trip")
	_check(typeof(restored.get("transport")) == TYPE_VECTOR2, "Vector2 transport survives JSON round-trip")
	_check(typeof(restored.get("bounds")) == TYPE_RECT2, "Rect2 bounds survives JSON round-trip")
	_check(typeof(restored.get("history")) == TYPE_PACKED_STRING_ARRAY, "PackedStringArray history survives JSON round-trip")
	var nested: Array = restored.get("nested", [])
	_check(nested.size() == 2, "nested array shape preserved")
	if nested.size() == 2:
		_check(typeof(Dictionary(nested[0]).get("year")) == TYPE_INT, "nested year remains int")
		_check(typeof(Dictionary(nested[0]).get("count")) == TYPE_INT, "nested count remains int")
		_check(typeof(Dictionary(nested[0]).get("ratio")) == TYPE_FLOAT, "nested ratio remains float")
	var after_hash := Persistence.value_hash(restored)
	_check(before_hash == after_hash, "canonical value hash survives JSON round-trip exactly")
	print("ECO.EVO1-P2.8 Codec Preflight: PASS (%d assertions) value_hash=%s bytes=%d" % [assertions, before_hash, text.to_utf8_buffer().size()])
	_finish(true)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		push_error("ECO.EVO1-P2.8 codec preflight assertion failed: " + message)
		quit(1)

func _finish(success: bool) -> void:
	quit(0 if success else 1)

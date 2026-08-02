extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")

const DEFAULT_MAX_ENTRIES := 512

var _materials: Dictionary = {}
var _last_access: Dictionary = {}
var _clock := 0
var _hits := 0
var _misses := 0
var _evictions := 0
var _max_entries := DEFAULT_MAX_ENTRIES

func _init(max_entries: int = DEFAULT_MAX_ENTRIES) -> void:
	_max_entries = maxi(max_entries, 1)

func resolve(material_key: String) -> Dictionary:
	if material_key.is_empty() or material_key.length() > 128:
		return C.failure("INVALID_CONSTRUCTION_PROXY_MATERIAL_KEY")
	_clock += 1
	if _materials.has(material_key):
		_hits += 1
		_last_access[material_key] = _clock
		return C.success({"material": _materials[material_key], "cache_hit": true})
	_misses += 1
	_evict_for_insert()
	var material := StandardMaterial3D.new()
	material.resource_name = "ConstructionProxy_%s" % material_key
	material.roughness = 0.82
	material.metallic = 0.08
	material.set_meta("construction_proxy_material_key", material_key)
	_materials[material_key] = material
	_last_access[material_key] = _clock
	return C.success({"material": material, "cache_hit": false})

func get_material_count() -> int:
	return _materials.size()

func has_material(material_key: String) -> bool:
	return _materials.has(material_key)

func get_stats() -> Dictionary:
	return {
		"entries": _materials.size(),
		"hits": _hits,
		"misses": _misses,
		"evictions": _evictions,
		"max_entries": _max_entries,
	}

func clear() -> void:
	_materials.clear()
	_last_access.clear()

func _evict_for_insert() -> void:
	if _materials.size() < _max_entries:
		return
	var victim := ""
	var victim_access := 9223372036854775807
	var keys: Array = _materials.keys()
	keys.sort()
	for raw_key in keys:
		var key := String(raw_key)
		var access := int(_last_access.get(key, 0))
		if access < victim_access:
			victim = key
			victim_access = access
	if victim.is_empty():
		return
	_materials.erase(victim)
	_last_access.erase(victim)
	_evictions += 1

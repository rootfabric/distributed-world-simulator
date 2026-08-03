extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Artifact = preload("res://scripts/construction/proxies/construction_proxy_artifact.gd")
const Backend = preload("res://scripts/construction/proxies/construction_proxy_array_mesh_backend.gd")

const DEFAULT_MAX_ENTRIES := 256
const DEFAULT_MAX_GPU_BYTES := 134217728

var _backend
var _entries: Dictionary = {}
var _clock := 0
var _total_gpu_bytes := 0
var _hits := 0
var _misses := 0
var _evictions := 0
var _oversized_bypasses := 0
var _max_entries := DEFAULT_MAX_ENTRIES
var _max_gpu_bytes := DEFAULT_MAX_GPU_BYTES

func _init(max_entries: int = DEFAULT_MAX_ENTRIES, max_gpu_bytes: int = DEFAULT_MAX_GPU_BYTES, backend = null) -> void:
	_max_entries = maxi(max_entries, 1)
	_max_gpu_bytes = maxi(max_gpu_bytes, 1)
	_backend = backend if backend != null else Backend.new()

func materialize(artifact: Dictionary) -> Dictionary:
	var checked: Dictionary = Artifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	var content_hash := String(artifact["content_hash"])
	_clock += 1
	if _entries.has(content_hash):
		_hits += 1
		_entries[content_hash]["last_access"] = _clock
		return C.success({
			"mesh": _entries[content_hash]["mesh"],
			"descriptor": Dictionary(_entries[content_hash]["descriptor"]).duplicate(true),
			"cache_hit": true,
			"cache_bypassed": false,
		})
	_misses += 1
	var compiled: Dictionary = _backend.compile(artifact)
	if not bool(compiled.get("success", false)):
		return compiled
	var descriptor: Dictionary = compiled["descriptor"]
	var gpu_bytes := int(descriptor["estimated_gpu_bytes"])
	if gpu_bytes > _max_gpu_bytes:
		_oversized_bypasses += 1
		return C.success({
			"mesh": compiled["mesh"],
			"descriptor": descriptor,
			"cache_hit": false,
			"cache_bypassed": true,
		})
	_entries[content_hash] = {
		"mesh": compiled["mesh"],
		"descriptor": descriptor.duplicate(true),
		"gpu_bytes": gpu_bytes,
		"last_access": _clock,
	}
	_total_gpu_bytes += gpu_bytes
	_evict_to_budget(content_hash)
	return C.success({"mesh": compiled["mesh"], "descriptor": descriptor, "cache_hit": false, "cache_bypassed": false})

func clear() -> void:
	_entries.clear()
	_total_gpu_bytes = 0

func get_entry_count() -> int:
	return _entries.size()

func get_total_gpu_bytes() -> int:
	return _total_gpu_bytes

func has_content_hash(content_hash: String) -> bool:
	return _entries.has(content_hash)

func get_mesh(content_hash: String):
	return _entries.get(content_hash, {}).get("mesh", null)

func get_descriptor(content_hash: String) -> Dictionary:
	return Dictionary(_entries.get(content_hash, {})).get("descriptor", {}).duplicate(true)

func get_stats() -> Dictionary:
	return {
		"entries": _entries.size(),
		"gpu_bytes": _total_gpu_bytes,
		"hits": _hits,
		"misses": _misses,
		"evictions": _evictions,
		"oversized_bypasses": _oversized_bypasses,
		"max_entries": _max_entries,
		"max_gpu_bytes": _max_gpu_bytes,
	}

func _evict_to_budget(protected_hash: String) -> void:
	while _entries.size() > _max_entries or _total_gpu_bytes > _max_gpu_bytes:
		if _entries.size() <= 1:
			break
		var victim := ""
		var victim_access := 9223372036854775807
		var hashes: Array = _entries.keys()
		hashes.sort()
		for raw_hash in hashes:
			var content_hash := String(raw_hash)
			if content_hash == protected_hash:
				continue
			var access := int(_entries[content_hash]["last_access"])
			if access < victim_access:
				victim = content_hash
				victim_access = access
		if victim.is_empty():
			break
		_total_gpu_bytes -= int(_entries[victim]["gpu_bytes"])
		_entries.erase(victim)
		_evictions += 1

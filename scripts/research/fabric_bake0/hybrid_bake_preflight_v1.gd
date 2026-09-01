extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ModeSignature = preload("res://scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd")
const ModeDescriptor = preload("res://scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd")
const Transition = preload("res://scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd")
const CacheEntry = preload("res://scripts/research/fabric_bake0/lazy_mode_cache_entry_v1.gd")

const FALLBACKS: Array[String] = ["FULL", "NO_SAFE_BAKE"]

static func validate_bundle(mode_descriptors: Array, transitions: Array, cache_entries: Array) -> Dictionary:
	var modes_by_hash := {}
	var cache_keys := {}
	for index in range(mode_descriptors.size()):
		var raw = mode_descriptors[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_B0_5_MODE_DESCRIPTOR", {"index": index})
		var descriptor: Dictionary = raw
		var checked: Dictionary = ModeDescriptor.validate(descriptor)
		if not bool(checked.get("success", false)):
			return checked
		var mode_hash := String(descriptor["mode_signature"]["mode_hash"])
		if modes_by_hash.has(mode_hash):
			return Utils.failure("DUPLICATE_B0_5_MODE_HASH", {"mode_hash": mode_hash})
		modes_by_hash[mode_hash] = descriptor
	for index in range(transitions.size()):
		var raw = transitions[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_B0_5_TRANSITION", {"index": index})
		var transition: Dictionary = raw
		var checked: Dictionary = Transition.validate(transition)
		if not bool(checked.get("success", false)):
			return checked
		if not modes_by_hash.has(String(transition["from_mode_hash"])):
			return Utils.failure("B0_5_TRANSITION_FROM_MODE_UNKNOWN")
		if not modes_by_hash.has(String(transition["to_mode_hash"])):
			return Utils.failure("B0_5_TRANSITION_TO_MODE_UNKNOWN")
		var from_descriptor: Dictionary = modes_by_hash[String(transition["from_mode_hash"])]
		var to_descriptor: Dictionary = modes_by_hash[String(transition["to_mode_hash"])]
		if String(from_descriptor["mode_signature"]["source_frontier_hash"]) != String(transition["source_frontier_hash"]):
			return Utils.failure("B0_5_TRANSITION_FRONTIER_MISMATCH")
		if String(to_descriptor["mode_signature"]["source_frontier_hash"]) != String(transition["source_frontier_hash"]):
			return Utils.failure("B0_5_TRANSITION_FRONTIER_MISMATCH")
	for index in range(cache_entries.size()):
		var raw = cache_entries[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_B0_5_CACHE_ENTRY", {"index": index})
		var entry: Dictionary = raw
		var checked: Dictionary = CacheEntry.validate(entry)
		if not bool(checked.get("success", false)):
			return checked
		if cache_keys.has(String(entry["cache_key"])):
			return Utils.failure("DUPLICATE_B0_5_CACHE_KEY")
		cache_keys[String(entry["cache_key"])] = true
		if not modes_by_hash.has(String(entry["mode_hash"])):
			return Utils.failure("B0_5_CACHE_MODE_UNKNOWN")
		var descriptor: Dictionary = modes_by_hash[String(entry["mode_hash"])]
		checked = CacheEntry.validate_against(entry, descriptor["mode_signature"], descriptor)
		if not bool(checked.get("success", false)):
			return checked
	return Utils.success({
		"mode_count": mode_descriptors.size(),
		"transition_count": transitions.size(),
		"cache_entry_count": cache_entries.size(),
		"execution_authorized": false,
	})

static func lookup_mode(
	mode_signature: Dictionary,
	mode_descriptor: Dictionary,
	cache_entries: Array,
	fallback: String = "FULL"
) -> Dictionary:
	if not FALLBACKS.has(fallback):
		return Utils.failure("INVALID_B0_5_FALLBACK")
	var checked: Dictionary = ModeSignature.validate(mode_signature)
	if not bool(checked.get("success", false)):
		return checked
	checked = ModeDescriptor.validate(mode_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	if String(mode_descriptor["mode_signature"]["mode_hash"]) != String(mode_signature["mode_hash"]):
		return Utils.failure("B0_5_DESCRIPTOR_MODE_MISMATCH")
	if String(mode_descriptor["dynamic_rom_binding"]["interface_kind"]) == "UNRESOLVED_B0_4_INTERFACE":
		return Utils.success({
			"action": "FALLBACK",
			"fallback": fallback,
			"reason": "B0_4_INTERFACE_UNRESOLVED",
			"cache_key": mode_descriptor["cache_key"],
			"execution_authorized": false,
		})
	for raw in cache_entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw
		if String(entry.get("cache_key", "")) != String(mode_descriptor["cache_key"]):
			continue
		checked = CacheEntry.validate_against(entry, mode_signature, mode_descriptor)
		if not bool(checked.get("success", false)):
			return Utils.success({
				"action": "FALLBACK",
				"fallback": fallback,
				"reason": String(checked.get("error_code", "CACHE_INVALID")),
				"cache_key": mode_descriptor["cache_key"],
				"execution_authorized": false,
			})
		if String(entry["validity_state"]) != "VALID":
			return Utils.success({
				"action": "FALLBACK",
				"fallback": fallback,
				"reason": String(entry["invalidation_reason"]),
				"cache_key": mode_descriptor["cache_key"],
				"execution_authorized": false,
			})
		return Utils.success({
			"action": "CACHE_ENTRY_MATCH",
			"fallback": "",
			"reason": "EXACT_MODE_CACHE_MATCH",
			"cache_key": entry["cache_key"],
			"execution_authorized": false,
		})
	return Utils.success({
		"action": "COMPILE_REQUIRED",
		"fallback": fallback,
		"reason": "EXACT_MODE_CACHE_MISS",
		"cache_key": mode_descriptor["cache_key"],
		"execution_authorized": false,
	})

static func unknown_mode_fallback(mode_signature: Dictionary, cache_entries: Array, fallback: String = "FULL") -> Dictionary:
	if not FALLBACKS.has(fallback):
		return Utils.failure("INVALID_B0_5_FALLBACK")
	var checked: Dictionary = ModeSignature.validate(mode_signature)
	if not bool(checked.get("success", false)):
		return checked
	for raw in cache_entries:
		if typeof(raw) == TYPE_DICTIONARY and String(raw.get("mode_hash", "")) == String(mode_signature["mode_hash"]):
			return Utils.failure("B0_5_UNKNOWN_MODE_PROBE_MATCHED_EXACT_CACHE")
	return Utils.success({
		"action": "FALLBACK",
		"fallback": fallback,
		"reason": "UNKNOWN_PHYSICAL_MODE",
		"nearest_mode_reuse": false,
		"execution_authorized": false,
	})

static func reconcile_cache(
	entry: Dictionary,
	current_signature: Dictionary,
	current_descriptor: Dictionary
) -> Dictionary:
	var checked: Dictionary = CacheEntry.validate(entry)
	if not bool(checked.get("success", false)):
		return checked
	checked = ModeSignature.validate(current_signature)
	if not bool(checked.get("success", false)):
		return checked
	checked = ModeDescriptor.validate(current_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	var reason := CacheEntry.detect_invalidation(entry, current_signature, current_descriptor)
	if reason == "NONE":
		return Utils.success({"entry": entry.duplicate(true), "changed": false, "reason": reason})
	var stale := CacheEntry.invalidate(entry, reason)
	if stale.is_empty():
		return Utils.failure("B0_5_CACHE_INVALIDATION_FAILED")
	return Utils.success({"entry": stale, "changed": true, "reason": reason})

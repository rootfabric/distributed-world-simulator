extends RefCounted

# R31b P1 — source-fenced immutable durable chunk cache.
#
# Server-only, default OFF, opt-in via DWS_NET_R31BP1_DURABLE_CHUNKS=1 /
# --r31bp1-durable-chunks. Caches ONLY the M4 Item Graph and ResourceMining
# durable components between quiescent authority exports. This is an
# implementation candidate, NOT a verified performance fix.
#
# Invariants:
# - A cached chunk may be reused only when owner, epoch, revision/generation,
#   instance identity and monotone state serial ALL match the live source
#   fence. Any mismatch is a miss and re-exports from source (fail CLOSED).
# - Exactly two private chunks; each at most MAX_CHUNK_BYTES (4 MiB). An
#   oversize component bypasses with the unchanged full component export and
#   is measured, never hidden.
# - The cache never hands out its private snapshot: every hit returns
#   duplicate(true), and every miss independently clones the fresh source
#   export into the private store.
# - No live data, Node or Resource reference ever enters the cache: the stored
#   value is a detached JSON-safe DTO duplicate.
# - The cached payload is byte-equal to the legacy component export, so the
#   final durable payload and disk checkpoint remain exactly equal to legacy.

const MAX_CHUNK_BYTES := 4 * 1024 * 1024

const COMPONENT_KINDS := ["item_graph", "resource_mining"]

var _enabled := false
var _chunks: Dictionary = {}
var _metrics: Dictionary = {}


func configure(enabled: bool) -> Dictionary:
	if not enabled is bool:
		return _failure("R31BP1_CHUNK_CACHE_INVALID_MODE")
	_enabled = bool(enabled)
	_chunks = {}
	_metrics = {
		"item_graph": _fresh_component_metrics(),
		"resource_mining": _fresh_component_metrics(),
	}
	return _success({"enabled": _enabled})


func is_enabled() -> bool:
	return _enabled


# Returns {"value": Dictionary, "hit": bool, "bypass": String, "bytes": int}.
# `value` is always a private-to-caller duplicate(true); on bypass or source
# failure the caller receives the unchanged full component export result.
func export_component(service, kind: String) -> Dictionary:
	if not _enabled:
		return _failure("R31BP1_CHUNK_CACHE_DISABLED")
	if kind not in COMPONENT_KINDS or service == null or not service.has_method("get_r31bp1_chunk_fence") or not service.has_method("export_durable_state"):
		return _failure("R31BP1_CHUNK_CACHE_COMPONENT_INVALID")
	var fence: Dictionary = service.get_r31bp1_chunk_fence()
	if fence.is_empty() or String(fence.get("kind", "")) != kind:
		return _failure("R31BP1_CHUNK_CACHE_FENCE_INVALID")
	if _chunk_bytes_within_budget(_chunks.get(kind, {})):
		var cached: Dictionary = _chunks.get(kind, {})
		if _fence_matches(Dictionary(cached.get("fence", {})), fence):
			_metrics[kind]["hits"] = int(_metrics[kind]["hits"]) + 1
			return {
				"value": Dictionary(cached.get("chunk", {})).duplicate(true),
				"hit": true,
				"bypass": "",
				"bytes": int(cached.get("bytes", 0)),
			}
	var began_us: int = Time.get_ticks_usec()
	var source: Dictionary = service.export_durable_state()
	var export_ms: float = float(Time.get_ticks_usec() - began_us) / 1000.0
	_metrics[kind]["misses"] = int(_metrics[kind]["misses"]) + 1
	if source.is_empty():
		# Fail CLOSED: never serve a stale chunk when the source cannot export.
		_chunks.erase(kind)
		_note_bypass(kind, "SOURCE_EXPORT_EMPTY")
		return {"value": {}, "hit": false, "bypass": "SOURCE_EXPORT_EMPTY", "bytes": 0}
	# Deterministic future-proof fence: no source callback may change its
	# revision/epoch/serial while materializing a cacheable snapshot. No
	# second exporter invocation can make that mixed snapshot coherent.
	var after_fence: Dictionary = service.get_r31bp1_chunk_fence()
	if not _fence_matches(fence, after_fence):
		_chunks.erase(kind)
		_note_bypass(kind, "SOURCE_FENCE_CHANGED")
		return {"value": {}, "hit": false, "bypass": "SOURCE_FENCE_CHANGED", "bytes": 0}
	var bytes := _json_byte_size(source)
	if bytes > MAX_CHUNK_BYTES:
		# Oversize bypass: unchanged full component export, measured, not hidden.
		_chunks.erase(kind)
		_note_bypass(kind, "CHUNK_OVERSIZE")
		_metrics[kind]["bytes"] = 0
		return {
			"value": source.duplicate(true),
			"hit": false,
			"bypass": "CHUNK_OVERSIZE",
			"bytes": bytes,
			"export_ms": export_ms,
		}
	# Independent clone into the private store; the caller gets another clone.
	_chunks[kind] = {
		"fence": fence.duplicate(true),
		"chunk": source.duplicate(true),
		"bytes": bytes,
	}
	_metrics[kind]["bytes"] = bytes
	return {"value": source.duplicate(true), "hit": false, "bypass": "", "bytes": bytes}


func get_report() -> Dictionary:
	var report: Dictionary = {"enabled": _enabled, "max_chunk_bytes": MAX_CHUNK_BYTES}
	for kind in COMPONENT_KINDS:
		var component: Dictionary = Dictionary(_metrics.get(kind, _fresh_component_metrics())).duplicate(true)
		component["cached"] = _chunks.has(kind)
		component["fence"] = Dictionary(Dictionary(_chunks.get(kind, {}).get("fence", {}))).duplicate(true)
		report[kind] = component
	return report


func _fence_matches(stored: Dictionary, live: Dictionary) -> bool:
	if stored.is_empty() or live.is_empty():
		return false
	for field in ["kind", "instance_id", "authority_owner_id", "authority_epoch", "state_serial"]:
		if stored.get(field, null) != live.get(field, null):
			return false
	# ItemGraph's snapshot includes BOTH revision and tick; ownership
	# changes outside the main command path also have a separate serial.
	if String(live.get("kind", "")) == "item_graph":
		return (
			stored.get("revision", null) == live.get("revision", null)
			and stored.get("tick", null) == live.get("tick", null)
		)
	return stored.get("generation", null) == live.get("generation", null)


func _chunk_bytes_within_budget(entry) -> bool:
	return (
		entry is Dictionary and not entry.is_empty()
		and int(entry.get("bytes", 0)) > 0
		and int(entry.get("bytes", 0)) <= MAX_CHUNK_BYTES
	)


func _json_byte_size(value: Dictionary) -> int:
	return JSON.stringify(value).to_utf8_buffer().size()


func _note_bypass(kind: String, reason: String) -> void:
	_metrics[kind]["bypasses"] = int(_metrics[kind]["bypasses"]) + 1
	var reasons: Dictionary = Dictionary(_metrics[kind].get("bypass_reasons", {}))
	reasons[reason] = int(reasons.get(reason, 0)) + 1
	_metrics[kind]["bypass_reasons"] = reasons


func _fresh_component_metrics() -> Dictionary:
	return {
		"hits": 0, "misses": 0, "bypasses": 0, "bytes": 0,
		"bypass_reasons": {},
	}


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}

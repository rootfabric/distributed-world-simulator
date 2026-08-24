extends RefCounted

## EG4 bounded dynamic upstream set: the gateway keeps AT MOST cap ACTIVE
## upstream projection sources, with least-recently-active eviction of idle
## sources when the cap is hit.
##
## Discipline: sources are identified by canonical authority ids only. The set
## never invents connectivity and never guesses: registering beyond the cap
## either evicts an IDLE source (explicitly marked) or fails closed with
## UPSTREAM_SET_FULL.

const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.eg4_upstream_set.v1"
const DEFAULT_CAP := 4

var _cap: int = DEFAULT_CAP
# source_authority_id -> {"recency": int, "idle": bool}
var _sources: Dictionary = {}
var _recency_clock: int = 0
var _counters := {
	"registered": 0,
	"evicted_lru": 0,
	"released": 0,
	"rejected_full": 0,
}


func configure(options: Dictionary) -> Dictionary:
	for key in options.keys():
		var value = options[key]
		match String(key):
			"cap":
				if not GatewayUtilsScript.require_positive_integer(options, "cap").get("success", false):
					return _failure("INVALID_OPTION", {"option": "cap"})
				_cap = int(value)
			_:
				return _failure("UNKNOWN_OPTION", {"option": String(key)})
	return _success({})


## Register a source as ACTIVE-upstream. When the set is full, the LEAST
## recently-active IDLE source is evicted (returned in details.evicted); if no
## source is evictable the registration FAILS CLOSED.
func register(source_authority_id: String) -> Dictionary:
	var check: Dictionary = _require_source_id(source_authority_id)
	if not bool(check.get("success", false)):
		return check
	if _sources.has(source_authority_id):
		_note_activity(source_authority_id)
		return _success({"already_registered": true, "evicted": ""})
	var evicted := ""
	if _sources.size() >= _cap:
		evicted = _evict_least_recently_active_idle()
		if evicted.is_empty():
			_counters["rejected_full"] = int(_counters["rejected_full"]) + 1
			return _failure("UPSTREAM_SET_FULL", {
				"cap": _cap,
				"source_authority_id": source_authority_id,
			})
		_counters["evicted_lru"] = int(_counters["evicted_lru"]) + 1
	_recency_clock += 1
	_sources[source_authority_id] = {"recency": _recency_clock, "idle": false}
	_counters["registered"] = int(_counters["registered"]) + 1
	return _success({"already_registered": false, "evicted": evicted})


## Traffic evidence: bumps LRU recency and clears the idle mark.
func note_activity(source_authority_id: String) -> Dictionary:
	if not _sources.has(source_authority_id):
		return _failure("UNKNOWN_SOURCE", {"source_authority_id": source_authority_id})
	_note_activity(source_authority_id)
	return _success({})


## Mark a source idle: eligible for LRU eviction under cap pressure.
func mark_idle(source_authority_id: String) -> Dictionary:
	if not _sources.has(source_authority_id):
		return _failure("UNKNOWN_SOURCE", {"source_authority_id": source_authority_id})
	_sources[source_authority_id]["idle"] = true
	return _success({})


func is_idle(source_authority_id: String) -> bool:
	return bool(_sources.get(source_authority_id, {}).get("idle", false))


## Explicit removal (detach, source loss, maintenance).
func release(source_authority_id: String) -> Dictionary:
	if not _sources.has(source_authority_id):
		return _failure("UNKNOWN_SOURCE", {"source_authority_id": source_authority_id})
	_sources.erase(source_authority_id)
	_counters["released"] = int(_counters["released"]) + 1
	return _success({"released": source_authority_id})


func has(source_authority_id: String) -> bool:
	return _sources.has(source_authority_id)


func size() -> int:
	return _sources.size()


func cap() -> int:
	return _cap


func sources() -> Array[String]:
	var output: Array[String] = []
	for source_value in _sources.keys():
		output.append(String(source_value))
	output.sort()
	return output


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"cap": _cap,
		"size": _sources.size(),
		"sources": sources(),
		"idle_sources": _idle_sources(),
		"counters": _counters.duplicate(true),
	}


## ---- internals ---------------------------------------------------------------


func _note_activity(source_authority_id: String) -> void:
	_recency_clock += 1
	_sources[source_authority_id]["recency"] = _recency_clock
	_sources[source_authority_id]["idle"] = false


func _idle_sources() -> Array[String]:
	var output: Array[String] = []
	for source_value in _sources.keys():
		var source := String(source_value)
		if bool(_sources[source]["idle"]):
			output.append(source)
	output.sort()
	return output


func _evict_least_recently_active_idle() -> String:
	var best := ""
	var best_recency := -1
	for source_value in _sources.keys():
		var source := String(source_value)
		if not bool(_sources[source]["idle"]):
			continue
		var recency := int(_sources[source]["recency"])
		if best.is_empty() or recency < best_recency:
			best = source
			best_recency = recency
	if not best.is_empty():
		_sources.erase(best)
	return best


func _require_source_id(source_authority_id: String) -> Dictionary:
	return GatewayUtilsScript.require_id(
			{"source_authority_id": source_authority_id}, "source_authority_id", "authority")


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "details": details}


func _failure(error_code: String, details: Dictionary) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}

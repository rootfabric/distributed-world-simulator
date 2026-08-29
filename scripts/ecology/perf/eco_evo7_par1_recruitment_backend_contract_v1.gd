extends RefCounted

## ECO.EVO7 PAR1 — direct parallel recruitment backend contract (v1).
##
## PAR1 compares two DIRECT parallel backends with an identical contract:
##   A. PROCESS_POOL  — persistent OS worker processes (PAR0 pool, reused
##                      transport, no serial oracle inside);
##   B. WORKER_THREAD_POOL — Godot WorkerThreadPool group tasks.
##
## Contract (both backends return exactly this shape):
##   evaluate_generation(generation, candidates, routes, immutable_context)
##     -> {
##       success: bool,
##       backend: String,            # "PROCESS_POOL" | "WORKER_THREAD_POOL"
##       worker_count: int,
##       canonical_events: Array[Dictionary],  # sorted by candidate_hash
##       canonical_hash: String,      # frozen LS3.3 recruitment-pool hash
##       failure_code: String,        # "" when success
##       failure_detail: String,
##       timings_ms: { ... backend-specific noncanonical telemetry }
##     }
##
## Shared invariants (enforced by both backends):
##   - input canonicalization: items sorted by candidate_hash, routes matched
##     by candidate_hash, sizes must agree;
##   - no serial oracle inside a backend;
##   - every event is stamped with recruitment_event_hash exactly as the
##     serial LS3.3 path does (Par0Kernel.recruitment_event_hash);
##   - canonical merge sorts by candidate_hash, never by completion order;
##   - aggregate hash recomputed on the coordinator with the frozen formula;
##   - FAIL CLOSED: any worker error/timeout/stale/missing response returns
##     success=false and NO canonical result. Never fall back to serial.

const Kernel = preload("res://scripts/ecology/perf/eco_evo7_par0_recruitment_kernel_v1.gd")

const BACKEND_PROCESS := "PROCESS_POOL"
const BACKEND_WORKER_THREAD := "WORKER_THREAD_POOL"

const CONTRACT_SCHEMA := "distributed_world_simulator.ecology.evo7_par1_recruitment_backend_contract.v1"
const CONTRACT_VERSION := "1.0.0"

## Canonical (candidate, route) item list, sorted by candidate_hash.
## Returns [] on identity mismatch (fail-closed input rejection).
static func canonical_items(candidates: Array, routes: Array) -> Array:
	var route_by_hash := {}
	for route_value in routes:
		var route: Dictionary = route_value
		route_by_hash[String(route["candidate_hash"])] = route
	var items: Array = []
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var candidate_hash := String(candidate["candidate_hash"])
		if not route_by_hash.has(candidate_hash):
			return []
		items.append({"candidate": candidate, "route": route_by_hash[candidate_hash]})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate"]["candidate_hash"]) < String(b["candidate"]["candidate_hash"])
	)
	return items

## Frozen LS3.3 recruitment-pool aggregate hash (identical formula to
## LS3.3 _recruitment_hash / PAR0.2 executor _recruitment_hash).
static func recruitment_hash(events: Array, context: Dictionary) -> String:
	var hashes := PackedStringArray()
	for event in events:
		hashes.append(String(event.get("recruitment_event_hash", "")))
	hashes.sort()
	return (String(context["schema"]) + "|" + String(context["version"]) + "|recruitment-pool|" + "|".join(hashes)).sha256_text()

## Serial reference evaluation over the SAME canonical items using the SAME
## kernel (test/benchmark oracle only — never part of a backend).
static func serial_evaluate(items: Array, context: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_value in items:
		var item: Dictionary = item_value
		var event_result := Kernel.evaluate_recruitment_event(
			item["candidate"], item["route"], context)
		if event_result.is_empty():
			return []
		var event: Dictionary = event_result
		event["recruitment_event_hash"] = Kernel.recruitment_event_hash(
			event, String(context["schema"]), String(context["version"]))
		out.append(event)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["candidate_hash"]) < String(b["candidate_hash"])
	)
	return out

## Validate a backend result against the contract shape.
static func validate_result(result: Dictionary, backend: String) -> bool:
	if typeof(result) != TYPE_DICTIONARY:
		return false
	if bool(result.get("success", false)):
		if String(result.get("backend", "")) != backend:
			return false
		if int(result.get("worker_count", 0)) < 1:
			return false
		var events_value = result.get("canonical_events")
		if not events_value is Array or (events_value as Array).is_empty():
			return false
		if String(result.get("canonical_hash", "")).is_empty():
			return false
		if String(result.get("failure_code", "")) != "":
			return false
		if not result.has("timings_ms"):
			return false
		return true
	if String(result.get("failure_code", "")).is_empty():
		return false
	return true

## Exact byte-level event comparison (PAR0 comparator semantics).
## Untyped arrays on purpose: backends return Array[Dictionary] while test
## fixtures may carry untyped arrays of dictionaries.
static func events_exact(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		var left: Dictionary = a[index]
		var right: Dictionary = b[index]
		for key in left.keys():
			if not right.has(key) or left[key] != right[key]:
				return false
		if left.keys().size() != right.keys().size():
			return false
	return true

extends RefCounted

## N3 R0a: deterministic single-coordinator REGION lease and route contract.
## It is NOT a distributed lock or durable lease store. All mutating methods
## must be invoked only by a trusted control-plane owner, never client input.
## No gameplay writes may use these receipts until a durable, globally fenced
## B1/B2 owner and the canonical mutation-admission port are integrated.

const SCHEMA := "planet_simulator.n3_region_lease_directory.v1"
const MAX_SAFE_INTEGER: int = 9007199254740991
const MIN_TTL_MS := 100
const MAX_TTL_MS := 3600000
const ROUTE_FIELDS: Array[String] = [
	"world_id", "region_id", "authority_id", "server_instance_id",
	"lease_generation", "route_revision", "expires_at_ms",
]

var _leases: Dictionary = {}
var _claims: Dictionary = {}
var _last_clock_ms: int = -1
var _directory_available := true


## expected_generation=0 for a previously unseen region. After expiry/release,
## the next acquire must CAS against the previous generation. A restarted
## authority must use a NEW claim_id and is issued a NEW generation.
func acquire_region(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, claim_id: String, expected_generation: int,
		ttl_ms: int, now_ms: int) -> Dictionary:
	var validation := _validate_ids(world_id, region_id, authority_id, server_instance_id, claim_id)
	if not bool(validation.get("success", false)):
		return validation
	var ttl := _validate_ttl(ttl_ms, now_ms)
	if not bool(ttl.get("success", false)):
		return ttl
	var clock := _check_clock(now_ms)
	if not bool(clock.get("success", false)):
		return clock
	if not _directory_available:
		return _fail("DIRECTORY_UNAVAILABLE")
	var key := _key(world_id, region_id)
	if _claims.has(claim_id):
		var old_claim: Dictionary = _claims[claim_id]
		if String(old_claim["key"]) != key or String(old_claim["authority_id"]) != authority_id \
				or String(old_claim["server_instance_id"]) != server_instance_id \
				or int(old_claim["expected_generation"]) != expected_generation \
				or int(old_claim["ttl_ms"]) != ttl_ms:
			return _fail("CLAIM_ID_CONFLICT")
		if not _leases.has(key):
			return _fail("CLAIM_REPLAY_STALE")
		var replay_lease: Dictionary = _leases[key]
		if _is_active(replay_lease, now_ms) and int(replay_lease["lease_generation"]) == int(old_claim["lease_generation"]) \
				and String(replay_lease["claim_id"]) == claim_id:
			return _ok({"route": _route(replay_lease), "duplicate": true})
		return _fail("CLAIM_REPLAY_STALE")
	var generation := 0
	var route_revision := 0
	if _leases.has(key):
		var previous: Dictionary = _leases[key]
		generation = int(previous["lease_generation"])
		route_revision = int(previous["route_revision"])
		if _is_active(previous, now_ms):
			return _fail("REGION_LEASE_CONFLICT")
	if expected_generation != generation:
		return _fail("STALE_LEASE_GENERATION")
	if generation >= MAX_SAFE_INTEGER or route_revision >= MAX_SAFE_INTEGER:
		return _fail("LEASE_COUNTER_EXHAUSTED")
	var lease := {
		"world_id": world_id,
		"region_id": region_id,
		"authority_id": authority_id,
		"server_instance_id": server_instance_id,
		"claim_id": claim_id,
		"lease_generation": generation + 1,
		"route_revision": route_revision + 1,
		"expires_at_ms": now_ms + ttl_ms,
		"healthy": true,
		"released": false,
	}
	_leases[key] = lease
	_claims[claim_id] = {
		"key": key, "authority_id": authority_id,
		"server_instance_id": server_instance_id,
		"expected_generation": expected_generation, "ttl_ms": ttl_ms,
		"lease_generation": generation + 1,
	}
	return _ok({"route": _route(lease), "duplicate": false})


## renewal_sequence prevents a delayed duplicate heartbeat from extending TTL.
func renew_region(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, lease_generation: int, expected_route_revision: int,
		ttl_ms: int, now_ms: int) -> Dictionary:
	var ttl := _validate_ttl(ttl_ms, now_ms)
	if not bool(ttl.get("success", false)):
		return ttl
	var current := _current_writer(world_id, region_id, authority_id, server_instance_id, lease_generation, now_ms)
	if not bool(current.get("success", false)):
		return current
	var lease: Dictionary = _leases[_key(world_id, region_id)]
	if int(lease["route_revision"]) != expected_route_revision:
		return _fail("STALE_ROUTE_REVISION")
	if expected_route_revision >= MAX_SAFE_INTEGER:
		return _fail("LEASE_COUNTER_EXHAUSTED")
	lease["route_revision"] = expected_route_revision + 1
	lease["expires_at_ms"] = maxi(int(lease["expires_at_ms"]), now_ms + ttl_ms)
	return _ok({"route": _route(lease)})


func set_region_health(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, lease_generation: int, expected_route_revision: int,
		healthy: bool, now_ms: int) -> Dictionary:
	var current := _current_writer(world_id, region_id, authority_id, server_instance_id, lease_generation, now_ms, false)
	if not bool(current.get("success", false)):
		return current
	var lease: Dictionary = _leases[_key(world_id, region_id)]
	if int(lease["route_revision"]) != expected_route_revision:
		return _fail("STALE_ROUTE_REVISION")
	if bool(lease["healthy"]) != healthy:
		if expected_route_revision >= MAX_SAFE_INTEGER:
			return _fail("LEASE_COUNTER_EXHAUSTED")
		lease["route_revision"] = expected_route_revision + 1
		lease["healthy"] = healthy
	return _ok({"route": _route(lease), "healthy": healthy})


func release_region(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, lease_generation: int, now_ms: int) -> Dictionary:
	var current := _current_writer(world_id, region_id, authority_id, server_instance_id, lease_generation, now_ms, false)
	if not bool(current.get("success", false)):
		return current
	var lease: Dictionary = _leases[_key(world_id, region_id)]
	if int(lease["route_revision"]) >= MAX_SAFE_INTEGER:
		return _fail("LEASE_COUNTER_EXHAUSTED")
	lease["route_revision"] = int(lease["route_revision"]) + 1
	lease["released"] = true
	lease["expires_at_ms"] = now_ms
	return _ok({"released_generation": lease_generation})


## Query-only: B0 request/reply may expose this projection; never endpoints,
## claim_id, or canonical player/item state.
func resolve_region(world_id: String, region_id: String, now_ms: int) -> Dictionary:
	var validation := _validate_region_ids(world_id, region_id)
	if not bool(validation.get("success", false)):
		return validation
	var clock := _check_clock(now_ms)
	if not bool(clock.get("success", false)):
		return clock
	if not _directory_available:
		return _fail("DIRECTORY_UNAVAILABLE")
	var key := _key(world_id, region_id)
	if not _leases.has(key):
		return _fail("REGION_NOT_FOUND")
	var lease: Dictionary = _leases[key]
	if not _is_active(lease, now_ms):
		return _fail("REGION_LEASE_EXPIRED")
	if not bool(lease["healthy"]):
		return _fail("REGION_UNHEALTHY")
	return _ok({"route": _route(lease)})


## Route verification is for diagnostics/control plane. Cached B0 replies
## are not write authority; canonical mutation admission needs a fresh check.
func verify_route(route: Dictionary, now_ms: int) -> Dictionary:
	if route.size() != ROUTE_FIELDS.size():
		return _fail("INVALID_ROUTE_FIELDS")
	for field in ROUTE_FIELDS:
		if not route.has(field):
			return _fail("INVALID_ROUTE_FIELDS")
	var current := resolve_region(str(route.get("world_id", "")), str(route.get("region_id", "")), now_ms)
	if not bool(current.get("success", false)):
		return current
	if Dictionary(current["details"]["route"]) != route:
		return _fail("STALE_ROUTE")
	return _ok({"valid": true})


func check_writer(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, lease_generation: int, now_ms: int) -> Dictionary:
	return _current_writer(world_id, region_id, authority_id, server_instance_id, lease_generation, now_ms)


func set_directory_available(available: bool) -> void:
	_directory_available = available


func get_report() -> Dictionary:
	var projection: Array = []
	for value in _leases.values():
		var lease: Dictionary = value
		projection.append({
			"world_id": lease["world_id"], "region_id": lease["region_id"],
			"authority_id": lease["authority_id"],
			"server_instance_id": lease["server_instance_id"],
			"lease_generation": lease["lease_generation"],
			"route_revision": lease["route_revision"],
			"expires_at_ms": lease["expires_at_ms"],
			"healthy": lease["healthy"], "released": lease["released"],
		})
	projection.sort_custom(func(a, b): return str(a["region_id"]) < str(b["region_id"]))
	return {"schema": SCHEMA, "regions": projection,
		"directory_available": _directory_available,
		"durable_distributed_lock": false, "canonical_writer_integrated": false}


func _current_writer(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, lease_generation: int, now_ms: int,
		require_healthy: bool = true) -> Dictionary:
	var ids := _validate_ids(world_id, region_id, authority_id, server_instance_id, "claim/internal-validation")
	if not bool(ids.get("success", false)):
		return ids
	var clock := _check_clock(now_ms)
	if not bool(clock.get("success", false)):
		return clock
	if not _directory_available:
		return _fail("DIRECTORY_UNAVAILABLE")
	var key := _key(world_id, region_id)
	if not _leases.has(key):
		return _fail("REGION_NOT_FOUND")
	var lease: Dictionary = _leases[key]
	if not _is_active(lease, now_ms):
		return _fail("REGION_LEASE_EXPIRED")
	if int(lease["lease_generation"]) != lease_generation:
		return _fail("STALE_LEASE_GENERATION")
	if String(lease["authority_id"]) != authority_id or String(lease["server_instance_id"]) != server_instance_id:
		return _fail("WRONG_REGION_OWNER")
	if require_healthy and not bool(lease["healthy"]):
		return _fail("REGION_UNHEALTHY")
	return _ok({"lease_generation": lease_generation})


func _is_active(lease: Dictionary, now_ms: int) -> bool:
	return not bool(lease["released"]) and now_ms < int(lease["expires_at_ms"])


func _validate_ttl(ttl_ms: int, now_ms: int) -> Dictionary:
	if ttl_ms < MIN_TTL_MS or ttl_ms > MAX_TTL_MS:
		return _fail("INVALID_LEASE_TTL")
	if now_ms < 0 or now_ms > MAX_SAFE_INTEGER - ttl_ms:
		return _fail("INVALID_CLOCK")
	return _ok({})


func _check_clock(now_ms: int) -> Dictionary:
	if now_ms < 0 or now_ms > MAX_SAFE_INTEGER:
		return _fail("INVALID_CLOCK")
	if now_ms < _last_clock_ms:
		return _fail("CLOCK_REGRESSION")
	_last_clock_ms = now_ms
	return _ok({})


func _validate_ids(world_id: String, region_id: String, authority_id: String,
		server_instance_id: String, claim_id: String) -> Dictionary:
	var region_check := _validate_region_ids(world_id, region_id)
	if not bool(region_check.get("success", false)):
		return region_check
	for item in [[authority_id, "authority"], [server_instance_id, "server-instance"], [claim_id, "claim"]]:
		if not _valid_id(str(item[0]), str(item[1])):
			return _fail("INVALID_CANONICAL_ID")
	return _ok({})


func _validate_region_ids(world_id: String, region_id: String) -> Dictionary:
	if not _valid_id(world_id, "world") or not _valid_id(region_id, "region"):
		return _fail("INVALID_CANONICAL_ID")
	return _ok({})


func _valid_id(value: String, prefix: String) -> bool:
	if value.length() < prefix.length() + 2 or value.length() > 192 \
			or value != value.to_lower() or value != value.strip_edges() \
			or not value.begins_with(prefix + "/") or value.contains("//") \
			or value.ends_with("/") or value.contains(":"):
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") \
				or (character >= "0" and character <= "9") \
				or character in ["-", "_", ".", "/"]):
			return false
	for segment in value.split("/", false):
		var all_ip_chars := str(segment).contains(".")
		for character in str(segment):
			if character != "." and (character < "0" or character > "9"):
				all_ip_chars = false
		if all_ip_chars:
			return false
	return true


func _key(world_id: String, region_id: String) -> String:
	return world_id + "|" + region_id


func _route(lease: Dictionary) -> Dictionary:
	var result := {}
	for field in ROUTE_FIELDS:
		result[field] = lease[field]
	return result


func _ok(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _fail(error_code: String) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": {}}

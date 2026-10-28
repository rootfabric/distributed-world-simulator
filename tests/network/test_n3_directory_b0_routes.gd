extends SceneTree

const Directory = preload("res://scripts/network/gateway/runtime/n3_region_lease_directory.gd")
const RouteService = preload("res://scripts/network/gateway/runtime/n3_directory_route_service.gd")
const DirectAdapter = preload("res://scripts/network/bus/adapters/in_memory_service_request_reply_adapter.gd")
const Request = preload("res://scripts/network/bus/service_request_envelope.gd")
const Response = preload("res://scripts/network/bus/service_response_envelope.gd")

class FakeClock:
	extends RefCounted
	var current_ms: int = 100
	func now_msec() -> int:
		return current_ms

var assertions := 0
var failures: Array[String] = []

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[n3-b0][FAIL] ", message)

func _response(value: Dictionary) -> Dictionary:
	return value.get("details", {}).get("response", {})

func _init() -> void:
	var d = Directory.new()
	var clock := FakeClock.new()
	var service = RouteService.new()
	_assert(bool(service.configure(d, clock).get("success", false)), "service configuration failed")
	var adapter = DirectAdapter.new("adapter/n3-directory-local")
	_assert(bool(adapter.register_handler(RouteService.SERVICE_ID, service).get("success", false)), "B0 service registration failed")
	var earth = d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a", "claim/a", 0, 500, 100)
	var moon = d.acquire_region("world/solar", "region/moon", "authority/b", "server-instance/b", "claim/b", 0, 500, 100)
	_assert(bool(earth.get("success", false)) and bool(moon.get("success", false)), "B0 fixture two region leases failed")
	var req_a := Request.create("request/n3/earth-1", RouteService.SERVICE_ID, RouteService.OPERATION,
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/earth"}, 100)
	var req_b := Request.create("request/n3/moon-1", RouteService.SERVICE_ID, RouteService.OPERATION,
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/moon"}, 100)
	var result_a: Dictionary = adapter.request(req_a)
	var result_b: Dictionary = adapter.request(req_b)
	_assert(bool(result_a.get("success", false)) and bool(result_b.get("success", false)), "B0 request/reply failed")
	var response_a: Dictionary = _response(result_a)
	var response_b: Dictionary = _response(result_b)
	_assert(bool(Response.validate(response_a).get("success", false)) and bool(Response.validate(response_b).get("success", false)), "B0 response contract invalid")
	_assert(str(response_a.get("payload", {}).get("route", {}).get("authority_id", "")) == "authority/a", "earth route owner wrong")
	_assert(str(response_b.get("payload", {}).get("route", {}).get("authority_id", "")) == "authority/b", "moon route owner wrong")
	_assert(response_a.get("payload_schema") == RouteService.ROUTE_SCHEMA, "B0 route payload schema mismatch")
	var bad_op := Request.create("request/n3/admin-deny", RouteService.SERVICE_ID, "acquire_region",
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/earth"}, 100)
	var blocked: Dictionary = _response(adapter.request(bad_op))
	_assert(not bool(blocked.get("success", true)) and str(blocked.get("error_code", "")) == "UNSUPPORTED_DIRECTORY_OPERATION", "control-plane mutation exposed to B0 client")
	var extra := Request.create("request/n3/extra-deny", RouteService.SERVICE_ID, RouteService.OPERATION,
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/earth", "authority_id": "authority/b"}, 100)
	var extra_res: Dictionary = _response(adapter.request(extra))
	_assert(not bool(extra_res.get("success", true)) and str(extra_res.get("error_code", "")) == "INVALID_ROUTE_QUERY", "caller-injected owner metadata accepted")
	var unknown := Request.create("request/n3/unknown", RouteService.SERVICE_ID, RouteService.OPERATION,
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/unknown"}, 100)
	var unknown_response: Dictionary = _response(adapter.request(unknown))
	_assert(not bool(unknown_response.get("success", true)) and str(unknown_response.get("error_code", "")) == "REGION_NOT_FOUND", "unknown region got route")
	clock.current_ms = 600
	var expired := Request.create("request/n3/earth-expired", RouteService.SERVICE_ID, RouteService.OPERATION,
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/earth"}, 100)
	var expired_response: Dictionary = _response(adapter.request(expired))
	_assert(not bool(expired_response.get("success", true)) and str(expired_response.get("error_code", "")) == "REGION_LEASE_EXPIRED", "expired route returned by fresh B0 lookup")
	var cached: Dictionary = adapter.request(req_a)
	_assert(bool(cached.get("details", {}).get("duplicate", false)), "B0 same-request ID replay not marked cached")
	_assert(d.verify_route(response_a.get("payload", {}).get("route", {}), 600).get("error_code") == "REGION_LEASE_EXPIRED", "cached B0 response bypassed live lease validation")
	var forbidden := Request.create("request/n3/broker-leak", RouteService.SERVICE_ID, RouteService.OPERATION,
			RouteService.REQUEST_SCHEMA, {"world_id": "world/solar", "region_id": "region/moon", "nats_subject": "world.leases"}, 100)
	var metadata_denied: Dictionary = adapter.request(forbidden)
	_assert(not bool(metadata_denied.get("success", true)), "B0 adapter-specific metadata accepted in route query")
	_finish()

func _finish() -> void:
	print(JSON.stringify({"test": "n3_directory_b0_routes", "verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

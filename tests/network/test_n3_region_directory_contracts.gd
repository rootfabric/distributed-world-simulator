extends SceneTree

const Directory = preload("res://scripts/network/gateway/runtime/n3_region_lease_directory.gd")

var assertions := 0
var failures: Array[String] = []

func _assert(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures.append(reason)
		print("[n3-r0][FAIL] ", reason)

func _err(value: Dictionary) -> String:
	return str(value.get("error_code", ""))

func _route(value: Dictionary) -> Dictionary:
	return Dictionary(value.get("details", {})).get("route", {})

func _ok(value: Dictionary) -> bool:
	return bool(value.get("success", false))

func _init() -> void:
	var d = Directory.new()
	_assert(_err(d.acquire_region("bad", "region/earth", "authority/a", "server-instance/a", "claim/a", 0, 500, 100)) == "INVALID_CANONICAL_ID", "bad world id accepted")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/127.0.0.1", "server-instance/a", "claim/a", 0, 500, 100)) == "INVALID_CANONICAL_ID", "IP-like authority admitted")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a", "claim/a", 0, 0, 100)) == "INVALID_LEASE_TTL", "zero ttl admitted")
	var earth = d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a", "claim/a", 0, 500, 100)
	var moon = d.acquire_region("world/solar", "region/moon", "authority/b", "server-instance/b", "claim/b", 0, 500, 100)
	_assert(_ok(earth) and _ok(moon), "two distinct regions were not leased")
	_assert(int(_route(earth).get("lease_generation", -1)) == 1, "first generation not 1")
	_assert(_route(d.resolve_region("world/solar", "region/earth", 101)).get("authority_id") == "authority/a", "earth routed to wrong owner")
	_assert(_route(d.resolve_region("world/solar", "region/moon", 101)).get("authority_id") == "authority/b", "moon routed to wrong owner")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/b", "server-instance/b", "claim/conflict", 1, 500, 110)) == "REGION_LEASE_CONFLICT", "conflicting owner admitted")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a2", "claim/restart", 1, 500, 111)) == "REGION_LEASE_CONFLICT", "same authority restart concurrently admitted")
	_assert(bool(d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a", "claim/a", 0, 500, 111).get("details", {}).get("duplicate", false)), "identical retry not idempotent")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a", "claim/a", 1, 500, 111)) == "CLAIM_ID_CONFLICT", "claim id reused with different CAS")
	_assert(_ok(d.check_writer("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 112)), "true active writer denied")
	_assert(_err(d.check_writer("world/solar", "region/earth", "authority/b", "server-instance/b", 1, 112)) == "WRONG_REGION_OWNER", "wrong writer admitted")
	_assert(_err(d.check_writer("world/solar", "region/earth", "authority/a", "server-instance/a2", 1, 112)) == "WRONG_REGION_OWNER", "wrong server instance admitted")
	_assert(_err(d.check_writer("world/solar", "region/earth", "authority/a", "server-instance/a", 0, 112)) == "STALE_LEASE_GENERATION", "stale generation admitted")
	var first_route: Dictionary = _route(earth)
	_assert(_ok(d.verify_route(first_route, 113)), "valid route rejected")
	var forged: Dictionary = first_route.duplicate(true)
	forged["nats_subject"] = "secret"
	_assert(_err(d.verify_route(forged, 114)) == "INVALID_ROUTE_FIELDS", "extra route metadata admitted")
	var changed: Dictionary = first_route.duplicate(true)
	changed["authority_id"] = "authority/b"
	_assert(_err(d.verify_route(changed, 115)) == "STALE_ROUTE", "forged authority route admitted")
	var renewed = d.renew_region("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 1, 500, 400)
	_assert(_ok(renewed) and int(_route(renewed).get("expires_at_ms", -1)) == 900, "renewal did not move expiry")
	_assert(int(_route(renewed).get("route_revision", -1)) == 2, "renewal did not fence cached routes")
	_assert(_err(d.renew_region("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 1, 500, 401)) == "STALE_ROUTE_REVISION", "duplicate delayed renewal changed ttl")
	_assert(_err(d.verify_route(first_route, 402)) == "STALE_ROUTE", "old route survived renewal")
	_assert(_ok(d.set_region_health("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 2, false, 403)), "health degraded failed")
	_assert(_err(d.resolve_region("world/solar", "region/earth", 404)) == "REGION_UNHEALTHY", "unhealthy region resolved")
	_assert(_err(d.check_writer("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 404)) == "REGION_UNHEALTHY", "unhealthy writer accepted")
	_assert(_ok(d.set_region_health("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 3, true, 405)), "health restore failed")
	_assert(_ok(d.resolve_region("world/solar", "region/earth", 406)), "restored region could not resolve")
	_assert(_ok(d.release_region("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 407)), "release failed")
	_assert(_err(d.resolve_region("world/solar", "region/earth", 407)) == "REGION_LEASE_EXPIRED", "released lease still visible")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/b", "server-instance/b", "claim/stale-cas", 0, 500, 407)) == "STALE_LEASE_GENERATION", "stale CAS after release admitted")
	var reacquired = d.acquire_region("world/solar", "region/earth", "authority/b", "server-instance/b", "claim/reacquire", 1, 500, 408)
	_assert(_ok(reacquired) and int(_route(reacquired).get("lease_generation", -1)) == 2, "reacquire generation did not advance")
	_assert(_err(d.check_writer("world/solar", "region/earth", "authority/a", "server-instance/a", 1, 408)) == "STALE_LEASE_GENERATION", "former writer survived re-acquire")
	_assert(_err(d.acquire_region("world/solar", "region/earth", "authority/a", "server-instance/a", "claim/a", 0, 500, 409)) == "CLAIM_REPLAY_STALE", "stale claim replay resurrected writer")
	_assert(_ok(d.check_writer("world/solar", "region/moon", "authority/b", "server-instance/b", 1, 409)), "independent moon region lost writer")
	d.set_directory_available(false)
	_assert(_err(d.resolve_region("world/solar", "region/moon", 410)) == "DIRECTORY_UNAVAILABLE", "directory outage resolved a route")
	_assert(_err(d.check_writer("world/solar", "region/moon", "authority/b", "server-instance/b", 1, 410)) == "DIRECTORY_UNAVAILABLE", "outage admitted write")
	d.set_directory_available(true)
	_assert(_err(d.resolve_region("world/solar", "region/moon", 409)) == "CLOCK_REGRESSION", "clock rollback admitted")
	_assert(_ok(d.resolve_region("world/solar", "region/moon", 411)), "moon route did not recover")
	_assert(_err(d.resolve_region("world/solar", "region/moon", 600)) == "REGION_LEASE_EXPIRED", "expired moon route accepted")
	_assert(_err(d.check_writer("world/solar", "region/moon", "authority/b", "server-instance/b", 1, 600)) == "REGION_LEASE_EXPIRED", "expired moon write admitted")
	_assert(_err(d.acquire_region("world/solar", "region/moon", "authority/c", "server-instance/c", "claim/moon-old", 0, 500, 601)) == "STALE_LEASE_GENERATION", "expired lease generation reset")
	_assert(_ok(d.acquire_region("world/solar", "region/moon", "authority/c", "server-instance/c", "claim/moon-new", 1, 500, 602)), "expired lease safe reacquire failed")
	var route := _route(d.resolve_region("world/solar", "region/moon", 603))
	var expected_fields: Array[String] = Directory.ROUTE_FIELDS.duplicate()
	expected_fields.sort()
	var fields: Array[String] = []
	for key in route.keys():
		fields.append(str(key))
	fields.sort()
	_assert(fields == expected_fields, "route leaked endpoints, claim id or unexpected fields")
	var report := d.get_report()
	_assert(not bool(report.get("durable_distributed_lock", true)), "lab claimed distributed lease durability")
	_assert(not bool(report.get("canonical_writer_integrated", true)), "lab claimed canonical admission")
	for row in report.get("regions", []):
		_assert(not row.has("claim_id") and not row.has("endpoint"), "diagnostic report leaked claim/endpoint")
	_finish()

func _finish() -> void:
	var summary := {"test": "n3_region_directory_contracts", "assertions": assertions,
		"failures": failures, "verdict": "PASS" if failures.is_empty() else "FAIL"}
	print(JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)

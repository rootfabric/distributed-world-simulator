extends SceneTree

## P6 R3 route regression: replay and PENDING reservations must short-circuit
## before a handler can execute twice.

const RouteScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_gateway_command_route.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const AdmissionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-route][FAIL] %s" % message)


class CountingHandler extends RefCounted:
	var executions: int = 0
	var malformed_once: bool = false

	func execute_command(command: Dictionary):
		executions += 1
		if malformed_once:
			malformed_once = false
			return "malformed"
		return {"result": "OK", "command_kind": String(command.get("command_kind", ""))}


func _build_route(registry, ledger, handler) -> Dictionary:
	var admission = AdmissionScript.new()
	var adapter = AdapterScript.new()
	var route = RouteScript.new()
	var a: Dictionary = admission.configure(registry, ledger)
	var c: Dictionary = adapter.configure(registry, ledger)
	var r: Dictionary = route.configure(registry, ledger, admission, adapter, handler)
	return {"admission": admission, "adapter": adapter, "route": route, "ok": bool(a.get("success", false)) and bool(c.get("success", false)) and bool(r.get("success", false))}


func _init() -> void:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(16)
	registry.bind("client-session/p6-r3-route", "player/worker", "entity/worker-1")
	var handler = CountingHandler.new()
	var stack := _build_route(registry, ledger, handler)
	_assert(bool(stack["ok"]), "route stack configure failed")
	var route = stack["route"]

	var command := {"command_kind": "BUILD", "domain_id": "p6-domain/outpost-world-state"}
	var first: Dictionary = route.route_command("client-session/p6-r3-route", "operation/ok", command)
	_assert(bool(first.get("success", false)) and String(first.get("details", {}).get("result", "")) == "EXECUTED", "first route failed")
	_assert(handler.executions == 1, "handler execution count after first route wrong")
	var replay: Dictionary = route.route_command("client-session/p6-r3-route", "operation/ok", command)
	_assert(bool(replay.get("success", false)) and String(replay.get("details", {}).get("result", "")) == "ALREADY_APPLIED", "replay did not short-circuit")
	_assert(handler.executions == 1, "replay executed handler again")

	# Reproduce the old crash window: handler runs, but returns malformed before
	# admission.complete(). The reservation remains PENDING.
	handler.malformed_once = true
	var malformed: Dictionary = route.route_command("client-session/p6-r3-route", "operation/pending", command)
	_assert(not bool(malformed.get("success", false)) and String(malformed.get("error_code", "")) == "HANDLER_MALFORMED_OUTCOME", "malformed handler outcome not rejected")
	_assert(handler.executions == 2, "malformed handler was not executed exactly once")
	_assert(ledger.is_pending("player/worker", "operation/pending"), "malformed outcome lost PENDING reservation")

	# Critical regression: retry must be rejected before handler invocation.
	var retry: Dictionary = route.route_command("client-session/p6-r3-route", "operation/pending", command)
	_assert(not bool(retry.get("success", false)) and String(retry.get("error_code", "")) == "OPERATION_PENDING", "PENDING retry not rejected")
	_assert(handler.executions == 2, "PENDING retry executed handler twice")

	if failures.is_empty():
		print("[p6-r3-route] all %d assertions passed" % assertions)
		print("[p6-r3-route][stage] ROUTE_PENDING_NO_DOUBLE_EXECUTION_PASS")
		quit(0)
	else:
		print("[p6-r3-route] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

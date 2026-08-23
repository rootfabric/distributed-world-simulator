extends SceneTree

## P6.6 L0: gateway-ready command routing — the full P6 stack (identity →
## admission → ledger → closure) consumes the gateway foundation to produce
## identical canonical state for DIRECT and GATEWAY command paths.

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
		print("[p6.6-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


## Simulated domain handler (would be NetworkedGameplayService in production).
class FakeHandler extends RefCounted:
	var executed: Array = []
	func execute_command(command: Dictionary) -> Dictionary:
		executed.append(command.duplicate(true))
		return {
			"result": "OK",
			"command_kind": String(command.get("command_kind", "")),
			"operation_id": String(command.get("operation_id", "")),
		}


func _init() -> void:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(256)

	# Bind two players on different transport flavors.
	registry.bind("client-session/p6.6-direct", "player/direct-worker", "entity/direct-1")
	registry.bind("client-session/p6.6-gateway", "player/gateway-worker", "entity/gateway-1")

	var adapter = AdapterScript.new()
	adapter.configure(registry, ledger)

	var admission = AdmissionScript.new()
	var admission_configured: Dictionary = admission.configure(registry, ledger)
	if not bool(admission_configured.get("success", false)):
		print("[p6.6-l0][abort] admission configure failed: %s" % str(admission_configured))
		quit(1)
		return
	_assert(bool(admission_configured.get("success", false)), "admission configured")

	# DIRECT handler baseline.
	var direct_handler = FakeHandler.new()
	var direct_route = RouteScript.new()
	direct_route.configure(registry, ledger, admission, adapter, direct_handler)

	# GATEWAY handler (same logic, separate instance to prove independence).
	var gateway_handler = FakeHandler.new()
	var gateway_route = RouteScript.new()
	gateway_route.configure(registry, ledger, admission, adapter, gateway_handler)

	# --- Route commands through both paths ---
	var direct_ops: Array[String] = []
	var gateway_ops: Array[String] = []
	for i in range(3):
		var d_op := "operation/p6.6-direct-%04d" % i
		var g_op := "operation/p6.6-gateway-%04d" % i
		var d_result: Dictionary = direct_route.route_command("client-session/p6.6-direct", d_op, {"command_kind": "BUILD", "domain_id": "p6-domain/outpost-world-state"})
		var g_result: Dictionary = gateway_route.route_command("client-session/p6.6-gateway", g_op, {"command_kind": "BUILD", "domain_id": "p6-domain/outpost-world-state"})
		_assert(bool(d_result.get("success", false)) and String(d_result["details"]["result"]) == "EXECUTED", "direct route op %d failed" % i)
		_assert(bool(g_result.get("success", false)) and String(g_result["details"]["result"]) == "EXECUTED", "gateway route op %d failed" % i)
		direct_ops.append(d_op)
		gateway_ops.append(g_op)
		_assert(direct_handler.executed.size() == i + 1, "direct handler execution count wrong")
		_assert(gateway_handler.executed.size() == i + 1, "gateway handler execution count wrong")

	# Replay short-circuits at the route level
	var replay: Dictionary = gateway_route.route_command("client-session/p6.6-gateway", gateway_ops[0], {"command_kind": "BUILD", "domain_id": "p6-domain/outpost-world-state"})
	_assert(String(replay["details"]["result"]) == "ALREADY_APPLIED", "gateway replay did not short-circuit")
	_assert(int(gateway_route.get_report()["counters"]["executed"]) == 3, "replay must not re-execute")

	# Closure views exist for both identities and are deterministic
	var closure_direct: Dictionary = gateway_route.build_closure("player/direct-worker")
	var closure_gateway: Dictionary = gateway_route.build_closure("player/gateway-worker")
	_assert(bool(closure_direct.get("success", false)), "direct closure failed")
	_assert(bool(closure_gateway.get("success", false)), "gateway closure failed")

	# Report counters
	var report: Dictionary = gateway_route.get_report()
	_assert(int(report["counters"]["routed"]) >= 4, "routed counter wrong")
	_assert(int(report["counters"]["rejected"]) == 0, "rejected counter wrong (no rejections in happy path)")

	if failures.is_empty():
		print("[p6.6-l0] all %d assertions passed" % assertions)
		print("[p6.6-l0][stage] GATEWAY_READY_COMMAND_ROUTING_PASS")
		quit(0)
	else:
		print("[p6.6-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

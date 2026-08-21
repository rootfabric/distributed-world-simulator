extends SceneTree

## EG1 L0 contracts: route/session table semantics, admission matrix,
## revision stability under gameplay traffic, namespace separation.

const RouteTable = preload("res://scripts/network/gateway/runtime/eg1_gateway_route_table.gd")
const SessionBinding = preload("res://scripts/network/gateway/gateway_session_binding.gd")
const RouteBinding = preload("res://scripts/network/gateway/gateway_route_binding.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg1-contracts][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _attach(table, suffix: String) -> Dictionary:
	return table.attach(
			"gateway-session/eg1/%s" % suffix,
			"peer/enet/eg1-client-%s" % suffix,
			"client-session/eg1/%s" % suffix,
			"player/eg1-%s" % suffix,
			"entity/eg1-player-%s" % suffix,
			"world/main",
			"authority/sim-a",
			"server-instance/sim-a-eg0"
	)


func _init() -> void:
	var table := RouteTable.new()

	# --- attach happy path ---
	var first := _attach(table, "alpha")
	_assert(bool(first.get("success", false)), "attach alpha failed: %s" % _err(first))
	var row: Dictionary = first.get("details", {}).get("row", {})
	_assert(int(row.get("session_slot", 0)) >= 1, "session_slot not allocated")
	_assert(String(row["binding"]["state"]) == "ATTACHED", "binding state must start ATTACHED")
	_assert(String(row["route_binding"]["route_role"]) == "ACTIVE", "route role must start ACTIVE")
	_assert(int(row["binding"]["binding_revision"]) == 1, "initial binding_revision must be 1")
	_assert(int(row["route_binding"]["route_revision"]) == 1, "initial route_revision must be 1")

	# --- binding DTO validators accept the produced rows ---
	_assert(bool(SessionBinding.validate(row["binding"]).get("success", false)), "produced session binding failed validation")
	_assert(bool(RouteBinding.validate(row["route_binding"]).get("success", false)), "produced route binding failed validation")

	# --- uniqueness fences ---
	_assert(_err(table.attach(
					"gateway-session/eg1/alpha",
					"peer/enet/eg1-other",
					"client-session/eg1/dup",
					"player/eg1-dup",
					"entity/eg1-player-dup",
					"world/main",
					"authority/sim-a",
					"server-instance/sim-a-eg0"
			)) == "GATEWAY_SESSION_EXISTS", "duplicate gateway_session_id was accepted")
	_assert(_err(_attach(table, "gamma")) != "GATEWAY_SESSION_EXISTS", "distinct sessions sharing suffix collision check broken")

	var beta := _attach(table, "beta")
	_assert(bool(beta.get("success", false)), "attach beta failed")
	var slot_alpha := int(row["session_slot"])
	var slot_beta := int(beta.get("details", {}).get("row", {}).get("session_slot", 0))
	_assert(slot_alpha != slot_beta, "session slots are not unique")

	# --- client transport peer is one-to-one ---
	_assert(_err(table.lookup_by_client_peer("peer/enet/unknown")) == "UNKNOWN_CLIENT_TRANSPORT_PEER", "lookup_by_client_peer invented a row")

	# --- identity namespaces stay separated inside a row ---
	_assert(String(row["gateway_session_id"]).begins_with("gateway-session/"), "gateway session id outside its namespace")
	_assert(String(row["binding"]["client_session_id"]).begins_with("client-session/"), "client session id outside its namespace")
	_assert(String(row["binding"]["logical_player_id"]).begins_with("player/"), "logical player id outside its namespace")
	_assert(String(row["binding"]["player_entity_id"]).begins_with("entity/"), "player entity id outside its namespace")
	_assert(String(row["route_binding"]["route_binding_id"]).begins_with("gateway-route/"), "route binding id outside its namespace")
	_assert(typeof(row["session_slot"]) == TYPE_INT, "session_slot must be an integer, never a PlayerId string")

	# --- admission matrix ---
	var gs := "gateway-session/eg1/alpha"
	for channel in ["INPUT_MOVEMENT", "WORLD_OPERATION"]:
		_assert(bool(table.can_admit_frame(channel, gs).get("success", false)), "ACTIVE+ATTACHED must admit %s" % channel)
	for channel in ["SESSION_CONTROL", "AUTHORITATIVE_SNAPSHOT", "TELEMETRY", "RECOVERY_FULL_STATE"]:
		_assert(bool(table.can_admit_frame(channel, gs).get("success", false)), "ACTIVE must admit control channel %s" % channel)

	# gameplay traffic (repeated admissions) must NOT change revisions or roles
	var revisions_before := [int(table.lookup(gs)["details"]["row"]["binding"]["binding_revision"]), int(table.lookup(gs)["details"]["row"]["route_binding"]["route_revision"])]
	for _i in range(10):
		table.can_admit_frame("WORLD_OPERATION", gs)
		table.can_admit_frame("INPUT_MOVEMENT", gs)
	var after_traffic := [int(table.lookup(gs)["details"]["row"]["binding"]["binding_revision"]), int(table.lookup(gs)["details"]["row"]["route_binding"]["route_revision"])]
	_assert(revisions_before == after_traffic, "gameplay traffic mutated table revisions (zero-ownership violated)")

	# WARM rejects mutating channels but admits control channels
	table.set_route_role(gs, "WARM")
	_assert(_err(table.can_admit_frame("WORLD_OPERATION", gs)) == "ROUTE_ROLE_REJECTS_MUTATIONS", "WARM admitted WORLD_OPERATION")
	_assert(_err(table.can_admit_frame("INPUT_MOVEMENT", gs)) == "ROUTE_ROLE_REJECTS_MUTATIONS", "WARM admitted INPUT_MOVEMENT")
	_assert(bool(table.can_admit_frame("AUTHORITATIVE_SNAPSHOT", gs).get("success", false)), "WARM must admit AUTHORITATIVE_SNAPSHOT")
	_assert(bool(table.can_admit_frame("SESSION_CONTROL", gs).get("success", false)), "WARM must admit SESSION_CONTROL")

	# role set to the same value is a no-op; real change bumps route_revision exactly once
	var noop := table.set_route_role(gs, "WARM")
	_assert(bool(noop.get("success", false)) and not bool(noop["details"]["changed"]), "identical role set reported changed")
	var rev_after_warm := int(table.lookup(gs)["details"]["row"]["route_binding"]["route_revision"])
	table.set_route_role(gs, "ACTIVE")
	var rev_after_back := int(table.lookup(gs)["details"]["row"]["route_binding"]["route_revision"])
	_assert(rev_after_back == rev_after_warm + 1, "route_revision did not bump exactly once per real change")

	# DRAIN rejects mutations; DETACHED rejects everything and drains the route
	table.set_route_role(gs, "DRAIN")
	_assert(_err(table.can_admit_frame("WORLD_OPERATION", gs)) == "ROUTE_ROLE_REJECTS_MUTATIONS", "DRAIN admitted WORLD_OPERATION")
	table.set_binding_state(gs, "DETACHED")
	_assert(_err(table.can_admit_frame("SESSION_CONTROL", gs)) == "GATEWAY_SESSION_DETACHED", "DETACHED admitted SESSION_CONTROL")
	var detached_row: Dictionary = table.lookup(gs)["details"]["row"]
	_assert(String(detached_row["binding"]["state"]) == "DETACHED", "detach did not persist state")
	_assert(String(detached_row["route_binding"]["route_role"]) == "DRAIN", "detach did not drain the route")

	# release frees the client transport peer binding
	_assert(bool(table.release(gs).get("success", false)), "release failed")
	_assert(_err(table.lookup(gs)) == "UNKNOWN_GATEWAY_SESSION", "released row still present")
	_assert(bool(_attach(table, "alpha").get("success", false)), "reattach after release failed")

	# backend link binding + unknown fences
	_assert(_err(table.bind_backend_link("gateway-session/eg1/nope", "backend-link/x")) == "UNKNOWN_GATEWAY_SESSION", "bind_backend_link invented a session")
	_assert(bool(table.bind_backend_link("gateway-session/eg1/alpha", "backend-link/eg1/spike").get("success", false)), "backend link bind failed")
	_assert(String(table.lookup("gateway-session/eg1/alpha")["details"]["row"]["backend_link_id"]) == "backend-link/eg1/spike", "backend link not persisted")

	# snapshot integrity
	var snap := table.snapshot()
	_assert(int(snap["session_count"]) == table.session_count(), "snapshot count mismatch")
	_assert(int(snap["allocated_session_slots"]) >= int(snap["session_count"]), "slot counter regressed below live rows")

	_finish()


func _finish() -> void:
	var summary := {
		"test": "eg1_gateway_contracts_l0",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-contracts] L0 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg1-contracts] L0 FAIL")
		quit(1)

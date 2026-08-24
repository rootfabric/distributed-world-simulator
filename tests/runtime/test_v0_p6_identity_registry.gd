extends SceneTree

## P6.2 L0: topology-neutral identity registry contracts.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const OwnershipMapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.2-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _registry() -> RegistryScript:
	return RegistryScript.new()


func _init() -> void:
	var reg = _registry()

	# --- ownership map integration: our domain exists and is gateway-only/server-only ---
	var domains = OwnershipMapScript.DOMAINS
	var identity_domain = null
	for domain_value in domains:
		var d: Dictionary = domain_value
		if String(d["domain_id"]) == "p6-domain/player-identity-bindings":
			identity_domain = d
	_assert(identity_domain != null, "PLAYER_IDENTITY_BINDINGS declared in the ownership map")
	if identity_domain != null:
		_assert(String(identity_domain["transport_path"]) == "GATEWAY_ONLY", "identity domain transport must be GATEWAY_ONLY")
		_assert(String(identity_domain["write_authority"]) == "SERVER_ONLY", "identity domain write authority must be SERVER_ONLY")
		_assert(bool(identity_domain["reconnect_restore"]), "identity domain must be restorable on reconnect")

	# --- happy bind + resolve ---
	var b1: Dictionary = reg.bind("client-session/x-direct", "player/alpha", "entity/alpha-1")
	if not bool(b1.get("success", false)):
		_assert(false, "direct-flavored bind failed: %s" % _err(b1))
		print("[p6.2-l0][abort] cannot continue without a successful first bind")
		quit(1)
		return
	_assert(true, "direct-flavored bind ok")
	var r1: Dictionary = reg.resolve_by_session("client-session/x-direct")
	if not bool(r1.get("success", false)):
		_assert(false, "resolve_by_session failed: %s" % _err(r1))
		print("[p6.2-l0][abort] cannot continue without resolve")
		quit(1)
		return
	_assert(String(r1["details"]["binding"]["logical_player_id"]) == "player/alpha", "logical identity mismatch")
	var r2: Dictionary = reg.resolve("player/alpha")
	_assert(bool(r2.get("success", false)), "resolve by player failed")

	# --- topology neutrality: identical behavior for every transport flavor ---
	for flavor in ["client-session/x-gateway", "client-session/x-enet", "client-session/x-loopback"]:
		var bf: Dictionary = reg.bind(flavor, "player/flavor-" + flavor, "entity/flavor-1")
		_assert(bool(bf.get("success", false)), "bind failed for flavor %s" % flavor)
		var rf: Dictionary = reg.resolve_by_session(flavor)
		_assert(bool(rf.get("success", false)) and String(rf["details"]["binding"]["logical_player_id"]).begins_with("player/flavor"), "flavor resolve failed")
	var direct_again: Dictionary = reg.bind("client-session/x-direct", "player/alpha", "entity/alpha-1")
	_assert(bool(direct_again.get("success", false)) and bool(direct_again["details"].get("idempotent", false)), "idempotent re-bind not detected")

	# --- rebind preserves logical identity across successive transport changes ---
	var rb1: Dictionary = reg.rebind_on_transport_change("client-session/x-direct", "client-session/x-via-gateway-1")
	_assert(bool(rb1.get("success", false)), "first rebind failed: %s" % _err(rb1))
	_assert(String(rb1["details"]["preserved_logical_player_id"]) == "player/alpha", "first rebind lost logical identity")
	_assert(int(rb1["details"]["binding"]["binding_revision"]) == 2, "rebind revision must increment")
	var rb2: Dictionary = reg.rebind_on_transport_change("client-session/x-via-gateway-1", "client-session/x-via-enet-2")
	_assert(bool(rb2.get("success", false)), "second rebind failed")
	_assert(String(rb2["details"]["binding"]["logical_player_id"]) == "player/alpha", "second rebind lost logical identity")
	var resolved_after: Dictionary = reg.resolve("player/alpha")
	_assert(String(resolved_after["details"]["binding"]["client_session_id"]) == "client-session/x-via-enet-2", "live binding points at stale session")
	var history: Array = reg.list_bindings_for_player("player/alpha")
	_assert(history.size() >= 3, "history must retain superseded rows")
	var superseded_states: Array[String] = []
	for row_value in history:
		var row: Dictionary = row_value
		if String(row["binding_id"]) == String(rb1["details"]["binding"]["binding_id"]):
			superseded_states.append(String(row["state"]))
	_assert(superseded_states.has("SUPERSEDED"), "superseded state observable in retained history")

	# --- fail-closed negatives ---
	_assert(_err(reg.bind("", "player/z", "entity/z")) == "INVALID_ID_NAMESPACE", "empty session rejected with exact code")
	_assert(_err(reg.bind("session-not-canonical", "player/z", "entity/z")) == "INVALID_ID_NAMESPACE", "non-canonical session rejected with exact code")
	_assert(_err(reg.bind("client-session/new", "not-a-player-id", "entity/z")) == "INVALID_ID_NAMESPACE", "non-canonical player rejected with exact code")
	var dup_logical: Dictionary = reg.bind("client-session/other-live", "player/flavor-client-session/x-gateway", "entity/dup")
	_assert(not bool(dup_logical.get("success", false)), "double live bind for same logical player accepted")
	_assert(_err(dup_logical) == "LOGICAL_PLAYER_ALREADY_LIVE", "LOGICAL_PLAYER_ALREADY_LIVE exact code asserted")
	var dup_session: Dictionary = reg.bind("client-session/x-via-enet-2", "player/beta", "entity/beta-1")
	_assert(not bool(dup_session.get("success", false)), "double live bind for occupied session accepted")
	_assert(_err(dup_session) == "IDENTITY_ALREADY_BOUND", "IDENTITY_ALREADY_BOUND exact code asserted")
	var unknown_rebind: Dictionary = reg.rebind_on_transport_change("client-session/nobody", "client-session/anywhere")
	_assert(_err(unknown_rebind) == "UNKNOWN_SESSION", "unknown-session rebind not rejected")
	var same_session: Dictionary = reg.rebind_on_transport_change("client-session/x-via-enet-2", "client-session/x-via-enet-2")
	_assert(_err(same_session) == "SAME_SESSION_REBIND", "same-session rebind not rejected")
	var onto_live: Dictionary = reg.rebind_on_transport_change("client-session/x-gateway", "client-session/x-via-enet-2")
	_assert(_err(onto_live) == "NEW_SESSION_ALREADY_LIVE", "rebind onto already-live target session rejected with exact code")
	var unknown_player_resolve: Dictionary = reg.resolve("player/nobody")
	_assert(_err(unknown_player_resolve) == "UNKNOWN_PLAYER", "unknown player resolve not rejected")

	# --- report shape: topology neutral flag, no transport internals ---
	var report: Dictionary = reg.get_report()
	_assert(bool(report.get("topology_neutral", false)), "report must declare topology_neutral")
	_assert(not JSON.stringify(report).contains("ENET_MULTIPLAYER"), "report leaked transport internals")

	if failures.is_empty():
		print("[p6.2-l0] all %d assertions passed" % assertions)
		print("[p6.2-l0][stage] TOPOLOGY_NEUTRAL_IDENTITY_PASS")
		quit(0)
	else:
		print("[p6.2-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

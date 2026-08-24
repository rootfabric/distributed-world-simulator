extends SceneTree

## P6.5 L0: AuthorityDomain-ready closure adapter — live view == shadow view,
## topology-neutral manifest, determinism, divergence detection.

const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6.5-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _init() -> void:
	var registry = RegistryScript.new()
	var ledger = LedgerScript.new()
	ledger.configure(64)

	registry.bind("client-session/leg-a", "player/carry-1", "entity/carry-1")
	ledger.record_applied("player/carry-1", "operation/p6.5-op-1")
	ledger.record_applied("player/carry-1", "operation/p6.5-op-2")

	var adapter = AdapterScript.new()
	var configured: Dictionary = adapter.configure(registry, ledger)
	_assert(bool(configured.get("success", false)), "adapter configure failed")

	# Live vs shadow equality (two construction paths, same inputs).
	var live: Dictionary = adapter.build_closure_view("player/carry-1")
	_assert(bool(live.get("success", false)), "live view build failed")
	var live_view: Dictionary = live["details"]["view"]
	var shadow: Dictionary = adapter.reconstruct_shadow_view("player/carry-1")
	_assert(bool(shadow.get("success", false)), "shadow view build failed")
	var shadow_view: Dictionary = shadow["details"]["view"]
	var comparison: Dictionary = adapter.compare_views(live_view, shadow_view)
	_assert(bool(comparison.get("success", false)) and String(comparison["details"]["result"]) == "EQUAL", "live != shadow closure")

	# Topology neutrality: no session ids or transport flavor anywhere.
	var flat := JSON.stringify(_flat_keys(live_view))
	_assert(not flat.contains("client-session"), "view leaked a session id")
	_assert(not flat.contains("gateway"), "view leaked gateway internals")
	_assert(not flat.contains("enet"), "view leaked transport flavor")

	# Carried operations sorted + only this player's ops present.
	var ops: Array = live_view["carried_operations"]
	_assert(ops.size() == 2, "unexpected carried operation count")
	_assert(String(ops[0]) == "operation/p6.5-op-1" and String(ops[1]) == "operation/p6.5-op-2", "operations not in canonical order: %s" % str(ops))

	# Declared domains present and canonically ordered.
	var declared: Array = live_view["declared_domains"]
	_assert(declared.size() >= 6, "ownership map snapshot incomplete")
	_assert(String(declared[0]["domain_id"]) < String(declared[declared.size() - 1]["domain_id"]), "domains not canonically ordered")

	# Determinism: rebuild twice → byte-identical canonical forms.
	var again: Dictionary = adapter.build_closure_view("player/carry-1")
	var form_a := JSON.stringify(_flat_form(live_view), "", false)
	var form_b := JSON.stringify(_flat_form(again["details"]["view"]), "", false)
	_assert(form_a == form_b, "closure view not deterministic across constructions")

	# Divergence detection: capture a shadow BEFORE the state change, then
	# mutate the ledger — the fresh live view must diverge from the stale one.
	var stale_shadow: Dictionary = adapter.reconstruct_shadow_view("player/carry-1")["details"]["view"]
	ledger.record_applied("player/carry-1", "operation/p6.5-op-3")
	var fresh_live: Dictionary = adapter.build_closure_view("player/carry-1")["details"]["view"]
	var diverged: Dictionary = adapter.compare_views(fresh_live, stale_shadow)
	_assert(_err(diverged) == "DIVERGED" and (diverged["details"]["divergences"] as Array).has("canonical_view"), "divergence not detected after state change")
	var healed: Dictionary = adapter.compare_views(adapter.reconstruct_shadow_view("player/carry-1")["details"]["view"], fresh_live)
	_assert(bool(healed.get("success", false)) and String(healed["details"]["result"]) == "EQUAL", "fresh shadow must match fresh live after state change")

	# Unknown player fail-closed.
	var unknown: Dictionary = adapter.build_closure_view("player/nobody")
	_assert(_err(unknown) == "UNKNOWN_PLAYER", "unknown player not rejected")

	if failures.is_empty():
		print("[p6.5-l0] all %d assertions passed" % assertions)
		print("[p6.5-l0][stage] AUTHORITY_DOMAIN_READY_CLOSURE_PASS")
		quit(0)
	else:
		print("[p6.5-l0] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)


func _flat_keys(value) -> String:
	var parts: Array[String] = []
	_walk(value, "", parts)
	return "|".join(parts)


func _walk(value, prefix: String, parts: Array[String]) -> void:
	if value is Dictionary:
		for k in (value as Dictionary).keys():
			_walk(value[k], prefix + "/" + String(k), parts)
	elif value is Array:
		for i in range((value as Array).size()):
			_walk(value[i], prefix + "/%d" % i, parts)
	else:
		parts.append(prefix + "=" + str(value))


func _flat_form(view: Dictionary) -> Dictionary:
	var out := {}
	for key in view.keys():
		if key == "canonical_view":
			continue
		out[key] = _canonical_static(view[key])
	out["canonical_view"] = _canonical_static(view.get("canonical_view", {}))
	return out


static func _canonical_static(value):
	if value is Dictionary:
		var keys: Array = (value as Dictionary).keys()
		keys.sort()
		var out := {}
		for k in keys:
			out[k] = _canonical_static(value[k])
		return out
	if value is Array:
		var arr_out: Array = []
		for item in (value as Array):
			arr_out.append(_canonical_static(item))
		return arr_out
	return value

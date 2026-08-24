extends RefCounted

## P6.5 AuthorityDomain-ready closure adapter.
##
## Builds a deterministic CLOSURE VIEW of everything that would be CARRIED
## for a logical player across a future authority transfer: identity binding,
## applied-operation digests, and the declared per-domain state keys the
## player touches. The view is:
##   - keyed ONLY by logical_player_id / player_entity_id (no session ids,
##     no transport flavor, no gateway internals) — topology-neutral by
##     construction;
##   - canonically ordered (key-sorted recursive copy) so two independent
##     constructions from the same inputs are byte-identical;
##   - comparable: compare_views(live, shadow) returns EQUAL or a canonical
##     divergence list, enabling "live closure == reconstructed shadow" proofs.
##
## This adapter does NOT perform transfers; it prepares the carried-state
## manifest shape that a future AuthorityDomain (I3 donor semantics) would
## consume.

const RegistryScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const LedgerScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")

const SCHEMA := "planet_simulator.p6_closure_view.v1"

var _registry = null
var _ledger = null


func configure(p_registry, p_ledger) -> Dictionary:
	if p_registry == null or not p_registry.has_method("resolve"):
		return {"success": false, "error_code": "INVALID_IDENTITY_REGISTRY", "details": {}}
	if p_ledger == null or not p_ledger.has_method("snapshot"):
		return {"success": false, "error_code": "INVALID_OPERATION_LEDGER", "details": {}}
	_registry = p_registry
	_ledger = p_ledger
	return {"success": true, "details": {}}


## Build the carried-state manifest for one logical player.
func build_closure_view(logical_player_id: String) -> Dictionary:
	var binding: Dictionary = _registry.resolve(logical_player_id)
	if not bool(binding.get("success", false)):
		return {"success": false, "error_code": "UNKNOWN_PLAYER", "details": {}}
	var row: Dictionary = binding["details"]["binding"]
	var applied_keys: Array = []
	var snap: Dictionary = _ledger.snapshot()
	for key_value in (snap.get("applied", {}) as Dictionary).keys():
		var full_key := String(key_value)
		if full_key.begins_with(logical_player_id + "|"):
			applied_keys.append(full_key.trim_prefix(logical_player_id + "|"))
	applied_keys.sort()
	var view := {
		"schema": SCHEMA,
		"logical_player_id": String(row["logical_player_id"]),
		"player_entity_id": String(row["player_entity_id"]),
		"identity_binding_revision": int(row["binding_revision"]),
		"carried_operations": applied_keys,
		"declared_domains": OwnershipMapDomainsSnapshot(),
	}
	view["canonical_view"] = _canonical_copy(view)
	return {"success": true, "details": {"view": _canonical_copy(view)}}


## Independent reconstruction path for shadow comparison: rebuilds the view
## through a DIFFERENT construction order (domain-first, then identity).
func reconstruct_shadow_view(logical_player_id: String) -> Dictionary:
	var domains_first := {
		"schema": SCHEMA,
		"declared_domains": OwnershipMapDomainsSnapshot(),
	}
	var operations: Array = []
	var snap: Dictionary = _ledger.snapshot()
	var applied: Dictionary = snap.get("applied", {})
	var keys: Array = (applied as Dictionary).keys()
	keys.sort()
	for key_value in keys:
		var full_key := String(key_value)
		if full_key.begins_with(logical_player_id + "|"):
			operations.append(full_key.trim_prefix(logical_player_id + "|"))
	domains_first["carried_operations"] = operations
	var identity: Dictionary = _registry.resolve(logical_player_id)
	if not bool(identity.get("success", false)):
		return {"success": false, "error_code": "UNKNOWN_PLAYER", "details": {}}
	var row: Dictionary = identity["details"]["binding"]
	domains_first["logical_player_id"] = String(row["logical_player_id"])
	domains_first["player_entity_id"] = String(row["player_entity_id"])
	domains_first["identity_binding_revision"] = int(row["binding_revision"])
	domains_first["canonical_view"] = _canonical_copy(domains_first)
	return {"success": true, "details": {"view": domains_first}}


## Compare live vs shadow views. Returns EQUAL or a list of divergences at
## the top-level field granularity (canonical forms compared as strings).
func compare_views(live_view: Dictionary, shadow_view: Dictionary) -> Dictionary:
	var divergences: Array = []
	for key in ["canonical_view"]:
		var live_form := JSON.stringify(_canonical_copy(live_view.get(key, {})), "", false)
		var shadow_form := JSON.stringify(_canonical_copy(shadow_view.get(key, {})), "", false)
		if live_form != shadow_form:
			divergences.append(key)
	if divergences.is_empty():
		return {"success": true, "details": {"result": "EQUAL"}}
	return {"success": false, "error_code": "DIVERGED", "details": {"divergences": divergences}}


static func OwnershipMapDomainsSnapshot() -> Array:
	var snapshot_domains: Array = []
	const MapScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")
	for entry_value in MapScript.DOMAINS:
		var entry: Dictionary = entry_value
		snapshot_domains.append({
			"domain_id": String(entry["domain_id"]),
			"persistence_replay": bool(entry["persistence_replay"]),
			"reconnect_restore": bool(entry["reconnect_restore"]),
			"transport_path": String(entry["transport_path"]),
			"write_authority": String(entry["write_authority"]),
		})
	snapshot_domains.sort_custom(func(a, b) -> bool: return String(a["domain_id"]) < String(b["domain_id"]))
	return snapshot_domains


func _canonical_copy(value):
	if value is Dictionary:
		var sorted_keys: Array = (value as Dictionary).keys()
		sorted_keys.sort()
		var out := {}
		for k in sorted_keys:
			out[k] = _canonical_copy(value[k])
		return out
	if value is Array:
		var arr_out: Array = []
		for item in (value as Array):
			arr_out.append(_canonical_copy(item))
		return arr_out
	return value

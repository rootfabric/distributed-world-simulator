extends SceneTree

## V0-P6.1 L0: canonical ownership map contract.
## Run: godot --headless --path <wt> --script res://tests/runtime/test_v0_p6_ownership_map.gd
## Exit 0 = PASS.

const OwnershipMap = preload(
	"res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd"
)

const MINIMUM_DOMAIN_COUNT := 6

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var domains: Array = OwnershipMap.DOMAINS

	# --- every domain has required fields with correct types -----------------
	_assert_true(domains.size() >= MINIMUM_DOMAIN_COUNT, "map declares at least %d domains" % MINIMUM_DOMAIN_COUNT)
	for entry_value in domains:
		var entry: Dictionary = entry_value
		var domain_id := String(entry.get("domain_id", ""))
		_assert_true(OwnershipMap.validate_domain(entry).get("success", false) == true,
			"domain passes schema validation: %s" % domain_id)
		for field in ["persistence_replay", "reconnect_restore"]:
			_assert_true(typeof(entry.get(field)) == TYPE_BOOL, "%s.%s is bool" % [domain_id, field])
		_assert_true(String(entry.get("write_authority", "")) == OwnershipMap.WRITE_AUTHORITY_SERVER_ONLY,
			"%s write authority is SERVER_ONLY" % domain_id)
		_assert_true(not String(entry.get("notes", "")).is_empty(), "%s carries notes" % domain_id)

	# --- ids canonical p6-domain/* -------------------------------------------
	var declared_ids: Array = []
	for entry_value in domains:
		var entry: Dictionary = entry_value
		var domain_id := String(entry.get("domain_id", ""))
		_assert_true(domain_id.begins_with("p6-domain/"), "id canonical prefix: %s" % domain_id)
		declared_ids.append(domain_id)
	for expected in [
		"p6-domain/outpost-world-state",
		"p6-domain/item-inventory",
		"p6-domain/equipment-tool-slots",
		"p6-domain/construction-builds",
		"p6-domain/player-identity-bindings",
		"p6-domain/interaction-operation-ledger",
	]:
		_assert_true(declared_ids.has(expected), "required minimum domain declared: %s" % expected)
	_assert_true(declared_ids.size() == _unique_count(declared_ids), "no duplicate declared ids")

	# --- exactly one persistence owner across all replay domains --------------
	_assert_true(OwnershipMap.single_persistence_owner(),
		"single_persistence_owner(): one owner across all replay domains")
	var replay_owner_values := {}
	for entry_value in domains:
		var entry: Dictionary = entry_value
		if bool(entry.get("persistence_replay", false)):
			replay_owner_values[String(entry.get("owner", ""))] = true
	_assert_true(replay_owner_values.size() == 1, "exactly one distinct owner across replay domains")

	# --- gateway-only transport for every client-facing domain ----------------
	_assert_true(OwnershipMap.gateway_only_transport(), "gateway_only_transport(): all client-facing domains")
	for entry_value in domains:
		var entry: Dictionary = entry_value
		_assert_true(String(entry.get("transport_path", "")) == "GATEWAY_ONLY",
			"transport_path GATEWAY_ONLY: %s" % String(entry.get("domain_id", "")))

	# --- no private truth ------------------------------------------------------
	_assert_true(OwnershipMap.no_private_truth(), "no_private_truth(): map is consistent and free of forbidden stores")
	_assert_true(OwnershipMap.assert_domains_declared(["p6-domain/item-inventory"]).get("success", false) == true,
		"declared candidate accepted by assert_domains_declared")
	var undeclared_result: Dictionary = OwnershipMap.assert_domains_declared([
		"p6-domain/item-inventory",
		"p6-domain/private-outpost-truth-store",
	])
	_assert_true(undeclared_result.get("success", false) != true, "undeclared persisted domain rejected")
	_assert_true(String(undeclared_result.get("error_code", "")) == "PRIVATE_TRUTH_UNDECLARED",
		"undeclared domain error_code PRIVATE_TRUTH_UNDECLARED")

	# --- deterministic snapshot across two constructions -----------------------
	var first_snapshot: Dictionary = OwnershipMap.new().snapshot()
	var second_snapshot: Dictionary = OwnershipMap.new().snapshot()
	_assert_true(first_snapshot == second_snapshot, "snapshot equality across two constructions")
	var first_json := OwnershipMap.snapshot_canonical_json()
	var second_json := OwnershipMap.snapshot_canonical_json()
	_assert_true(first_json == second_json, "canonical JSON stable across two constructions")
	_assert_true(not first_json.is_empty() and first_json.contains("p6-domain/outpost-world-state"),
		"canonical JSON embeds sorted domain content")
	var round_trip: Variant = JSON.parse_string(first_json)
	_assert_true(round_trip is Dictionary and not (round_trip as Dictionary).is_empty(),
		"canonical JSON parses back to the map")

	# --- negative: second persistence owner fails validation helpers ----------
	var intruder: Dictionary = OwnershipMap.find_domain("p6-domain/outpost-world-state").duplicate(true)
	intruder["domain_id"] = "p6-domain/shadow-outpost-state"
	intruder["owner"] = "p6-owner/shadow-local-store"
	var bad_map: Array = OwnershipMap.DOMAINS.duplicate()
	bad_map.append(intruder)
	var multi_owner_result: Dictionary = OwnershipMap.validate_map(bad_map)
	_assert_true(multi_owner_result.get("success", false) != true, "second persistence owner rejected by validate_map")
	_assert_true(String(multi_owner_result.get("error_code", "")) == "MULTIPLE_PERSISTENCE_OWNERS",
		"second owner error_code MULTIPLE_PERSISTENCE_OWNERS")
	_assert_true(OwnershipMap.try_register_domain(intruder).get("success", false) != true,
		"second persistence owner rejected by try_register_domain")
	_assert_true(OwnershipMap.DOMAINS.size() == domains.size(),
		"try_register_domain never mutates the frozen declaration")

	# --- negative: non-gateway transport fails validation helpers --------------
	var direct_route: Dictionary = OwnershipMap.find_domain("p6-domain/construction-builds").duplicate(true)
	direct_route["transport_path"] = "DIRECT_ENET"
	var direct_entry_result: Dictionary = OwnershipMap.validate_domain(direct_route)
	_assert_true(direct_entry_result.get("success", false) != true, "non-gateway transport rejected by validate_domain")
	_assert_true(String(direct_entry_result.get("error_code", "")) == "NON_GATEWAY_TRANSPORT",
		"non-gateway transport error_code NON_GATEWAY_TRANSPORT")
	_assert_true(OwnershipMap.try_register_domain(direct_route).get("success", false) != true,
		"non-gateway transport rejected by try_register_domain")

	# --- fail-closed misc: empty map and duplicate id --------------------------
	_assert_true(OwnershipMap.validate_map([]).get("error_code", "") == "EMPTY_DOMAIN_MAP",
		"empty map fails closed")
	var duplicated: Array = OwnershipMap.DOMAINS.duplicate()
	duplicated.append(OwnershipMap.find_domain("p6-domain/item-inventory"))
	_assert_true(OwnershipMap.validate_map(duplicated).get("error_code", "") == "DUPLICATE_DOMAIN_ID",
		"duplicate domain id fails closed")
	_assert_true(OwnershipMap.validate_domain({}).get("error_code", "") == "EMPTY_DOMAIN_ENTRY",
		"empty entry fails closed")

	print("V0-P6 ownership map: %d assertions, %d failures" % [_assertions, _failures])
	quit(0 if _failures == 0 else 1)


func _unique_count(values: Array) -> int:
	var seen: Dictionary = {}
	for value in values:
		seen[value] = true
	return seen.size()


func _assert_true(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("[V0-P6] %s" % message)

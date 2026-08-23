extends SceneTree

## P6 R3: canonical ownership composition contract.

const OwnershipMap = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-ownership][FAIL] %s" % message)


func _init() -> void:
	var domains: Array = OwnershipMap.DOMAINS
	_assert(domains.size() == 6, "expected six declared composition domains")
	_assert(bool(OwnershipMap.validate_map(domains).get("success", false)), "ownership map invalid")
	_assert(OwnershipMap.single_persistence_owner(), "durable domains do not share existing persistence owner")
	_assert(OwnershipMap.canonical_owners_are_external_to_p6(), "P6 still claims a canonical owner")
	_assert(OwnershipMap.gateway_only_transport(), "a P6 client-facing domain bypasses gateway")
	_assert(OwnershipMap.no_private_truth(), "private P6 truth remains")

	var canonical_owners: Dictionary = {}
	for entry_value in domains:
		var entry := Dictionary(entry_value)
		var domain_id := String(entry["domain_id"])
		_assert(bool(OwnershipMap.validate_domain(entry).get("success", false)), "invalid domain %s" % domain_id)
		_assert(String(entry["persistence_owner"]) == OwnershipMap.EXISTING_PERSISTENCE_OWNER_ID, "domain uses non-canonical persistence owner: %s" % domain_id)
		_assert(not String(entry["canonical_owner"]).begins_with("p6"), "P6 owns canonical domain: %s" % domain_id)
		canonical_owners[String(entry["canonical_owner"])] = true
	_assert(canonical_owners.size() >= 4, "canonical owners were incorrectly collapsed into one P6 owner")

	_assert(String(OwnershipMap.find_domain("p6-domain/item-inventory")["canonical_owner"]) == "item/m4-canonical-item-graph", "item owner is not M4")
	_assert(String(OwnershipMap.find_domain("p6-domain/equipment-tool-slots")["canonical_owner"]) == "item/m4-canonical-item-graph", "equipment owner is not M4/P5 composition")
	_assert(String(OwnershipMap.find_domain("p6-domain/construction-builds")["canonical_owner"]) == "construction/p4-authority", "construction owner is not P4")
	_assert(String(OwnershipMap.find_domain("p6-domain/interaction-operation-ledger")["canonical_owner"]) == "replay/m6-durable-replay", "replay owner is not M6")

	# A new P6 persistence owner is rejected even when all other fields look valid.
	var bad := OwnershipMap.find_domain("p6-domain/outpost-world-state").duplicate(true)
	bad["domain_id"] = "p6-domain/private-copy"
	bad["persistence_owner"] = "p6-owner/private-store"
	var bad_result: Dictionary = OwnershipMap.validate_domain(bad)
	_assert(not bool(bad_result.get("success", false)), "private P6 persistence owner accepted")

	# A new P6 canonical owner is rejected as duplicate truth.
	bad = OwnershipMap.find_domain("p6-domain/construction-builds").duplicate(true)
	bad["domain_id"] = "p6-domain/private-construction"
	bad["canonical_owner"] = "p6/construction"
	bad_result = OwnershipMap.validate_domain(bad)
	_assert(not bool(bad_result.get("success", false)), "private P6 canonical owner accepted")

	var first := OwnershipMap.snapshot_canonical_json()
	var second := OwnershipMap.snapshot_canonical_json()
	_assert(first == second and not first.is_empty(), "ownership snapshot not deterministic")

	if failures.is_empty():
		print("[p6-r3-ownership] all %d assertions passed" % assertions)
		print("[p6-r3-ownership][stage] CANONICAL_OWNER_COMPOSITION_PASS")
		quit(0)
	else:
		print("[p6-r3-ownership] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

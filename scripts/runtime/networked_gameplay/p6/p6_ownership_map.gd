extends RefCounted

## P6 canonical ownership map — R3 repaired semantics.
##
## P6 is a composition boundary, not a canonical state owner. `canonical_owner`
## names the already accepted gameplay/replay owner of each domain while
## `persistence_owner` names the ONE existing authoritative recovery pipeline
## that durably checkpoints authority_state + replay_state.
##
## No `p6-owner/*` identity exists after R3. P6 may route, project and validate;
## it may not become an Item Graph, Construction, equipment, persistence or
## durable replay owner.

const SCHEMA_ID := "distributed_world_simulator.p6_ownership_map.v2"
const TRANSPORT_GATEWAY_ONLY := "GATEWAY_ONLY"
const WRITE_AUTHORITY_SERVER_ONLY := "SERVER_ONLY"
const EXISTING_PERSISTENCE_OWNER_ID := "persistence/authoritative-recovery"
const DOMAIN_ID_PREFIX := "p6-domain/"

const REQUIRED_ENTRY_FIELDS: Array = [
	"domain_id",
	"canonical_owner",
	"persistence_owner",
	"persistence_replay",
	"reconnect_restore",
	"transport_path",
	"write_authority",
	"notes",
]

const DOMAINS: Array = [
	{
		"domain_id": DOMAIN_ID_PREFIX + "outpost-world-state",
		"canonical_owner": "v0/p4-p5-product-composition",
		"persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Composition/read-model identity only. Canonical Item/Construction/player truth remains in the owners below; no mutable P6OutpostState is authoritative.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "item-inventory",
		"canonical_owner": "item/m4-canonical-item-graph",
		"persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Inventory and containers remain the canonical M4 Item Graph.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "equipment-tool-slots",
		"canonical_owner": "item/m4-canonical-item-graph",
		"persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "P5 equipment/tool slots are canonical relations on the M4 Item Graph; P6 owns no equipment store.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "construction-builds",
		"canonical_owner": "construction/p4-authority",
		"persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Construct/part/bond truth remains the accepted P4 Construction authority bound to the same M4 Item Graph.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "player-identity-bindings",
		"canonical_owner": "networked-gameplay/player-ownership",
		"persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Canonical player/entity/ownership recovery stays in NetworkedGameplayService ownership state; P6 session registry is transport-local only.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "interaction-operation-ledger",
		"canonical_owner": "replay/m6-durable-replay",
		"persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Durable OperationId replay truth is NetworkedGameplayService + M6 durable replay outbox inside authoritative checkpoints. P6 guard is transient/fail-closed only.",
	},
]

const FORBIDDEN_PRIVATE_OWNER_PREFIXES: Array[String] = [
	"p6-owner/",
	"p6/persistence",
	"p6/item",
	"p6/construction",
	"p6/replay",
]


static func snapshot() -> Dictionary:
	var domains: Array = []
	for entry_value in DOMAINS:
		domains.append(_canonical_copy(Dictionary(entry_value)))
	domains.sort_custom(_compare_snapshots_by_domain_id)
	return {
		"schema": SCHEMA_ID,
		"existing_persistence_owner": EXISTING_PERSISTENCE_OWNER_ID,
		"transport_policy": TRANSPORT_GATEWAY_ONLY,
		"write_authority_policy": WRITE_AUTHORITY_SERVER_ONLY,
		"domains": domains,
	}


static func snapshot_canonical_json() -> String:
	return JSON.stringify(_canonical_copy(snapshot()), "", false)


static func declared_domain_ids() -> Array:
	var ids: Array = []
	for entry_value in DOMAINS:
		ids.append(String(Dictionary(entry_value).get("domain_id", "")))
	return ids


static func find_domain(domain_id: String) -> Dictionary:
	for entry_value in DOMAINS:
		var entry := Dictionary(entry_value)
		if String(entry.get("domain_id", "")) == domain_id:
			return entry.duplicate(true)
	return {}


static func is_domain_declared(domain_id: String) -> bool:
	return not find_domain(domain_id).is_empty()


static func single_persistence_owner() -> bool:
	var owner := ""
	for entry_value in DOMAINS:
		var entry := Dictionary(entry_value)
		if not bool(entry.get("persistence_replay", false)):
			continue
		var candidate := String(entry.get("persistence_owner", ""))
		if owner.is_empty():
			owner = candidate
		elif candidate != owner:
			return false
	return owner == EXISTING_PERSISTENCE_OWNER_ID


static func canonical_owners_are_external_to_p6() -> bool:
	for entry_value in DOMAINS:
		var owner := String(Dictionary(entry_value).get("canonical_owner", ""))
		for prefix in FORBIDDEN_PRIVATE_OWNER_PREFIXES:
			if owner.begins_with(prefix):
				return false
	return true


static func gateway_only_transport() -> bool:
	for entry_value in DOMAINS:
		if String(Dictionary(entry_value).get("transport_path", "")) != TRANSPORT_GATEWAY_ONLY:
			return false
	return true


static func no_private_truth() -> bool:
	return bool(validate_map(DOMAINS).get("success", false)) and canonical_owners_are_external_to_p6()


static func assert_domains_declared(candidate_domain_ids: Array) -> Dictionary:
	var undeclared: Array = []
	for candidate_value in candidate_domain_ids:
		var candidate := String(candidate_value)
		if not is_domain_declared(candidate):
			undeclared.append(candidate)
	if not undeclared.is_empty():
		return {"success": false, "error_code": "PRIVATE_TRUTH_UNDECLARED", "undeclared_domain_ids": undeclared}
	return {"success": true}


static func validate_domain(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return _validation_failure("EMPTY_DOMAIN_ENTRY")
	for field in REQUIRED_ENTRY_FIELDS:
		if not entry.has(field):
			return _validation_failure("MISSING_REQUIRED_FIELD", {"field": String(field)})
	for field in entry.keys():
		if not REQUIRED_ENTRY_FIELDS.has(field):
			return _validation_failure("UNKNOWN_FIELD", {"field": String(field)})
	for field in ["domain_id", "canonical_owner", "persistence_owner", "transport_path", "write_authority", "notes"]:
		if typeof(entry[field]) != TYPE_STRING:
			return _validation_failure("BAD_FIELD_TYPE", {"field": String(field)})
	for field in ["persistence_replay", "reconnect_restore"]:
		if typeof(entry[field]) != TYPE_BOOL:
			return _validation_failure("BAD_FIELD_TYPE", {"field": String(field)})
	var domain_id := String(entry["domain_id"])
	if not _is_canonical_domain_id(domain_id):
		return _validation_failure("NON_CANONICAL_DOMAIN_ID", {"domain_id": domain_id})
	if String(entry["transport_path"]) != TRANSPORT_GATEWAY_ONLY:
		return _validation_failure("NON_GATEWAY_TRANSPORT", {"transport_path": String(entry["transport_path"])})
	if String(entry["write_authority"]) != WRITE_AUTHORITY_SERVER_ONLY:
		return _validation_failure("INVALID_WRITE_AUTHORITY", {"write_authority": String(entry["write_authority"])})
	if not _is_namespaced_id(String(entry["canonical_owner"])) or not _is_namespaced_id(String(entry["persistence_owner"])):
		return _validation_failure("NON_CANONICAL_OWNER_ID")
	if bool(entry["persistence_replay"]) and String(entry["persistence_owner"]) != EXISTING_PERSISTENCE_OWNER_ID:
		return _validation_failure("NON_CANONICAL_PERSISTENCE_OWNER", {"persistence_owner": String(entry["persistence_owner"])})
	for prefix in FORBIDDEN_PRIVATE_OWNER_PREFIXES:
		if String(entry["canonical_owner"]).begins_with(prefix) or String(entry["persistence_owner"]).begins_with(prefix):
			return _validation_failure("P6_PRIVATE_OWNER_FORBIDDEN")
	return {"success": true}


static func validate_map(domains: Array) -> Dictionary:
	if domains.is_empty():
		return _validation_failure("EMPTY_DOMAIN_MAP")
	var seen_ids: Dictionary = {}
	var persistence_owners: Dictionary = {}
	for entry_value in domains:
		if not entry_value is Dictionary:
			return _validation_failure("BAD_DOMAIN_ENTRY_TYPE")
		var entry := Dictionary(entry_value)
		var result := validate_domain(entry)
		if not bool(result.get("success", false)):
			return result
		var domain_id := String(entry["domain_id"])
		if seen_ids.has(domain_id):
			return _validation_failure("DUPLICATE_DOMAIN_ID", {"domain_id": domain_id})
		seen_ids[domain_id] = true
		if bool(entry["persistence_replay"]):
			persistence_owners[String(entry["persistence_owner"])] = true
	if persistence_owners.size() != 1 or not persistence_owners.has(EXISTING_PERSISTENCE_OWNER_ID):
		return _validation_failure("MULTIPLE_PERSISTENCE_OWNERS", {"owners": persistence_owners.keys()})
	return {"success": true}


static func try_register_domain(entry: Dictionary) -> Dictionary:
	var result := validate_domain(entry)
	if not bool(result.get("success", false)):
		return result
	var combined: Array = DOMAINS.duplicate(true)
	combined.append(entry.duplicate(true))
	return validate_map(combined)


static func _validation_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	var failure := {"success": false, "error_code": error_code}
	for key in details.keys():
		failure[key] = details[key]
	return failure


static func _is_canonical_domain_id(domain_id: String) -> bool:
	return domain_id.begins_with(DOMAIN_ID_PREFIX) and _is_lower_tokens(domain_id.trim_prefix(DOMAIN_ID_PREFIX))


static func _is_namespaced_id(value: String) -> bool:
	var parts := value.split("/")
	if parts.size() < 2:
		return false
	for part in parts:
		if not _is_lower_tokens(String(part)):
			return false
	return true


static func _is_lower_tokens(text: String) -> bool:
	if text.is_empty():
		return false
	var matcher := RegEx.new()
	matcher.compile("^[a-z0-9]+([._-][a-z0-9]+)*$")
	return matcher.search(text) != null


static func _canonical_copy(value: Variant) -> Variant:
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array = source.keys()
		keys.sort()
		var ordered: Dictionary = {}
		for key in keys:
			ordered[key] = _canonical_copy(source[key])
		return ordered
	if value is Array:
		var items: Array = []
		for element in value:
			items.append(_canonical_copy(element))
		return items
	return value


static func _compare_snapshots_by_domain_id(a: Variant, b: Variant) -> bool:
	return String(a.get("domain_id", "")) < String(b.get("domain_id", ""))

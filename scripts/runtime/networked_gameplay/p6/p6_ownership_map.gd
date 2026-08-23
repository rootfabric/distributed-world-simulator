extends RefCounted
## P6.1 canonical ownership map (DECLARATION ONLY — persistence itself belongs to P6.7).
##
## Single machine-readable registry of every canonical state domain the P6
## persistent shared outpost will own. Every later P6 stage must resolve
## ownership questions against this map instead of inventing local truth.
##
## Design rules encoded here:
## - exactly ONE persistence owner identity for every replay domain;
## - ALL client-facing traffic moves through the edge gateway (GATEWAY_ONLY);
## - ONLY the server writes persistent/shared truth (SERVER_ONLY);
## - no state outside this map may ever be persisted (fail-closed helpers).

const SCHEMA_ID := "distributed_world_simulator.p6_ownership_map.v1"

const TRANSPORT_GATEWAY_ONLY := "GATEWAY_ONLY"
const WRITE_AUTHORITY_SERVER_ONLY := "SERVER_ONLY"

## The single canonical persistence/recovery owner for all P6 replay state
## (Directory-backed one-writer server authority; see V0_P6 roadmap P6.1).
const SINGLE_PERSISTENCE_OWNER_ID := "p6-owner/directory-one-writer"

const DOMAIN_ID_PREFIX := "p6-domain/"

const REQUIRED_ENTRY_FIELDS: Array = [
	"domain_id",
	"owner",
	"persistence_replay",
	"reconnect_restore",
	"transport_path",
	"write_authority",
	"notes",
]

## Declared ownership map. Frozen at compile time; entries must never be
## mutated at runtime. Order of fields inside each entry follows
## REQUIRED_ENTRY_FIELDS; snapshots re-sort keys deterministically.
const DOMAINS: Array = [
	{
		"domain_id": DOMAIN_ID_PREFIX + "outpost-world-state",
		"owner": SINGLE_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Outpost shared world state; canonical truth stays with the accepted network/gameplay owner, persisted only by the single directory one-writer.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "item-inventory",
		"owner": SINGLE_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Inventory/containers remain canonical M4 Item Graph truth; P6 adds no second item store.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "equipment-tool-slots",
		"owner": SINGLE_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Equipment/tools stay accepted P5 composition relations over the M4 Item Graph; no private equipment truth.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "construction-builds",
		"owner": SINGLE_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Construction/outpost builds remain canonical P4 Construction owner truth; P6 adds no second construction store.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "player-identity-bindings",
		"owner": SINGLE_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Player identity bindings follow the existing canonical player owner; topology-neutral identity resolution lands in P6.2.",
	},
	{
		"domain_id": DOMAIN_ID_PREFIX + "interaction-operation-ledger",
		"owner": SINGLE_PERSISTENCE_OWNER_ID,
		"persistence_replay": true,
		"reconnect_restore": true,
		"transport_path": TRANSPORT_GATEWAY_ONLY,
		"write_authority": WRITE_AUTHORITY_SERVER_ONLY,
		"notes": "Interaction dedup/operation ledger remains the existing operation ledger; P6 adds no second replay oracle.",
	},
]

const FORBIDDEN_PRIVATE_TRUTH_NAMES: Array = [
	"OutpostTruthStore",
	"OutpostInventory",
	"OutpostPersistence",
]


## --- Deterministic introspection -------------------------------------------

## Deep, key-sorted snapshot of the whole map. Two constructions MUST produce
## identical canonical JSON (determinism contract enforced by the L0 test).
static func snapshot() -> Dictionary:
	var domains: Array = []
	for entry_value in DOMAINS:
		var entry: Dictionary = entry_value
		domains.append(_canonical_copy(entry))
	domains.sort_custom(_compare_snapshots_by_domain_id)
	return {
		"schema": SCHEMA_ID,
		"single_persistence_owner": SINGLE_PERSISTENCE_OWNER_ID,
		"transport_policy": TRANSPORT_GATEWAY_ONLY,
		"write_authority_policy": WRITE_AUTHORITY_SERVER_ONLY,
		"domains": domains,
	}


## Canonical JSON of snapshot(): object keys sorted recursively, stable order.
static func snapshot_canonical_json() -> String:
	return JSON.stringify(_canonical_copy(snapshot()))


static func declared_domain_ids() -> Array:
	var ids: Array = []
	for entry_value in DOMAINS:
		ids.append(String(entry_value.get("domain_id", "")))
	return ids


static func find_domain(domain_id: String) -> Dictionary:
	for entry_value in DOMAINS:
		var entry: Dictionary = entry_value
		if String(entry.get("domain_id", "")) == domain_id:
			return entry.duplicate(true)
	return {}


static func is_domain_declared(domain_id: String) -> bool:
	return not find_domain(domain_id).is_empty()


## --- Ownership invariants ---------------------------------------------------

## True iff every replay domain declares the SAME single persistence owner.
static func single_persistence_owner() -> bool:
	var owners: Array = []
	for entry_value in DOMAINS:
		var entry: Dictionary = entry_value
		if bool(entry.get("persistence_replay", false)):
			owners.append(String(entry.get("owner", "")))
	if owners.is_empty():
		return false
	for owner in owners:
		if String(owner) != SINGLE_PERSISTENCE_OWNER_ID:
			return false
	return true


## True iff every client-facing domain routes exclusively through the gateway.
## All declared domains are client-facing shared outpost state.
static func gateway_only_transport() -> bool:
	for entry_value in DOMAINS:
		var entry: Dictionary = entry_value
		if String(entry.get("transport_path", "")) != TRANSPORT_GATEWAY_ONLY:
			return false
	return true


## True iff this map is internally consistent and no forbidden private-truth
## store name is declared as a domain or owner. Later stages additionally call
## assert_domains_declared() from persistence call sites (P6.7+ enforcement).
static func no_private_truth() -> bool:
	if validate_map(DOMAINS).get("success", false) != true:
		return false
	for entry_value in DOMAINS:
		var entry: Dictionary = entry_value
		var label := "%s %s" % [String(entry.get("domain_id", "")), String(entry.get("owner", ""))]
		for forbidden in FORBIDDEN_PRIVATE_TRUTH_NAMES:
			if label.contains(String(forbidden)):
				return false
	return true


## Fail-closed gate for later stages: EVERY persisted domain id must already be
## declared here. Unknown ids are reported as PRIVATE_TRUTH_UNDECLARED.
static func assert_domains_declared(candidate_domain_ids: Array) -> Dictionary:
	var undeclared: Array = []
	for candidate_value in candidate_domain_ids:
		var candidate := String(candidate_value)
		if not is_domain_declared(candidate):
			undeclared.append(candidate)
	if not undeclared.is_empty():
		return {
			"success": false,
			"error_code": "PRIVATE_TRUTH_UNDECLARED",
			"undeclared_domain_ids": undeclared,
		}
	return {"success": true}


## --- Validation helpers (fail-closed; used by tests and future stages) ------

## Validate one candidate entry against the required schema and policies.
static func validate_domain(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return _validation_failure("EMPTY_DOMAIN_ENTRY")
	for field in REQUIRED_ENTRY_FIELDS:
		if not entry.has(field):
			return _validation_failure("MISSING_REQUIRED_FIELD", {"field": String(field)})
	for field in entry.keys():
		if not REQUIRED_ENTRY_FIELDS.has(field):
			return _validation_failure("UNKNOWN_FIELD", {"field": String(field)})
	var type_errors := {
		"domain_id": TYPE_STRING,
		"owner": TYPE_STRING,
		"persistence_replay": TYPE_BOOL,
		"reconnect_restore": TYPE_BOOL,
		"transport_path": TYPE_STRING,
		"write_authority": TYPE_STRING,
		"notes": TYPE_STRING,
	}
	for field in type_errors.keys():
		var expected: int = type_errors[field]
		if typeof(entry[field]) != expected:
			return _validation_failure("BAD_FIELD_TYPE", {"field": String(field)})
	var domain_id := String(entry["domain_id"])
	if not _is_canonical_domain_id(domain_id):
		return _validation_failure("NON_CANONICAL_DOMAIN_ID", {"domain_id": domain_id})
	if String(entry["transport_path"]) != TRANSPORT_GATEWAY_ONLY:
		return _validation_failure("NON_GATEWAY_TRANSPORT", {"transport_path": String(entry["transport_path"])})
	if String(entry["write_authority"]) != WRITE_AUTHORITY_SERVER_ONLY:
		return _validation_failure("INVALID_WRITE_AUTHORITY", {"write_authority": String(entry["write_authority"])})
	if not _is_namespaced_id(String(entry["owner"])):
		return _validation_failure("NON_CANONICAL_OWNER_ID", {"owner": String(entry["owner"])})
	return {"success": true}


## Validate a full candidate map: entry schema, unique ids, and exactly one
## persistence owner across all replay domains.
static func validate_map(domains: Array) -> Dictionary:
	if domains.is_empty():
		return _validation_failure("EMPTY_DOMAIN_MAP")
	var seen_ids: Dictionary = {}
	var replay_owners: Dictionary = {}
	for entry_value in domains:
		var entry: Dictionary = entry_value
		var domain_result := validate_domain(entry)
		if domain_result.get("success", false) != true:
			return domain_result
		var domain_id := String(entry["domain_id"])
		if seen_ids.has(domain_id):
			return _validation_failure("DUPLICATE_DOMAIN_ID", {"domain_id": domain_id})
		seen_ids[domain_id] = true
		if bool(entry["persistence_replay"]):
			replay_owners[String(entry["owner"])] = true
	if replay_owners.size() > 1:
		return _validation_failure(
			"MULTIPLE_PERSISTENCE_OWNERS",
			{"owners": replay_owners.keys()}
		)
	if replay_owners.is_empty():
		return _validation_failure("NO_PERSISTENCE_OWNER")
	return {"success": true}


## Admission check for adding a domain to the map WITHOUT mutating anything
## (this stage is declaration-only): the candidate must pass entry validation
## and the combined map [DOMAINS, candidate] must still satisfy every
## invariant. Returns success/failure; NEVER mutates DOMAINS.
static func try_register_domain(entry: Dictionary) -> Dictionary:
	var entry_result := validate_domain(entry)
	if entry_result.get("success", false) != true:
		return entry_result
	var combined: Array = DOMAINS.duplicate()
	combined.append(entry.duplicate(true))
	return validate_map(combined)


## --- Internals ---------------------------------------------------------------

static func _validation_failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	var failure := {"success": false, "error_code": error_code}
	for key in details.keys():
		failure[key] = details[key]
	return failure


static func _is_canonical_domain_id(domain_id: String) -> bool:
	if not domain_id.begins_with(DOMAIN_ID_PREFIX):
		return false
	return _is_lower_snake_tokens(domain_id.trim_prefix(DOMAIN_ID_PREFIX))


static func _is_namespaced_id(id: String) -> bool:
	var parts := id.split("/")
	if parts.size() < 2:
		return false
	for part in parts:
		if not _is_lower_snake_tokens(part):
			return false
	return true


static func _is_lower_snake_tokens(text: String) -> bool:
	if text.is_empty():
		return false
	var matcher := RegEx.new()
	matcher.compile("^[a-z0-9]+(-[a-z0-9]+)*$")
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

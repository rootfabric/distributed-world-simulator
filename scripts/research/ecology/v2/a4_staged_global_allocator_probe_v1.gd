extends RefCounted
## ECO ARCH2 A14.6 R2: TEST-ONLY, detached, resumable global A4 allocator.
## The existing Field.allocate_demands remains the ONE accepted biology
## authority. This prototype reconstructs BOTH its deterministic passes in
## bounded item batches, and executes the real A4 allocator once at the final
## proof barrier. NEVER use its partial cursors as canonical Field/Runtime.
##
## No LAB or WORLD_COMPAT production integration in R2. All inputs and
## speculative arrays are owned/detached. Hosts can cancel at any boundary
## simply by discarding the transient cursor. Checksums are host-integrity,
## NOT adversarial authentication. A single large demand, bucket, or sealing
## operation can still exceed the requested wall time.
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const F = preload("res://scripts/research/ecology/v2/environment_field_contract_v1.gd")
const Ports = preload("res://scripts/research/ecology/v2/organism_environment_ports_v1.gd")
const Field = preload("res://scripts/research/ecology/v2/local_environment_field_v1.gd")
const Frontier = preload("res://scripts/research/ecology/v2/a5_allocation_frontier_probe_v1.gd")

const SCHEMA := "dws.ecology.a14-6-r2-staged-global-a4.v1"
const PHASES := ["NORMALIZE", "BUILD_CLAIMS", "PRIMARY", "RESIDUAL", "FINALIZE"]
const DEFAULT_CURSOR_CAP_BYTES := 8388608
const MAX_CURSOR_CAP_BYTES := 16777216
const MAX_QUOTA := 4096
const KEYS := [
	"schema", "source_hash", "demands_hash", "owner_token", "owner_epoch",
	"revision", "phase", "index", "normalized", "seen", "primary_buckets",
	"residual_buckets", "primary_keys", "residual_keys",
	"grants", "working_field", "checksum",
]

static func begin(source: Dictionary, demands: Array, owner_token: String,
		owner_epoch: int, revision: int,
		cursor_cap_bytes: int = DEFAULT_CURSOR_CAP_BYTES) -> Dictionary:
	if not C.integer(cursor_cap_bytes, 1024, MAX_CURSOR_CAP_BYTES):
		return _fail("A14_6_R2_CAP_PARAMETERS")
	var precondition: String = _precondition(source, demands,
		owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	var demands_hash: String = C.digest(demands)
	if demands_hash.is_empty():
		return _fail("A14_6_R2_DEMANDS_HASH")
	var cursor := {
		"schema": SCHEMA,
		"source_hash": String(source.integrity_hash),
		"demands_hash": demands_hash,
		"owner_token": owner_token,
		"owner_epoch": owner_epoch,
		"revision": revision,
		"phase": "NORMALIZE",
		"index": 0,
		"normalized": [],
		"seen": {},
		"primary_buckets": {},
		"residual_buckets": {},
		"primary_keys": [],
		"residual_keys": [],
		"grants": {},
		"working_field": source.duplicate(true),
		"checksum": "",
	}
	var sealed: Dictionary = _seal_cursor(cursor, cursor_cap_bytes)
	if sealed.is_empty():
		return _fail("A14_6_R2_CURSOR_CAP")
	return {"success": true, "complete": false, "phase": "NORMALIZE",
		"processed_items": 0, "cursor": sealed}

static func resume(source: Dictionary, demands: Array, owner_token: String,
		owner_epoch: int, revision: int, cursor: Dictionary,
		max_items_per_call: int = 16,
		cursor_cap_bytes: int = DEFAULT_CURSOR_CAP_BYTES) -> Dictionary:
	if not C.integer(max_items_per_call, 1, MAX_QUOTA) \
			or not C.integer(cursor_cap_bytes, 1024, MAX_CURSOR_CAP_BYTES):
		return _fail("A14_6_R2_RESUME_PARAMETERS")
	# Trusted, sealed original state is revalidated on EVERY call. A4 itself
	# requires the same owner/epoch/revision/operation-count precondition.
	var precondition: String = _precondition(source, demands,
		owner_token, owner_epoch, revision)
	if not precondition.is_empty():
		return _fail(precondition)
	if not C.keys(cursor, KEYS) or String(cursor.get("schema", "")) != SCHEMA:
		return _fail("A14_6_R2_CURSOR_SCHEMA")
	if not cursor.normalized is Array or not cursor.seen is Dictionary \
			or not cursor.primary_buckets is Dictionary \
			or not cursor.residual_buckets is Dictionary \
			or not cursor.primary_keys is Array \
			or not cursor.residual_keys is Array \
			or not cursor.grants is Dictionary \
			or not cursor.working_field is Dictionary:
		return _fail("A14_6_R2_CURSOR_TYPES")
	var unsigned: Dictionary = cursor.duplicate(false)
	unsigned.checksum = ""
	var checksum: String = C.digest(unsigned)
	if checksum.is_empty() or checksum != String(cursor.checksum):
		return _fail("A14_6_R2_CURSOR_CHECKSUM")
	if String(cursor.source_hash) != String(source.integrity_hash) \
			or String(cursor.demands_hash) != C.digest(demands) \
			or String(cursor.owner_token) != owner_token \
			or int(cursor.owner_epoch) != owner_epoch \
			or int(cursor.revision) != revision:
		return _fail("A14_6_R2_SOURCE_CHANGED")
	var phase: String = String(cursor.phase)
	if not phase in PHASES:
		return _fail("A14_6_R2_CURSOR_PHASE")
	var total: int = _phase_count(phase, cursor, demands)
	if not C.integer(cursor.index, 0, total):
		return _fail("A14_6_R2_CURSOR_INDEX")
	# R2D: transaction-local phase copy-on-write (COW), not unchecked
	# mutation of the incoming immutable cursor. The legacy full deep-copy
	# cloned every already sealed field, demand and outcome on each A4
	# subphase, even when that subphase only touched one partition.
	#
	# The complete original checksum/source validation above is retained.
	# Copy only nested structures THIS phase actually writes; all others
	# remain read-only shared data. See R2D old-vs-new cursor-byte tests.
	var next: Dictionary = _copy_for_phase(cursor, phase)
	var index: int = int(next.index)
	var stop: int = mini(total, index + max_items_per_call)
	if phase == "NORMALIZE":
		var result: String = _normalize(next, source, demands, index, stop)
		if not result.is_empty():
			return _fail(result)
		if stop == total:
			next.normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return String(a.demand.request_id) < String(b.demand.request_id))
			_next_phase(next, "BUILD_CLAIMS")
	elif phase == "BUILD_CLAIMS":
		_build_claims(next, index, stop)
		if stop == total:
			var primary: Array = next.primary_buckets.keys()
			primary.sort()
			next.primary_keys = primary
			var residual: Array = next.residual_buckets.keys()
			residual.sort()
			next.residual_keys = residual
			_next_phase(next, "PRIMARY")
	elif phase == "PRIMARY":
		_primary(next, index, stop)
		if stop == total:
			_next_phase(next, "RESIDUAL")
	elif phase == "RESIDUAL":
		_residual(next, index, stop)
		if stop == total:
			_next_phase(next, "FINALIZE")
	elif phase == "FINALIZE":
		return _finalize(next, source, demands, owner_token,
			owner_epoch, revision)
	if phase != "FINALIZE" and stop < total:
		next.index = stop
	# Seal the detached speculative work, not the caller cursor. On a cap
	# failure no next cursor or state is returned (fail closed / cancel).
	var resealed: Dictionary = _seal_cursor(next, cursor_cap_bytes)
	if resealed.is_empty():
		return _fail("A14_6_R2_CURSOR_CAP")
	return {"success": true, "complete": false,
		"phase": String(resealed.phase), "processed_items": stop - index,
		"cursor": resealed}

static func _precondition(source: Dictionary, demands: Array,
		owner_token: String, owner_epoch: int, revision: int) -> String:
	var error: String = F.validate_state(source)
	if not error.is_empty():
		return "A14_6_R2_FIELD:" + error
	if owner_token != String(source.owner_token):
		return "A14_6_R2_STALE_OWNER"
	if owner_epoch != int(source.owner_epoch):
		return "A14_6_R2_STALE_OWNER_EPOCH"
	if revision != int(source.revision):
		return "A14_6_R2_STALE_REVISION"
	if revision >= F.MAX_REVISION:
		return "A14_6_R2_REVISION_LIMIT"
	if demands.is_empty():
		return "A14_6_R2_DEMAND_BATCH_EMPTY"
	if demands.size() > F.MAX_BATCH:
		return "A14_6_R2_DEMAND_BATCH_LIMIT"
	if int(source.operation_count) > C.MAX_INT - demands.size():
		return "A14_6_R2_OPERATION_COUNT_LIMIT"
	return ""

static func _phase_count(phase: String, cursor: Dictionary,
		demands: Array) -> int:
	if phase == "NORMALIZE":
		return demands.size()
	if phase == "BUILD_CLAIMS":
		return cursor.normalized.size()
	if phase == "PRIMARY":
		return cursor.primary_keys.size()
	if phase == "RESIDUAL":
		return cursor.residual_keys.size()
	return 1

static func _next_phase(cursor: Dictionary, phase: String) -> void:
	cursor.phase = phase
	cursor.index = 0

static func _normalize(next: Dictionary, source: Dictionary,
		demands: Array, first: int, stop: int) -> String:
	for pos in range(first, stop):
		var raw: Variant = demands[pos]
		var error: String = Ports.validate_demand(raw)
		if not error.is_empty():
			return "A14_6_R2_DEMAND:" + error
		var demand: Dictionary = raw
		var id: String = String(demand.request_id)
		if next.seen.has(id):
			return "A14_6_R2_DUPLICATE_REQUEST"
		next.seen[id] = true
		var indices: Array = Frontier.covered_cells(
			source, demand.position_mm, int(demand.extent_mm))
		if indices.is_empty():
			return "A14_6_R2_DEMAND_OUT_OF_BOUNDS"
		next.normalized.append({
			"demand": demand.duplicate(true),
			"indices": indices,
		})
	return ""

static func _build_claims(next: Dictionary, first: int, stop: int) -> void:
	var normalized: Array = next.normalized
	for pos in range(first, stop):
		var item: Dictionary = normalized[pos]
		var d: Dictionary = item.demand
		var id: String = String(d.request_id)
		next.grants[id] = {
			"request_id": id, "organism_id": String(d.organism_id),
			"resource": String(d.resource), "requested": int(d.amount),
			"granted": 0, "unmet": int(d.amount),
		}
		var indices: Array = item.indices
		var count: int = indices.size()
		var base_amount: int = int(d.amount / count)
		var remainder: int = int(d.amount) % count
		for i in count:
			var index: int = int(indices[i])
			var key := "%04d|%s" % [index, String(d.resource)]
			# Residual pro-rata includes all covered buckets even when
			# the primary amount in this bucket is ZERO.
			if not next.residual_buckets.has(key):
				next.residual_buckets[key] = []
			next.residual_buckets[key].append(id)
			var claim: int = base_amount + (1 if i < remainder else 0)
			if claim == 0:
				continue
			if not next.primary_buckets.has(key):
				next.primary_buckets[key] = []
			next.primary_buckets[key].append({"request_id": id, "amount": claim})

static func _primary(next: Dictionary, first: int, stop: int) -> void:
	for pos in range(first, stop):
		var key: String = String(next.primary_keys[pos])
		var parts: PackedStringArray = key.split("|")
		var index: int = int(parts[0])
		var resource: String = String(parts[1])
		var claims: Array = next.primary_buckets[key]
		claims.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.request_id) < String(b.request_id))
		var total_claim := 0
		for claim in claims:
			total_claim += int(claim.amount)
		var available: int = next.working_field.cells[index].stocks[resource]
		var target: int = mini(available, total_claim)
		var used := 0
		var cell_grants: Array = []
		for claim in claims:
			# This rounding rule MUST be byte-identical to the accepted A4.
			var amount: int = int(claim.amount) if total_claim <= available \
					else int(target * int(claim.amount) / total_claim)
			cell_grants.append({"request_id": String(claim.request_id),
				"amount": amount, "claim": int(claim.amount)})
			used += amount
		var leftover: int = target - used
		for grant in cell_grants:
			if leftover <= 0:
				break
			if int(grant.amount) < int(grant.claim):
				grant.amount += 1
				leftover -= 1
		for grant in cell_grants:
			if int(grant.amount) <= 0:
				continue
			var amount: int = int(grant.amount)
			next.working_field.cells[index].stocks[resource] -= amount
			next.working_field.ledger.outputs[resource] += amount
			next.grants[String(grant.request_id)].granted += amount

static func _residual(next: Dictionary, first: int, stop: int) -> void:
	for pos in range(first, stop):
		var key: String = String(next.residual_keys[pos])
		var parts: PackedStringArray = key.split("|")
		var index: int = int(parts[0])
		var resource: String = String(parts[1])
		var available: int = next.working_field.cells[index].stocks[resource]
		if available <= 0:
			continue
		var ids: Array = next.residual_buckets[key]
		ids.sort()
		var remaining_by_id := {}
		var total_remaining := 0
		for id in ids:
			var remaining: int = int(next.grants[id].requested) \
					- int(next.grants[id].granted)
			if remaining <= 0:
				continue
			remaining_by_id[id] = remaining
			total_remaining += remaining
		if total_remaining <= 0:
			continue
		var target: int = mini(available, total_remaining)
		var allocations: Array = []
		var used := 0
		for id in ids:
			if not remaining_by_id.has(id):
				continue
			var remaining: int = int(remaining_by_id[id])
			var amount: int = int(target * remaining / total_remaining)
			allocations.append({"request_id": id, "amount": amount,
				"remaining": remaining})
			used += amount
		var leftover: int = target - used
		for allocation in allocations:
			if leftover <= 0:
				break
			if int(allocation.amount) < int(allocation.remaining):
				allocation.amount += 1
				leftover -= 1
		for allocation in allocations:
			var amount: int = int(allocation.amount)
			if amount <= 0:
				continue
			next.working_field.cells[index].stocks[resource] -= amount
			next.working_field.ledger.outputs[resource] += amount
			next.grants[String(allocation.request_id)].granted += amount

static func _finalize(next: Dictionary, source: Dictionary, demands: Array,
		owner_token: String, owner_epoch: int, revision: int) -> Dictionary:
	for id in next.grants:
		next.grants[id].unmet = int(next.grants[id].requested) \
			- int(next.grants[id].granted)
	var state: Dictionary = next.working_field.duplicate(true)
	state.revision += 1
	state.operation_count += next.normalized.size()
	# The same sealing order as A4 Field._seal_mutated_state():
	# each changed cell first, then final global state integrity hash.
	for i in state.cells.size():
		state.cells[i] = F.seal_cell(state.cells[i])
	state = F.seal_state(state)
	var state_error: String = F.validate_state(state)
	if not state_error.is_empty():
		return _fail("A14_6_R2_FINAL_FIELD:" + state_error)
	var result_grants: Array = next.grants.values()
	result_grants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.request_id) < String(b.request_id))
	# R2 proof barrier: the single trusted A4 allocator runs once on the
	# unchanged original state. It is the ORIGINAL resource owner and
	# independently seals/validates the result. Performance gains are NOT
	# claimed while this expensive exact reference remains obligatory.
	var reference: Dictionary = Field.allocate_demands(
		source, demands, owner_token, owner_epoch, revision)
	if not bool(reference.get("success", false)):
		return _fail("A14_6_R2_REFERENCE:" + String(reference.get("error", "?")))
	if C.encode(state) != C.encode(reference.state) \
			or C.encode(result_grants) != C.encode(reference.grants) \
			or int(state.revision) != int(reference.revision) \
			or String(Field.state_hash(state)) != String(reference.state_hash):
		return _fail("A14_6_R2_REFERENCE_MISMATCH")
	if String(source.integrity_hash) != String(next.source_hash):
		return _fail("A14_6_R2_FINAL_SOURCE_CHANGED")
	# Only after full global proof do we expose ONE completed A4 result.
	# No partial cursor is a valid snapshot or authoritative field state.
	return {"success": true, "complete": true, "phase": "COMPLETE",
		"reference_equal": true, "state": state,
		"grants": result_grants, "revision": int(state.revision),
		"state_hash": Field.state_hash(state),
		"grants_hash": C.digest(result_grants)}

## R2D: preserve public cursor immutability with precise phase COW.
## NORMALIZE writes 'seen' and 'normalized'; BUILD_CLAIMS writes buckets
## and grants; PRIMARY/RESIDUAL alter the corresponding sort buckets,
## the working Field and the grant totals; FINALIZE changes only 'unmet'
## in grants before duplicating working_field into the finalized state.
## Every aliased input container is read-only in its selected phase.
static func _copy_for_phase(cursor: Dictionary, phase: String) -> Dictionary:
	var next: Dictionary = cursor.duplicate(false)
	match phase:
		"NORMALIZE":
			next["normalized"] = cursor.normalized.duplicate(true)
			next["seen"] = cursor.seen.duplicate(true)
		"BUILD_CLAIMS":
			next["primary_buckets"] = cursor.primary_buckets.duplicate(true)
			next["residual_buckets"] = cursor.residual_buckets.duplicate(true)
			next["grants"] = cursor.grants.duplicate(true)
		"PRIMARY":
			next["primary_buckets"] = cursor.primary_buckets.duplicate(true)
			next["grants"] = cursor.grants.duplicate(true)
			next["working_field"] = cursor.working_field.duplicate(true)
		"RESIDUAL":
			next["residual_buckets"] = cursor.residual_buckets.duplicate(true)
			next["grants"] = cursor.grants.duplicate(true)
			next["working_field"] = cursor.working_field.duplicate(true)
		"FINALIZE":
			next["grants"] = cursor.grants.duplicate(true)
	return next

static func _seal_cursor(cursor: Dictionary, cap_bytes: int) -> Dictionary:
	cursor.checksum = ""
	# The original C.digest(cursor) calls C.encode() once, then encodes
	# the exact same large cursor AGAIN after populating the checksum
	# solely to enforce the cap. Encode the canonical unsigned object
	# once and compute the identical SHA256 directly.
	var unsigned_text: String = C.encode(cursor)
	if unsigned_text.is_empty():
		return {}
	var digest: String = unsigned_text.sha256_text()
	# The canonical representation includes checksum as JSON string "".
	# Replacing it with a SHA256 hex string adds EXACTLY 64 ASCII/UTF8
	# bytes (no escaping changes). This preserves the original sealed
	# cursor byte cap without a second O(cursor size) encode.
	if digest.length() != 64:
		return {}
	cursor.checksum = digest
	if unsigned_text.to_utf8_buffer().size() + 64 > cap_bytes:
		return {}
	return cursor

static func _fail(error: String) -> Dictionary:
	return {"success": false, "error": error}

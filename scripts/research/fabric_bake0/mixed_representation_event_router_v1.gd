extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const O = preload("res://scripts/research/fabric_bake0/mixed_representation_ownership_contract_v1.gd")
const S = preload("res://scripts/research/fabric_bake0/mixed_representation_executable_subject_v1.gd")
const F = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const A = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const RI = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")

const ROUTE_SCHEMA := "planet_simulator.fabric_bake_cross_representation_event_route.v1"
const RECEIPT_SCHEMA := "planet_simulator.fabric_bake_cross_representation_commit_receipt.v1"
const COMMIT_SCHEMA := "planet_simulator.fabric_bake_cross_representation_event_commit.v1"
const QUALIFICATION := "BRIDGE_2_C_CROSS_REPRESENTATION_EVENT_ROUTING"
const ROUTE_FIELDS: Array[String] = ["schema","subject_hash","ownership_contract_hash","source_frontier_hash","authority_epoch_binding","event_id","region_id","event_kind","canonical_effect","candidate_representation_ids","emitter_representation_id","emitter_execution_identity_hash","emitter_runtime_state_hash","evaluator_representation_id","evaluator_execution_identity_hash","commit_owner","canonical_revision_policy","event_commit_policy","observer_routes","routing_qualification","route_hash","checksum"]
const OBS_FIELDS: Array[String] = ["delivery_id","event_id","representation_id","representation_kind","witness_hash","execution_identity_hash","delivery_role","canonical_write_authorized","delivery_hash"]
const RECEIPT_FIELDS: Array[String] = ["schema","event_id","canonical_effect","commit_owner","previous_source_frontier_hash","current_source_frontier","current_authority_envelope","representation_invalidation","canonical_revision_advanced","source_mutation_kind","receipt_hash","checksum"]
const COMMIT_FIELDS: Array[String] = ["schema","route_hash","receipt_hash","event_id","canonical_effect","commit_owner","previous_source_frontier_hash","current_source_frontier_hash","canonical_revision_advanced","source_invalidation_checksum","observer_deliveries","ledger_append_event_id","commit_state","commit_hash","checksum"]
const DELIVERY_FIELDS: Array[String] = ["delivery_id","event_id","representation_id","delivery_kind","canonical_write_authorized","receipt_hash","delivery_hash"]

static func prepare_route(subject: Dictionary, ownership: Dictionary, event: Dictionary, emitter_id: String, execution_hash: String, state_hash: String, committed: Array = []) -> Dictionary:
	var c := S.validate(subject, ownership)
	if not _ok(c): return c
	c = U.validate_sorted_unique_strings(committed, true)
	if not _ok(c): return U.failure("BRIDGE2_C_INVALID_EXTERNAL_EVENT_LEDGER")
	var rr := O.resolve_event(ownership, event, committed)
	if not _ok(rr): return rr
	var r: Dictionary = rr["details"]["resolution"]
	if emitter_id != String(r["evaluator_representation_id"]): return U.failure("BRIDGE2_C_EMITTER_NOT_ACTIVE_EVALUATOR")
	var e := _entry(subject, emitter_id)
	if e.is_empty(): return U.failure("BRIDGE2_C_EMITTER_EXECUTABLE_WITNESS_MISSING")
	if execution_hash != String(e["execution_identity_hash"]): return U.failure("BRIDGE2_C_EMITTER_EXECUTION_IDENTITY_MISMATCH")
	if state_hash != String(e["runtime_state_hash"]): return U.failure("BRIDGE2_C_EMITTER_RUNTIME_STATE_MISMATCH")
	var obs: Array = []
	for i in range(r["observer_representation_ids"].size()):
		var id := String(r["observer_representation_ids"][i])
		var oe := _entry(subject, id)
		if oe.is_empty(): return U.failure("BRIDGE2_C_OBSERVER_EXECUTABLE_WITNESS_MISSING")
		var d := {"delivery_id":"delivery/bridge2-c/%s/%02d" % [_token(String(event["event_id"])),i],"event_id":String(event["event_id"]),"representation_id":id,"representation_kind":String(oe["representation_kind"]),"witness_hash":String(oe["witness_hash"]),"execution_identity_hash":String(oe["execution_identity_hash"]),"delivery_role":"OBSERVER","canonical_write_authorized":false,"delivery_hash":""}
		d["delivery_hash"] = U.canonical_hash(_without(d,["delivery_hash"]))
		obs.append(d)
	var v := {"schema":ROUTE_SCHEMA,"subject_hash":String(subject["subject_hash"]),"ownership_contract_hash":String(ownership["contract_hash"]),"source_frontier_hash":String(subject["canonical_source_frontier_hash"]),"authority_epoch_binding":String(subject["authority_epoch_binding"]),"event_id":String(event["event_id"]),"region_id":String(event["region_id"]),"event_kind":String(event["event_kind"]),"canonical_effect":String(event["canonical_effect"]),"candidate_representation_ids":event["candidate_representation_ids"].duplicate(true),"emitter_representation_id":emitter_id,"emitter_execution_identity_hash":execution_hash,"emitter_runtime_state_hash":state_hash,"evaluator_representation_id":String(r["evaluator_representation_id"]),"evaluator_execution_identity_hash":String(e["execution_identity_hash"]),"commit_owner":String(r["commit_owner"]),"canonical_revision_policy":String(r["canonical_revision_policy"]),"event_commit_policy":String(r["event_commit_policy"]),"observer_routes":obs,"routing_qualification":QUALIFICATION,"route_hash":"","checksum":""}
	v["route_hash"] = U.canonical_hash(_without(v,["route_hash","checksum"]))
	v["checksum"] = U.compute_checksum(v)
	c = validate_route(v, subject, ownership)
	return U.success({"route":v}) if _ok(c) else c

static func validate_route(v: Dictionary, subject: Dictionary, ownership: Dictionary) -> Dictionary:
	var c := S.validate(subject, ownership)
	if not _ok(c): return c
	c = U.validate_exact_fields(v, ROUTE_FIELDS)
	if not _ok(c): return c
	if v.get("schema") != ROUTE_SCHEMA: return U.failure("UNSUPPORTED_BRIDGE2_C_ROUTE_SCHEMA")
	if String(v["subject_hash"]) != String(subject["subject_hash"]): return U.failure("BRIDGE2_C_ROUTE_SUBJECT_MISMATCH")
	if String(v["ownership_contract_hash"]) != String(ownership["contract_hash"]): return U.failure("BRIDGE2_C_ROUTE_OWNERSHIP_MISMATCH")
	if String(v["source_frontier_hash"]) != String(subject["canonical_source_frontier_hash"]): return U.failure("BRIDGE2_C_ROUTE_FRONTIER_MISMATCH")
	if String(v["authority_epoch_binding"]) != String(subject["authority_epoch_binding"]): return U.failure("BRIDGE2_C_ROUTE_AUTHORITY_MISMATCH")
	if String(v["routing_qualification"]) != QUALIFICATION or String(v["event_commit_policy"]) != O.EVENT_COMMIT_POLICY: return U.failure("BRIDGE2_C_ROUTE_NOT_QUALIFIED")
	var ev := {"event_id":String(v["event_id"]),"region_id":String(v["region_id"]),"event_kind":String(v["event_kind"]),"canonical_effect":String(v["canonical_effect"]),"candidate_representation_ids":v["candidate_representation_ids"].duplicate(true)}
	var rr := O.resolve_event(ownership, ev, [])
	if not _ok(rr): return U.failure("BRIDGE2_C_ROUTE_OWNERSHIP_RESOLUTION_INVALID")
	var r: Dictionary = rr["details"]["resolution"]
	if String(v["evaluator_representation_id"]) != String(r["evaluator_representation_id"]): return U.failure("BRIDGE2_C_ROUTE_EVALUATOR_OWNERSHIP_MISMATCH")
	if String(v["commit_owner"]) != String(r["commit_owner"]): return U.failure("BRIDGE2_C_ROUTE_COMMIT_OWNER_OWNERSHIP_MISMATCH")
	if String(v["canonical_revision_policy"]) != String(r["canonical_revision_policy"]): return U.failure("BRIDGE2_C_ROUTE_REVISION_POLICY_OWNERSHIP_MISMATCH")
	if String(v["emitter_representation_id"]) != String(v["evaluator_representation_id"]): return U.failure("BRIDGE2_C_ROUTE_EMITTER_EVALUATOR_MISMATCH")
	var e := _entry(subject,String(v["emitter_representation_id"]))
	if e.is_empty(): return U.failure("BRIDGE2_C_ROUTE_EMITTER_WITNESS_MISSING")
	if String(v["emitter_execution_identity_hash"]) != String(e["execution_identity_hash"]) or String(v["evaluator_execution_identity_hash"]) != String(e["execution_identity_hash"]): return U.failure("BRIDGE2_C_ROUTE_EMITTER_EXECUTION_MISMATCH")
	if String(v["emitter_runtime_state_hash"]) != String(e["runtime_state_hash"]): return U.failure("BRIDGE2_C_ROUTE_EMITTER_STATE_MISMATCH")
	if typeof(v["observer_routes"]) != TYPE_ARRAY or v["observer_routes"].size() != r["observer_representation_ids"].size(): return U.failure("BRIDGE2_C_OBSERVER_ROUTE_OWNERSHIP_COVERAGE_MISMATCH")
	for i in range(v["observer_routes"].size()):
		var d: Dictionary = v["observer_routes"][i]
		c = U.validate_exact_fields(d, OBS_FIELDS)
		if not _ok(c): return c
		if String(d["representation_id"]) != String(r["observer_representation_ids"][i]): return U.failure("BRIDGE2_C_OBSERVER_ROUTE_OWNERSHIP_MISMATCH")
		if String(d["event_id"]) != String(v["event_id"]) or String(d["delivery_role"]) != "OBSERVER" or bool(d["canonical_write_authorized"]): return U.failure("BRIDGE2_C_OBSERVER_CANONICAL_WRITE_FORBIDDEN")
		var oe := _entry(subject,String(d["representation_id"]))
		if oe.is_empty() or String(d["representation_kind"]) != String(oe["representation_kind"]) or String(d["witness_hash"]) != String(oe["witness_hash"]) or String(d["execution_identity_hash"]) != String(oe["execution_identity_hash"]): return U.failure("BRIDGE2_C_OBSERVER_EXECUTION_BINDING_MISMATCH")
		if String(d["delivery_hash"]) != U.canonical_hash(_without(d,["delivery_hash"])): return U.failure("BRIDGE2_C_OBSERVER_ROUTE_HASH_MISMATCH")
	if not U.is_lower_hex_64(v["route_hash"]) or String(v["route_hash"]) != U.canonical_hash(_without(v,["route_hash","checksum"])): return U.failure("BRIDGE2_C_ROUTE_HASH_MISMATCH")
	return U.validate_checksum(v)

static func create_commit_receipt(route: Dictionary, ownership: Dictionary, frontier: Dictionary, authority: Dictionary, invalidation: Dictionary = {}, mutation_kind: String = "NONE") -> Dictionary:
	var c := O.validate(ownership)
	if not _ok(c): return c
	c = F.validate(frontier)
	if not _ok(c): return c
	c = A.validate_b0_safety(authority)
	if not _ok(c): return c
	var canonical := String(route.get("canonical_effect","")) == "CANONICAL_MUTATION"
	var v := {"schema":RECEIPT_SCHEMA,"event_id":String(route.get("event_id","")),"canonical_effect":String(route.get("canonical_effect","")),"commit_owner":String(route.get("commit_owner","")),"previous_source_frontier_hash":String(route.get("source_frontier_hash","")),"current_source_frontier":frontier.duplicate(true),"current_authority_envelope":authority.duplicate(true),"representation_invalidation":invalidation.duplicate(true),"canonical_revision_advanced":canonical,"source_mutation_kind":mutation_kind,"receipt_hash":"","checksum":""}
	v["receipt_hash"] = U.canonical_hash(_without(v,["receipt_hash","checksum"]))
	v["checksum"] = U.compute_checksum(v)
	c = validate_receipt(v,route,ownership)
	return U.success({"receipt":v}) if _ok(c) else c

static func validate_receipt(v: Dictionary, route: Dictionary, ownership: Dictionary) -> Dictionary:
	var c := O.validate(ownership)
	if not _ok(c): return c
	c = U.validate_exact_fields(v, RECEIPT_FIELDS)
	if not _ok(c): return c
	if v.get("schema") != RECEIPT_SCHEMA: return U.failure("UNSUPPORTED_BRIDGE2_C_RECEIPT_SCHEMA")
	if String(v["event_id"]) != String(route["event_id"]): return U.failure("BRIDGE2_C_RECEIPT_EVENT_MISMATCH")
	if String(v["canonical_effect"]) != String(route["canonical_effect"]): return U.failure("BRIDGE2_C_RECEIPT_EFFECT_MISMATCH")
	if String(v["commit_owner"]) != String(route["commit_owner"]): return U.failure("BRIDGE2_C_RECEIPT_COMMIT_OWNER_MISMATCH")
	if String(v["previous_source_frontier_hash"]) != String(route["source_frontier_hash"]): return U.failure("BRIDGE2_C_RECEIPT_PREVIOUS_FRONTIER_MISMATCH")
	c = F.validate(v["current_source_frontier"])
	if not _ok(c): return c
	c = A.validate_b0_safety(v["current_authority_envelope"])
	if not _ok(c): return c
	if String(v["current_authority_envelope"]["authority_epoch_binding"]) != String(route["authority_epoch_binding"]): return U.failure("BRIDGE2_C_RECEIPT_AUTHORITY_BINDING_CHANGED")
	if String(route["canonical_effect"]) == "CANONICAL_MUTATION":
		if not bool(v["canonical_revision_advanced"]): return U.failure("BRIDGE2_C_CANONICAL_RECEIPT_REVISION_NOT_ADVANCED")
		if String(v["current_source_frontier"]["frontier_hash"]) == String(route["source_frontier_hash"]): return U.failure("BRIDGE2_C_CANONICAL_RECEIPT_FRONTIER_NOT_ADVANCED")
		if String(v["current_authority_envelope"]["execution_owner"]) != String(route["commit_owner"]): return U.failure("BRIDGE2_C_CANONICAL_RECEIPT_OWNER_MISMATCH")
		if typeof(v["representation_invalidation"]) != TYPE_DICTIONARY or v["representation_invalidation"].is_empty(): return U.failure("BRIDGE2_C_CANONICAL_RECEIPT_INVALIDATION_REQUIRED")
		c = RI.validate(v["representation_invalidation"])
		if not _ok(c): return c
		if String(v["source_mutation_kind"]) == "NONE": return U.failure("BRIDGE2_C_CANONICAL_RECEIPT_MUTATION_KIND_REQUIRED")
		if not _has_revision(v["current_source_frontier"],v["representation_invalidation"]["new_source_revision"]): return U.failure("BRIDGE2_C_CANONICAL_RECEIPT_NEW_REVISION_NOT_IN_FRONTIER")
	else:
		if bool(v["canonical_revision_advanced"]): return U.failure("BRIDGE2_C_DERIVED_RECEIPT_CANONICAL_REVISION_FORBIDDEN")
		if String(v["current_source_frontier"]["frontier_hash"]) != String(route["source_frontier_hash"]): return U.failure("BRIDGE2_C_DERIVED_RECEIPT_FRONTIER_CHANGED")
		if not v["representation_invalidation"].is_empty(): return U.failure("BRIDGE2_C_DERIVED_RECEIPT_INVALIDATION_FORBIDDEN")
		if String(v["source_mutation_kind"]) != "NONE": return U.failure("BRIDGE2_C_DERIVED_RECEIPT_MUTATION_FORBIDDEN")
	if not U.is_lower_hex_64(v["receipt_hash"]) or String(v["receipt_hash"]) != U.canonical_hash(_without(v,["receipt_hash","checksum"])): return U.failure("BRIDGE2_C_RECEIPT_HASH_MISMATCH")
	return U.validate_checksum(v)

static func commit_route(route: Dictionary, receipt: Dictionary, subject: Dictionary, ownership: Dictionary, committed: Array = []) -> Dictionary:
	var c := validate_route(route,subject,ownership)
	if not _ok(c): return c
	c = validate_receipt(receipt,route,ownership)
	if not _ok(c): return c
	c = U.validate_sorted_unique_strings(committed,true)
	if not _ok(c): return U.failure("BRIDGE2_C_INVALID_EXTERNAL_EVENT_LEDGER")
	if committed.has(String(route["event_id"])): return U.failure("BRIDGE2_C_EVENT_ALREADY_COMMITTED")
	var kind := "CANONICAL_COMMIT_OBSERVATION" if String(route["canonical_effect"]) == "CANONICAL_MUTATION" else "DERIVED_EVENT_OBSERVATION"
	var ds: Array = []
	for p in route["observer_routes"]:
		var d := {"delivery_id":String(p["delivery_id"]),"event_id":String(route["event_id"]),"representation_id":String(p["representation_id"]),"delivery_kind":kind,"canonical_write_authorized":false,"receipt_hash":String(receipt["receipt_hash"]),"delivery_hash":""}
		d["delivery_hash"] = U.canonical_hash(_without(d,["delivery_hash"]))
		ds.append(d)
	var inv := "" if receipt["representation_invalidation"].is_empty() else String(receipt["representation_invalidation"]["checksum"])
	var v := {"schema":COMMIT_SCHEMA,"route_hash":String(route["route_hash"]),"receipt_hash":String(receipt["receipt_hash"]),"event_id":String(route["event_id"]),"canonical_effect":String(route["canonical_effect"]),"commit_owner":String(route["commit_owner"]),"previous_source_frontier_hash":String(route["source_frontier_hash"]),"current_source_frontier_hash":String(receipt["current_source_frontier"]["frontier_hash"]),"canonical_revision_advanced":bool(receipt["canonical_revision_advanced"]),"source_invalidation_checksum":inv,"observer_deliveries":ds,"ledger_append_event_id":String(route["event_id"]),"commit_state":"COMMITTED","commit_hash":"","checksum":""}
	v["commit_hash"] = U.canonical_hash(_without(v,["commit_hash","checksum"]))
	v["checksum"] = U.compute_checksum(v)
	c = validate_commit(v,route,receipt)
	return U.success({"commit":v}) if _ok(c) else c

static func validate_commit(v: Dictionary, route: Dictionary, receipt: Dictionary) -> Dictionary:
	var c := U.validate_exact_fields(v, COMMIT_FIELDS)
	if not _ok(c): return c
	if v.get("schema") != COMMIT_SCHEMA: return U.failure("UNSUPPORTED_BRIDGE2_C_COMMIT_SCHEMA")
	if String(v["route_hash"]) != String(route["route_hash"]): return U.failure("BRIDGE2_C_COMMIT_ROUTE_MISMATCH")
	if String(v["receipt_hash"]) != String(receipt["receipt_hash"]): return U.failure("BRIDGE2_C_COMMIT_RECEIPT_MISMATCH")
	if String(v["event_id"]) != String(route["event_id"]) or String(v["commit_owner"]) != String(route["commit_owner"]): return U.failure("BRIDGE2_C_COMMIT_EVENT_OR_OWNER_MISMATCH")
	if String(v["commit_state"]) != "COMMITTED" or String(v["ledger_append_event_id"]) != String(v["event_id"]): return U.failure("BRIDGE2_C_COMMIT_STATE_OR_LEDGER_INVALID")
	if typeof(v["observer_deliveries"]) != TYPE_ARRAY or v["observer_deliveries"].size() != route["observer_routes"].size(): return U.failure("BRIDGE2_C_OBSERVER_DELIVERY_COVERAGE_MISMATCH")
	for i in range(v["observer_deliveries"].size()):
		var d: Dictionary = v["observer_deliveries"][i]
		c = U.validate_exact_fields(d, DELIVERY_FIELDS)
		if not _ok(c): return c
		if String(d["delivery_id"]) != String(route["observer_routes"][i]["delivery_id"]) or bool(d["canonical_write_authorized"]): return U.failure("BRIDGE2_C_OBSERVER_DELIVERY_ROUTE_OR_WRITE_MISMATCH")
		if String(d["receipt_hash"]) != String(receipt["receipt_hash"]) or String(d["delivery_hash"]) != U.canonical_hash(_without(d,["delivery_hash"])): return U.failure("BRIDGE2_C_OBSERVER_DELIVERY_RECEIPT_OR_HASH_MISMATCH")
	if not U.is_lower_hex_64(v["commit_hash"]) or String(v["commit_hash"]) != U.canonical_hash(_without(v,["commit_hash","checksum"])): return U.failure("BRIDGE2_C_COMMIT_HASH_MISMATCH")
	return U.validate_checksum(v)

static func _entry(subject: Dictionary,id: String) -> Dictionary:
	for e in subject.get("entries",[]):
		if String(e.get("representation_id","")) == id: return e
	return {}

static func _has_revision(frontier: Dictionary, rev: Dictionary) -> bool:
	for s in frontier.get("sources",[]):
		if String(s.get("source_domain","")) == String(rev.get("source_domain","")) and String(s.get("source_id","")) == String(rev.get("source_id","")) and int(s.get("authority_epoch",-1)) == int(rev.get("authority_epoch",-2)) and int(s.get("source_revision",-1)) == int(rev.get("source_revision",-2)): return true
	return false

static func _token(id: String) -> String: return U.canonical_hash({"event_id":id}).substr(0,12)
static func _ok(v: Dictionary) -> bool: return bool(v.get("success",false))
static func _without(v: Dictionary, fields: Array) -> Dictionary:
	var p := v.duplicate(true)
	for f in fields: p.erase(f)
	return p

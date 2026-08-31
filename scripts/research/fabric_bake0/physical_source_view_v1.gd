extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")

const REQUEST_FIELDS: Array[String] = ["canonical_source_frontier", "authority_envelope", "payloads"]
const PAYLOAD_FIELDS: Array[String] = ["source_domain", "source_id", "payload"]
const KIND := "BRIDGE1_PHYSICAL_SOURCE_VIEW"

static func create(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE1_INVALID_SOURCE_FRONTIER")
	checked = Frontier.validate(request["canonical_source_frontier"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(request.get("authority_envelope")) != TYPE_DICTIONARY:
		return Utils.failure("BRIDGE1_INVALID_AUTHORITY_ENVELOPE")
	checked = AuthorityEnvelope.validate_b0_safety(request["authority_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	if typeof(request.get("payloads")) != TYPE_ARRAY:
		return Utils.failure("BRIDGE1_INVALID_SOURCE_PAYLOADS")

	var frontier: Dictionary = request["canonical_source_frontier"]
	var payload_by_key: Dictionary = {}
	var bindings: Array = []
	for raw in request["payloads"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE1_INVALID_SOURCE_PAYLOAD")
		var payload_record: Dictionary = raw
		checked = Utils.validate_exact_fields(payload_record, PAYLOAD_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var domain := String(payload_record.get("source_domain", ""))
		var source_id := String(payload_record.get("source_id", ""))
		if not Utils.is_source_domain(domain) or not Utils.is_canonical_id(source_id, 2):
			return Utils.failure("BRIDGE1_INVALID_SOURCE_PAYLOAD_ID")
		if typeof(payload_record.get("payload")) != TYPE_DICTIONARY:
			return Utils.failure("BRIDGE1_SOURCE_PAYLOAD_NOT_DICTIONARY", {"source_id": source_id})
		var key := Utils.source_key(domain, source_id)
		if payload_by_key.has(key):
			return Utils.failure("BRIDGE1_DUPLICATE_SOURCE_PAYLOAD", {"source_key": key})
		var source := _find_source(frontier, domain, source_id)
		if source.is_empty():
			return Utils.failure("BRIDGE1_PAYLOAD_OUTSIDE_SOURCE_FRONTIER", {"source_key": key})
		var payload_hash := Utils.canonical_hash(payload_record["payload"])
		if payload_hash != String(source["source_hash"]):
			return Utils.failure("BRIDGE1_SOURCE_PAYLOAD_HASH_MISMATCH", {
				"source_key": key,
				"declared": source["source_hash"],
				"actual": payload_hash,
			})
		payload_by_key[key] = Dictionary(payload_record["payload"]).duplicate(true)
		bindings.append({"source_key": key, "payload_hash": payload_hash})

	var source_keys := Frontier.source_keys(frontier)
	if payload_by_key.size() != source_keys.size():
		return Utils.failure("BRIDGE1_SOURCE_PAYLOAD_COVERAGE_MISMATCH", {
			"payloads": payload_by_key.size(), "sources": source_keys.size(),
		})
	for key in source_keys:
		if not payload_by_key.has(String(key)):
			return Utils.failure("BRIDGE1_SOURCE_PAYLOAD_MISSING", {"source_key": key})

	bindings = Utils.sorted_dicts(bindings, "source_key")
	return {
		"success": true,
		"kind": KIND,
		"frontier": frontier.duplicate(true),
		"authority_envelope": Dictionary(request["authority_envelope"]).duplicate(true),
		"payload_by_key": payload_by_key,
		"payload_bindings": bindings,
		"view_hash": Utils.canonical_hash({
			"frontier_hash": frontier["frontier_hash"],
			"authority_binding": request["authority_envelope"]["authority_epoch_binding"],
			"payload_bindings": bindings,
		}),
	}

static func payload(view: Dictionary, source_domain: String, source_id: String) -> Dictionary:
	if not bool(view.get("success", false)) or String(view.get("kind", "")) != KIND:
		return {}
	var key := Utils.source_key(source_domain, source_id)
	if not Dictionary(view.get("payload_by_key", {})).has(key):
		return {}
	return Dictionary(view["payload_by_key"][key]).duplicate(true)

static func _find_source(frontier: Dictionary, source_domain: String, source_id: String) -> Dictionary:
	for source in frontier.get("sources", []):
		if String(source.get("source_domain", "")) == source_domain and String(source.get("source_id", "")) == source_id:
			return Dictionary(source)
	return {}

extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")
const InteractionTimeScript = preload("res://scripts/network/gateway/interaction_time.gd")
const CollisionQueryScript = preload("res://scripts/network/gateway/collision_query.gd")

const SCHEMA := "planet_simulator.collision_proof.v1"
const PROTOCOL_VERSION := 1
const COLLISION_KINDS: Array[String] = ["NONE", "STATIC", "ENTITY", "TERRAIN", "BOUNDARY"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"interaction_id",
	"query_revision",
	"world_id",
	"authority_id",
	"authority_epoch",
	"path_t_start",
	"path_t_end",
	"first_collision_t",
	"collided_entity_id",
	"collision_kind",
	"hit_zone",
	"interaction_time",
	"history_revision",
	"transform_revision",
	"proof_revision",
]


static func create(
		interaction_id: String,
		query_revision: int,
		world_id: String,
		authority_id: String,
		authority_epoch: int,
		path_t_start: float,
		path_t_end: float,
		first_collision_t,
		collided_entity_id,
		collision_kind: String,
		hit_zone,
		interaction_time: Dictionary,
		history_revision: int,
		transform_revision: int,
		proof_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"interaction_id": interaction_id,
		"query_revision": query_revision,
		"world_id": world_id,
		"authority_id": authority_id,
		"authority_epoch": authority_epoch,
		"path_t_start": path_t_start,
		"path_t_end": path_t_end,
		"first_collision_t": first_collision_t,
		"collided_entity_id": collided_entity_id,
		"collision_kind": collision_kind,
		"hit_zone": hit_zone,
		"interaction_time": interaction_time.duplicate(true),
		"history_revision": history_revision,
		"transform_revision": transform_revision,
		"proof_revision": proof_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["interaction_id", "interaction"],
		["world_id", "world"],
		["authority_id", "authority"],
	]:
		var id_check: Dictionary = CwipUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_positive_integer(value, "query_revision"),
		CwipUtilsScript.require_positive_integer(value, "authority_epoch"),
		CwipUtilsScript.require_path_range(value),
		GatewayUtilsScript.require_enum(value, "collision_kind", COLLISION_KINDS),
		CwipUtilsScript.require_positive_integer(value, "history_revision"),
		CwipUtilsScript.require_positive_integer(value, "transform_revision"),
		CwipUtilsScript.require_positive_integer(value, "proof_revision"),
		CwipUtilsScript.require_optional_string(value, "hit_zone"),
	]:
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("interaction_time")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_INTERACTION_TIME", "interaction_time must be a Dictionary")
	var time_check: Dictionary = InteractionTimeScript.validate(Dictionary(value.get("interaction_time")))
	if not bool(time_check.get("success", false)):
		return time_check
	var collision_kind := String(value.get("collision_kind"))
	if collision_kind == "NONE":
		if value.get("first_collision_t") != null or value.get("collided_entity_id") != null or value.get("hit_zone") != null:
			return NetworkUtilsScript.validation_failure("INVALID_NO_COLLISION_PROOF", "NONE proof cannot carry collision fields")
		return NetworkUtilsScript.validation_success()
	var first_collision_check: Dictionary = CwipUtilsScript.require_nonnegative_number(value, "first_collision_t")
	if not bool(first_collision_check.get("success", false)):
		return first_collision_check
	var first_t := float(value.get("first_collision_t"))
	if first_t < float(value.get("path_t_start")) or first_t > float(value.get("path_t_end")):
		return NetworkUtilsScript.validation_failure("INVALID_COLLISION_T", "first_collision_t must be within proof path range")
	var entity_check: Dictionary = CwipUtilsScript.require_optional_id(value, "collided_entity_id", "entity")
	if not bool(entity_check.get("success", false)):
		return entity_check
	if collision_kind == "ENTITY" and value.get("collided_entity_id") == null:
		return NetworkUtilsScript.validation_failure("MISSING_COLLIDED_ENTITY", "ENTITY collision requires collided_entity_id")
	return NetworkUtilsScript.validation_success()


static func validate_against_query(proof: Dictionary, query: Dictionary) -> Dictionary:
	var proof_check: Dictionary = validate(proof)
	if not bool(proof_check.get("success", false)):
		return proof_check
	var query_check: Dictionary = CollisionQueryScript.validate(query)
	if not bool(query_check.get("success", false)):
		return query_check
	if String(proof.get("interaction_id")) != String(query.get("interaction_id")) \
			or int(proof.get("query_revision")) != int(query.get("query_revision")):
		return NetworkUtilsScript.validation_failure(
			"PROOF_QUERY_MISMATCH",
			"CollisionProof must bind to the exact CollisionQuery revision",
		)
	var segment: Dictionary = Dictionary(query.get("domain_segment"))
	if String(proof.get("world_id")) != String(segment.get("world_id")) \
			or String(proof.get("authority_id")) != String(segment.get("authority_ref")):
		return NetworkUtilsScript.validation_failure(
			"PROOF_DOMAIN_MISMATCH",
			"CollisionProof world/authority must match queried domain",
		)
	if int(proof.get("authority_epoch")) != int(query.get("authority_epoch_observed")):
		return NetworkUtilsScript.validation_failure(
			"STALE_AUTHORITY_EPOCH_EVIDENCE",
			"CollisionProof authority_epoch must match queried authority epoch",
		)
	if not is_equal_approx(float(proof.get("path_t_start")), float(segment.get("path_t_start"))) \
			or not is_equal_approx(float(proof.get("path_t_end")), float(segment.get("path_t_end"))):
		return NetworkUtilsScript.validation_failure(
			"PROOF_DOMAIN_MISMATCH",
			"CollisionProof path range must match queried domain segment",
		)
	if NetworkUtilsScript.canonical_json(proof.get("interaction_time")) != NetworkUtilsScript.canonical_json(query.get("interaction_time")):
		return NetworkUtilsScript.validation_failure(
			"STALE_INTERACTION_TIME_EVIDENCE",
			"CollisionProof interaction_time must match CollisionQuery",
		)
	var evidence: Dictionary = Dictionary(segment.get("reference_frame_evidence"))
	if int(proof.get("transform_revision")) != int(evidence.get("transform_revision")):
		return NetworkUtilsScript.validation_failure(
			"STALE_TRANSFORM_EVIDENCE",
			"CollisionProof transform_revision must match queried reference-frame evidence",
		)
	return NetworkUtilsScript.validation_success()


static func validate_newer(candidate: Dictionary, current: Dictionary) -> Dictionary:
	var candidate_check: Dictionary = validate(candidate)
	if not bool(candidate_check.get("success", false)):
		return candidate_check
	var current_check: Dictionary = validate(current)
	if not bool(current_check.get("success", false)):
		return current_check
	for field in ["interaction_id", "world_id", "authority_id"]:
		if String(candidate.get(String(field))) != String(current.get(String(field))):
			return NetworkUtilsScript.validation_failure("PROOF_IDENTITY_MISMATCH", "Cannot compare proofs from different interaction/world/authority")
	if int(candidate.get("query_revision")) != int(current.get("query_revision")) \
			or int(candidate.get("authority_epoch")) != int(current.get("authority_epoch")) \
			or int(candidate.get("transform_revision")) != int(current.get("transform_revision")):
		return NetworkUtilsScript.validation_failure(
			"PROOF_LINEAGE_CHANGED",
			"Query, authority epoch and transform revision define proof lineage and cannot change via proof_revision",
		)
	if not is_equal_approx(float(candidate.get("path_t_start")), float(current.get("path_t_start"))) \
			or not is_equal_approx(float(candidate.get("path_t_end")), float(current.get("path_t_end"))):
		return NetworkUtilsScript.validation_failure(
			"PROOF_LINEAGE_CHANGED",
			"Domain path range cannot change within one proof lineage",
		)
	if NetworkUtilsScript.canonical_json(candidate.get("interaction_time")) != NetworkUtilsScript.canonical_json(current.get("interaction_time")):
		return NetworkUtilsScript.validation_failure(
			"PROOF_LINEAGE_CHANGED",
			"InteractionTime cannot change within one proof lineage",
		)
	if int(candidate.get("history_revision")) < int(current.get("history_revision")):
		return NetworkUtilsScript.validation_failure("STALE_HISTORY_REVISION", "history_revision cannot rewind")
	if int(candidate.get("proof_revision")) <= int(current.get("proof_revision")):
		return NetworkUtilsScript.validation_failure("STALE_PROOF_REVISION", "proof_revision must advance")
	return NetworkUtilsScript.validation_success()

extends RefCounted

## EG4.5 gateway cross-world interaction router: the ROUTING ORCHESTRATOR ONLY.
##
## Pipeline (one route() call):
##   1. fail-closed contract validation of the CrossWorldInteractionIntent
##      (CONTRACT_VIOLATION before anything is routed);
##   2. operation-id idempotency: an already-committed operation replays its
##      relayed result (ALREADY_APPLIED) without touching any authority leg;
##   3. projection-subscription freshness whenever the intent carries a
##      projection target hint: a stale subscription rejects the candidate
##      pending a fresh interest revision;
##   4. action validation by the ACTION AUTHORITY (the gateway never validates
##      action semantics itself);
##   5. involved domain segments from the domain router (routing topology
##      only), one CollisionQuery per segment, delivered to that segment's
##      world authority over its backend leg;
##   6. CollisionProof collection with per-proof contract validation against
##      the exact query revision (fail-closed; any stale/timeout/unavailable
##      proof leg aborts the whole resolution deterministically);
##   7. DETERMINISTIC FIRST-VALID RESOLUTION performed by the ACTION AUTHORITY
##      over the collected proof set (tie-break authority_id); the gateway
##      only validates the InteractionResolution contract and binds it to the
##      canonical proof_set_digest — ZERO collision logic lives here;
##   8. one EffectCommitRequest to the TARGET EFFECT AUTHORITY (the authority
##      that owns the winning world), carrying the resolution digest;
##      synthetic-only is enforced at the gateway boundary too:
##      product_canonical_mutation_allowed must be EXACTLY false;
##   9. the EffectCommitResult is relayed verbatim; an unavailable target is
##      preserved under a deterministic retry token with NO partial effect.
##
## The gateway NEVER resolves collisions, NEVER treats the projection hint as
## authority evidence (PROJECTION_HIT_IS_CANDIDATE_ONLY), and NEVER owns the
## effect journal (sim-side only, exactly-once per operation id).

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")
const IntentScript = preload("res://scripts/network/gateway/cross_world_interaction_intent.gd")
const DomainSegmentScript = preload("res://scripts/network/gateway/interaction_domain_segment.gd")
const QueryScript = preload("res://scripts/network/gateway/collision_query.gd")
const ProofScript = preload("res://scripts/network/gateway/collision_proof.gd")
const ResolutionScript = preload("res://scripts/network/gateway/interaction_resolution.gd")
const CommitRequestScript = preload("res://scripts/network/gateway/effect_commit_request.gd")
const CommitResultScript = preload("res://scripts/network/gateway/effect_commit_result.gd")

const SCHEMA := "planet_simulator.eg45_interaction_router.v1"
const PRODUCT_CANONICAL_MUTATION_ALLOWED := false
const SYNTHETIC_FLAG_FIELD := "product_canonical_mutation_allowed"
# Backend-leg error codes that mean "the authority could not be reached right
# now" (as opposed to an explicit domain rejection).
const LEG_UNAVAILABLE_CODES: Array[String] = ["LEG_UNAVAILABLE", "LEG_TIMEOUT"]

var _action_authority = null
var _backend_legs: Dictionary = {}
var _domain_router = null
var _projection_subscriptions = null
# operation_id -> {"result": Dict, "resolution": Dict, "losers": Array}
var _committed_by_operation: Dictionary = {}
# retry_token -> {"commit_request": Dict, "resolution": Dict, "losers": Array}
var _pending_commit_by_retry_token: Dictionary = {}
# operation_id -> retry_token
var _retry_token_by_operation: Dictionary = {}
var _next_query_revision: int = 1
var _counters := {
	"intents_received": 0,
	"contract_violations": 0,
	"replays_served": 0,
	"stale_projection_rejections": 0,
	"action_rejections": 0,
	"queries_routed": 0,
	"proofs_collected": 0,
	"proof_legs_aborted": 0,
	"invalid_proofs": 0,
	"resolutions_completed": 0,
	"no_collision_resolutions": 0,
	"resolution_refusals": 0,
	"commits_attempted": 0,
	"commits_committed": 0,
	"commits_duplicate_replay": 0,
	"commits_rejected": 0,
	"commits_unavailable": 0,
	"projection_candidate_rejections": 0,
}


func configure(p_action_authority, p_backend_legs, p_domain_router, p_projection_subscriptions) -> Dictionary:
	if p_action_authority == null \
			or not p_action_authority.has_method("validate_action") \
			or not p_action_authority.has_method("resolve_collisions"):
		return NetworkUtilsScript.validation_failure("INVALID_ACTION_AUTHORITY", "action authority must validate actions and resolve collisions")
	if typeof(p_backend_legs) != TYPE_DICTIONARY or Dictionary(p_backend_legs).is_empty():
		return NetworkUtilsScript.validation_failure("INVALID_BACKEND_LEGS", "at least one world authority backend leg is required")
	for authority_id in p_backend_legs.keys():
		var leg_value: Variant = p_backend_legs[authority_id]
		if leg_value == null or not (leg_value is Object) \
				or not (leg_value as Object).has_method("resolve_collision") \
				or not (leg_value as Object).has_method("commit_effect"):
			return NetworkUtilsScript.validation_failure("INVALID_BACKEND_LEG", "backend leg %s must resolve collisions and commit effects" % String(authority_id))
	if p_domain_router == null or not p_domain_router.has_method("involved_domain_segments"):
		return NetworkUtilsScript.validation_failure("INVALID_DOMAIN_ROUTER", "domain router must provide involved domain segments")
	if p_projection_subscriptions == null or not p_projection_subscriptions.has_method("current_interest_revision"):
		return NetworkUtilsScript.validation_failure("INVALID_PROJECTION_SUBSCRIPTIONS", "projection subscription tracker must expose current_interest_revision")
	_action_authority = p_action_authority
	_backend_legs = Dictionary(p_backend_legs).duplicate(true)
	_domain_router = p_domain_router
	_projection_subscriptions = p_projection_subscriptions
	return NetworkUtilsScript.validation_success()


## Route one CrossWorldInteractionIntent through the full pipeline.
func route(intent: Dictionary) -> Dictionary:
	_counters["intents_received"] = int(_counters["intents_received"]) + 1
	# --- 1. fail-closed contract validation BEFORE anything is routed ---
	var intent_check: Dictionary = IntentScript.validate(intent)
	if not bool(intent_check.get("success", false)):
		_counters["contract_violations"] = int(_counters["contract_violations"]) + 1
		return _outcome(false, "CONTRACT_VIOLATION", String(intent_check.get("message", "")), {
			"underlying_error_code": String(intent_check.get("error_code", "")),
			"routed": false,
		})
	var intent_dict: Dictionary = Dictionary(intent)
	var operation_id := String(intent_dict["operation_id"])
	# --- 2. same-operation-id idempotency (gateway-side replay) ---
	if _committed_by_operation.has(operation_id):
		var cached: Dictionary = Dictionary(_committed_by_operation[operation_id])
		_counters["replays_served"] = int(_counters["replays_served"]) + 1
		return _outcome(true, "ALREADY_APPLIED", "operation already committed; relayed prior result", {
			"result": Dictionary(cached["result"]).duplicate(true),
			"resolution": Dictionary(cached["resolution"]).duplicate(true),
			"losers": (cached["losers"] as Array).duplicate(true),
			"already_applied": true,
		})
	# --- 3. projection subscription freshness (hint is candidate-only) ---
	var projection_check: Dictionary = _check_projection_subscription(intent_dict)
	if not bool(projection_check.get("success", false)):
		return projection_check
	# --- 4. action authority validates the action ---
	var action_check_value: Variant = _action_authority.validate_action(intent_dict)
	if typeof(action_check_value) != TYPE_DICTIONARY:
		return _outcome(false, "ACTION_AUTHORITY_MALFORMED", "action authority returned a non-dictionary verdict", {})
	var action_check: Dictionary = Dictionary(action_check_value)
	if not bool(action_check.get("success", false)):
		_counters["action_rejections"] = int(_counters["action_rejections"]) + 1
		return _outcome(false, "ACTION_VALIDATION_REJECTED", "action authority refused the action", {
			"underlying_error_code": String(action_check.get("error_code", "")),
		})
	# --- 5. involved domain segments (routing topology ONLY) ---
	var segments_result_value: Variant = _domain_router.involved_domain_segments(intent_dict)
	if typeof(segments_result_value) != TYPE_DICTIONARY:
		return _outcome(false, "DOMAIN_ROUTE_UNAVAILABLE", "domain router returned a non-dictionary result", {})
	var segments_result: Dictionary = Dictionary(segments_result_value)
	if not bool(segments_result.get("success", false)):
		return _outcome(false, "DOMAIN_ROUTE_UNAVAILABLE", String(segments_result.get("message", "no domain route for interaction")), {})
	var segment_check: Dictionary = _validated_segments(segments_result)
	if not bool(segment_check.get("success", false)):
		return segment_check
	var segments: Array = segment_check["segments"]
	var epoch_by_authority: Dictionary = Dictionary(segments_result.get("authority_epoch_by_authority", {}))
	# --- 6. one CollisionQuery per involved world authority, proofs collected ---
	var collection: Dictionary = _collect_proofs(intent_dict, segments, epoch_by_authority)
	if not bool(collection.get("success", false)):
		return collection
	var queries: Array = collection["queries"]
	var proofs: Array = collection["proofs"]
	var proof_set_digest := String(CwipUtilsScript.proof_set_digest(proofs))
	if proof_set_digest.is_empty():
		return _outcome(false, "INVALID_PROOF_SET", "collected proof set has no canonical digest", {})
	# --- 7. ACTION AUTHORITY resolves first valid collision deterministically ---
	var resolution_request := {
		"intent": intent_dict.duplicate(true),
		"queries": queries.duplicate(true),
		"proofs": proofs.duplicate(true),
	}
	var resolution_result_value: Variant = _action_authority.resolve_collisions(resolution_request)
	if typeof(resolution_result_value) != TYPE_DICTIONARY:
		return _outcome(false, "RESOLUTION_REFUSED", "action authority returned a non-dictionary resolution", {})
	var resolution_result: Dictionary = Dictionary(resolution_result_value)
	if not bool(resolution_result.get("success", false)):
		_counters["resolution_refusals"] = int(_counters["resolution_refusals"]) + 1
		return _outcome(false, "RESOLUTION_REFUSED", String(resolution_result.get("message", "action authority refused resolution")), {
			"underlying_error_code": String(resolution_result.get("error_code", "")),
		})
	var binding: Dictionary = _bound_resolution(resolution_result, proof_set_digest)
	if not bool(binding.get("success", false)):
		return binding
	var resolution: Dictionary = binding["resolution"]
	var losers: Array = binding["losers"]
	_counters["resolutions_completed"] = int(_counters["resolutions_completed"]) + 1
	if String(resolution["result"]) != "COLLISION":
		_counters["no_collision_resolutions"] = int(_counters["no_collision_resolutions"]) + 1
		return _outcome(true, String(resolution["result"]), "terminal non-collision resolution relayed", {
			"resolution": resolution.duplicate(true),
			"losers": losers,
		})
	# --- 8. effect proposal must be synthetic-only, then commit at the target ---
	var proposal_check: Dictionary = _validated_effect_proposal(resolution_result)
	if not bool(proposal_check.get("success", false)):
		return proposal_check
	var proposal: Dictionary = proposal_check["proposal"]
	var targeting: Dictionary = _commit_target(resolution, queries, proofs)
	if not bool(targeting.get("success", false)):
		return targeting
	var commit_request: Dictionary = CommitRequestScript.create(
			String(intent_dict["interaction_id"]),
			operation_id,
			String(resolution["proof_set_digest"]),
			String(targeting["target_entity_id"]),
			String(targeting["target_authority"]),
			int(targeting["target_authority_epoch_observed"]),
			String(proposal["effect_kind"]),
			String(proposal["effect_definition_id"]),
			Dictionary(proposal["effect_payload"]))
	var request_check: Dictionary = CommitRequestScript.validate(commit_request)
	if not bool(request_check.get("success", false)):
		return _outcome(false, "CONTRACT_VIOLATION", "router-built EffectCommitRequest failed validation", {
			"underlying_error_code": String(request_check.get("error_code", "")),
		})
	return _send_commit(commit_request, resolution, losers)


## Retry a commit whose target authority was unavailable mid-resolution.
## The preserved retry token replays the SAME EffectCommitRequest — no
## re-resolution, no partial effect from the failed attempt.
func retry_pending_commit(retry_token: String) -> Dictionary:
	if not _pending_commit_by_retry_token.has(retry_token):
		return _outcome(false, "UNKNOWN_RETRY_TOKEN", "no pending commit for this retry token", {})
	var pending: Dictionary = Dictionary(_pending_commit_by_retry_token[retry_token])
	var envelope: Dictionary = _send_commit(
			Dictionary(pending["commit_request"]),
			Dictionary(pending["resolution"]),
			(pending["losers"] as Array).duplicate(true))
	if String(envelope["error_code"]) == "EFFECT_COMMIT_UNAVAILABLE":
		# still unavailable: keep the pending commit and its token alive
		return envelope
	return envelope


## Explicit direct-commit attempt surface (e.g. a client trying to commit an
## effect at a projection-hit target). Fail-closed: a commit decision may ONLY
## follow an authority InteractionResolution produced by route(). A projection
## hit is candidate-only evidence and is ALWAYS rejected here.
func attempt_direct_effect_commit(request: Dictionary) -> Dictionary:
	_counters["projection_candidate_rejections"] = int(_counters["projection_candidate_rejections"]) + 1
	var cites_projection := request.has("projection_revision") \
			or String(request.get("evidence_source", "")) == "projection_hit" \
			or request.has("optional_projection_target_hint")
	if cites_projection:
		return _outcome(false, "PROJECTION_HIT_IS_CANDIDATE_ONLY",
				"a projection hit is candidate-only evidence; commits require an authority collision resolution",
				{"routed": false})
	return _outcome(false, "DIRECT_COMMIT_NOT_ROUTED",
			"effect commits are only issued through authority-resolved routing",
			{"routed": false})


func pending_retry_token(operation_id: String) -> String:
	return String(_retry_token_by_operation.get(operation_id, ""))


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"product_canonical_mutation_allowed": PRODUCT_CANONICAL_MUTATION_ALLOWED,
		"role": "ROUTING_ORCHESTRATOR_ONLY_NO_COLLISION_LOGIC",
		"counters": _counters.duplicate(true),
		"committed_operations": _committed_by_operation.keys(),
		"pending_retry_tokens": _pending_commit_by_retry_token.keys(),
	}


# --- pipeline steps ---------------------------------------------------------


## Stale projection subscription => candidate-only rejection pending a fresh
## interest revision. Only intents CARRYING a projection hint are checked; a
## hint-less intent carries no projection claim at all.
func _check_projection_subscription(intent: Dictionary) -> Dictionary:
	if intent.get("optional_projection_target_hint") == null:
		return NetworkUtilsScript.validation_success()
	var actor_id := String(intent["actor_id"])
	var carried_revision := int(intent["projection_revision"])
	var current_revision := int(_projection_subscriptions.current_interest_revision(actor_id))
	if carried_revision != current_revision:
		_counters["stale_projection_rejections"] = int(_counters["stale_projection_rejections"]) + 1
		return _outcome(false, "STALE_PROJECTION_SUBSCRIPTION",
				"projection hint was built on a stale interest revision; refresh interest and resubmit",
				{
					"details": {
						"actor_id": actor_id,
						"carried_projection_revision": carried_revision,
						"current_interest_revision": current_revision,
						"pending_fresh_interest_revision": true,
					},
					"routed": false,
				})
	return NetworkUtilsScript.validation_success()


## Validate every involved domain segment fail-closed and order them
## deterministically by authority_ref (query issuance order only).
func _validated_segments(segments_result: Dictionary) -> Dictionary:
	var segments_value: Variant = segments_result.get("segments")
	if typeof(segments_value) != TYPE_ARRAY or (segments_value as Array).is_empty():
		return _outcome(false, "DOMAIN_ROUTE_UNAVAILABLE", "involved domain segment set is empty", {})
	var segments: Array = []
	for segment_value in segments_value:
		if typeof(segment_value) != TYPE_DICTIONARY:
			return _outcome(false, "CONTRACT_VIOLATION", "domain segment must be a Dictionary", {})
		var segment_check: Dictionary = DomainSegmentScript.validate(Dictionary(segment_value))
		if not bool(segment_check.get("success", false)):
			return _outcome(false, "CONTRACT_VIOLATION", "involved domain segment failed validation", {
				"underlying_error_code": String(segment_check.get("error_code", "")),
			})
		segments.append(Dictionary(segment_value))
	segments.sort_custom(func(a, b) -> bool: return String(a["authority_ref"]) < String(b["authority_ref"]))
	return {"success": true, "error_code": "", "message": "", "segments": segments}


## Deliver one CollisionQuery per segment over its backend leg and collect
## CollisionProofs. Any stale evidence, timeout or unavailable leg aborts the
## WHOLE resolution deterministically (no partial state survives).
func _collect_proofs(intent: Dictionary, segments: Array, epoch_by_authority: Dictionary) -> Dictionary:
	var interaction_id := String(intent["interaction_id"])
	var queries: Array = []
	var proofs: Array = []
	for segment_value in segments:
		var segment: Dictionary = Dictionary(segment_value)
		var authority_id := String(segment["authority_ref"])
		if not epoch_by_authority.has(authority_id):
			return _outcome(false, "MISSING_AUTHORITY_EPOCH", "no observed authority epoch for %s" % authority_id, {})
		var query: Dictionary = QueryScript.create(
				interaction_id,
				Dictionary(intent["interaction_time"]),
				segment,
				int(intent["world_graph_revision"]),
				int(epoch_by_authority[authority_id]),
				_next_query_revision)
		_next_query_revision += 1
		var query_check: Dictionary = QueryScript.validate(query)
		if not bool(query_check.get("success", false)):
			return _outcome(false, "CONTRACT_VIOLATION", "router-built CollisionQuery failed validation", {
				"underlying_error_code": String(query_check.get("error_code", "")),
			})
		var leg_value: Variant = _backend_legs.get(authority_id)
		if leg_value == null or not (leg_value is Object):
			_counters["proof_legs_aborted"] = int(_counters["proof_legs_aborted"]) + 1
			return _outcome(false, "RESOLUTION_LINK_TIMEOUT", "no backend leg for world authority %s" % authority_id, {
				"authority_id": authority_id,
			})
		var leg: Object = leg_value
		_counters["queries_routed"] = int(_counters["queries_routed"]) + 1
		var response_value: Variant = leg.resolve_collision(query)
		if typeof(response_value) != TYPE_DICTIONARY:
			_counters["proof_legs_aborted"] = int(_counters["proof_legs_aborted"]) + 1
			return _outcome(false, "RESOLUTION_LINK_TIMEOUT", "world authority %s returned a malformed response" % authority_id, {})
		var response: Dictionary = Dictionary(response_value)
		if not bool(response.get("success", false)):
			_counters["proof_legs_aborted"] = int(_counters["proof_legs_aborted"]) + 1
			var leg_error := String(response.get("error_code", "LEG_UNAVAILABLE"))
			if LEG_UNAVAILABLE_CODES.has(leg_error):
				return _outcome(false, "RESOLUTION_LINK_TIMEOUT",
						"world authority %s did not answer its collision query in time" % authority_id,
						{"authority_id": authority_id, "underlying_error_code": leg_error})
			# explicit authority-side refusal (e.g. STALE_REFERENCE_FRAME):
			# relayed verbatim, whole resolution aborted, nothing committed.
			return _outcome(false, leg_error, String(response.get("message", "world authority refused its collision query")), {
				"authority_id": authority_id,
			})
		var proof_value: Variant = response.get("proof")
		if typeof(proof_value) != TYPE_DICTIONARY:
			_counters["invalid_proofs"] = int(_counters["invalid_proofs"]) + 1
			return _outcome(false, "INVALID_PROOF", "world authority %s returned no CollisionProof" % authority_id, {})
		var proof: Dictionary = Dictionary(proof_value)
		var proof_check: Dictionary = ProofScript.validate(proof)
		if bool(proof_check.get("success", false)):
			proof_check = ProofScript.validate_against_query(proof, query)
		if not bool(proof_check.get("success", false)):
			_counters["invalid_proofs"] = int(_counters["invalid_proofs"]) + 1
			return _outcome(false, "INVALID_PROOF", "CollisionProof from %s failed validation" % authority_id, {
				"underlying_error_code": String(proof_check.get("error_code", "")),
			})
		_counters["proofs_collected"] = int(_counters["proofs_collected"]) + 1
		queries.append(query)
		proofs.append(proof)
	return {"success": true, "error_code": "", "message": "", "queries": queries, "proofs": proofs}


## Validate the resolution contract and bind it to the canonical proof set
## digest. This is the gateway's ONLY involvement in resolution: contract +
## digest binding, never selection.
func _bound_resolution(resolution_result: Dictionary, proof_set_digest: String) -> Dictionary:
	var resolution_value: Variant = resolution_result.get("resolution")
	if typeof(resolution_value) != TYPE_DICTIONARY:
		return _outcome(false, "RESOLUTION_REFUSED", "action authority returned no InteractionResolution", {})
	var resolution: Dictionary = Dictionary(resolution_value)
	var resolution_check: Dictionary = ResolutionScript.validate(resolution)
	if not bool(resolution_check.get("success", false)):
		return _outcome(false, "RESOLUTION_CONTRACT_VIOLATION", "InteractionResolution failed contract validation", {
			"underlying_error_code": String(resolution_check.get("error_code", "")),
		})
	if String(resolution["proof_set_digest"]) != proof_set_digest:
		return _outcome(false, "RESOLUTION_DIGEST_MISMATCH", "resolution does not bind the collected proof set digest", {})
	var losers_value: Variant = resolution_result.get("losers", [])
	if typeof(losers_value) != TYPE_ARRAY:
		return _outcome(false, "RESOLUTION_CONTRACT_VIOLATION", "losers must be an Array", {})
	return {"success": true, "error_code": "", "message": "",
			"resolution": resolution.duplicate(true), "losers": (losers_value as Array).duplicate(true)}


## Synthetic-only enforcement at the gateway boundary: the effect proposal must
## carry product_canonical_mutation_allowed EXACTLY false.
func _validated_effect_proposal(resolution_result: Dictionary) -> Dictionary:
	var proposal_value: Variant = resolution_result.get("effect_proposal")
	if typeof(proposal_value) != TYPE_DICTIONARY:
		return _outcome(false, "CONTRACT_VIOLATION", "action authority returned no effect proposal", {})
	var proposal: Dictionary = Dictionary(proposal_value)
	if String(proposal.get("effect_kind", "")).strip_edges().is_empty():
		return _outcome(false, "CONTRACT_VIOLATION", "effect proposal carries no effect_kind", {})
	var definition_check: Dictionary = GatewayUtilsScript.require_id(
			{"effect_definition_id": proposal.get("effect_definition_id")}, "effect_definition_id", "effect-definition")
	if not bool(definition_check.get("success", false)):
		return _outcome(false, "CONTRACT_VIOLATION", "effect_definition_id must be a canonical effect-definition id", {})
	var payload_value: Variant = proposal.get("effect_payload")
	if typeof(payload_value) != TYPE_DICTIONARY:
		return _outcome(false, "CONTRACT_VIOLATION", "effect_payload must be a Dictionary", {})
	var payload: Dictionary = Dictionary(payload_value)
	var flag: Variant = payload.get(SYNTHETIC_FLAG_FIELD)
	if typeof(flag) != TYPE_BOOL or bool(flag) != PRODUCT_CANONICAL_MUTATION_ALLOWED:
		return _outcome(false, "SYNTHETIC_FLAG_REQUIRED",
				"%s must be exactly false on every cross-world synthetic effect" % SYNTHETIC_FLAG_FIELD, {})
	return {"success": true, "error_code": "", "message": "", "proposal": proposal}


## Resolve the commit target STRICTLY from the winning resolution + the proof
## set (never from the projection hint).
func _commit_target(resolution: Dictionary, queries: Array, proofs: Array) -> Dictionary:
	var winning_world_id := String(resolution["winning_world_id"])
	for proof_value in proofs:
		var proof: Dictionary = Dictionary(proof_value)
		if String(proof["world_id"]) != winning_world_id:
			continue
		for query_value in queries:
			var query: Dictionary = Dictionary(query_value)
			var segment: Dictionary = Dictionary(query["domain_segment"])
			if String(segment["world_id"]) != winning_world_id:
				continue
			return {"success": true, "error_code": "", "message": "",
					"target_entity_id": String(resolution["winning_entity_id"]),
					"target_authority": String(segment["authority_ref"]),
					"target_authority_epoch_observed": int(proof["authority_epoch"])}
	return _outcome(false, "RESOLUTION_WINNING_PROOF_MISSING",
			"winning world %s has no matching collected proof" % winning_world_id, {})


## Send the EffectCommitRequest over the target's backend leg and relay the
## journal outcome verbatim. Unavailable targets preserve a deterministic
## retry token; explicit domain rejections become REJECTED results; neither
## leaves a partial effect behind.
func _send_commit(commit_request: Dictionary, resolution: Dictionary, losers: Array) -> Dictionary:
	_counters["commits_attempted"] = int(_counters["commits_attempted"]) + 1
	var operation_id := String(commit_request["operation_id"])
	var target_authority := String(commit_request["target_authority"])
	var leg_value: Variant = _backend_legs.get(target_authority)
	if leg_value == null or not (leg_value is Object):
		return _commit_unavailable(commit_request, resolution, losers)
	var leg: Object = leg_value
	var response_value: Variant = leg.commit_effect(commit_request)
	if typeof(response_value) != TYPE_DICTIONARY:
		return _commit_unavailable(commit_request, resolution, losers)
	var response: Dictionary = Dictionary(response_value)
	if not bool(response.get("success", false)):
		var error_code := String(response.get("error_code", "LEG_UNAVAILABLE"))
		if LEG_UNAVAILABLE_CODES.has(error_code):
			return _commit_unavailable(commit_request, resolution, losers)
		# explicit rejection by the target authority's own validation
		_counters["commits_rejected"] = int(_counters["commits_rejected"]) + 1
		_forget_pending(operation_id)
		var rejected: Dictionary = CommitResultScript.create(
				String(commit_request["interaction_id"]),
				operation_id,
				"REJECTED",
				null,
				int(commit_request["target_authority_epoch_observed"]))
		var rejected_check: Dictionary = CommitResultScript.validate(rejected)
		if not bool(rejected_check.get("success", false)):
			return _outcome(false, "CONTRACT_VIOLATION", "rejected-result construction failed validation", {})
		return _outcome(true, "", "explicit rejection relayed; no partial effect exists", {
			"result": rejected,
			"resolution": resolution.duplicate(true),
			"losers": losers,
			"details": {"rejected_reason": error_code},
		})
	var details_value: Variant = response.get("details")
	if typeof(details_value) != TYPE_DICTIONARY:
		return _commit_unavailable(commit_request, resolution, losers)
	var details: Dictionary = Dictionary(details_value)
	var result_value: Variant = details.get("result")
	if typeof(result_value) != TYPE_DICTIONARY:
		return _commit_unavailable(commit_request, resolution, losers)
	var result: Dictionary = Dictionary(result_value)
	var result_check: Dictionary = CommitResultScript.validate(result)
	if not bool(result_check.get("success", false)):
		return _outcome(false, "CONTRACT_VIOLATION", "relayed EffectCommitResult failed validation", {
			"underlying_error_code": String(result_check.get("error_code", "")),
		})
	var status := String(result["result"])
	if status == "COMMITTED":
		_counters["commits_committed"] = int(_counters["commits_committed"]) + 1
	elif status == "DUPLICATE_REPLAY":
		_counters["commits_duplicate_replay"] = int(_counters["commits_duplicate_replay"]) + 1
	else:
		return _outcome(false, "UNEXPECTED_COMMIT_STATUS", "journal reported unexpected status %s" % status, {})
	_forget_pending(operation_id)
	_committed_by_operation[operation_id] = {
		"result": result.duplicate(true),
		"resolution": resolution.duplicate(true),
		"losers": losers.duplicate(true),
	}
	return _outcome(true, "", "commit outcome relayed", {
		"result": result.duplicate(true),
		"resolution": resolution.duplicate(true),
		"losers": losers.duplicate(true),
		"already_applied": false,
	})


func _commit_unavailable(commit_request: Dictionary, resolution: Dictionary, losers: Array) -> Dictionary:
	_counters["commits_unavailable"] = int(_counters["commits_unavailable"]) + 1
	var operation_id := String(commit_request["operation_id"])
	var retry_token := String(NetworkUtilsScript.payload_hash({
		"operation_id": operation_id,
		"resolution_digest": String(commit_request["resolution_digest"]),
		"target_authority": String(commit_request["target_authority"]),
	}))
	_pending_commit_by_retry_token[retry_token] = {
		"commit_request": commit_request.duplicate(true),
		"resolution": resolution.duplicate(true),
		"losers": losers.duplicate(true),
	}
	_retry_token_by_operation[operation_id] = retry_token
	return _outcome(false, "EFFECT_COMMIT_UNAVAILABLE",
			"target effect authority unavailable mid-resolution; retry token preserved, no partial effect",
			{
				"retry_token": retry_token,
				"resolution": resolution.duplicate(true),
				"losers": losers.duplicate(true),
			})


func _forget_pending(operation_id: String) -> void:
	var token := String(_retry_token_by_operation.get(operation_id, ""))
	if not token.is_empty():
		_pending_commit_by_retry_token.erase(token)
		_retry_token_by_operation.erase(operation_id)


func _outcome(success: bool, error_code: String, message: String, extras: Dictionary) -> Dictionary:
	var envelope := {
		"success": success,
		"error_code": error_code,
		"message": message,
		"result": null,
		"resolution": null,
		"losers": [],
		"already_applied": false,
		"retry_token": "",
		"details": {},
	}
	for key in extras.keys():
		envelope[key] = extras[key]
	return envelope

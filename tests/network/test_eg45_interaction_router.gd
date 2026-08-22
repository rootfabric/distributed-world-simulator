extends SceneTree

## EG4.5 L0: cross-world interaction ROUTER proof with FAKE authorities.
## Covers the happy path (B_SHOOTER_A_TARGET_CLEAR shape), the three routing
## predicates and ALL TEN negative cases. World authorities are in-process
## stubs behind the real backend-leg boundary; the sim-side synthetic effect
## journal is the REAL EG4.5 component, proving exactly-once semantics.

const RouterScript = preload("res://scripts/network/gateway/runtime/eg45_interaction_router.gd")
const JournalScript = preload("res://tools/network/eg45_synthetic_effect_journal.gd")
const IntentScript = preload("res://scripts/network/gateway/cross_world_interaction_intent.gd")
const EvidenceScript = preload("res://scripts/network/gateway/reference_frame_evidence.gd")
const SegmentScript = preload("res://scripts/network/gateway/interaction_domain_segment.gd")
const ProofScript = preload("res://scripts/network/gateway/collision_proof.gd")
const ResolutionScript = preload("res://scripts/network/gateway/interaction_resolution.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")
const InteractionTimeScript = preload("res://scripts/network/gateway/interaction_time.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg45-router][FAIL] %s" % message)


# --- fakes -------------------------------------------------------------------


class FakeProjectionSubscriptions extends RefCounted:
	var revision_by_actor: Dictionary = {}

	func current_interest_revision(actor_id: String) -> int:
		return int(revision_by_actor.get(actor_id, 0))


class FakeDomainRouter extends RefCounted:
	var segments: Array = []
	var epoch_by_authority: Dictionary = {}
	var calls: int = 0

	func involved_domain_segments(_intent: Dictionary) -> Dictionary:
		calls += 1
		return {
			"success": true,
			"segments": segments.duplicate(true),
			"authority_epoch_by_authority": epoch_by_authority.duplicate(true),
		}


class FakeActionAuthority extends RefCounted:
	var validate_calls: int = 0
	var resolve_calls: int = 0
	var reject_action_code := ""
	var proposal_flag_value: bool = false
	var _resolution_revision: int = 0

	func validate_action(intent: Dictionary) -> Dictionary:
		validate_calls += 1
		if not reject_action_code.is_empty():
			return {"success": false, "error_code": reject_action_code, "message": "action refused"}
		return {"success": true, "error_code": "", "message": ""}

	func resolve_collisions(request: Dictionary) -> Dictionary:
		resolve_calls += 1
		var proofs: Array = request["proofs"]
		var winner = null
		var candidates: Array = []
		for proof_value in proofs:
			var proof: Dictionary = proof_value
			if proof.get("first_collision_t") == null:
				continue
			candidates.append(proof)
			if winner == null or _proof_before(proof, winner):
				winner = proof
		var losers: Array = []
		for candidate in candidates:
			if winner != null and String(candidate["authority_id"]) != String(winner["authority_id"]):
				losers.append({
					"authority_id": String(candidate["authority_id"]),
					"reason": "LOST_RESOLUTION",
				})
		var interaction_id := String(request["intent"]["interaction_id"])
		var result := "NO_COLLISION"
		var winning_world = null
		var winning_entity = null
		var winning_t = null
		if winner != null:
			result = "COLLISION"
			winning_world = String(winner["world_id"])
			winning_entity = winner.get("collided_entity_id")
			winning_t = float(winner["first_collision_t"])
		_resolution_revision += 1
		var resolution := ResolutionScript.create(
				interaction_id, result, winning_world, winning_entity, winning_t,
				String(CwipUtilsScript.proof_set_digest(proofs)), _resolution_revision)
		var resolution_check: Dictionary = ResolutionScript.validate(resolution)
		if not bool(resolution_check.get("success", false)):
			return {"success": false, "error_code": "RESOLUTION_INVALID", "message": "fake authority built an invalid resolution"}
		return {
			"success": true,
			"resolution": resolution,
			"losers": losers,
			"effect_proposal": {
				"effect_kind": "synthetic_impact",
				"effect_definition_id": "effect-definition/eg45-impact-v1",
				"effect_payload": {
					"product_canonical_mutation_allowed": proposal_flag_value,
					"interaction_id": interaction_id,
					"target_entity_id": winning_entity,
				},
			},
		}

	func _proof_before(a: Dictionary, b: Dictionary) -> bool:
		var ta := float(a["first_collision_t"])
		var tb := float(b["first_collision_t"])
		if not is_equal_approx(ta, tb):
			return ta < tb
		return String(a["authority_id"]) < String(b["authority_id"])


class FakeWorldLeg extends RefCounted:
	var authority_id: String
	var world_id: String
	var authority_epoch: int
	var transform_revision: int = 11
	var history_revision: int = 6
	var proof_revision: int = 2
	# scripted collision outcome: null first_collision_t means a NONE proof
	var collision_t = null
	var collision_kind := "NONE"
	var collided_entity = null
	# scripted refusals: "", "STALE_REFERENCE_FRAME" (auto from stale evidence), "LEG_TIMEOUT"
	var force_error := ""
	var commit_unavailable: bool = false
	var journal = null
	var queries_received: Array = []

	func _init(p_authority: String, p_world: String, p_epoch: int) -> void:
		authority_id = p_authority
		world_id = p_world
		authority_epoch = p_epoch
		journal = JournalScript.new()
		var configured: Dictionary = journal.configure(authority_id, authority_epoch)
		if not bool(configured.get("success", false)):
			push_error("fake leg journal configuration failed")

	func resolve_collision(query: Dictionary) -> Dictionary:
		queries_received.append(query.duplicate(true))
		if not force_error.is_empty():
			return {"success": false, "error_code": force_error, "message": "leg refusal %s" % force_error}
		var segment: Dictionary = query["domain_segment"]
		var evidence: Dictionary = segment["reference_frame_evidence"]
		# own-domain validation: this authority validates ITS collision domain
		if int(evidence["transform_revision"]) != transform_revision:
			return {"success": false, "error_code": "STALE_REFERENCE_FRAME", "message": "evidence does not match the current transform revision"}
		var proof := ProofScript.create(
				String(query["interaction_id"]), int(query["query_revision"]),
				world_id, authority_id, authority_epoch,
				float(segment["path_t_start"]), float(segment["path_t_end"]),
				collision_t, collided_entity, collision_kind, null,
				Dictionary(query["interaction_time"]),
				history_revision, transform_revision, proof_revision)
		var proof_check: Dictionary = ProofScript.validate(proof)
		if not bool(proof_check.get("success", false)):
			return {"success": false, "error_code": "INVALID_PROOF_CONSTRUCTION", "message": String(proof_check.get("message", ""))}
		return {"success": true, "proof": proof}

	func commit_effect(request: Dictionary) -> Dictionary:
		if commit_unavailable:
			return {"success": false, "error_code": "LEG_UNAVAILABLE", "message": "target effect authority unreachable"}
		return journal.commit(request)


# --- fixture -----------------------------------------------------------------


func _segment(world: String, authority: String, source_rf: String, target_rf: String, transform_revision: int) -> Dictionary:
	return SegmentScript.create(world, authority, 0.0, 10.0,
			EvidenceScript.create(source_rf, target_rf, transform_revision, 7), 5)


func _fixture(c_segment_first: bool) -> Dictionary:
	var leg_a := FakeWorldLeg.new("authority/sim-a", "world/sim-a", 3)
	var leg_c := FakeWorldLeg.new("authority/sim-c", "world/sim-c", 4)
	var seg_a := _segment("world/sim-a", "authority/sim-a", "reference-frame/sim-c-main", "reference-frame/sim-a-main", 11)
	var seg_c := _segment("world/sim-c", "authority/sim-c", "reference-frame/sim-c-main", "reference-frame/sim-c-main", 11)
	var domain := FakeDomainRouter.new()
	domain.segments = [seg_c, seg_a] if c_segment_first else [seg_a, seg_c]
	domain.epoch_by_authority = {"authority/sim-a": 3, "authority/sim-c": 4}
	var subs := FakeProjectionSubscriptions.new()
	subs.revision_by_actor = {"player/shooter-b": 4}
	var action := FakeActionAuthority.new()
	var legs := {"authority/sim-a": leg_a, "authority/sim-c": leg_c}
	var router = RouterScript.new()
	var configured: Dictionary = router.configure(action, legs, domain, subs)
	if not bool(configured.get("success", false)):
		print("[eg45-router][FAIL] fixture router configuration rejected: %s" % String(configured.get("message", "")))
		failures.append("fixture router configuration rejected")
	return {
		"router": router, "action": action, "domain": domain, "subs": subs,
		"leg_a": leg_a, "leg_c": leg_c,
	}


func _intent(operation_suffix: String, hint = null, projection_revision: int = 0) -> Dictionary:
	return IntentScript.create(
			"interaction/shoot-" + operation_suffix,
			"operation/" + operation_suffix,
			1, "HITSCAN",
			"player/shooter-b", "entity/shooter-c-1",
			"authority/action", 2,
			InteractionTimeScript.create(1000, 123.5, 42, 1),
			"world/sim-c", "reference-frame/sim-c-main",
			{"origin": [1.0, 2.0, 3.0]},
			{"direction": [0.0, 0.0, -1.0]},
			{"max_range": 50.0},
			"capability-definition/hitscan-v1", 4,
			hint, projection_revision, 7, 9)


func _set_clear_path(leg_c) -> void:
	leg_c.collision_t = null
	leg_c.collision_kind = "NONE"
	leg_c.collided_entity = null


# --- tests -------------------------------------------------------------------


func test_happy_path_clear() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var envelope: Dictionary = fx["router"].route(_intent("0001"))
	_assert(bool(envelope["success"]), "clear path routes successfully")
	_assert(String(envelope["error_code"]) == "", "clear path carries no error")
	var result: Dictionary = envelope["result"]
	_assert(String(result["result"]) == "COMMITTED", "clear path commits the effect")
	_assert(int(result["canonical_effect_revision"]) == 1, "first effect takes canonical revision 1")
	var resolution: Dictionary = envelope["resolution"]
	_assert(String(resolution["result"]) == "COLLISION", "resolution reports COLLISION")
	_assert(String(resolution["winning_world_id"]) == "world/sim-a", "clear path winner is the far target world")
	_assert(int(fx["leg_a"].journal.effect_count()) == 1, "target authority holds exactly one effect")
	_assert(int(fx["leg_c"].journal.effect_count()) == 0, "shooter world holds no effect")
	_assert(int(fx["domain"].calls) == 1, "domain router consulted exactly once")
	print("[eg45-router][predicate] B_SHOOTER_A_TARGET_CLEAR")


func test_wall_blocks() -> void:
	var fx: Dictionary = _fixture(true)
	fx["leg_c"].collision_t = 2.0
	fx["leg_c"].collision_kind = "STATIC"
	fx["leg_c"].collided_entity = "entity/wall-c-1"
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var envelope: Dictionary = fx["router"].route(_intent("0002"))
	_assert(bool(envelope["success"]), "walled shot still resolves and commits")
	_assert(String(envelope["resolution"]["winning_world_id"]) == "world/sim-c", "wall wins in the shooter world")
	_assert(is_equal_approx(float(envelope["resolution"]["winning_collision_t"]), 2.0), "wall collision is the first one on the path")
	_assert(int(fx["leg_c"].journal.effect_count()) == 1, "wall impact committed in shooter world")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0, "far target never committed behind the wall")
	print("[eg45-router][predicate] B_SHOOTER_C_WALL_BLOCKS_A_TARGET")


func test_near_wins_over_far() -> void:
	var fx: Dictionary = _fixture(true)
	fx["leg_c"].collision_t = 5.0
	fx["leg_c"].collision_kind = "ENTITY"
	fx["leg_c"].collided_entity = "entity/near-c-1"
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/far-a-1"
	var envelope: Dictionary = fx["router"].route(_intent("0003"))
	_assert(bool(envelope["success"]), "near-vs-far shot resolves")
	_assert(String(envelope["resolution"]["winning_entity_id"]) == "entity/near-c-1", "near target beats far target")
	_assert(int(fx["leg_c"].journal.effect_count()) == 1, "near-target effect committed in shooter world")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0, "far-target world untouched")
	var losers: Array = envelope["losers"]
	_assert(losers.size() == 1 and String(losers[0]["authority_id"]) == "authority/sim-a", "far authority recorded as loser")
	print("[eg45-router][predicate] B_SHOOTER_C_NEAR_TARGET_WINS_OVER_A_FAR_TARGET")


func test_neg01_duplicate_intent_idempotent() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var first: Dictionary = fx["router"].route(_intent("0101"))
	var second: Dictionary = fx["router"].route(_intent("0101"))
	_assert(bool(first["success"]) and bool(second["success"]), "duplicate intent yields successful outcomes twice")
	_assert(bool(second["already_applied"]), "duplicate intent reported as already applied")
	_assert(String(second["error_code"]) == "ALREADY_APPLIED", "duplicate intent replays with ALREADY_APPLIED marker")
	_assert(String(second["result"]["operation_id"]) == String(first["result"]["operation_id"]), "replayed result is the prior result")
	_assert(int(fx["leg_a"].journal.effect_count()) == 1, "duplicate intent creates no second effect")
	_assert(int(fx["domain"].calls) == 1, "duplicate intent does not re-route (domain router untouched)")
	_assert(int(fx["action"].resolve_calls) == 1, "duplicate intent does not re-resolve")


func test_neg02_stale_reference_frame() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	# stale evidence handed to sim-a: transform_revision rewinds under its feet
	fx["domain"].segments[0]["reference_frame_evidence"]["transform_revision"] = 10
	var envelope: Dictionary = fx["router"].route(_intent("0201"))
	_assert(not bool(envelope["success"]), "stale evidence aborts routing")
	_assert(String(envelope["error_code"]) == "STALE_REFERENCE_FRAME", "stale evidence relays STALE_REFERENCE_FRAME")
	_assert(String(envelope["authority_id"]) == "authority/sim-c", "refusing authority identified (sim-c segment carries rewound evidence)")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0, "no effect committed on stale evidence")
	_assert(int(fx["leg_c"].journal.effect_count()) == 0, "no effect committed anywhere on stale evidence")


func test_neg03_simultaneous_claim_deterministic_tie_break() -> void:
	var first_run: Dictionary = _tie_break_fixture(true)
	var second_run: Dictionary = _tie_break_fixture(false)
	for run in [first_run, second_run]:
		var envelope: Dictionary = run["fx"]["router"].route(run["intent"])
		_assert(bool(envelope["success"]), "tie-break resolution completes regardless of arrival order")
		_assert(String(envelope["resolution"]["winning_world_id"]) == "world/sim-a", "equal-t claim deterministically won by lower authority id")
		var losers: Array = envelope["losers"]
		_assert(losers.size() == 1 and String(losers[0]["reason"]) == "LOST_RESOLUTION", "loser claim recorded as LOST_RESOLUTION")
		_assert(String(losers[0]["authority_id"]) == "authority/sim-c", "higher authority id loses the tie-break")
	_assert(String(first_run["fx"]["router"].get_report()["committed_operations"][0]) \
			== String(second_run["fx"]["router"].get_report()["committed_operations"][0]), "tie-break produces identical committed operations across permutations")


func _tie_break_fixture(c_segment_first: bool) -> Dictionary:
	var fx: Dictionary = _fixture(c_segment_first)
	fx["leg_c"].collision_t = 5.0
	fx["leg_c"].collision_kind = "ENTITY"
	fx["leg_c"].collided_entity = "entity/near-c-1"
	fx["leg_a"].collision_t = 5.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/far-a-1"
	return {"fx": fx, "intent": _intent("0301")}


func test_neg04_target_unavailable_mid_resolution() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	fx["leg_a"].commit_unavailable = true
	var envelope: Dictionary = fx["router"].route(_intent("0401"))
	_assert(not bool(envelope["success"]), "unavailable target fails the pipeline")
	_assert(String(envelope["error_code"]) == "EFFECT_COMMIT_UNAVAILABLE", "commit unavailability reported explicitly")
	var token := String(envelope["retry_token"])
	_assert(not token.is_empty(), "retry token preserved for unavailable target")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0, "no partial effect at unavailable target")
	_assert(int(fx["leg_c"].journal.effect_count()) == 0, "no partial effect anywhere else")
	_assert(String(fx["router"].pending_retry_token("operation/0401")) == token, "router remembers the pending token per operation")
	fx["leg_a"].commit_unavailable = false
	var retried: Dictionary = fx["router"].retry_pending_commit(token)
	_assert(bool(retried["success"]) and String(retried["result"]["result"]) == "COMMITTED", "retry after recovery commits exactly once")
	_assert(int(fx["leg_a"].journal.effect_count()) == 1, "retry applies exactly one effect")
	_assert(String(fx["router"].pending_retry_token("operation/0401")) == "", "retry token consumed after success")


func test_neg05_stale_projection_subscription() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var intent: Dictionary = _intent("0501", "entity/target-a-1", 3)
	var envelope: Dictionary = fx["router"].route(intent)
	_assert(not bool(envelope["success"]), "stale projection subscription rejects the candidate")
	_assert(String(envelope["error_code"]) == "STALE_PROJECTION_SUBSCRIPTION", "candidate-only rejection uses STALE_PROJECTION_SUBSCRIPTION")
	_assert(bool(envelope["details"]["pending_fresh_interest_revision"]), "rejection requests a fresh interest revision")
	_assert(int(envelope["details"]["current_interest_revision"]) == 4, "current interest revision surfaced in rejection")
	_assert(int(fx["router"].get_report()["counters"]["queries_routed"]) == 0, "nothing was routed on a stale subscription")
	_assert(int(fx["action"].validate_calls) == 0, "action authority never consulted on stale subscription")


func test_neg06_domain_validation_rejects_commit() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var journal = fx["leg_a"].journal
	journal.set_domain_validator(func(_payload) -> Dictionary:
		return {"allowed": false, "reason": "TARGET_OUT_OF_ARC"})
	var envelope: Dictionary = fx["router"].route(_intent("0601"))
	_assert(bool(envelope["success"]), "explicit domain rejection is a well-formed terminal outcome")
	var result: Dictionary = envelope["result"]
	_assert(String(result["result"]) == "REJECTED", "domain rejection relays a REJECTED result")
	_assert(String(envelope["details"]["rejected_reason"]) == "TARGET_OUT_OF_ARC", "domain rejection reason relayed verbatim")
	_assert(int(journal.effect_count()) == 0, "rejected commit leaves no partial effect")
	_assert(String(journal.rejection_reason("operation/0601")) == "TARGET_OUT_OF_ARC", "journal records the explicit rejection")


func test_neg07_replay_after_success_exactly_once() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var first: Dictionary = fx["router"].route(_intent("0701"))
	_assert(String(first["result"]["result"]) == "COMMITTED", "original commit succeeds")
	var counter_after_first: int = fx["leg_a"].journal.next_canonical_effect_revision()
	var replay_same_router: Dictionary = fx["router"].route(_intent("0701"))
	_assert(String(replay_same_router["error_code"]) == "ALREADY_APPLIED", "replay after success reports ALREADY_APPLIED")
	_assert(int(fx["leg_a"].journal.next_canonical_effect_revision()) == counter_after_first, "counter unchanged by replay")
	# gateway restart simulation: a FRESH router over the SAME authorities must
	# still be exactly-once thanks to the sim-side journal
	var fresh_router = RouterScript.new()
	var configured: Dictionary = fresh_router.configure(fx["action"], {
		"authority/sim-a": fx["leg_a"], "authority/sim-c": fx["leg_c"],
	}, fx["domain"], fx["subs"])
	_assert(bool(configured.get("success", false)), "fresh router configures over the same authorities")
	var replay_fresh_router: Dictionary = fresh_router.route(_intent("0701"))
	_assert(String(replay_fresh_router["result"]["result"]) == "DUPLICATE_REPLAY", "post-restart replay hits the journal exactly-once guard")
	_assert(int(fx["leg_a"].journal.next_canonical_effect_revision()) == counter_after_first, "counter unchanged after post-restart replay")
	_assert(int(fx["leg_a"].journal.effect_count()) == 1, "still exactly one effect after all replays")
	print("[eg45-router][exit] CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS")


func test_neg08_non_canonical_payload() -> void:
	var fx: Dictionary = _fixture(true)
	var intent: Dictionary = _intent("0801")
	intent["interaction_kind"] = "LASER_BEAM"
	var envelope: Dictionary = fx["router"].route(intent)
	_assert(not bool(envelope["success"]), "non-canonical payload fails closed")
	_assert(String(envelope["error_code"]) == "CONTRACT_VIOLATION", "non-canonical payload reports CONTRACT_VIOLATION")
	_assert(int(fx["domain"].calls) == 0, "contract violation happens BEFORE routing (domain router untouched)")
	_assert(int(fx["action"].validate_calls) == 0, "contract violation happens BEFORE action validation")
	_assert(int(fx["router"].get_report()["counters"]["queries_routed"]) == 0, "no collision query left the gateway")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0 and int(fx["leg_c"].journal.effect_count()) == 0, "no effects exist after violation")


func test_neg09_projection_hint_is_candidate_only() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	var direct_attempt: Dictionary = fx["router"].attempt_direct_effect_commit({
		"interaction_id": "interaction/shoot-0901",
		"operation_id": "operation/0901",
		"target_entity_id": "entity/target-a-1",
		"evidence_source": "projection_hit",
		"projection_revision": 4,
	})
	_assert(not bool(direct_attempt["success"]), "direct projection-hit commit attempt is refused")
	_assert(String(direct_attempt["error_code"]) == "PROJECTION_HIT_IS_CANDIDATE_ONLY", "projection-hit commit reports PROJECTION_HIT_IS_CANDIDATE_ONLY")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0, "projection-hit attempt leaves no effect")
	var bare_attempt: Dictionary = fx["router"].attempt_direct_effect_commit({
		"operation_id": "operation/0902",
		"target_entity_id": "entity/target-a-1",
	})
	_assert(String(bare_attempt["error_code"]) == "DIRECT_COMMIT_NOT_ROUTED", "any direct commit outside routing is fail-closed")
	_assert(int(fx["router"].get_report()["counters"]["commits_attempted"]) == 0, "no commit ever left the gateway via the direct surface")
	print("[eg45-router][exit] PROJECTION_HIT_IS_CANDIDATE_ONLY_PASS")


func test_neg10_link_break_mid_resolution() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	fx["leg_a"].force_error = "LEG_TIMEOUT"
	var envelope: Dictionary = fx["router"].route(_intent("1001"))
	_assert(not bool(envelope["success"]), "link break mid-resolution fails the pipeline")
	_assert(String(envelope["error_code"]) == "RESOLUTION_LINK_TIMEOUT", "link break reports RESOLUTION_LINK_TIMEOUT")
	_assert(envelope["resolution"] == null, "no resolution survives a link break")
	_assert(int(fx["leg_c"].journal.effect_count()) == 0 and int(fx["leg_a"].journal.effect_count()) == 0, "no half-mutated worlds after link break")
	_assert(int(fx["leg_a"].queries_received.size()) == 1, "broken authority received exactly its one query before the break")
	# deterministic rollback: state is clean, the same operation retries cleanly
	fx["leg_a"].force_error = ""
	var retried: Dictionary = fx["router"].route(_intent("1001"))
	_assert(bool(retried["success"]) and String(retried["result"]["result"]) == "COMMITTED", "clean retry after rollback commits")
	_assert(int(fx["leg_a"].journal.effect_count()) == 1, "rollback left no duplicate or partial effect")


func test_synthetic_flag_enforced_at_gateway() -> void:
	var fx: Dictionary = _fixture(true)
	_set_clear_path(fx["leg_c"])
	fx["leg_a"].collision_t = 8.0
	fx["leg_a"].collision_kind = "ENTITY"
	fx["leg_a"].collided_entity = "entity/target-a-1"
	fx["action"].proposal_flag_value = true
	var envelope: Dictionary = fx["router"].route(_intent("1101"))
	_assert(not bool(envelope["success"]), "non-synthetic proposal refused at the gateway boundary")
	_assert(String(envelope["error_code"]) == "SYNTHETIC_FLAG_REQUIRED", "gateway enforces product_canonical_mutation_allowed=false")
	_assert(int(fx["leg_a"].journal.effect_count()) == 0, "no effect committed for a non-synthetic proposal")
	_assert(bool(fx["router"].get_report()["product_canonical_mutation_allowed"] == false), "router declares product_canonical_mutation_allowed=false")


func _init() -> void:
	test_happy_path_clear()
	test_wall_blocks()
	test_near_wins_over_far()
	test_neg01_duplicate_intent_idempotent()
	test_neg02_stale_reference_frame()
	test_neg03_simultaneous_claim_deterministic_tie_break()
	test_neg04_target_unavailable_mid_resolution()
	test_neg05_stale_projection_subscription()
	test_neg06_domain_validation_rejects_commit()
	test_neg07_replay_after_success_exactly_once()
	test_neg08_non_canonical_payload()
	test_neg09_projection_hint_is_candidate_only()
	test_neg10_link_break_mid_resolution()
	test_synthetic_flag_enforced_at_gateway()

	if failures.size() > 0:
		print("[eg45-router] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
		return
	print("[eg45-router] all %d assertions passed" % assertions)
	print("[eg45-router][exit] CROSS_WORLD_INTERACTION_CONTRACTS_PASS")
	print("[eg45-router][exit] CROSS_WORLD_DOMAIN_ROUTING_PASS")
	print("[eg45-router][exit] MULTI_AUTHORITY_COLLISION_PROOF_PASS")
	print("[eg45-router][exit] DETERMINISTIC_FIRST_COLLISION_RESOLUTION_PASS")
	quit(0)

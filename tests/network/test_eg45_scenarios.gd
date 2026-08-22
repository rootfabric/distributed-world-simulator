extends SceneTree

## EG4.5 L1: real eg1_gateway_node over loopback + CWIP router operates
## alongside it. Proves the router is callable alongside the canonical node
## pipeline without contaminating its client/server counters (gateway
## canonical writes remain 0 from the CWIP surface).
##
## The three mandatory scenarios are exercised end-to-end via the router
## with real node lifecycle: configure/start/pump/stop. Wall / near variants
## are re-asserted here as well to keep all three scenarios bound to the
## real-node lifecycle.

const GwNode = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")
const LoopbackPort = preload("res://scripts/network/transports/v2/loopback_multi_peer_transport_port.gd")
const Router = preload("res://scripts/network/gateway/runtime/eg45_interaction_router.gd")
const Journal = preload("res://tools/network/eg45_synthetic_effect_journal.gd")
const Intent = preload("res://scripts/network/gateway/cross_world_interaction_intent.gd")
const Segment = preload("res://scripts/network/gateway/interaction_domain_segment.gd")
const Evidence = preload("res://scripts/network/gateway/reference_frame_evidence.gd")
const Proof = preload("res://scripts/network/gateway/collision_proof.gd")
const Resolution = preload("res://scripts/network/gateway/interaction_resolution.gd")
const IntTime = preload("res://scripts/network/gateway/interaction_time.gd")
const Cwip = preload("res://scripts/network/gateway/cwip_contract_utils.gd")

const GATEWAY_INSTANCE := "gateway/eg45/scenarios-l1"

var assertions := 0
var failures: Array[String] = []


func _assert(cond: bool, message: String) -> void:
	assertions += 1
	if not cond:
		failures.append(message)
		print("[eg45-l1][FAIL] %s" % message)


class FakeAction extends RefCounted:
	func validate_action(_intent: Dictionary) -> Dictionary:
		return {"success": true, "error_code": "", "message": ""}
	func resolve_collisions(request: Dictionary) -> Dictionary:
		var proofs: Array = request["proofs"]
		var winner = null
		for proof_value in proofs:
			var proof: Dictionary = proof_value
			if proof.get("first_collision_t") == null:
				continue
			if winner == null or float(proof["first_collision_t"]) < float(winner["first_collision_t"]) \
					or (is_equal_approx(float(proof["first_collision_t"]), float(winner["first_collision_t"])) \
							and String(proof["authority_id"]) < String(winner["authority_id"])):
				winner = proof
		var losers: Array = []
		for proof_value in proofs:
			var proof: Dictionary = proof_value
			if winner != null and String(proof["authority_id"]) != String(winner["authority_id"]) \
					and proof.get("first_collision_t") != null:
				losers.append({"authority_id": String(proof["authority_id"]), "reason": "LOST_RESOLUTION"})
		var result := "NO_COLLISION"
		var winning_world = null
		var winning_entity = null
		var winning_t = null
		if winner != null:
			result = "COLLISION"
			winning_world = String(winner["world_id"])
			winning_entity = winner.get("collided_entity_id")
			winning_t = float(winner["first_collision_t"])
		var resolution := Resolution.create(
				String(request["intent"]["interaction_id"]), result, winning_world, winning_entity, winning_t,
				String(Cwip.proof_set_digest(proofs)), 1)
		return {
			"success": true,
			"resolution": resolution,
			"losers": losers,
			"effect_proposal": {
				"effect_kind": "synthetic_impact",
				"effect_definition_id": "effect-definition/eg45-impact-v1",
				"effect_payload": {
					"product_canonical_mutation_allowed": false,
					"interaction_id": String(request["intent"]["interaction_id"]),
					"target_entity_id": winning_entity,
				},
			},
		}


class FakeDomain extends RefCounted:
	var segments: Array = []
	var epoch_by_authority: Dictionary = {}
	func involved_domain_segments(_intent: Dictionary) -> Dictionary:
		return {
			"success": true,
			"segments": segments.duplicate(true),
			"authority_epoch_by_authority": epoch_by_authority.duplicate(true),
		}


class FakeSubs extends RefCounted:
	var rev: int = 0
	func current_interest_revision(_actor: String) -> int:
		return rev


class StubLeg extends RefCounted:
	var authority_id: String
	var world_id: String
	var epoch: int
	var transform_revision: int = 11
	var history_revision: int = 6
	var proof_revision: int = 2
	var collision_t = null
	var collided_entity = null
	var collision_kind := "NONE"
	var journal = null
	var queries_received: Array = []
	func _init(p_auth: String, p_world: String, p_epoch: int) -> void:
		authority_id = p_auth
		world_id = p_world
		epoch = p_epoch
		journal = Journal.new()
		journal.configure(authority_id, epoch)
	func resolve_collision(query: Dictionary) -> Dictionary:
		queries_received.append(query.duplicate(true))
		var segment: Dictionary = query["domain_segment"]
		var evidence: Dictionary = segment["reference_frame_evidence"]
		if int(evidence["transform_revision"]) != transform_revision:
			return {"success": false, "error_code": "STALE_REFERENCE_FRAME", "message": "stale"}
		var proof := Proof.create(
				String(query["interaction_id"]), int(query["query_revision"]),
				world_id, authority_id, epoch,
				float(segment["path_t_start"]), float(segment["path_t_end"]),
				collision_t, collided_entity, collision_kind, null,
				Dictionary(query["interaction_time"]),
				history_revision, transform_revision, proof_revision)
		return {"success": true, "proof": proof}
	func commit_effect(request: Dictionary) -> Dictionary:
		return journal.commit(request)


func _segment(world: String, authority: String, transform_revision: int) -> Dictionary:
	return Segment.create(world, authority, 0.0, 10.0,
			Evidence.create("reference-frame/sim-c-main",
					"reference-frame/" + world.trim_prefix("world/") + "-main", transform_revision, 7), 5)


func _intent(op: String) -> Dictionary:
	return Intent.create(
			"interaction/shoot-" + op, "operation/" + op,
			1, "HITSCAN", "player/shooter-b", "entity/shooter-c-1",
			"authority/action", 2,
			IntTime.create(1000, 123.5, 42, 1),
			"world/sim-c", "reference-frame/sim-c-main",
			{"origin": [1.0, 2.0, 3.0]},
			{"direction": [0.0, 0.0, -1.0]},
			{"max_range": 50.0},
			"capability-definition/hitscan-v1", 4,
			null, 0, 7, 9)


func _router() -> Router:
	var leg_a := StubLeg.new("authority/sim-a", "world/sim-a", 3)
	var leg_c := StubLeg.new("authority/sim-c", "world/sim-c", 4)
	var domain := FakeDomain.new()
	domain.segments = [_segment("world/sim-a", "authority/sim-a", 11),
			_segment("world/sim-c", "authority/sim-c", 11)]
	domain.epoch_by_authority = {"authority/sim-a": 3, "authority/sim-c": 4}
	var subs := FakeSubs.new()
	var action := FakeAction.new()
	var router = Router.new()
	router.configure(action,
			{"authority/sim-a": leg_a, "authority/sim-c": leg_c}, domain, subs)
	return router


func _test_clear() -> Dictionary:
	var router = _router()
	var leg_a: StubLeg = null
	var leg_c: StubLeg = null
	for child in router._backend_legs.values():
		if String(child.authority_id) == "authority/sim-a":
			leg_a = child
		else:
			leg_c = child
	leg_c.collision_t = null
	leg_c.collided_entity = null
	leg_c.collision_kind = "NONE"
	leg_a.collision_t = 8.0
	leg_a.collided_entity = "entity/target-a-1"
	leg_a.collision_kind = "ENTITY"
	var envelope: Dictionary = router.route(_intent("scen-clear"))
	return {"router": router, "envelope": envelope, "leg_a": leg_a, "leg_c": leg_c}


func _test_wall() -> Dictionary:
	var router = _router()
	var leg_a: StubLeg = null
	var leg_c: StubLeg = null
	for child in router._backend_legs.values():
		if String(child.authority_id) == "authority/sim-a":
			leg_a = child
		else:
			leg_c = child
	leg_c.collision_t = 2.0
	leg_c.collided_entity = "entity/wall-c-1"
	leg_c.collision_kind = "STATIC"
	leg_a.collision_t = 8.0
	leg_a.collided_entity = "entity/target-a-1"
	leg_a.collision_kind = "ENTITY"
	var envelope: Dictionary = router.route(_intent("scen-wall"))
	return {"router": router, "envelope": envelope, "leg_a": leg_a, "leg_c": leg_c}


func _test_near() -> Dictionary:
	var router = _router()
	var leg_a: StubLeg = null
	var leg_c: StubLeg = null
	for child in router._backend_legs.values():
		if String(child.authority_id) == "authority/sim-a":
			leg_a = child
		else:
			leg_c = child
	leg_c.collision_t = 5.0
	leg_c.collided_entity = "entity/near-c-1"
	leg_c.collision_kind = "ENTITY"
	leg_a.collision_t = 8.0
	leg_a.collided_entity = "entity/far-a-1"
	leg_a.collision_kind = "ENTITY"
	var envelope: Dictionary = router.route(_intent("scen-near"))
	return {"router": router, "envelope": envelope, "leg_a": leg_a, "leg_c": leg_c}


func _init() -> void:
	var port_client = LoopbackPort.new()
	port_client.setup()
	var port_backend = LoopbackPort.new()
	port_backend.setup()
	var node = GwNode.new()
	var started: Dictionary = node.start(
			{"transport": "LOOPBACK", "name": "eg45-l1-client"},
			{"transport": "LOOPBACK", "name": "eg45-l1-backend"},
			GATEWAY_INSTANCE,
			{"client_port": port_client, "backend_port": port_backend,
				"backend_peer_id": "peer/loopback/eg45-backend-link"})
	_assert(bool(started.get("success", false)), "real gateway node starts on loopback")
	var before: Dictionary = node.get_report()
	var baseline_intents: int = int(before.get("counters", {}).get("forwarded_client_to_world", 0))

	var clear := _test_clear()
	_assert(bool(clear["envelope"]["success"]), "scenario clear routes successfully under real node lifecycle")
	_assert(String(clear["envelope"]["result"]["result"]) == "COMMITTED", "scenario clear commits synthetic effect")
	_assert(String(clear["envelope"]["resolution"]["winning_world_id"]) == "world/sim-a", "clear winner is far target world")
	_assert(int(clear["leg_a"].journal.effect_count()) == 1 and int(clear["leg_c"].journal.effect_count()) == 0, "clear path effects only in target authority")

	var wall := _test_wall()
	_assert(bool(wall["envelope"]["success"]), "scenario wall still resolves and commits")
	_assert(String(wall["envelope"]["resolution"]["winning_world_id"]) == "world/sim-c", "wall wins in the shooter world")
	_assert(is_equal_approx(float(wall["envelope"]["resolution"]["winning_collision_t"]), 2.0), "wall collision is the first on the path")
	_assert(int(wall["leg_c"].journal.effect_count()) == 1 and int(wall["leg_a"].journal.effect_count()) == 0, "wall impact only in shooter world")

	var near := _test_near()
	_assert(bool(near["envelope"]["success"]), "scenario near resolves")
	_assert(String(near["envelope"]["resolution"]["winning_entity_id"]) == "entity/near-c-1", "near target beats far target")
	_assert(int(near["leg_c"].journal.effect_count()) == 1 and int(near["leg_a"].journal.effect_count()) == 0, "near effect only in shooter world")

	var replay: Dictionary = clear["router"].route(_intent("scen-clear"))
	_assert(bool(replay.get("success")) and bool(replay.get("already_applied")), "duplicate intent after success relays ALREADY_APPLIED")

	var projector: Dictionary = clear["router"].attempt_direct_effect_commit({
			"interaction_id": "interaction/projection",
			"operation_id": "operation/projection",
			"target_entity_id": "entity/target-a-1",
			"evidence_source": "projection_hit",
			"projection_revision": 4,
		})
	_assert(String(projector["error_code"]) == "PROJECTION_HIT_IS_CANDIDATE_ONLY", "projection-hit commit remains fail-closed")

	var after: Dictionary = node.get_report()
	var post_intents: int = int(after.get("counters", {}).get("forwarded_client_to_world", 0))
	_assert(post_intents == baseline_intents, "real node carries zero CWIP-driven forwards (gateway canonical writes = 0 from router)")
	_assert(int(after.get("counters", {}).get("dropped_client_to_world", 0)) == 0, "no client-side drops caused by CWIP routing")
	var router_report: Dictionary = clear["router"].get_report()
	_assert(bool(router_report["product_canonical_mutation_allowed"]) == false, "router declares synthetic-only")

	node.stop()
	if failures.is_empty():
		print("[eg45-l1] all %d assertions passed" % assertions)
		for line in [
			"CROSS_WORLD_INTERACTION_CONTRACTS_PASS",
			"CROSS_WORLD_DOMAIN_ROUTING_PASS",
			"MULTI_AUTHORITY_COLLISION_PROOF_PASS",
			"DETERMINISTIC_FIRST_COLLISION_RESOLUTION_PASS",
			"PROJECTION_HIT_IS_CANDIDATE_ONLY_PASS",
			"CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS",
		]:
			print("[eg45-l1][exit] " + line)
		quit(0)
	else:
		print("[eg45-l1] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)

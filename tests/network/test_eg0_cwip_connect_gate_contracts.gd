extends SceneTree

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ConnectGateScript = preload("res://scripts/network/gateway/gateway_connect_gate.gd")
const InteractionTimeScript = preload("res://scripts/network/gateway/interaction_time.gd")
const ReferenceFrameEvidenceScript = preload("res://scripts/network/gateway/reference_frame_evidence.gd")
const IntentScript = preload("res://scripts/network/gateway/cross_world_interaction_intent.gd")
const DomainSegmentScript = preload("res://scripts/network/gateway/interaction_domain_segment.gd")
const CollisionQueryScript = preload("res://scripts/network/gateway/collision_query.gd")
const CollisionProofScript = preload("res://scripts/network/gateway/collision_proof.gd")
const ResolutionScript = preload("res://scripts/network/gateway/interaction_resolution.gd")
const EffectRequestScript = preload("res://scripts/network/gateway/effect_commit_request.gd")
const EffectResultScript = preload("res://scripts/network/gateway/effect_commit_result.gd")

const FIXTURE_PATH := "res://tests/network/fixtures/edge_gateway/eg0_cwip_connect_gate_fixtures.v1.json"

var assertions: int = 0
var failures: Array[String] = []
var fixture: Dictionary = {}


func _init() -> void:
	fixture = _load_fixture()
	if fixture.is_empty():
		_finish()
		return
	_test_connect_gate()
	_test_cwip_fixture_chain()
	_test_cwip_fail_closed_fences()
	_test_cross_contract_identity_continuity()
	_finish()


func _test_connect_gate() -> void:
	var gate: Dictionary = Dictionary(fixture.get("connect_gate", {})).duplicate(true)
	_assert_ok(ConnectGateScript.validate(gate), "Valid GatewayConnectGate rejected")

	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(gate)
	_assert(bool(round_trip.get("success", false)), "GatewayConnectGate is not JSON round-trip safe")
	if bool(round_trip.get("success", false)):
		_assert_ok(
			ConnectGateScript.validate(Dictionary(round_trip.get("value", {}))),
			"Round-tripped GatewayConnectGate rejected",
		)

	for pair in [
		["protocol_admitted", "PROTOCOL_NOT_ADMITTED"],
		["identity_verified", "IDENTITY_NOT_VERIFIED"],
		["placement_resolved", "PLACEMENT_NOT_RESOLVED"],
		["authority_resolved", "AUTHORITY_NOT_RESOLVED"],
		["backend_route_attached", "BACKEND_ROUTE_NOT_ATTACHED"],
		["player_domain_ready", "PLAYER_DOMAIN_NOT_READY"],
		["world_ready", "WORLD_NOT_READY"],
	]:
		var blocked: Dictionary = gate.duplicate(true)
		blocked[String(pair[0])] = false
		_assert_error(
			ConnectGateScript.validate(blocked),
			String(pair[1]),
			"Connect gate did not fail closed for %s" % String(pair[0]),
		)

	var endpoint_leak: Dictionary = gate.duplicate(true)
	endpoint_leak["simulation_server_endpoint"] = "10.0.0.2:7777"
	_assert_error(
		ConnectGateScript.validate(endpoint_leak),
		"UNEXPECTED_FIELD",
		"Connect gate accepted simulation-server endpoint leakage",
	)

	var credential_leak: Dictionary = gate.duplicate(true)
	credential_leak["access_credential"] = "secret-must-not-be-persisted"
	_assert_error(
		ConnectGateScript.validate(credential_leak),
		"UNEXPECTED_FIELD",
		"Connect gate accepted access credential persistence",
	)

	var same_numeric_revision: Dictionary = gate.duplicate(true)
	same_numeric_revision["route_revision"] = same_numeric_revision["authority_epoch"]
	_assert_ok(
		ConnectGateScript.validate(same_numeric_revision),
		"RouteRevision was incorrectly coupled to AuthorityEpoch numeric value",
	)


func _test_cwip_fixture_chain() -> void:
	_assert_ok(InteractionTimeScript.validate(Dictionary(fixture.get("interaction_time", {}))), "Valid interaction_time fixture rejected")
	_assert_ok(ReferenceFrameEvidenceScript.validate(Dictionary(fixture.get("reference_frame_evidence", {}))), "Valid reference_frame_evidence fixture rejected")
	_assert_ok(IntentScript.validate(Dictionary(fixture.get("intent", {}))), "Valid intent fixture rejected")
	_assert_ok(DomainSegmentScript.validate(Dictionary(fixture.get("domain_segment", {}))), "Valid domain_segment fixture rejected")
	_assert_ok(CollisionQueryScript.validate(Dictionary(fixture.get("collision_query", {}))), "Valid collision_query fixture rejected")
	_assert_ok(CollisionProofScript.validate(Dictionary(fixture.get("collision_proof", {}))), "Valid collision_proof fixture rejected")
	_assert_ok(ResolutionScript.validate(Dictionary(fixture.get("resolution", {}))), "Valid resolution fixture rejected")
	_assert_ok(EffectRequestScript.validate(Dictionary(fixture.get("effect_request", {}))), "Valid effect_request fixture rejected")
	_assert_ok(EffectResultScript.validate(Dictionary(fixture.get("effect_result", {}))), "Valid effect_result fixture rejected")

	for name in [
		"interaction_time",
		"reference_frame_evidence",
		"intent",
		"domain_segment",
		"collision_query",
		"collision_proof",
		"resolution",
		"effect_request",
		"effect_result",
	]:
		var value: Dictionary = Dictionary(fixture.get(String(name), {})).duplicate(true)
		var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
		_assert(bool(round_trip.get("success", false)), "%s fixture is not JSON round-trip safe" % String(name))
		if bool(round_trip.get("success", false)):
			_assert(
				NetworkUtilsScript.canonical_json(round_trip.get("value")) == NetworkUtilsScript.canonical_json(value),
				"%s changed across canonical JSON round-trip" % String(name),
			)


func _test_cwip_fail_closed_fences() -> void:
	var intent: Dictionary = Dictionary(fixture.get("intent", {})).duplicate(true)
	var forged_hint: Dictionary = intent.duplicate(true)
	forged_hint["optional_projection_target_hint"] = "authority/test/a"
	_assert_error(
		IntentScript.validate(forged_hint),
		"PROJECTION_TARGET_HINT_NOT_ENTITY",
		"Authority identity accepted as projection target hint",
	)

	var hint_without_revision: Dictionary = intent.duplicate(true)
	hint_without_revision["projection_revision"] = 0
	_assert_error(
		IntentScript.validate(hint_without_revision),
		"INVALID_PROJECTION_REVISION",
		"Projection target hint accepted without a versioned projection revision",
	)

	var query: Dictionary = Dictionary(fixture.get("collision_query", {})).duplicate(true)
	var stale_graph: Dictionary = query.duplicate(true)
	stale_graph["world_graph_revision"] = int(stale_graph["world_graph_revision"]) + 1
	_assert_error(
		CollisionQueryScript.validate(stale_graph),
		"STALE_WORLD_GRAPH_EVIDENCE",
		"CollisionQuery accepted mismatched WorldGraph/reference-frame evidence",
	)

	var segment: Dictionary = Dictionary(fixture.get("domain_segment", {})).duplicate(true)
	var reversed_segment: Dictionary = segment.duplicate(true)
	reversed_segment["path_t_start"] = 0.9
	reversed_segment["path_t_end"] = 0.3
	_assert_error(
		DomainSegmentScript.validate(reversed_segment),
		"INVALID_PATH_RANGE",
		"InteractionDomainSegment accepted reversed path range",
	)

	var proof: Dictionary = Dictionary(fixture.get("collision_proof", {})).duplicate(true)
	var outside_proof: Dictionary = proof.duplicate(true)
	outside_proof["first_collision_t"] = 0.95
	_assert_error(
		CollisionProofScript.validate(outside_proof),
		"INVALID_COLLISION_T",
		"CollisionProof accepted collision outside its domain segment",
	)
	_assert_error(
		CollisionProofScript.validate_newer(proof.duplicate(true), proof),
		"STALE_PROOF_REVISION",
		"Duplicate/stale CollisionProof revision accepted as newer",
	)

	var no_collision_with_entity: Dictionary = proof.duplicate(true)
	no_collision_with_entity["collision_kind"] = "NONE"
	no_collision_with_entity["first_collision_t"] = null
	no_collision_with_entity["hit_zone"] = null
	_assert_error(
		CollisionProofScript.validate(no_collision_with_entity),
		"INVALID_NO_COLLISION_PROOF",
		"NONE CollisionProof accepted a collided entity",
	)

	var resolution: Dictionary = Dictionary(fixture.get("resolution", {})).duplicate(true)
	var gateway_authored_resolution: Dictionary = resolution.duplicate(true)
	gateway_authored_resolution["gateway_instance_id"] = "gateway/test/g1"
	_assert_error(
		ResolutionScript.validate(gateway_authored_resolution),
		"UNEXPECTED_FIELD",
		"InteractionResolution accepted Gateway routing metadata",
	)

	var effect_request: Dictionary = Dictionary(fixture.get("effect_request", {})).duplicate(true)
	var stale_effect_owner: Dictionary = effect_request.duplicate(true)
	stale_effect_owner["target_authority_epoch_observed"] = 0
	_assert_error(
		EffectRequestScript.validate(stale_effect_owner),
		"INVALID_INTEGER",
		"EffectCommitRequest accepted an invalid target authority epoch",
	)

	var effect_result: Dictionary = Dictionary(fixture.get("effect_result", {})).duplicate(true)
	var rejected_with_revision: Dictionary = effect_result.duplicate(true)
	rejected_with_revision["result"] = "REJECTED"
	_assert_error(
		EffectResultScript.validate(rejected_with_revision),
		"UNEXPECTED_CANONICAL_EFFECT_REVISION",
		"Rejected EffectCommitResult claimed a canonical effect revision",
	)


func _test_cross_contract_identity_continuity() -> void:
	var intent: Dictionary = Dictionary(fixture.get("intent", {}))
	var query: Dictionary = Dictionary(fixture.get("collision_query", {}))
	var proof: Dictionary = Dictionary(fixture.get("collision_proof", {}))
	var resolution: Dictionary = Dictionary(fixture.get("resolution", {}))
	var request: Dictionary = Dictionary(fixture.get("effect_request", {}))
	var result: Dictionary = Dictionary(fixture.get("effect_result", {}))

	var interaction_id := String(intent.get("interaction_id"))
	var operation_id := String(intent.get("operation_id"))
	for value in [query, proof, resolution, request, result]:
		_assert(
			String(value.get("interaction_id")) == interaction_id,
			"interaction_id changed across CWIP contract chain",
		)
	for value in [request, result]:
		_assert(
			String(value.get("operation_id")) == operation_id,
			"operation_id changed before/after effect commit",
		)

	var duplicate_request: Dictionary = request.duplicate(true)
	_assert(
		NetworkUtilsScript.canonical_json(duplicate_request) == NetworkUtilsScript.canonical_json(request),
		"Retry with the same InteractionId/OperationId is not canonically stable",
	)


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		_fail("Cannot open fixture: %s" % FIXTURE_PATH)
		return {}
	var decoded = JSON.parse_string(file.get_as_text())
	if typeof(decoded) != TYPE_DICTIONARY:
		_fail("Fixture root must be a Dictionary")
		return {}
	var result := Dictionary(decoded)
	_assert(
		String(result.get("schema")) == "distributed_world_simulator.eg0_cwip_connect_gate_fixtures.v1",
		"Unexpected CWIP/connect-gate fixture schema",
	)
	return result


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result])


func _assert_error(result: Dictionary, error_code: String, message: String) -> void:
	_assert(
		not bool(result.get("success", false)) and String(result.get("error_code", "")) == error_code,
		"%s: %s" % [message, result],
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EG0 CWIP + Connect Gate contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("EG0 CWIP + Connect Gate contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

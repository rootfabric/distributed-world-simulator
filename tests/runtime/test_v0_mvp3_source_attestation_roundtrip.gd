extends SceneTree

# R13 targeted regression: the frozen live-player export packet must carry a
# checksum bound to its transport-canonical JSON form. Accumulated fixed-tick
# movement doubles are not stable across a first JSON round trip in Godot's
# full-precision formatter, so a pre-transport checksum rejected every
# legitimate graphical handoff at the target source-attestation gate
# (LIVE_PLAYER_SOURCE_ATTESTATION_MISMATCH). Legitimate crossings must PASS;
# stale, forged, tampered, wrong-identity, and absent attestations must FAIL
# exactly at the attestation surface.

const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Identity = preload("res://scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd")
const Ledger = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")
const Admission = preload("res://scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd")
const Closure = preload("res://scripts/runtime/networked_gameplay/p6/p6_closure_adapter.gd")
const Coordinator = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd")
const Carry = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_player_carrying_domain.gd")
const Pivot = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_gateway_route_pivot.gd")
const CommandRoute = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_player_command_route.gd")
const InputDTO = preload("res://scripts/runtime/networked_gameplay/contracts/player_input_command.gd")
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const AtomicJson = preload("res://scripts/testing/process_harness/atomic_json_file.gd")

const SESSION := "transport-session/mvp3/a"

var assertions := 0
var failures: Array[String] = []
var state: Dictionary = {}
var sequences := 0
var last_operation_id := ""
var evidence: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> bool:
	assertions += 1
	if not ok:
		failures.append(description)
		push_error(description)
	return ok


func success(result: Dictionary, description: String) -> bool:
	return check(bool(result.get("success", false)), description + ": " + str(result.get("error_code", "")))


func pivot_move(dx: float) -> bool:
	sequences += 1
	var operation_id := "operation/mvp3/attestation-r13/a/%d" % sequences
	var wire := InputDTO.create("message/mvp3/attestation-r13/a/%d" % sequences, operation_id, "a", SESSION, 1, 1, sequences, "MOVEMENT_DELTA", {"delta_x": dx, "delta_z": 0.0})
	var command := {"domain_id": "p6-domain/outpost-world-state", "command_kind": "PLAYER_INTERACTION", "operation_id": operation_id, "wire": wire}
	var result: Dictionary = state["pivot"].route_command("client-session/mvp3/a", operation_id, command)
	if not success(result, "ledger-applied pivot movement"):
		return false
	last_operation_id = operation_id
	return true


func fixed_intent() -> Dictionary:
	return {"move_x": 1.0, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false}


func accumulate_fixed_ticks(owner, max_ticks: int) -> bool:
	# Freeze on the first tick whose accumulated position double is not
	# stable across a canonical JSON round trip: exactly the class that
	# broke the pre-R13 checksum at the target attestation gate.
	var found := false
	for tick in range(1, max_ticks + 1):
		owner.advance_fixed_server_tick(tick)
		sequences += 1
		var result: Dictionary = owner.simulate_fixed_movement_tick("a", SESSION, 1, sequences, fixed_intent(), 1.0 / 60.0)
		if not check(bool(result.get("success", false)) and not bool(result.get("replay", false)), "canonical fixed-tick movement applied: tick %d" % tick):
			return false
		var position_x: Dictionary = {"x": float(owner.get_player("a")["position"]["x"])}
		var round_trip: Dictionary = Utils.json_round_trip(position_x)
		if Utils.payload_hash(position_x) != Utils.payload_hash(round_trip.get("value", {})):
			found = true
			break
	return found


func transport_round_trips(packet: Dictionary, times: int) -> Dictionary:
	var carried := packet
	for _trip in range(times):
		var round_trip: Dictionary = Utils.json_round_trip(carried)
		if not bool(round_trip.get("success", false)) or not round_trip.get("value") is Dictionary:
			return {}
		carried = round_trip["value"]
	return carried


func rehash(packet: Dictionary) -> Dictionary:
	return Utils.finalize_json_checksum(packet)


func setup_fixture() -> bool:
	var source = Service.new()
	var target = Service.new()
	if not success(source.setup("authority/a", 1, 0, {"fixed_tick_authority": true, "region_id": "region/mvp3/a"}), "source service setup"):
		return false
	if not success(target.setup("authority/b", 1, 0, {"fixed_tick_authority": true, "region_id": "region/mvp3/b"}), "target service setup"):
		return false
	if not success(source.join("a", SESSION, "operation/mvp3/attestation-r13/join/a"), "canonical initial join"):
		return false
	var identity = Identity.new()
	var ledger = Ledger.new()
	var admission = Admission.new()
	var closure = Closure.new()
	if not success(ledger.configure(1024), "accepted ledger"):
		return false
	if not success(identity.bind("client-session/mvp3/a", "player/mvp3/a", "entity/mvp3/a"), "accepted P6 identity alias"):
		return false
	if not success(admission.configure(identity, ledger), "accepted admission") or not success(closure.configure(identity, ledger), "accepted closure"):
		return false
	var port_a = source.get_live_player_transfer_port()
	var port_b = target.get_live_player_transfer_port()
	if not check(port_a != null and port_b != null, "owner-native live ports exist"):
		return false
	if not success(port_a.register_peer("authority/b", port_b), "trusted peer B") or not success(port_b.register_peer("authority/a", port_a), "trusted peer A"):
		return false
	var coordinator = Coordinator.new()
	if not success(coordinator.configure("authority/a", 1, {"logical_player_id": "player/mvp3/a", "player_entity_id": "entity/mvp3/a", "last_input_sequence": 0, "last_operation_id": ""}), "existing SM1 coordinator"):
		return false
	var carrying = Carry.new()
	if not success(carrying.configure(identity, ledger, closure, coordinator), "accepted carrying domain"):
		return false
	for port in [port_a, port_b]:
		if not success(port.bind_player("a", SESSION, 1, coordinator), "trusted native per-player binding"):
			return false
	var by_authority: Dictionary = {}
	for entry in [["authority/a", source], ["authority/b", target]]:
		var route = CommandRoute.new()
		if not success(route.configure(entry[1], "a", SESSION, identity, ledger, admission, closure), "production P6/M3 command adapter"):
			return false
		by_authority[entry[0]] = route
	var pivot = Pivot.new()
	if not success(pivot.configure(by_authority, coordinator, "gateway/mvp3/attestation-r13", "client-session/mvp3/a"), "accepted stable gateway pivot"):
		return false
	state = {"owners": {"authority/a": source, "authority/b": target}, "ports": {"authority/a": port_a, "authority/b": port_b}, "coordinator": coordinator, "carrying": carrying, "pivot": pivot, "ledger": ledger}
	return true


func cross(player: String, target_id: String, transfer_id: String) -> bool:
	var coordinator = state["coordinator"]
	var carrying = state["carrying"]
	var decision: Dictionary = coordinator.snapshot()
	var source_id := String(decision["active_authority_id"])
	var source_epoch := int(decision["authority_epoch"])
	var source = state["owners"][source_id]
	var target = state["owners"][target_id]
	var source_port = state["ports"][source_id]
	var target_port = state["ports"][target_id]
	var before: Dictionary = source.get_player(player)
	if not success(coordinator.begin_transfer(transfer_id, source_id, target_id, source_epoch), "real SM1 freeze"):
		return false
	var prepared: Dictionary = carrying.prepare_transfer(transfer_id, "client-session/mvp3/" + player, int(before["last_input_sequence"]), last_operation_id)
	if not success(prepared, "accepted carrying captures actual live watermark"):
		return false
	var exported: Dictionary = source_port.prepare_export(player, transfer_id, prepared["details"]["manifest"])
	if not success(exported, "native source live export"):
		return false
	var packet: Dictionary = exported["details"]["packet"]
	# The process composition seals the export reply at the source and seals
	# the forwarded stage request again at the gateway: two full canonical
	# JSON round trips before the target recomputes the attestation.
	var delivered: Dictionary = transport_round_trips(packet, 2)
	if not check(not delivered.is_empty(), "packet survives two JSON transport round trips"):
		return false
	var stage: Dictionary = target_port.stage_export(player, delivered)
	if not success(stage, "legitimate %s -> %s staging passes the source attestation after JSON transport" % [source_id, target_id]):
		return false
	if source_id == "authority/a":
		# Negative controls run before the first crossing completes so the
		# staged state is still open on this target port.
		var tampered_keep_checksum: Dictionary = delivered.duplicate(true)
		tampered_keep_checksum["player"]["position"]["x"] = float(tampered_keep_checksum["player"]["position"]["x"]) + 1e-9
		check(String(target_port.stage_export(player, tampered_keep_checksum).get("error_code", "")) == "LIVE_PLAYER_SOURCE_CHECKSUM_INVALID", "tampering without rehash rejected at the checksum attestation")
		var tampered_rehashed: Dictionary = delivered.duplicate(true)
		tampered_rehashed["player"]["position"]["x"] = float(tampered_rehashed["player"]["position"]["x"]) + 0.5
		check(String(target_port.stage_export(player, rehash(tampered_rehashed)).get("error_code", "")) == "LIVE_PLAYER_SOURCE_PACKET_DIVERGED", "rehashed tampering rejected by trusted source attestation comparison")
		var wrong_identity: Dictionary = delivered.duplicate(true)
		wrong_identity["logical_player_id"] = "b"
		check(String(target_port.stage_export(player, rehash(wrong_identity)).get("error_code", "")) == "LIVE_PLAYER_EXPORT_TUPLE_MISMATCH", "wrong player identity rejected at the export tuple gate")
		var wrong_epoch: Dictionary = delivered.duplicate(true)
		wrong_epoch["player"]["ownership_epoch"] = 99
		check(String(target_port.stage_export(player, rehash(wrong_epoch)).get("error_code", "")) == "LIVE_PLAYER_SOURCE_PACKET_DIVERGED", "forged ownership epoch rejected by trusted source attestation comparison")
		var stale_transfer: Dictionary = delivered.duplicate(true)
		stale_transfer["transfer_id"] = "transfer/mvp3/attestation-r13/never-exported"
		check(String(target_port.stage_export(player, rehash(stale_transfer)).get("error_code", "")) == "LIVE_PLAYER_TRANSFER_NOT_CURRENT", "unknown transfer id cannot stage")
	var warm: Dictionary = carrying.build_composite_warm_report(transfer_id, stage["details"]["shadow_report"])
	if not success(warm, "live target stage checksum nested in accepted SM1 warm chain"):
		return false
	if not success(coordinator.validate_warm_target(transfer_id, target_id, warm["details"]["warm_report"]), "SM1 warm validation"):
		return false
	var committed: Dictionary = coordinator.commit_ownership(transfer_id, source_id, target_id, source_epoch, source_epoch + 1)
	if not success(committed, "existing SM1 ownership commit"):
		return false
	var token := String(committed["details"]["commit_token"])
	if not success(source_port.retire_source(player, transfer_id, token), "actual source native fence retired"):
		return false
	if not success(coordinator.retire_source(transfer_id, source_id, token), "accepted SM1 source retirement"):
		return false
	if not success(coordinator.activate_target(transfer_id, target_id, source_epoch + 1, token), "accepted SM1 target activation"):
		return false
	var installed: Dictionary = target_port.activate_target(player, transfer_id, token)
	if not success(installed, "actual target canonical actor installed"):
		return false
	var after: Dictionary = target.get_player(player)
	check(after["transport_session_id"] == before["transport_session_id"] and after["logical_player_id"] == before["logical_player_id"], "identity preserved across the seam")
	check(source.get_player(player).is_empty(), "retired source is not a second canonical actor")
	evidence["transfers"].append({"transfer_id": transfer_id, "source": source_id, "target": target_id, "before": before, "after": after, "delivered": delivered.duplicate(true), "delivered_checksum": delivered.get("checksum", ""), "attestation": "TRANSPORT_CANONICAL"})
	return true


func stale_attestation_after_ownership_moved() -> void:
	# Ownership has returned to authority/a. A freshly frozen transfer that
	# reuses an old delivered packet has no matching prepared export on the
	# current source and must fail at the attestation gate.
	var coordinator = state["coordinator"]
	var delivered: Dictionary = evidence["transfers"][1].get("delivered", {})
	if delivered.is_empty():
		check(false, "stale control requires the delivered packet of the completed return crossing")
		return
	var stale: Dictionary = delivered.duplicate(true)
	var decision: Dictionary = coordinator.snapshot()
	stale["transfer_id"] = "transfer/mvp3/attestation-r13/stale-reuse"
	stale["source_authority_id"] = String(decision["active_authority_id"])
	var next_target := "authority/b" if String(decision["active_authority_id"]) == "authority/a" else "authority/a"
	stale["target_authority_id"] = next_target
	stale["source_epoch"] = int(decision["authority_epoch"])
	stale["target_epoch"] = int(decision["authority_epoch"]) + 1
	if success(coordinator.begin_transfer(stale["transfer_id"], stale["source_authority_id"], next_target, int(decision["authority_epoch"])), "freeze for stale attestation control"):
		var result: Dictionary = state["ports"][next_target].stage_export("a", rehash(stale))
		check(String(result.get("error_code", "")) == "LIVE_PLAYER_SOURCE_ATTESTATION_ABSENT", "stale attestation after ownership moved rejected as absent at the source attestation gate")
		coordinator.abort_before_commit(stale["transfer_id"], stale["source_authority_id"])


func run() -> void:
	evidence = {"schema": "distributed_world_simulator.mvp3_source_attestation_roundtrip_test.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "mvp3_predicate_verified": false, "transfers": []}
	var okay := setup_fixture()
	if okay:
		okay = pivot_move(0.25) and pivot_move(0.25)
	if okay:
		check(accumulate_fixed_ticks(state["owners"]["authority/a"], 40), "fixture reproduces the non-idempotent accumulated double class")
		var player: Dictionary = state["owners"]["authority/a"].get_player("a")
		evidence["accumulated_position_x"] = float(player["position"]["x"])
	if okay:
		okay = cross("a", "authority/b", "transfer/mvp3/attestation-r13/a-out")
	if okay:
		okay = pivot_move(0.25)
	if okay:
		okay = cross("a", "authority/a", "transfer/mvp3/attestation-r13/a-back")
	if okay:
		stale_attestation_after_ownership_moved()
	if okay:
		var final_player: Dictionary = state["owners"]["authority/a"].get_player("a")
		check(float(final_player["position"]["x"]) != 0.0, "post-return canonical position is real")
		check(int(final_player["last_input_sequence"]) >= 12, "input watermark carried across both seams")
	evidence["assertions"] = assertions
	evidence["failures"] = failures
	evidence["passed"] = okay and failures.is_empty()
	for authority in state.get("owners", {}):
		state["owners"][authority].shutdown()
	var evidence_path := OS.get_environment("MVP3_SOURCE_ATTESTATION_RESULT").strip_edges()
	var saved := {"success": true}
	if not evidence_path.is_empty():
		saved = AtomicJson.write_dictionary(evidence_path, evidence)
	print("MVP3_SOURCE_ATTESTATION_ROUNDTRIP assertions=%d failures=%d passed=%s" % [assertions, failures.size(), evidence["passed"]])
	quit(0 if bool(evidence["passed"]) and bool(saved.get("success", false)) else 1)

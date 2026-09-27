extends SceneTree

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

var assertions := 0
var failures: Array[String] = []
var services: Array = []
var routes: Array = []
var state: Dictionary = {}
var evidence: Dictionary = {}
var sequences := {"a": 0, "b": 0}
var last_commands: Dictionary = {}


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


func command(player: String, sequence: int, dx: float, suffix: String = "") -> Dictionary:
	var op := "operation/mvp3/live/%s/%d%s" % [player, sequence, suffix]
	var wire := InputDTO.create("message/mvp3/live/%s/%d%s" % [player, sequence, suffix], op, player, "transport-session/mvp3/" + player, 1, 1, sequence, "MOVEMENT_DELTA", {"delta_x": dx, "delta_z": 0.0})
	return {"domain_id": "p6-domain/outpost-world-state", "command_kind": "PLAYER_INTERACTION", "operation_id": op, "wire": wire}


func move(player: String, dx: float = 0.25) -> bool:
	sequences[player] += 1
	var cmd := command(player, sequences[player], dx)
	var result: Dictionary = state["pivots"][player].route_command("client-session/mvp3/" + player, cmd["operation_id"], cmd)
	if not success(result, "real independently controlled movement: " + player):
		return false
	last_commands[player] = cmd
	return true


func setup_fixture() -> bool:
	var source = Service.new()
	var target = Service.new()
	services = [source, target]
	for entry in [[source, "a"], [target, "b"]]:
		if not success(entry[0].setup("authority/" + entry[1], 1, 0, {"fixed_tick_authority": true, "region_id": "region/mvp3/" + entry[1]}), "real service setup"):
			return false
	for player in ["a", "b"]:
		if not success(source.join(player, "transport-session/mvp3/" + player, "operation/mvp3/join/" + player), "canonical initial join"):
			return false
	var durable: Dictionary = source.export_durable_state()
	if not success(source.validate_durable_state(durable), "unchanged restart positive control before live opt-in"):
		return false
	evidence["legacy_restart_before_live"] = durable
	var identity = Identity.new()
	var ledger = Ledger.new()
	var admission = Admission.new()
	var closure = Closure.new()
	if not success(ledger.configure(1024), "accepted ledger"):
		return false
	for player in ["a", "b"]:
		if not success(identity.bind("client-session/mvp3/" + player, "player/mvp3/" + player, "entity/mvp3/" + player), "accepted P6 identity alias"):
			return false
	if not success(admission.configure(identity, ledger), "accepted admission") or not success(closure.configure(identity, ledger), "accepted closure"):
		return false
	var port_a = source.get_live_player_transfer_port()
	var port_b = target.get_live_player_transfer_port()
	if not check(port_a != null and port_b != null, "owner-native live ports exist"):
		return false
	if not success(port_a.register_peer("authority/b", port_b), "trusted peer B") or not success(port_b.register_peer("authority/a", port_a), "trusted peer A"):
		return false
	state = {"owners": {"authority/a": source, "authority/b": target}, "ports": {"authority/a": port_a, "authority/b": port_b}, "coordinators": {}, "carrying": {}, "pivots": {}, "ledger": ledger, "closure": closure, "identity": identity}
	for player in ["a", "b"]:
		var coordinator = Coordinator.new()
		if not success(coordinator.configure("authority/a", 1, {"logical_player_id": "player/mvp3/" + player, "player_entity_id": "entity/mvp3/" + player, "last_input_sequence": 0, "last_operation_id": ""}), "existing SM1 coordinator"):
			return false
		state["coordinators"][player] = coordinator
		var carrying = Carry.new()
		if not success(carrying.configure(identity, ledger, closure, coordinator), "accepted carrying domain"):
			return false
		state["carrying"][player] = carrying
		for port in [port_a, port_b]:
			if not success(port.bind_player(player, "transport-session/mvp3/" + player, 1, coordinator), "trusted native per-player binding"):
				return false
		var by_authority: Dictionary = {}
		for authority in ["authority/a", "authority/b"]:
			var route = CommandRoute.new()
			if not success(route.configure(state["owners"][authority], player, "transport-session/mvp3/" + player, identity, ledger, admission, closure), "production P6/M3 command adapter"):
				return false
			routes.append(route)
			by_authority[authority] = route
		var pivot = Pivot.new()
		if not success(pivot.configure(by_authority, coordinator, "gateway/mvp3", "client-session/mvp3/" + player), "accepted stable gateway pivot"):
			return false
		state["pivots"][player] = pivot
	evidence["initial_players"] = {"a": source.get_player("a"), "b": source.get_player("b")}
	evidence["initial_graphs"] = {"authority/a": source.create_canonical_item_graph_snapshot(), "authority/b": target.create_canonical_item_graph_snapshot()}
	return true


func cross(player: String, target_id: String, transfer_id: String, attack: bool = false) -> bool:
	var coordinator = state["coordinators"][player]
	var carrying = state["carrying"][player]
	var pivot = state["pivots"][player]
	var decision: Dictionary = coordinator.snapshot()
	var source_id := String(decision["active_authority_id"])
	var source_epoch := int(decision["authority_epoch"])
	var source = state["owners"][source_id]
	var target = state["owners"][target_id]
	var source_port = state["ports"][source_id]
	var target_port = state["ports"][target_id]
	var before: Dictionary = source.get_player(player)
	var route_identity: Dictionary = pivot.get_client_route_identity()
	var graph_a: Dictionary = services[0].create_canonical_item_graph_snapshot()
	var graph_b: Dictionary = services[1].create_canonical_item_graph_snapshot()
	if not success(coordinator.begin_transfer(transfer_id, source_id, target_id, source_epoch), "real SM1 freeze"):
		return false
	var fixed_intent := {"move_x": 1.0, "move_z": 0.0, "look_yaw": 0.0, "look_pitch": 0.0, "jump_pressed": false, "sprint": false}
	check(not bool(source.move_player(player, "transport-session/mvp3/" + player, 1, sequences[player] + 1, 0.25, 0.0, "operation/mvp3/frozen/" + transfer_id.sha256_text()).get("success", false)), "direct canonical input fenced, not only gateway")
	check(not bool(source.simulate_fixed_movement_tick(player, "transport-session/mvp3/" + player, 1, sequences[player] + 1, fixed_intent, 1.0 / 60.0).get("success", false)), "direct fixed tick fenced during transfer")
	check(not bool(source.set_player_presentation(player, "transport-session/mvp3/" + player, 1, 0.0, true, "operation/mvp3/frozen-presentation/" + transfer_id.sha256_text()).get("success", false)), "presentation mutation fenced during transfer")
	check(not bool(target.move_player(player, "transport-session/mvp3/" + player, 1, sequences[player] + 1, 0.25, 0.0, "operation/mvp3/warm/" + transfer_id.sha256_text()).get("success", false)), "warm target cannot accept canonical input")
	var other := "b" if player == "a" else "a"
	if not move(other, -0.25):
		return false
	var carry_prepared: Dictionary = carrying.prepare_transfer(transfer_id, "client-session/mvp3/" + player, sequences[player], last_commands[player]["operation_id"])
	if not success(carry_prepared, "accepted carrying captures actual live watermark"):
		return false
	var manifest: Dictionary = carry_prepared["details"]["manifest"]
	var exported: Dictionary = source_port.prepare_export(player, transfer_id, manifest)
	if not success(exported, "native source live export"):
		return false
	var packet: Dictionary = exported["details"]["packet"]
	check(packet["player"] == before, "source actor is byte-equivalent through freeze")
	check(packet["ownership"]["ownership_epoch"] == 1 and packet["player"]["transport_session_id"] == before["transport_session_id"], "live binding is carried, not rejoined")
	check(not packet.has("canonical_item_graph") and not packet.has("players"), "no whole-world or Item Graph transfer")
	for operation in packet["replay"]:
		check(packet["replay"][operation]["live_player_id"] == player, "only actor replay slice is exported")
		check(not packet["replay"][operation]["result"]["details"].has("snapshot"), "no foreign world snapshot in replay slice")
	if attack:
		for field in ["position", "transport_session_id", "ownership_epoch", "logical_player_id"]:
			var forged := packet.duplicate(true)
			match field:
				"position": forged["player"]["position"]["x"] = 999.0
				"transport_session_id": forged["player"]["transport_session_id"] = "transport-session/foreign"
				"ownership_epoch": forged["player"]["ownership_epoch"] = 99
				"logical_player_id": forged["player"]["logical_player_id"] = other
			forged = Utils.finalize_json_checksum(forged)
			check(not bool(target_port.stage_export(player, forged).get("success", false)), "rehashed tampering rejected by trusted source attestation: " + field)
	var serialized = JSON.parse_string(JSON.stringify(packet, "", true, true))
	check(serialized is Dictionary, "transfer packet survives actual JSON transport encoding")
	var stage: Dictionary = target_port.stage_export(player, serialized)
	if not success(stage, "real target native staging after JSON roundtrip"):
		return false
	check(target.get_player(player).is_empty(), "staged actor not visible as authoritative player")
	check(not bool(target_port.activate_target(player, transfer_id, "forged-token").get("success", false)), "activation without SM1 commit rejected")
	var warm: Dictionary = carrying.build_composite_warm_report(transfer_id, stage["details"]["shadow_report"])
	if not success(warm, "live target stage checksum nested in accepted SM1 warm chain"):
		return false
	if not success(coordinator.validate_warm_target(transfer_id, target_id, warm["details"]["warm_report"]), "SM1 warm validation"):
		return false
	var committed: Dictionary = coordinator.commit_ownership(transfer_id, source_id, target_id, source_epoch, source_epoch + 1)
	if not success(committed, "existing SM1 ownership commit"):
		return false
	var token := String(committed["details"]["commit_token"])
	check(not bool(target_port.activate_target(player, transfer_id, token).get("success", false)), "commit alone cannot activate target before retirement")
	if not success(source_port.retire_source(player, transfer_id, token), "actual source native fence retired"):
		return false
	if not success(coordinator.retire_source(transfer_id, source_id, token), "accepted SM1 source retirement"):
		return false
	if not success(coordinator.activate_target(transfer_id, target_id, source_epoch + 1, token), "accepted SM1 target activation"):
		return false
	check(target.get_player(player).is_empty(), "old local row not revived by coordinator label change")
	check(not bool(target_port.activate_target(player, transfer_id, "wrong-proof").get("success", false)), "wrong commit token rejected after valid control-plane activation")
	var installed: Dictionary = target_port.activate_target(player, transfer_id, token)
	if not success(installed, "actual target canonical actor installed"):
		return false
	check(target.get_player(player) == before, "identity position velocity sequence and revision preserved exactly on install")
	check(typeof(target.get_player(player)["ownership_epoch"]) == TYPE_INT and typeof(target.get_player(player)["last_input_sequence"]) == TYPE_INT, "canonical counters retain integer types after JSON transport")
	check(source.get_player(player).is_empty(), "retired source not a second canonical actor")
	check(not bool(source.move_player(player, "transport-session/mvp3/" + player, 1, sequences[player] + 1, 0.25, 0.0, "operation/mvp3/retired/" + transfer_id.sha256_text()).get("success", false)), "retired direct source input rejected")
	check(not bool(source.simulate_fixed_movement_tick(player, "transport-session/mvp3/" + player, 1, sequences[player] + 1, fixed_intent, 1.0 / 60.0).get("success", false)), "retired fixed tick rejected")
	check(services[0].create_canonical_item_graph_snapshot() == graph_a and services[1].create_canonical_item_graph_snapshot() == graph_b, "both existing Item Graphs untouched by actor transfer")
	check(source.get_report()["authority_epoch"] == 1 and target.get_report()["authority_epoch"] == 1, "per-player seam does not rotate whole-service authority epochs")
	var old_command: Dictionary = last_commands[player]
	var replay: Dictionary = target.handle_live_player_input(old_command["wire"])
	check(bool(replay.get("success", false)) and bool(replay.get("replay", false)), "exact canonical replay survives transfer to other owner")
	check(target.get_player(player) == before, "exact replay does not move actor twice")
	var conflict: Dictionary = old_command["wire"].duplicate(true)
	conflict["payload"]["delta_x"] = -float(old_command["wire"]["payload"]["delta_x"])
	conflict = Utils.finalize_json_checksum(conflict)
	check(Utils.payload_hash(conflict) != Utils.payload_hash(old_command["wire"]), "negative replay control changes the actual command")
	check(target.handle_live_player_input(conflict).get("error_code") == "OPERATION_REPLAY_CONFLICT", "conflicting canonical replay rejected after seam")
	if not move(player, 0.25):
		return false
	var after: Dictionary = target.get_player(player)
	check(after["last_input_sequence"] == sequences[player] and after["position"] != before["position"], "real movement continues on receiving owner")
	if not success(carrying.validate_after_activation(transfer_id, "client-session/mvp3/" + player, sequences[player], last_commands[player]["operation_id"], coordinator), "accepted carrying continuity after real native move"):
		return false
	check(pivot.get_client_route_identity() == route_identity, "gateway identity remains unchanged")
	evidence["transfers"].append({"player": player, "transfer_id": transfer_id, "source": source_id, "target": target_id, "source_epoch": source_epoch, "target_epoch": source_epoch + 1, "packet": packet, "before": before, "after": after, "commit_token": token, "carrying": carrying.get_completed(transfer_id)})
	return true


func run() -> void:
	evidence = {"schema": "distributed_world_simulator.mvp3_live_owner_hooks_test.v1", "subject_head": OS.get_environment("EXPECTED_HEAD"), "subject_tree": OS.get_environment("EXPECTED_TREE"), "production_hooks_exercised": true, "network_graphical_scene_proven": false, "mvp3_predicate_verified": false, "transfers": []}
	var okay := setup_fixture()
	if okay:
		okay = move("a") and move("b")
	if okay:
		okay = cross("a", "authority/b", "transfer/mvp3/a-out", true)
	if okay:
		okay = cross("a", "authority/a", "transfer/mvp3/a-back", true)
	if okay:
		var stale_token: String = evidence["transfers"][0]["commit_token"]
		check(not bool(state["ports"]["authority/b"].activate_target("a", "transfer/mvp3/a-out", stale_token).get("success", false)), "historical activation cannot revive retired B after return A")
		okay = cross("b", "authority/b", "transfer/mvp3/b-out", true)
	if okay:
		okay = cross("b", "authority/a", "transfer/mvp3/b-back", true)
	if okay:
		var player := "a"
		var rejected := command(player, sequences[player], 0.25, "-new-op-stale-sequence")
		var before: Dictionary = services[0].get_player(player)
		var result: Dictionary = state["pivots"][player].route_command("client-session/mvp3/" + player, rejected["operation_id"], rejected)
		check(result.get("error_code") == "MVP3_CANONICAL_COMMIT_NOT_PROVEN", "real handler rejection cannot become P6 APPLIED")
		check(not state["ledger"].is_applied("player/mvp3/a", rejected["operation_id"]), "rejected operation absent from canonical P6 applied ledger")
		check(services[0].get_player(player) == before, "rejected input changes no canonical actor")
		check(state["identity"].get_report()["counters"]["rebinds"] == 0, "no ordinary session rebind")
		check(services[0].restore_durable_state(evidence["legacy_restart_before_live"]).get("error_code") == "LIVE_HANDOFF_RESTART_RECONCILIATION_REQUIRED", "restart cannot overwrite a live authority binding")
		check(services[0].export_durable_state().is_empty(), "no false standalone persistence proof for distributed live actors")
		evidence["final_players"] = {"a": services[0].get_player("a"), "b": services[0].get_player("b")}
		evidence["final_port_reports"] = {"a": state["ports"]["authority/a"].get_report(), "b": state["ports"]["authority/b"].get_report()}
	evidence["assertions"] = assertions
	evidence["failures"] = failures
	evidence["passed"] = okay and failures.is_empty()
	for route in routes:
		route.shutdown()
	for service in services:
		service.shutdown()
	var evidence_path := OS.get_environment("MVP3_OWNER_HOOKS_RESULT").strip_edges()
	var saved := {"success": true}
	if not evidence_path.is_empty():
		saved = AtomicJson.write_dictionary(evidence_path, evidence)
	print("MVP3_LIVE_OWNER_HOOKS assertions=%d failures=%d passed=%s" % [assertions, failures.size(), evidence["passed"]])
	quit(0 if bool(evidence["passed"]) and bool(saved.get("success", false)) else 1)
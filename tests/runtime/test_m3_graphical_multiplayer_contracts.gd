extends SceneTree

const RuntimeRole = preload("res://scripts/runtime/runtime_role.gd")
const LaunchOptions = preload("res://scripts/runtime/launch_options.gd")
const RuntimeDescriptor = preload("res://scripts/runtime/runtime_descriptor.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m3/m3_process_support.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const PresentationCommand = preload("res://scripts/runtime/networked_gameplay/contracts/player_presentation_command.gd")
const PlayerSnapshot = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")
const PlayerDelta = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_delta.gd")
const ProtocolFrame = preload("res://scripts/network/transports/v2/protocol_frame_v2.gd")
const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RemotePresenter = preload("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")

var failures: Array[String] = []
var assertions := 0

func _init() -> void:
	_test_identity_and_launch_options()
	_test_presentation_wire_contract()
	_test_unified_service_presentation_state()
	_test_protocol_float_round_trip()
	_test_transport_bound_operation_identity()
	_test_remote_presenter()
	_test_manifest_and_source_boundaries()
	_finish()

func _test_identity_and_launch_options() -> void:
	_assert(Support.CHECKPOINT == "v16.10.2-runtime-m3-dedicated-graphical-multiplayer", "M3 checkpoint identity")
	_assert(Support.BUILD_ID == "m3-dedicated-two-graphical-clients", "M3 build identity")
	var parsed := LaunchOptions.parse(PackedStringArray([
		"--role=game-client", "--world=moon", "--server-address=10.20.30.40", "--server-port=28770",
		"--player-identity=Player-A", "--m3-result-file=C:/temp/a.json", "--m3-peer-result-file=C:/temp/b.json", "--m3-phase=3",
	]))
	_assert(bool(parsed.get("success", false)), "M3 launch options parse")
	var options: Dictionary = parsed.get("options", {})
	_assert(String(options.get("role", "")) == RuntimeRole.GAME_CLIENT, "M3 role is game-client")
	_assert(String(options.get("server_address", "")) == "10.20.30.40", "M3 address parsed")
	_assert(int(options.get("server_port", 0)) == 28770, "M3 port parsed")
	_assert(String(options.get("player_identity", "")) == "player-a", "M3 identity normalized")
	_assert(int(options.get("m3_phase", 0)) == 3, "M3 phase parsed")
	_assert(String(options.get("m3_result_file", "")).ends_with("a.json"), "M3 report parsed")
	_assert(String(options.get("m3_peer_result_file", "")).ends_with("b.json"), "M3 peer report parsed")
	var descriptor := RuntimeDescriptor.create(options, {"checkpoint": Support.CHECKPOINT, "build_id": Support.BUILD_ID})
	_assert(bool(RuntimeDescriptor.validate(descriptor).get("success", false)), "M3 client descriptor valid")
	_assert(not bool(descriptor.get("authoritative", true)), "M3 client descriptor non-authoritative")
	_assert(not bool(descriptor.get("embedded_authority", true)), "M3 client descriptor has no embedded authority")
	_assert(bool(descriptor.get("presentation_enabled", false)), "M3 client presentation enabled")

func _test_presentation_wire_contract() -> void:
	var command := PresentationCommand.create(
		"message/m3/presentation/1", "operation/m3/presentation/1", "a", "transport-session/m3/a/1", 1, 2, 0.7853981633974483, true
	)
	_assert(bool(PresentationCommand.validate(command).get("success", false)), "presentation command valid")
	_assert(String(command.get("schema", "")) == PresentationCommand.SCHEMA, "presentation command schema")
	_assert(String(command.get("checksum", "")).length() == 64, "presentation command checksum")
	var unexpected := command.duplicate(true); unexpected["authority"] = true
	_assert(not bool(PresentationCommand.validate(unexpected).get("success", true)), "presentation command rejects unexpected field")
	var invalid_yaw := PresentationCommand.create("message/m3/presentation/2", "operation/m3/presentation/2", "a", "transport-session/m3/a/1", 1, 2, 4.0, true)
	_assert(not bool(PresentationCommand.validate(invalid_yaw).get("success", true)), "presentation command rejects yaw outside canonical range")
	var invalid_light := command.duplicate(true); invalid_light["flashlight_enabled"] = 1
	_assert(not bool(PresentationCommand.validate(invalid_light).get("success", true)), "presentation command requires boolean flashlight")
	var mutated := command.duplicate(true); mutated["orientation_yaw"] = 0.0
	_assert(not bool(PresentationCommand.validate(mutated).get("success", true)), "presentation command checksum binds orientation")

func _test_unified_service_presentation_state() -> void:
	var service = Service.new()
	_assert(bool(service.setup("m3-contract-authority", 1, 0, {"region_id": "region/m3/contracts", "topology_adapter": "ENET", "profile": Service.PROFILE_MULTIPLAYER_CORE}).get("success", false)), "M3 service setup")
	var join_a := service.join("a", "transport-session/m3/a/contracts", "operation/m3/contracts/join-a")
	var join_b := service.join("b", "transport-session/m3/b/contracts", "operation/m3/contracts/join-b")
	_assert(bool(join_a.get("success", false)) and bool(join_b.get("success", false)), "two players join unified service")
	var move_a := service.move_player("a", "transport-session/m3/a/contracts", 1, 1, 0.5, 0.5, "operation/m3/contracts/move-a")
	_assert(bool(move_a.get("success", false)), "A authoritative movement")
	var moved: Dictionary = move_a.get("details", {}).get("player", {})
	_assert(is_equal_approx(float(moved.get("orientation_yaw", -10.0)), PI / 4.0), "movement derives canonical orientation")
	_assert(not bool(moved.get("flashlight_enabled", true)), "flashlight starts disabled")
	var presentation := service.set_player_presentation("a", "transport-session/m3/a/contracts", 1, PI / 4.0, true, "operation/m3/contracts/presentation-a")
	_assert(bool(presentation.get("success", false)), "authority accepts presentation state")
	var player: Dictionary = presentation.get("details", {}).get("player", {})
	_assert(bool(player.get("flashlight_enabled", false)), "authority stores flashlight state")
	_assert(is_equal_approx(float(player.get("orientation_yaw", 0.0)), PI / 4.0), "authority stores orientation state")
	var delta: Dictionary = presentation.get("details", {}).get("delta", {})
	_assert(String(delta.get("event_type", "")) == "PLAYER_PRESENTATION_UPDATED", "presentation delta event")
	_assert(bool(PlayerDelta.validate(delta).get("success", false)), "presentation delta validates independently")
	var snapshot: Dictionary = presentation.get("details", {}).get("snapshot", {})
	_assert(bool(PlayerSnapshot.validate(snapshot).get("success", false)), "presentation snapshot validates independently")
	_assert(bool(service.set_player_presentation("a", "transport-session/m3/a/contracts", 1, PI / 4.0, true, "operation/m3/contracts/presentation-a").get("details", {}).get("replay", false)), "presentation operation replays safely")
	var conflict := service.set_player_presentation("a", "transport-session/m3/a/contracts", 1, PI / 4.0, false, "operation/m3/contracts/presentation-a")
	_assert(String(conflict.get("error_code", "")) == "OPERATION_REPLAY_CONFLICT", "changed presentation replay rejected")
	var spoof := service.set_player_presentation("a", "transport-session/m3/b/contracts", 1, 0.0, false, "operation/m3/contracts/spoof")
	_assert(not bool(spoof.get("success", true)), "foreign transport cannot mutate presentation")
	_assert(String(service.get_report().get("profile", "")) == Service.PROFILE_MULTIPLAYER_CORE, "M3 uses unified multiplayer service profile")
	service.shutdown()

func _test_protocol_float_round_trip() -> void:
	var payload := {
		"type": "GAMEPLAY_SNAPSHOT",
		"orientation_yaw": atan2(0.8, 0.2),
		"nested": PresentationCommand.create("message/m3/float/1", "operation/m3/float/1", "a", "transport-session/m3/a/float", 1, 1, atan2(0.8, 0.2), true),
	}
	var frame := ProtocolFrame.create("frame/m3/float/1", "transport-session/m3/a/float", 1, "STATE", "RELIABLE_ORDERED", "planet_simulator.m3_float_probe.v1", payload)
	_assert(bool(ProtocolFrame.validate(frame).get("success", false)), "protocol frame accepts adversarial orientation float")
	var encoded := ProtocolFrame.encode(frame)
	_assert(bool(encoded.get("success", false)), "protocol frame encodes adversarial float")
	var decoded := ProtocolFrame.decode(encoded.get("details", {}).get("packet", PackedByteArray()))
	_assert(bool(decoded.get("success", false)), "protocol frame decodes without payload checksum drift")
	_assert(NetworkUtils.canonical_json(decoded.get("details", {}).get("frame", {})) == NetworkUtils.canonical_json(frame), "protocol frame is canonical JSON round-trip stable")

func _test_transport_bound_operation_identity() -> void:
	var first_session := "transport-session/m3/a/100/1785"
	var reconnect_session := "transport-session/m3/a/200/1785"
	var first_join := Support.transport_bound_operation_id("A", "JOIN", first_session)
	var replay_join := Support.transport_bound_operation_id("a", "join", first_session)
	var reconnect_join := Support.transport_bound_operation_id("a", "join", reconnect_session)
	var first_leave := Support.transport_bound_operation_id("a", "leave", first_session)
	_assert(not first_join.is_empty(), "transport-bound join operation ID created")
	_assert(first_join == replay_join, "same transport session keeps idempotent join identity")
	_assert(first_join != reconnect_join, "reconnect transport session gets a distinct join identity")
	_assert(first_join != first_leave, "operation name remains part of replay identity")
	_assert(first_join.ends_with(first_session.sha256_text().left(16)), "transport session fingerprint binds operation identity")
	_assert(Support.transport_bound_operation_id("", "join", first_session).is_empty(), "empty player identity rejected")
	_assert(Support.transport_bound_operation_id("a", "", first_session).is_empty(), "empty operation name rejected")
	_assert(Support.transport_bound_operation_id("a", "join", "").is_empty(), "empty transport session rejected")
	var service = Service.new()
	_assert(bool(service.setup("m3-operation-identity", 1, 0, {"region_id": "region/m3/operation-identity", "topology_adapter": "ENET", "profile": Service.PROFILE_MULTIPLAYER_CORE}).get("success", false)), "operation identity service setup")
	var first_result := service.join("a", first_session, first_join)
	_assert(bool(first_result.get("success", false)), "first transport session join accepted")
	var leave_result := service.leave_transport_session(first_session, first_leave)
	_assert(bool(leave_result.get("success", false)), "first transport session leave accepted")
	var reconnect_result := service.join("a", reconnect_session, reconnect_join)
	_assert(bool(reconnect_result.get("success", false)), "reconnect join avoids replay conflict")
	_assert(int(reconnect_result.get("details", {}).get("player", {}).get("ownership_epoch", 0)) == 2, "reconnect advances ownership epoch")
	service.shutdown()

func _test_remote_presenter() -> void:
	var presenter = RemotePresenter.new()
	root.add_child(presenter)
	var record := {
		"logical_player_id": "b", "player_entity_id": "player/b", "transport_session_id": "transport-session/m3/b/presenter",
		"ownership_epoch": 1, "connected": true, "position": {"x": 4.0, "y": 1.0, "z": -2.0},
		"velocity": {"x": 0.5, "y": 0.0, "z": 0.5}, "inventory": [], "last_input_sequence": 1,
		"state_revision": 2, "orientation_yaw": PI / 4.0, "flashlight_enabled": true,
	}
	_assert(bool(presenter.setup(record).get("success", false)), "remote presenter setup")
	_assert(not presenter.has_input_authority(), "remote presenter has no input authority")
	var report := presenter.get_report()
	_assert(bool(report.get("flashlight_enabled", false)), "remote presenter applies flashlight")
	_assert(is_equal_approx(float(report.get("orientation_yaw", 0.0)), PI / 4.0), "remote presenter applies orientation")
	_assert(Vector3(report.get("target_position", [0, 0, 0])[0], report.get("target_position", [0, 0, 0])[1], report.get("target_position", [0, 0, 0])[2]).is_equal_approx(Vector3(4.0, 1.0, -2.0)), "remote presenter receives authoritative target")
	_assert(float(report.get("interpolation_rate", 0.0)) > 0.0, "remote presenter interpolation enabled")
	presenter.queue_free()

func _test_manifest_and_source_boundaries() -> void:
	var manifest := _load_json("res://config/network/dedicated-graphical-multiplayer.v1.json")
	_assert(String(manifest.get("schema", "")) == "planet_simulator.dedicated_graphical_multiplayer.v1", "M3 manifest schema")
	_assert(String(manifest.get("checkpoint", "")) == Support.CHECKPOINT, "M3 manifest checkpoint")
	_assert(String(manifest.get("status", "")) == "candidate", "M3 manifest candidate status")
	_assert(String(manifest.get("base_checkpoint", "")) == "v16.10.1-runtime-m2-dedicated-graphical-client", "M3 manifest M2 base")
	_assert(int(manifest.get("topology", {}).get("region_count", 0)) == 1, "M3 remains single authoritative region")
	_assert(String(manifest.get("topology", {}).get("transport", "")) == "ENet", "M3 graphical traffic uses ENet")
	_assert(not bool(manifest.get("presentation_contract", {}).get("remote_input_authority", true)), "M3 manifest forbids remote input authority")
	_assert(String(manifest.get("presentation_contract", {}).get("orientation", "")).contains("orientation_yaw"), "M3 manifest orientation channel")
	_assert(String(manifest.get("presentation_contract", {}).get("flashlight", "")).contains("flashlight_enabled"), "M3 manifest flashlight channel")
	_assert(manifest.get("acceptance", []).size() >= 10, "M3 manifest acceptance coverage")
	var client_source := _read("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
	var presenter_source := _read("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")
	var app_source := _read("res://scripts/app/lunar_app.gd")
	_assert(not client_source.contains("NetworkedGameplayService.new"), "graphical client does not construct authority")
	_assert(not presenter_source.contains("Input.is_action"), "remote presenter reads no input")
	_assert(presenter_source.contains("lerp(target_position"), "remote presenter interpolates")
	_assert(app_source.contains("RemotePlayerPresenter"), "graphical world composes remote presenter")
	_assert(app_source.contains("remote_despawn_count"), "graphical world tracks remote despawn")
	_assert(_read("res://tests/runtime/test_m3_graphical_multiplayer_processes.gd").contains("Xvfb"), "M3 process test uses graphical display")
	var process_source := _read("res://tests/runtime/test_m3_graphical_multiplayer_processes.gd")
	var client_section := process_source.substr(process_source.find("func _spawn_client"), process_source.find("func _spawn(") - process_source.find("func _spawn_client"))
	_assert(not client_section.contains("--headless"), "graphical client command omits headless flag")

func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("M3 graphical multiplayer contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("M3 graphical multiplayer contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)

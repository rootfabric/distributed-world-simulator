extends SceneTree

const Options = preload("res://scripts/runtime/networked_gameplay/live3/live3_launch_options.gd")
const Control = preload("res://scripts/runtime/networked_gameplay/live3/live3_host_control.gd")
const Port = preload("res://scripts/runtime/networked_gameplay/live3/live3_construction_recovery_port.gd")
const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const Legacy = preload("res://scripts/runtime/networked_gameplay/p5/networked_gameplay_service_p5.gd")
const Factory = preload("res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd")
const Bridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const App = preload("res://scripts/app/v0_simulator_app.gd")
const U = preload("res://scripts/network/contracts/network_contract_utils.gd")
var assertions := 0
var failures: Array[String] = []

class FailedSaveServer extends Node:
	func stop() -> Dictionary:
		return {"success": false, "error_code": "INJECTED_DISK_WRITE_FAILURE"}

func _init() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)
	else:
		print("PASS: ", label)
	return value

func native_binding(service, path: String):
	var made: Dictionary = Factory.create_gateway(service.get_canonical_item_graph_port(), "world/live3/contract", 1, path)
	if not check(bool(made.get("success", false)), "native P4 factory: " + str(made.get("error_code", ""))):
		return null
	var bridge = Bridge.new()
	check(bool(bridge.setup(made["details"]["gateway"]).get("success", false)), "native M3 Construction bridge")
	return bridge

func run() -> void:
	var args := ["--network-mvp", "--role=dedicated-server", "--world-slot=contract", "--world-save-root=user://live3-contracts"]
	var parsed: Dictionary = Options.parse(args)
	check(bool(parsed["success"]), "named slot parses: " + str(parsed["errors"]))
	check(parsed["options"].get("node_id") == "world/live3/contract", "slot has stable owner independent of PID")
	check(String(parsed["options"].get("m6_persistence_root", "")).ends_with("/contract"), "slot maps to native M6 root")
	for bad in ["", "../escape", "one/two", "MixedCase", "con", "lpt1", "x:y", "x\\y", "a.b"]:
		check(not Options.valid_slot(bad), "reject invalid slot: " + bad)
	check(not Options.parse(args + ["--world-slot=again"])["success"], "duplicate slot rejected")
	check(not Options.parse(["--network-mvp", "--role=game-client", "--world-slot=x"])["success"], "client cannot become persistence owner")
	check(not Options.parse(args + ["--m6-persistence-root=user://other"])["success"], "ambiguous native root rejected")
	check(not Options.parse(["--network-mvp", "--role=dedicated-server", "--world-slot=x", "--world-save-root=res://"])["success"], "source tree cannot be save root")
	var nonce := "12345678901234567890123456789012"
	var request := {"schema": Control.REQUEST_SCHEMA, "action": "SAVE_AND_STOP", "token": nonce, "process_id": 42, "request_id": "one"}
	check(Control.validate_request(request, nonce, 42)["success"], "operator save request accepted")
	check(not Control.validate_request(request, nonce, 43)["success"], "stale process request rejected")
	check(not Control.validate_request(request, nonce + "x", 42)["success"], "wrong nonce rejected")
	check(not Control.validate_request({}, nonce, 42)["success"], "malformed request rejected")

	var legacy = Legacy.new()
	var live = Service.new()
	var cfg := {"profile": "MULTIPLAYER_CORE", "playable_sandbox": true, "fixed_tick_authority": true}
	check(legacy.setup("world/live3/contract", 1, 0, cfg)["success"], "legacy service setup")
	check(live.setup("world/live3/contract", 1, 0, cfg)["success"], "LIVE3 service setup")
	check(U.canonical_json(legacy.export_durable_state()) == U.canonical_json(live.export_durable_state()), "unbound durable state byte-equivalent to P5")
	check(U.canonical_json(legacy.export_replay_state()) == U.canonical_json(live.export_replay_state()), "unbound replay byte-equivalent to P5")
	var m0 := ProjectSettings.globalize_path("res://artifacts/live3-contracts/%d-%d/m0" % [OS.get_process_id(), Time.get_ticks_usec()])
	var bridge = native_binding(live, m0)
	if bridge != null:
		check(live.bind_live3_construction(bridge)["success"], "bind the real native owners")
		var saved: Dictionary = live.export_durable_state()
		check(saved.has("live3_construction") and live.validate_durable_state(saved)["success"], "M6 cut includes validated native Construction payload")
		var recovered = Service.new()
		recovered.setup("world/live3/contract", 1, 0, cfg)
		check(recovered.restore_durable_state(saved)["success"], "restore native gameplay with pending Construction cut")
		check(recovered.live3_recovery_pending(), "Construction stays pending before native rebind")
		check(recovered.handle_join_command({}).get("error_code") == "LIVE3_CONSTRUCTION_REBIND_REQUIRED", "no join admission before Construction rebind")
		check(U.canonical_json(recovered.export_durable_state()) == U.canonical_json(saved), "unbound recovery DTO round-trips without inventing state")
		var recovered_bridge = native_binding(recovered, m0)
		if recovered_bridge != null:
			var result: Dictionary = recovered.bind_live3_construction(recovered_bridge)
			check(bool(result.get("success", false)), "rebind to SAME M0: " + str(result))
			check(not recovered.live3_recovery_pending(), "pending DTO discarded after owner rebind")
			check(U.canonical_json(recovered.export_durable_state()) == U.canonical_json(saved), "native Construction/build/replay cut exact after restore")
		var malformed: Dictionary = saved.duplicate(true)
		malformed["live3_construction"]["gateway"]["generation"] += 1
		malformed = U.finalize_json_checksum(malformed)
		check(not live.validate_durable_state(malformed)["success"], "nested corruption rejected even with outer checksum recomputed")
		malformed = saved.duplicate(true)
		malformed["live3_construction"]["build_plans"]["ghosts"] = []
		malformed["live3_construction"]["checksum"] = Port.checksum(malformed["live3_construction"])
		malformed = U.finalize_json_checksum(malformed)
		check(not live.validate_durable_state(malformed)["success"], "missing build progress rejected")
		check(U.canonical_json(live.export_durable_state()) == U.canonical_json(saved), "failed validation cannot mutate the live cut")
		recovered.shutdown()
	live.shutdown()
	legacy.shutdown()

	var app = App.new()
	var bad_server = FailedSaveServer.new()
	app.launch_options = {"live3_enabled": true}
	app._live3_bound = true
	app.dedicated_gameplay_server_runtime = bad_server
	app._requested_exit_code = 0
	app._stop_networked_gameplay_runtimes()
	check(app._requested_exit_code != 0, "failed native save propagates nonzero product exit")
	app.dedicated_gameplay_server_runtime = null
	bad_server.free()
	app.free()
	print("LIVE3_CONTRACTS assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

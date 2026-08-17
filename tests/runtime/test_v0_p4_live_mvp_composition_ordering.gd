extends SceneTree

const GameplayService = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const EarthResolver = preload("res://scripts/runtime/networked_gameplay/p3/earth_resource_spatial_resolver.gd")
const Authority = preload("res://scripts/construction/mvp/v0_p4_mvp_earth_outpost_authority.gd")
const Bridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const Server = preload("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
const Command = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Grant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")
const Bundle = preload("res://scripts/construction/multiplayer/construction_multiplayer_state_bundle.gd")

const NODE := "resource/earth/ore-demo/1"
const PLAYER := "alpha"
const TRANSPORT := "transport-session/v0-p4/p4-4/alpha"
var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_static_ordering()
	_runtime_ordering()
	_live_economy()
	_finish()

func _static_ordering() -> void:
	var base := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd")
	var setup_i := base.find("_service.setup(")
	var recovery_i := base.find("_setup_recovery()")
	var seam_i := base.find("_setup_network_condition_simulator(config)")
	var listen_i := base.find("_boundary.start_server(")
	_check(setup_i >= 0 and recovery_i >= 0, "base setup/recovery present")
	_check(seam_i > setup_i and seam_i > recovery_i, "P4 seam is after M4/recovery")
	_check(listen_i > seam_i, "P4 seam is before listen")
	var current := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd")
	_check(current.find("func _setup_network_condition_simulator(config: Dictionary)") >= 0, "current runtime owns prelisten override")
	_check(current.find("_setup_v0_p4_live_composition(config)") >= 0, "prelisten override binds P4")
	_check(current.find("func set_construction_bridge(bridge)") >= 0, "legacy prebind quarantine exists")
	_check(current.find("deferred_to_v0_p4_live_composition") >= 0, "legacy bridge is deferred")
	_check(current.find('config.get("enable_v0_p4_construction", true)') >= 0, "Earth P4 defaults enabled")
	_check(current.find('"%s/v0-p4-construction-m0" % persistence_root') >= 0, "P4 M0 root derives from persistence root")
	var app := FileAccess.get_file_as_string("res://scripts/app/simulator_app.gd")
	_check(app.find("MvpEarthOutpostAuthorityScript.create_gateway()") >= 0, "outer app remains byte-compatible")
	_check(app.find("\"world_id\": requested_world") >= 0, "existing app supplies world")
	_check(app.find("m6_persistence_root") >= 0, "existing app supplies persistence root")
	var service := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/networked_gameplay_service_p2.gd")
	_check(service.count("_canonical_multiplayer_items = CanonicalMultiplayerItemGraph.new()") == 1, "one canonical M4 owner is constructed")
	var canonical := FileAccess.get_file_as_string("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
	_check(canonical.begins_with('extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p4.gd"'), "stable M4 alias is P4-capable")

func _runtime_ordering() -> void:
	var service = _service("runtime-hook")
	if service == null: return
	var runtime = Server.new()
	get_root().add_child(runtime)
	var deferred: Dictionary = runtime.set_construction_bridge(Bridge.new())
	_ok(deferred, "legacy bridge quarantine")
	_check(bool(deferred.get("details", {}).get("deferred_to_v0_p4_live_composition", false)), "legacy bridge never becomes live")
	runtime.set("_service", service)
	runtime.set("_authority_owner_id", "authority/v0-p4/p4-4/runtime-hook")
	runtime.set("_authority_epoch", 1)
	var root := "user://v0-p4-p4-4-runtime-hook/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_ok(runtime._setup_v0_p4_live_composition({"world_id": "earth", "persistence_root": root}), "runtime P4 composition")
	var report: Dictionary = runtime.get_v0_p4_composition_report()
	_check(bool(report.get("enabled", false)), "P4 enabled")
	_check(bool(report.get("bound_before_clients", false)), "P4 bound before clients")
	_check(bool(report.get("single_item_graph_identity", false)), "single M4 identity")
	_check(not bool(report.get("fixture_material_truth_present", true)), "no fixture material truth")
	_check(bool(report.get("legacy_prebind_ignored", false)), "legacy prebind ignored")
	_check(String(report.get("repository_root", "")) == "%s/v0-p4-construction-m0" % root, "durable root derived")
	_check(bool(report.get("p4_construction_consume_ready", false)), "P4 consume ready")
	_check(bool(report.get("resource_mining_bound_to_same_service", false)), "P3 mining shares service")
	runtime.set("_service", null)
	runtime.queue_free()
	service.shutdown()

func _live_economy() -> void:
	var service = _service("economy")
	if service == null: return
	_ok(service.join(PLAYER, TRANSPORT, "operation/v0-p4/p4-4/join-alpha"), "player join")
	var graph = service.get_canonical_item_graph_port()
	var mining = service.get_resource_mining_port()
	_check(graph != null and mining != null, "live P3/P4 ports exist")
	_check(graph.has_method("apply_server_output") and graph.has_method("apply_server_construction_consume"), "same M4 has output+consume")
	var authority: Dictionary = Authority.create_gateway(graph, "authority/v0-p4/p4-4", 1, "user://v0-p4-p4-4/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	_ok(authority, "live authority")
	if not bool(authority.get("success", false)): return
	var a: Dictionary = authority.get("details", {})
	_check(bool(a.get("single_item_graph_identity", false)), "authority binds exact M4")
	_check(not bool(a.get("fixture_material_truth_present", true)), "authority has no fixture resource")
	var recipe: Dictionary = a.get("recipe_ore_quantity_by_stage", {})
	_check([int(recipe.get(0, 0)), int(recipe.get(1, 0)), int(recipe.get(2, 0))] == [2, 4, 2], "recipe is 2/4/2")
	_check(int(recipe.get(0, 0)) + int(recipe.get(1, 0)) + int(recipe.get(2, 0)) == 8, "recipe consumes canonical node exactly")
	var port = a.get("live_port")
	_check(port != null and port.is_bound_to_item_graph(graph), "port retains same M4 object")
	var bridge = Bridge.new()
	_ok(bridge.setup(a.get("gateway")), "bridge setup")
	var connected: Dictionary = bridge.connect_player(PLAYER, 1)
	_ok(connected, "Construction session")
	if not bool(connected.get("success", false)): return
	var session: Dictionary = connected.get("details", {}).get("session", {})
	var initial: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	_ok(Bundle.validate(initial), "initial Construction bundle")
	_check(_no_material(initial), "initial bundle has no copied ore/fastener")
	var before: Dictionary = graph.create_snapshot()
	_err(bridge.submit_player_command(PLAYER, _command(session, 0, "insufficient", 0, initial)), "CONSTRUCTION_MATERIAL_INSUFFICIENT", "build before mining")
	_check(String(before.get("checksum", "")) == String(graph.create_snapshot().get("checksum", "")), "insufficient build is M4-pure")
	_check(Dictionary(port.get_construct_snapshot(Authority.CONSTRUCT_ID)).is_empty(), "insufficient build creates no construct")
	var node: Dictionary = mining.get_node(NODE)
	var resolver = EarthResolver.new()
	_ok(resolver.setup(), "resolver setup")
	var resolved: Dictionary = resolver.resolve_planar(node.get("spatial", {}))
	_ok(resolved, "ore node resolve")
	if not bool(resolved.get("success", false)): return
	var pos: Dictionary = resolved.get("details", {}).get("planar_position", {})
	_ok(mining.mine(PLAYER, "operation/v0-p4/p4-4/mine-2", {"resource_node_id": NODE, "requested_units": 2}, pos), "mine first 2")
	_check(_ore(graph, PLAYER) == 2 and int(mining.get_node(NODE).get("remaining_units", -1)) == 6, "mine 2 -> same M4 and node 6")
	var b0: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	_ok(bridge.submit_player_command(PLAYER, _command(session, 1, "foundation", 0, b0)), "build foundation")
	_check(_ore(graph, PLAYER) == 0, "foundation consumes exact 2")
	_check(String(port.get_construct_snapshot(Authority.CONSTRUCT_ID).get("build_state", "")) == "PARTIAL", "foundation creates partial construct")
	_ok(mining.mine(PLAYER, "operation/v0-p4/p4-4/mine-6", {"resource_node_id": NODE, "requested_units": 6}, pos), "mine remaining 6")
	_check(_ore(graph, PLAYER) == 6 and int(mining.get_node(NODE).get("remaining_units", -1)) == 0, "mine remaining -> ore 6/node 0")
	var b1: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	_ok(bridge.submit_player_command(PLAYER, _command(session, 2, "shell", 1, b1)), "build shell")
	_check(_ore(graph, PLAYER) == 2, "shell consumes 4")
	var b2: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	var roof_cmd := _command(session, 3, "roof", 2, b2)
	_ok(bridge.submit_player_command(PLAYER, roof_cmd), "build roof")
	_check(_ore(graph, PLAYER) == 0, "roof consumes final 2")
	_check(String(port.get_construct_snapshot(Authority.CONSTRUCT_ID).get("build_state", "")) == "OPERATIONAL", "8 mined ore completes outpost")
	var final_bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	_ok(Bundle.validate(final_bundle), "final Construction bundle")
	_check(_no_material(final_bundle), "final bundle never copies M4 material")
	var replay: Dictionary = bridge.submit_player_command(PLAYER, roof_cmd)
	_ok(replay, "exact roof replay")
	_check(bool(replay.get("details", {}).get("result", {}).get("replay", false)), "replay served terminally")
	_check(_ore(graph, PLAYER) == 0 and int(mining.get_node(NODE).get("remaining_units", -1)) == 0, "replay cannot double-consume")
	service.shutdown()

func _service(suffix: String):
	var service = GameplayService.new()
	var result: Dictionary = service.setup("authority/v0-p4/p4-4/%s" % suffix, 1, 0, {"profile": GameplayService.PROFILE_MULTIPLAYER_CORE, "topology_adapter": "ENET", "region_id": "region/v0-p4/p4-4/%s" % suffix, "fixed_tick_authority": true})
	_ok(result, "service %s" % suffix)
	return service if bool(result.get("success", false)) else null

func _command(session: Dictionary, sequence: int, suffix: String, stage: int, bundle: Dictionary) -> Dictionary:
	return Command.create("multiplayer-command/v0-p4/p4-4/%s" % suffix, String(session.get("client_id", "")), String(session.get("session_id", "")), int(session.get("session_epoch", 0)), sequence, Grant.ACTION_BUILD, Authority.CONSTRUCT_ID, _construct_checksum(bundle), int(bundle.get("server_generation", 0)), int(session.get("permission_epoch", 0)), {"build_plan_id": Authority.BUILD_PLAN_ID, "stage_index": stage, "operation_id": "operation/v0-p4/p4-4/build/%s" % suffix, "provided_capabilities": ["INSPECT"] if stage == 2 else ["FASTEN"], "options": {}})

func _construct_checksum(bundle: Dictionary) -> String:
	for row in bundle.get("constructs", []):
		if row is Dictionary and String(row.get("construct_id", "")) == Authority.CONSTRUCT_ID: return String(row.get("checksum", ""))
	return ""

func _ore(graph, player: String) -> int:
	var total := 0
	for row in graph.create_snapshot().get("items", []):
		if row is Dictionary and String(row.get("definition_id", "")) == "item/ore":
			var loc: Dictionary = row.get("location", {})
			if String(loc.get("kind", "")) == "INVENTORY" and String(loc.get("player_id", "")) == player: total += int(row.get("quantity", 0))
	return total

func _no_material(bundle: Dictionary) -> bool:
	for row in bundle.get("items", []):
		if not row is Dictionary: return false
		var d := String(row.get("definition_id", "")); var i := String(row.get("item_instance_id", ""))
		if d in ["ore", "item/ore", "fastener"] or i.contains("fastener") or i.begins_with("item/server-output/"): return false
	return true

func _ok(result: Dictionary, label: String) -> void: _check(bool(result.get("success", false)), "%s: %s" % [label, result])
func _err(result: Dictionary, code: String, label: String) -> void: _check(not bool(result.get("success", false)) and String(result.get("error_code", "")) == code, "%s: %s" % [label, result])
func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures.append(label); push_error("FAIL: %s" % label)
func _finish() -> void:
	if failures.is_empty(): print("V0-P4 live MVP composition ordering: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	print("V0-P4 live MVP composition ordering: FAIL (%d failures, %d assertions)" % [failures.size(), assertions]); quit(1)

extends SceneTree

const Authority = preload("res://scripts/construction/mvp/mvp_earth_outpost_authority.gd")
const Bridge = preload("res://scripts/runtime/networked_gameplay/m3/m3_construction_replication_bridge.gd")
const Command = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Grant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var boot: Dictionary = Authority.create_gateway()
	_assert(bool(boot.get("success", false)), "production outpost gateway boots")
	if not bool(boot.get("success", false)):
		push_error(JSON.stringify(boot))
		_finish()
		return
	var bridge = Bridge.new()
	_assert(bool(bridge.setup(boot.get("gateway")).get("success", false)), "bridge uses production gateway")
	var joined: Dictionary = bridge.connect_player("a", 1)
	_assert(bool(joined.get("success", false)), "M3 player receives construction session")
	if not bool(joined.get("success", false)):
		push_error(JSON.stringify(joined))
		_finish()
		return
	var session: Dictionary = bridge.get_player_session("a")
	var command: Dictionary = Command.create("multiplayer-command/mvp/outpost/foundation", String(session["client_id"]), String(session["session_id"]), int(session["session_epoch"]), 0, Grant.ACTION_BUILD, Authority.CONSTRUCT_ID, "", 0, int(session["permission_epoch"]), {"build_plan_id":Authority.BUILD_PLAN_ID,"stage_index":0,"operation_id":"operation/mvp/outpost/foundation","provided_capabilities":["FASTEN"],"options":{}})
	var built: Dictionary = bridge.submit_player_command("a", command)
	_assert(bool(built.get("success", false)), "foundation commits through canonical gateway")
	var event: Dictionary = built.get("details", {}).get("event_packet", {}).get("event", {})
	_assert(not event.is_empty() and int(event.get("event_index", -1)) == 0, "canonical event is emitted")
	var bundle: Dictionary = bridge.get_snapshot_packet().get("state_bundle", {})
	_assert(int(bundle.get("server_generation", -1)) == 1, "bundle advances after commit")
	_finish()

func _assert(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
func _finish() -> void:
	if failures.is_empty(): print("MVP Earth outpost authority: PASS (%d assertions)" % assertions); quit(0); return
	for failure in failures: push_error(failure)
	quit(1)

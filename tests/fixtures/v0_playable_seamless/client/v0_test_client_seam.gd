extends "res://scripts/runtime/networked_gameplay/sm1/sm1_6_graphical_client.gd"

# Test-only presentation wrapper around the accepted SM1 graphical client.
# Networking, handoff, authority and identity semantics stay in the parent runtime.

var _test_root: Control
var _test_status: Label
var _test_route: Label
var _test_position: ProgressBar
var _test_observe := false
var _test_step_ms := 0
var _test_command_delay_pending := false


func _initialize() -> void:
	_test_observe = OS.get_environment("DWS_TEST_CLIENT_OBSERVE") == "1"
	_test_step_ms = maxi(0, int(OS.get_environment("DWS_TEST_CLIENT_STEP_MS")))
	super._initialize()
	if _finished:
		return
	_build_test_ui()
	_update_test_ui()


func _process(delta: float) -> bool:
	var keep_running := super._process(delta)
	if not _finished:
		_update_test_ui()
	return keep_running


func _handle_state(payload: Dictionary) -> void:
	super._handle_state(payload)
	if not _finished:
		_update_test_ui()


func _send_next_command() -> void:
	if not _test_observe or _test_step_ms <= 0:
		super._send_next_command()
		return
	if _test_command_delay_pending or _finished:
		return
	_test_command_delay_pending = true
	var timer := create_timer(maxf(0.05, float(_test_step_ms) / 1000.0))
	timer.timeout.connect(_dispatch_delayed_command)


func _dispatch_delayed_command() -> void:
	_test_command_delay_pending = false
	if _finished:
		return
	super._send_next_command()


func _build_test_ui() -> void:
	root.title = "DWS Test Client %s — Seam" % _client_id.to_upper()
	root.size = Vector2i(720, 360)
	var screen_size := DisplayServer.screen_get_size()
	if _client_id == "a":
		root.position = Vector2i(40, 80)
	else:
		root.position = Vector2i(maxi(40, screen_size.x - 760), 80)

	var background := ColorRect.new()
	background.color = Color(0.035, 0.045, 0.065, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	_test_root = Control.new()
	_test_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_test_root)

	var title := Label.new()
	title.text = "DWS TEST CLIENT %s  /  SEAM OBSERVATION" % _client_id.to_upper()
	title.position = Vector2(28, 22)
	title.add_theme_font_size_override("font_size", 22)
	_test_root.add_child(title)

	_test_status = Label.new()
	_test_status.position = Vector2(28, 70)
	_test_status.size = Vector2(660, 170)
	_test_status.add_theme_font_size_override("font_size", 17)
	_test_root.add_child(_test_status)

	_test_route = Label.new()
	_test_route.position = Vector2(28, 245)
	_test_route.size = Vector2(660, 30)
	_test_route.add_theme_font_size_override("font_size", 16)
	_test_root.add_child(_test_route)

	_test_position = ProgressBar.new()
	_test_position.position = Vector2(28, 295)
	_test_position.size = Vector2(660, 28)
	_test_position.min_value = 0.0
	_test_position.max_value = 11.0
	_test_position.show_percentage = false
	_test_root.add_child(_test_position)

	var seam_marker := Label.new()
	seam_marker.text = "Authority A                         SEAM                         Authority B"
	seam_marker.position = Vector2(28, 326)
	seam_marker.size = Vector2(660, 24)
	seam_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_test_root.add_child(seam_marker)


func _update_test_ui() -> void:
	if _test_status == null:
		return
	var epoch := int(_epochs[_epochs.size() - 1]) if not _epochs.is_empty() else 0
	var revision := int(_revisions[_revisions.size() - 1]) if not _revisions.is_empty() else 0
	var position_x := float(_last_state.get("position_x", 0.0))
	var authority := _last_authority if not _last_authority.is_empty() else "connecting"
	var mode := "OBSERVE" if _test_observe else "AUTOMATED"
	_test_status.text = (
		"mode: %s\n"
		+ "client: %s    gateway: %s\n"
		+ "player: %s\n"
		+ "entity: %s\n"
		+ "authority: %s    epoch: %d    world revision: %d\n"
		+ "position_x: %.2f    reconnects: %d    respawns: %d"
	) % [
		mode,
		_client_id,
		_gateway_endpoint_id if not _gateway_endpoint_id.is_empty() else "waiting",
		String(_last_state.get("logical_player_id", "waiting")),
		String(_last_state.get("player_entity_id", "waiting")),
		authority,
		epoch,
		revision,
		position_x,
		_reconnect_count,
		_respawn_count,
	]
	_test_route.text = "route history: %s" % " → ".join(PackedStringArray(_route_history))
	_test_position.value = clampf(position_x, 0.0, 11.0)

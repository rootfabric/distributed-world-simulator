extends "res://scripts/app/earth_p3_resource_mining_app.gd"

const EarthLocalAvatarPresenterScript = preload(
	"res://scripts/characters/runtime/earth_local_avatar_presenter.gd"
)
const EarthNetworkAvatarPresenterScript = preload(
	"res://scripts/characters/runtime/earth_network_avatar_presenter.gd"
)

var char1_avatar_presentation
var _char1_setup_error := ""
var _char1_third_person_camera: Camera3D
var _char1_third_person := false
var _char1_camera_toggles := 0
var _playtest_peer_layer: CanvasLayer
var _playtest_peer_hint: Label
var _playtest_hint_at := 0

# R3C.2: visual-only cache. Untracked remote slots never become canonical
# players, active presenter counts, ownership records or durable replay.
const R3C2_MAX_RETAINED_REMOTE_VISUALS := 2
var _r3c2_visual_prewarm_enabled := false
var _r3c2_prewarmed_remote_presenter
var _r3c2_retained_remote_presenters: Dictionary = {}
var _r3c2_prewarm_ms := 0.0
var _r3c2_visual_reuses := 0


func _ready() -> void:
	super._ready()
	if not initialized or not presentation_enabled:
		return
	char1_avatar_presentation = EarthLocalAvatarPresenterScript.new()
	char1_avatar_presentation.name = "CHAR1LocalAvatar"
	add_child(char1_avatar_presentation)
	var options: Dictionary = runtime_world_definition.get("options", {})
	var setup_result: Dictionary = char1_avatar_presentation.setup(
		earth_world,
		earth_explorer,
		String(options.get("avatar_character_id", ""))
	)
	if not bool(setup_result.get("success", false)):
		_char1_setup_error = String(
			setup_result.get("error_code", "CHAR1_SETUP_FAILED")
		)
		char1_avatar_presentation.queue_free()
		char1_avatar_presentation = null
	# Presentation camera is a child of the same Earth observer frame, not an
	# alternative gameplay body. Its origin/orientation inherit the existing
	# floating-origin and player mouse-look without altering authority.
	if earth_explorer != null and earth_explorer.get_camera() != null:
		_char1_third_person_camera = Camera3D.new()
		_char1_third_person_camera.name = "CHAR1ThirdPersonCamera"
		_char1_third_person_camera.position = Vector3(0.45, 0.40, 3.65)
		_char1_third_person_camera.rotation.x = -0.28
		_char1_third_person_camera.fov = 72.0
		_char1_third_person_camera.near = 0.18
		_char1_third_person_camera.far = earth_explorer.get_camera().far
		earth_explorer.add_child(_char1_third_person_camera)
		set_char1_camera_third_person(false)
	if OS.get_environment("DWS_PLAYTEST_PROFILE") == "PLAYTEST_R1_SAFE60":
		_playtest_peer_layer = CanvasLayer.new()
		_playtest_peer_layer.layer = 92
		add_child(_playtest_peer_layer)
		_playtest_peer_hint = Label.new()
		_playtest_peer_hint.position = Vector2(320, 90)
		_playtest_peer_hint.add_theme_color_override("font_color", Color(1.0, 0.92, 0.35))
		_playtest_peer_hint.add_theme_color_override("font_outline_color", Color.BLACK)
		_playtest_peer_hint.add_theme_constant_override("outline_size", 4)
		_playtest_peer_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_playtest_peer_layer.add_child(_playtest_peer_hint)
	# Heavy GLTF/PackedScene instantiation is a loading responsibility.
	# Do it before the client can reach CONNECTING->CONNECTED. A later
	# session_ready only rebinds the same read-only visual to a new NX5
	# interpolator; nothing here changes the M3 replica or transport owner.
	_r3c2_visual_prewarm_enabled = (
		runtime_role == "game-client"
		and OS.get_environment("DWS_NET_R3C2_AVATAR_PREWARM") == "1"
	)
	if _r3c2_visual_prewarm_enabled:
		var started_us := Time.get_ticks_usec()
		var candidate = _create_m3_remote_player_presenter()
		candidate.name = "R3C2PrewarmedRemoteAvatar"
		candidate.visible = false
		add_child(candidate)
		var warmed: Dictionary = candidate.prewarm_visual()
		_r3c2_prewarm_ms = float(Time.get_ticks_usec() - started_us) / 1000.0
		if bool(warmed.get("success", false)):
			# A hidden prewarmed visual must not continue idle animation or
			# interpolation until a canonical peer actually joins.
			candidate.process_mode = Node.PROCESS_MODE_DISABLED
			_r3c2_prewarmed_remote_presenter = candidate
		else:
			_char1_setup_error = String(warmed.get("error_code", "R3C2_REMOTE_VISUAL_PREWARM_FAILED"))
			candidate.queue_free()


func _create_m3_remote_player_presenter():
	# CHAR2 only changes which visual gets created by Earth. The wrapper retains
	# the exact accepted NX5 interpolation, snapshot and floating-origin logic.
	var presenter = EarthNetworkAvatarPresenterScript.new()
	presenter.set_visual_character_id(
		String(runtime_world_definition.get("options", {}).get(
			"avatar_character_id", "character/quaternius/regular"
		))
	)
	return presenter


func _create_m3_remote_player_presenter_for(logical_id: String):
	if _r3c2_visual_prewarm_enabled:
		var retained = _r3c2_retained_remote_presenters.get(logical_id)
		if retained != null and is_instance_valid(retained):
			_r3c2_retained_remote_presenters.erase(logical_id)
			retained.process_mode = Node.PROCESS_MODE_INHERIT
			retained.set_process(true)
			retained.visible = true
			_r3c2_visual_reuses += 1
			return retained
		if _r3c2_prewarmed_remote_presenter != null and is_instance_valid(_r3c2_prewarmed_remote_presenter):
			var warmed = _r3c2_prewarmed_remote_presenter
			_r3c2_prewarmed_remote_presenter = null
			warmed.process_mode = Node.PROCESS_MODE_INHERIT
			warmed.set_process(true)
			warmed.visible = true
			_r3c2_visual_reuses += 1
			return warmed
	return _create_m3_remote_player_presenter()


func _retire_m3_remote_player_presenter(logical_id: String, presenter) -> void:
	if not _r3c2_visual_prewarm_enabled:
		super._retire_m3_remote_player_presenter(logical_id, presenter)
		return
	if _r3c2_retained_remote_presenters.has(logical_id):
		var old = _r3c2_retained_remote_presenters[logical_id]
		if old != null and old != presenter and is_instance_valid(old):
			old.queue_free()
	if _r3c2_retained_remote_presenters.size() >= R3C2_MAX_RETAINED_REMOTE_VISUALS:
		var ids: Array = _r3c2_retained_remote_presenters.keys()
		ids.sort()
		var victim_id := String(ids[0])
		var victim = _r3c2_retained_remote_presenters[victim_id]
		if victim != null and is_instance_valid(victim):
			victim.queue_free()
		_r3c2_retained_remote_presenters.erase(victim_id)
	# Hide a derived render subtree instead of unloading Quaternius rig and
	# reloading its GLTF at the next network reconnect (the 3s baseline stall).
	presenter.visible = false
	presenter.set_process(false)
	presenter.process_mode = Node.PROCESS_MODE_DISABLED
	_r3c2_retained_remote_presenters[logical_id] = presenter


func set_char1_camera_third_person(enabled: bool) -> Dictionary:
	if earth_explorer == null or earth_explorer.get_camera() == null:
		return {"success": false, "error_code": "CHAR2_CAMERA_NOT_READY"}
	_char1_third_person = enabled
	if _char1_third_person_camera != null:
		_char1_third_person_camera.current = enabled
	earth_explorer.get_camera().current = not enabled
	if char1_avatar_presentation != null:
		char1_avatar_presentation.set_first_person_mode(not enabled)
	_char1_camera_toggles += 1
	return {"success": true, "view": "THIRD_PERSON" if enabled else "FIRST_PERSON"}


func _unhandled_input(event: InputEvent) -> void:
	# V/F7 are presentation-only camera toggles. All gameplay inputs continue
	# through the existing client prediction -> server movement path.
	if (
		runtime_role == "game-client"
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode in [KEY_V, KEY_F7]
	):
		set_char1_camera_third_person(not _char1_third_person)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	super._process(delta)
	_refresh_playtest_peer_hint()
	if (
		char1_avatar_presentation == null
		or not is_instance_valid(char1_avatar_presentation)
	):
		return
	if not _m3_attached:
		char1_avatar_presentation.apply_explorer_motion()
	char1_avatar_presentation.refresh_projection()


func _on_mvp_prediction_updated(
	predicted_state: Dictionary,
	presentation_state: Dictionary,
	report: Dictionary
) -> void:
	super._on_mvp_prediction_updated(predicted_state, presentation_state, report)
	if char1_avatar_presentation != null and not presentation_state.is_empty():
		char1_avatar_presentation.apply_player_record(presentation_state)


func register_runtime_commands(registry, owner_id: String) -> void:
	super.register_runtime_commands(registry, owner_id)
	_register_command(registry, owner_id, {
		"id": "character.camera.toggle",
		"description": "Переключить локальную камеру первого/третьего лица.",
		"usage": "character.camera.toggle",
		"category": "character",
	}, Callable(self, "_command_char1_camera_toggle"))
	_register_command(registry, owner_id, {
		"id": "character.camera.status",
		"description": "Показать read-only состояние камеры и локального тела.",
		"usage": "character.camera.status",
		"category": "character",
	}, Callable(self, "_command_char1_camera_status"))
	_register_command(registry, owner_id, {
		"id": "character.remote.status",
		"description": "Read-only remote Quaternius avatars from canonical NX5 snapshots.",
		"usage": "character.remote.status",
		"category": "character",
	}, Callable(self, "_command_char2_remote_avatar_status"))
	_register_command(registry, owner_id, {
		"id": "character.avatar.list",
		"description": "Показать доступные сменные CHAR1 avatar definitions.",
		"usage": "character.avatar.list",
		"category": "character",
	}, Callable(self, "_command_char1_avatar_list"))
	_register_command(registry, owner_id, {
		"id": "character.avatar.set",
		"description": "Сменить локальный production avatar через provider interface.",
		"usage": "character.avatar.set <character-id>",
		"category": "character",
	}, Callable(self, "_command_char1_avatar_set"))
	_register_command(registry, owner_id, {
		"id": "character.avatar.status",
		"description": "Показать состояние CHAR1 avatar host/provider.",
		"usage": "character.avatar.status",
		"category": "character",
	}, Callable(self, "_command_char1_avatar_status"))

func register_runtime_tests(registry, owner_id: String) -> void:
	super.register_runtime_tests(registry, owner_id)
	registry.register_test({
		"id": "character.char1.production_avatar",
		"description": "CHAR1 local avatar host configured through provider interfaces.",
		"category": "character",
	}, Callable(self, "_test_char1_avatar_ready"), owner_id)

func _command_char1_camera_toggle(_arguments: Array[String]) -> Dictionary:
	var result: Dictionary = set_char1_camera_third_person(not _char1_third_person)
	if bool(result.get("success", false)):
		result["output"] = "CHAR1 view: %s" % String(result.get("view", "UNKNOWN"))
	return result


func _command_char1_camera_status(_arguments: Array[String]) -> Dictionary:
	var data := {
		"view": "THIRD_PERSON" if _char1_third_person else "FIRST_PERSON",
		"local_body_visible": (
			bool(char1_avatar_presentation.create_report().get("local_body_visible", false))
			if char1_avatar_presentation != null else false
		),
		"remote_presenter_count": _m3_remote_presenters.size(),
	}
	return {"success": true, "output": JSON.stringify(data), "details": data}


func _command_char2_remote_avatar_status(_arguments: Array[String]) -> Dictionary:
	var players: Dictionary = {}
	for player_id_value in _m3_remote_presenters.keys():
		var player_id := String(player_id_value)
		var presenter = _m3_remote_presenters.get(player_id)
		if presenter == null or not is_instance_valid(presenter):
			continue
		var full: Dictionary = presenter.get_report()
		var avatar: Dictionary = full.get("char2_remote_avatar", {})
		players[player_id] = {
			"ready": bool(avatar.get("ready", false)),
			"character_id": String(avatar.get("character_id", "")),
			"provider_id": String(avatar.get("provider_id", "")),
			"asset_mode": String(avatar.get("asset_mode", "")),
			"motion_updates": int(avatar.get("motion_updates", 0)),
			"legacy_capsule_visible": bool(avatar.get("legacy_capsule_visible", true)),
			"interpolation_mode": String(full.get("interpolation_mode", "")),
			"input_authority": false,
		}
	var result := {
		"remote_count": players.size(),
		"remote_players": players,
		"protocol_changed": false,
	}
	return {"success": true, "output": JSON.stringify(result, "  "), "details": result}


func _on_m3_replica_updated(snapshot: Dictionary) -> void:
	super._on_m3_replica_updated(snapshot)
	if (
		char1_avatar_presentation == null
		or m3_multiplayer_client_runtime == null
	):
		return
	var local_id: String = (
		m3_multiplayer_client_runtime.get_local_player_id()
	)
	for player_value in snapshot.get("players", []):
		if not player_value is Dictionary:
			continue
		var record: Dictionary = player_value
		if (
			String(record.get("logical_player_id", "")) == local_id
			and bool(record.get("connected", false))
		):
			char1_avatar_presentation.apply_player_record(record)
			break

func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["char2_network_avatar"] = {
		"schema": "dws.char2.network_avatar_product.v1",
		"view_mode": "THIRD_PERSON" if _char1_third_person else "FIRST_PERSON",
		"camera_toggles": _char1_camera_toggles,
		"remote_avatar_count": _m3_remote_presenters.size(),
		"canonical_owner_created": false,
		"protocol_changed": false,
		"r3c2_visual_prewarm": {
			"enabled": _r3c2_visual_prewarm_enabled,
			"prewarm_ms": _r3c2_prewarm_ms,
			"reuses": _r3c2_visual_reuses,
			"retained_count": _r3c2_retained_remote_presenters.size(),
			"prewarmed_available": _r3c2_prewarmed_remote_presenter != null,
		},
	}
	report["char1_avatar"] = (
		char1_avatar_presentation.create_report()
		if (
			char1_avatar_presentation != null
			and is_instance_valid(char1_avatar_presentation)
		)
		else {
			"schema": "planet_simulator.earth_local_avatar_presenter.v1",
			"ready": false,
			"last_error_code": _char1_setup_error,
		}
	)
	return report

func prepare_for_unload() -> void:
	if _r3c2_prewarmed_remote_presenter != null and is_instance_valid(_r3c2_prewarmed_remote_presenter):
		_r3c2_prewarmed_remote_presenter.queue_free()
	_r3c2_prewarmed_remote_presenter = null
	for retained in _r3c2_retained_remote_presenters.values():
		if retained != null and is_instance_valid(retained):
			retained.queue_free()
	_r3c2_retained_remote_presenters.clear()
	if _char1_third_person_camera != null and is_instance_valid(_char1_third_person_camera):
		_char1_third_person_camera.queue_free()
	_char1_third_person_camera = null
	if (
		char1_avatar_presentation != null
		and is_instance_valid(char1_avatar_presentation)
	):
		char1_avatar_presentation.shutdown()
	super.prepare_for_unload()

func _command_char1_avatar_list(
	_arguments: Array[String]
) -> Dictionary:
	if char1_avatar_presentation == null:
		return {
			"success": false,
			"output": "CHAR1 avatar host не готов",
		}
	var ids: Array[String] = (
		char1_avatar_presentation.get_character_ids()
	)
	return {
		"success": true,
		"output": "\n".join(ids),
		"character_ids": ids,
	}

func _command_char1_avatar_set(
	arguments: Array[String]
) -> Dictionary:
	if char1_avatar_presentation == null:
		return {
			"success": false,
			"output": "CHAR1 avatar host не готов",
		}
	if arguments.is_empty():
		return {
			"success": false,
			"output": "Использование: character.avatar.set <character-id>",
		}
	var result: Dictionary = (
		char1_avatar_presentation.switch_avatar(arguments[0])
	)
	return {
		"success": bool(result.get("success", false)),
		"output": (
			"Avatar: %s"
			% char1_avatar_presentation.get_active_character_id()
			if bool(result.get("success", false))
			else "Avatar switch failed: %s"
			% String(result.get("error_code", "UNKNOWN"))
		),
		"details": result.get("details", {}),
	}

func _command_char1_avatar_status(
	_arguments: Array[String]
) -> Dictionary:
	var report: Dictionary = (
		char1_avatar_presentation.create_report()
		if (
			char1_avatar_presentation != null
			and is_instance_valid(char1_avatar_presentation)
		)
		else {
			"ready": false,
			"last_error_code": _char1_setup_error,
		}
	)
	return {
		"success": true,
		"output": JSON.stringify(report, "  "),
		"char1_avatar": report,
	}

func _test_char1_avatar_ready() -> Dictionary:
	var report: Dictionary = (
		char1_avatar_presentation.create_report()
		if (
			char1_avatar_presentation != null
			and is_instance_valid(char1_avatar_presentation)
		)
		else {}
	)
	var host: Dictionary = report.get("host", {})
	var presenter: Dictionary = host.get("presenter", {})
	var passed := (
		not report.is_empty()
		and not String(
			report.get("active_character_id", "")
		).is_empty()
		and bool(presenter.get("configured", false))
		and int(
			host.get("catalog", {}).get("character_count", 0)
		) >= 2
		and int(
			host.get("providers", {}).get("provider_count", 0)
		) >= 2
	)
	return {
		"success": passed,
		"passed": passed,
		"output": (
			"PASS: CHAR1 production avatar"
			if passed
			else "FAIL: CHAR1 production avatar"
		),
		"char1_avatar": report,
	}


func _refresh_playtest_peer_hint() -> void:
	if _playtest_peer_hint == null or Time.get_ticks_msec() < _playtest_hint_at:
		return
	_playtest_hint_at = Time.get_ticks_msec() + 250
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	var rows: Array[String] = []
	for player_id in _m3_remote_presenters:
		var presenter = _m3_remote_presenters[player_id]
		if not is_instance_valid(presenter): continue
		var offset: Vector3 = presenter.global_position - camera.global_position
		var local: Vector3 = camera.global_transform.basis.inverse() * offset
		var bearing := rad_to_deg(atan2(local.x, -local.z))
		var where := "впереди" if absf(bearing) < 25.0 else ("справа" if bearing > 0 else "слева")
		if absf(bearing) > 135.0: where = "сзади · поверните камеру"
		rows.append("%s · %.1f м · %s" % [str(player_id), offset.length(), where])
	_playtest_peer_hint.text = "DWS Playtest R1 · " + ("ожидание второго игрока" if rows.is_empty() else " | ".join(rows))

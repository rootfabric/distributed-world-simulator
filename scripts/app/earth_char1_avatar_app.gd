extends "res://scripts/app/earth_p3_resource_mining_app.gd"

const EarthLocalAvatarPresenterScript = preload(
	"res://scripts/characters/runtime/earth_local_avatar_presenter.gd"
)

var char1_avatar_presentation
var _char1_setup_error := ""

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

func _process(delta: float) -> void:
	super._process(delta)
	if (
		char1_avatar_presentation == null
		or not is_instance_valid(char1_avatar_presentation)
	):
		return
	if not _m3_attached:
		char1_avatar_presentation.apply_explorer_motion()
	char1_avatar_presentation.refresh_projection()

func register_runtime_commands(registry, owner_id: String) -> void:
	super.register_runtime_commands(registry, owner_id)
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

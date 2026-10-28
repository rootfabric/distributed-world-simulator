extends SceneTree

const Contract = preload(
	"res://scripts/characters/avatar/avatar_contract.gd"
)
const Bootstrap = preload(
	"res://scripts/characters/runtime/production_avatar_bootstrap.gd"
)
const Host = preload(
	"res://scripts/characters/avatar/player_avatar_host.gd"
)
const EarthPresenter = preload(
	"res://scripts/characters/runtime/earth_local_avatar_presenter.gd"
)

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	var runtime: Dictionary = Bootstrap.create_runtime()
	_check(
		bool(runtime.get("success", false)),
		"bootstrap failed: %s" % runtime
	)
	if not bool(runtime.get("success", false)):
		return _finish(null)
	var catalog = runtime.get("details", {}).get("catalog")
	var providers = runtime.get("details", {}).get("providers")
	_check(catalog != null, "catalog missing")
	_check(providers != null, "provider registry missing")
	_check(
		catalog.get_character_ids().size() >= 3,
		"expected multiple character definitions"
	)
	_check(
		providers.get_provider_ids().has(
			"avatar/procedural_humanoid"
		),
		"procedural provider missing"
	)
	_check(
		providers.get_provider_ids().has("avatar/quaternius"),
		"quaternius provider missing"
	)
	var offset_definition: Dictionary = catalog.get_definition_exact(
		"character/procedural/standard"
	)
	_check(
		absf(
			EarthPresenter.resolve_visual_vertical_offset(
				offset_definition,
				true
			) + 1.62
		) < 0.0001,
		"first-person avatar must place camera at configured eye height"
	)
	_check(
		absf(
			EarthPresenter.resolve_visual_vertical_offset(
				offset_definition,
				false
			) + 0.85
		) < 0.0001,
		"third-person presentation offset must remain provider data"
	)
	for character_id in catalog.get_character_ids():
		var definition: Dictionary = (
			catalog.get_definition_exact(character_id)
		)
		_check(
			bool(
				Contract.validate_definition(definition).get(
					"success",
					false
				)
			),
			"invalid definition: %s" % character_id
		)
		_check(
			not definition.has("presentation_scene_path"),
			"core definition coupled to scene path: %s"
			% character_id
		)
		_check(
			not definition.has("model_path"),
			"core definition coupled to model path: %s"
			% character_id
		)
		_check(
			not definition.has("animation_path"),
			"core definition coupled to animation path: %s"
			% character_id
		)
	var host := Host.new()
	get_root().add_child(host)
	var setup_result: Dictionary = host.setup(
		catalog,
		providers,
		"",
		true
	)
	_check(
		bool(setup_result.get("success", false)),
		"host setup failed: %s" % setup_result
	)
	host.set_first_person_mode(true)
	var motion := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {"x": 2.5, "y": 0.0, "z": 0.0},
		"grounded": true,
		"facing_yaw": 0.35,
		"state_revision": 7,
	}
	_check(
		bool(host.apply_motion_state(motion).get("success", false)),
		"motion rejected"
	)
	var action := {
		"schema": Contract.ACTION_SCHEMA,
		"action_id": "action/use",
		"action_sequence": 3,
		"active": true,
	}
	_check(
		bool(host.apply_action_state(action).get("success", false)),
		"action rejected"
	)
	var initial_report: Dictionary = host.create_report()
	_check(
		initial_report.get("active_character_id", "")
		== "character/quaternius/regular",
		"fallback character not active"
	)
	_check(
		initial_report.get("presenter", {}).get("provider_id", "")
		== "avatar/quaternius",
		"fallback provider mismatch"
	)
	var first_swap: Dictionary = host.switch_avatar(
		"character/procedural/standard"
	)
	_check(
		bool(first_swap.get("success", false)),
		"swap to procedural failed"
	)
	_check(
		host.get_active_character_id()
		== "character/procedural/standard",
		"procedural character not active"
	)
	_check(
		host.get_socket(&"hand_right") != null,
		"procedural hand socket unavailable"
	)
	var second_swap: Dictionary = host.switch_avatar(
		"character/procedural/high_visibility"
	)
	_check(
		bool(second_swap.get("success", false)),
		"second runtime swap failed"
	)
	var final_report: Dictionary = host.create_report()
	_check(
		final_report.get("active_character_id", "")
		== "character/procedural/high_visibility",
		"second character not active"
	)
	_check(
		int(final_report.get("swap_count", 0)) >= 3,
		"swap counter did not advance"
	)
	_check(
		bool(final_report.get("first_person_mode", false)),
		"first-person mode lost across swap"
	)
	_check(
		bool(
			final_report.get("presenter", {}).get(
				"has_motion_state",
				false
			)
		),
		"motion state not replayed on swap"
	)
	_check(
		bool(
			final_report.get("presenter", {}).get(
				"has_action_state",
				false
			)
		),
		"action state not replayed on swap"
	)
	_check(
		not bool(
			host.switch_avatar("character/unknown").get(
				"success",
				false
			)
		),
		"unknown character accepted"
	)
	_finish(host)

func _finish(host) -> void:
	if host != null:
		host.shutdown()
		host.queue_free()
	if failures.is_empty():
		print(
			"CHAR1 PRODUCTION AVATAR: PASS (%d assertions, 0 failures)"
			% assertions
		)
		quit(0)
		return
	for failure in failures:
		push_error("[CHAR1] %s" % failure)
	print(
		"CHAR1 PRODUCTION AVATAR: FAIL (%d assertions, %d failures)"
		% [assertions, failures.size()]
	)
	quit(1)

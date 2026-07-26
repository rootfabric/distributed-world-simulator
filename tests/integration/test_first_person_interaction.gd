extends SceneTree

const WorldInteractorScript = preload(
	"res://scripts/interaction/world_interactor.gd"
)
const SurveyBeaconInteractableScript = preload(
	"res://scripts/interaction/survey_beacon_interactable.gd"
)
const MockInteractionRepositoryScript = preload(
	"res://tests/support/mock_interaction_repository.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var interactor = WorldInteractorScript.new()
	_assert(interactor.has_method("setup"), "Interactor setup contract is missing.")
	_assert(
		interactor.has_method("perform_interaction"),
		"Interactor action contract is missing."
	)
	_assert(
		interactor.has_signal("focus_changed"),
		"Interactor focus_changed signal is missing."
	)
	_assert(not interactor.is_enabled(), "Interactor must start disabled.")
	_assert(
		is_equal_approx(interactor.interaction_distance_m, 6.0),
		"Interaction distance must be 6 m."
	)
	get_root().add_child(interactor)
	interactor.setup(null)

	var repository = MockInteractionRepositoryScript.new()
	get_root().add_child(repository)
	var beacon = SurveyBeaconInteractableScript.new()
	get_root().add_child(beacon)
	beacon.setup_interactable(repository, "entity/survey_beacon/test", true)

	_assert(
		beacon.is_in_group("world_interactable"),
		"Survey Beacon is not registered as world_interactable."
	)
	_assert(
		beacon.has_method("get_interaction_descriptor"),
		"Interaction descriptor contract is missing."
	)
	_assert(beacon.has_method("interact"), "Interact method is missing.")
	_assert(
		beacon.has_method("set_interaction_focus"),
		"Focus visualization contract is missing."
	)

	var before: Dictionary = beacon.get_interaction_descriptor(null)
	_assert(
		String(before.get("entity_id", "")) == "entity/survey_beacon/test",
		"Descriptor entity_id is incorrect."
	)
	_assert(
		String(before.get("prompt", "")).contains("выключить"),
		"Active beacon should offer signal deactivation."
	)

	interactor.set_enabled(true)
	interactor.current_target = beacon
	interactor.current_hit_position = Vector3(0.0, 1.0, 0.0)
	interactor.current_distance_m = 2.5
	var result: Dictionary = interactor.perform_interaction()
	_assert(bool(result.get("success", false)), "Beacon interaction failed.")
	_assert(
		repository.last_entity_id == "entity/survey_beacon/test",
		"Repository received an incorrect entity_id."
	)
	var after: Dictionary = beacon.get_interaction_descriptor(null)
	_assert(
		String(after.get("prompt", "")).contains("включить"),
		"Inactive beacon should offer signal activation."
	)
	var snapshot: Dictionary = interactor.get_current_snapshot()
	_assert(
		is_equal_approx(float(snapshot.get("distance_m", 0.0)), 2.5),
		"Interaction snapshot distance is incorrect."
	)
	_assert(
		snapshot.get("hit_position", []) is Array,
		"Interaction snapshot position must be JSON-safe."
	)
	beacon.set_interaction_focus(true)
	beacon.set_interaction_focus(false)

	var marker_config: Dictionary = _read_json(
		"res://config/navigation_markers.json"
	)
	_assert(
		int(marker_config.get("font_size", 0)) == 11,
		"Landmark font size must be reduced to 11."
	)
	_assert(
		int(marker_config.get("outline_size", -1)) == 2,
		"Landmark outline size must be reduced to 2."
	)

	if failures.is_empty():
		print("First-person interaction integration tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"First-person interaction integration tests: FAIL (%d)"
		% failures.size()
	)
	quit(1)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

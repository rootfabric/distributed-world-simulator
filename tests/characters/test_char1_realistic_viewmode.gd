extends SceneTree

# CHAR1 realistic avatar view-mode smoke: boots the real preview viewer,
# requires the real Quaternius asset path (FALLBACK is a FAIL here),
# and verifies third-person / first-person toggling plus semantic
# idle / walk / run locomotion through the production avatar host.
const ViewerScene = preload(
	"res://scenes/labs/character/char1_realistic_avatar_viewer.tscn"
)

const ACCEPTED_ASSET_MODES := [
	"QUATERNIUS_RETARGET",
	"QUATERNIUS_EMBEDDED",
]

var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewer = ViewerScene.instantiate()
	get_root().add_child(viewer)
	for i in range(10):
		await process_frame
	_check(
		viewer.get_asset_mode() in ACCEPTED_ASSET_MODES,
		"real Quaternius asset mode active (got %s)" % viewer.get_asset_mode()
	)
	var initial_report: Dictionary = viewer.create_report()
	_check(
		String(initial_report.get("character_id", "")) == "character/quaternius/regular",
		"viewer starts on the real Quaternius character"
	)
	_check(
		String(initial_report.get("provider_id", "")) == "avatar/quaternius",
		"viewer starts on the avatar/quaternius provider"
	)
	_check(
		String(initial_report.get("view_mode", "")) == "THIRD_PERSON",
		"third-person is the start view mode"
	)
	_capture("viewmode-third-person")
	_check(
		_image_has_visible_subject(),
		"character is visibly rendered in third-person"
	)

	viewer.toggle_view_mode()
	for i in range(4):
		await process_frame
	var fp_report: Dictionary = viewer.create_report()
	_check(
		String(fp_report.get("view_mode", "")) == "FIRST_PERSON",
		"toggle switches to first-person"
	)
	_check(bool(fp_report.get("first_person_mode", false)), "host reports first-person mode")
	var engine_report: Dictionary = _engine_report(viewer)
	_check(
		bool(engine_report.get("head_suppressed", false)),
		"local head mask is active in first-person (CH5 bone-scale approach)"
	)
	_check(
		bool(engine_report.get("target_skeleton", false)),
		"full body skeleton stays present in first-person"
	)
	_capture("viewmode-first-person")

	viewer.toggle_view_mode()
	for i in range(4):
		await process_frame
	var back_report: Dictionary = viewer.create_report()
	_check(
		String(back_report.get("view_mode", "")) == "THIRD_PERSON",
		"toggle returns to third-person"
	)
	_check(
		not bool(_engine_report(viewer).get("head_suppressed", true)),
		"local head mask is released back in third-person"
	)

	for semantic in ["walk", "run", "idle"]:
		viewer.set_semantic(semantic)
		for i in range(6):
			await process_frame
		var engine_semantic := String(_engine_report(viewer).get("current_semantic", ""))
		_check(
			engine_semantic == semantic,
			"semantic animation %s plays (engine reported %s)" % [semantic, engine_semantic]
		)

	var swap: Dictionary = viewer._host.switch_avatar("character/procedural/standard")
	_check(bool(swap.get("success", false)), "hot-swap to procedural fallback path works")
	viewer._host.switch_avatar("character/quaternius/regular")
	_finish(viewer)


func _engine_report(viewer) -> Dictionary:
	var report: Dictionary = viewer.create_report()
	var host_report: Dictionary = viewer._host.create_report()
	return host_report.get("presenter", {}).get("engine", report)


func _capture(label: String) -> void:
	var output_dir := ProjectSettings.globalize_path("res://artifacts/char1-viewmode")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var screenshot: Image = get_root().get_texture().get_image()
	screenshot.save_png(output_dir.path_join(label + ".png"))


func _image_has_visible_subject() -> bool:
	var image := get_root().get_texture().get_image()
	if image == null or image.is_empty():
		return false
	var background := image.get_pixel(4, 4)
	var visible_pixels := 0
	for y in range(image.get_height() / 4, image.get_height() * 3 / 4, 6):
		for x in range(image.get_width() / 3, image.get_width() * 2 / 3, 6):
			var color: Color = image.get_pixel(x, y)
			var distance := (
				absf(color.r - background.r)
				+ absf(color.g - background.g)
				+ absf(color.b - background.b)
			)
			if distance > 0.24:
				visible_pixels += 1
	return visible_pixels >= 12


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish(viewer) -> void:
	if viewer != null:
		viewer.queue_free()
	if failures.is_empty():
		print("CHAR1 VIEWMODE: PASS (%d assertions, 0 failures)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error("[CHAR1 viewmode] " + failure)
		print("CHAR1 VIEWMODE: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
		quit(1)

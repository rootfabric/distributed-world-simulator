extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")
const RendererProfile = preload("res://scripts/research/ecology/plant_renderer_profile_v1.gd")
var assertions := 0

func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph5_render_materialization_lab.tscn") as PackedScene
	_assert(packed != null)
	var instance := packed.instantiate()
	_assert(instance != null)
	root.add_child(instance)
	await process_frame
	_assert(instance.results.size() == Probes.ENVIRONMENT_ORDER.size())
	_assert(instance.status_label != null)
	_assert(instance.status_label.text.contains("Derived presentation only"))
	_assert(instance.status_label.text.contains("DEBUG_SKELETON"))
	instance.profile_index = RendererProfile.PROFILE_ORDER.find("FULL_PROCEDURAL")
	instance._refresh()
	_assert(instance.status_label.text.contains("FULL_PROCEDURAL"))
	instance.profile_index = RendererProfile.PROFILE_ORDER.find("IMPOSTOR_BILLBOARD")
	instance._refresh()
	_assert(instance.status_label.text.contains("IMPOSTOR_BILLBOARD"))
	for name in Probes.ENVIRONMENT_ORDER:
		_assert(not instance.results[name]["render_description"].is_empty())
	instance.queue_free()
	await process_frame
	print("ECO.PH5 Visual Lab Smoke: PASS (%d assertions)" % assertions)
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1

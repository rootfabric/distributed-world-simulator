extends SceneTree
const Registry = preload("res://scripts/presentation/avatar/avatar_registry.gd")
const RemotePresenter = preload("res://scripts/runtime/networked_gameplay/m3/remote_player_presenter.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry = Registry.new()
	var fallback: Node3D = registry.create_visual("unknown")
	_check(fallback.has_method("apply_avatar_state"), "fallback implements avatar port")
	root.add_child(fallback)
	fallback.call("apply_avatar_state", {"velocity": Vector3(2, 0, 0), "flashlight_enabled": true}, 0.016)
	_check(String(fallback.call("get_avatar_report").get("motion", "")) == "walk", "fallback uses motion")
	fallback.queue_free()

	_check(registry.register_scene("training", "res://scenes/avatars/training_avatar.tscn"), "register scene")
	var custom: Node3D = registry.create_visual("training")
	_check(custom.has_method("get_avatar_report"), "custom implements port")
	root.add_child(custom)
	custom.call("apply_avatar_state", {"velocity": Vector3.ZERO}, 0.016)
	_check(String(custom.call("get_avatar_report").get("visual_type", "")) == "training", "custom selected")
	_check(bool(custom.call("get_avatar_report").get("state_received", false)), "custom receives state")
	custom.queue_free()
	_check(not registry.register_scene("", "res://invalid.tscn"), "empty appearance rejected")
	_check(not registry.register_scene("unsafe", "user://unsafe.tscn"), "non-resource scene rejected")

	var presenter = RemotePresenter.new()
	root.add_child(presenter)
	_check(presenter.register_appearance_scene("training", "res://scenes/avatars/training_avatar.tscn"), "presenter accepts provider")
	var swap: Dictionary = presenter.set_appearance("training")
	_check(bool(swap.get("success", false)), "hot swap succeeds")
	_check(String(presenter.get_report().get("avatar", {}).get("visual_type", "")) == "training", "hot swap is visible")
	var reset: Dictionary = presenter.set_appearance("missing")
	_check(bool(reset.get("success", false)), "unknown appearance falls back")
	_check(String(presenter.get_report().get("avatar", {}).get("visual_type", "")) == "procedural_humanoid", "fallback visual restored")
	presenter.queue_free()
	if failures.is_empty():
		print("CHAR1 AVATAR REGISTRY PASS (%d/0)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CHAR1 AVATAR REGISTRY FAIL (%d/%d)" % [checks, failures.size()])
		quit(1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

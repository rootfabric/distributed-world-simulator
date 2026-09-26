extends SceneTree

const Scene = preload("res://scenes/ecology/habitat/persistent_habitat.tscn")
const Session = preload("res://scripts/ecology/habitat/persistent_habitat_session_v1.gd")
const Preset = preload("res://scripts/ecology/habitat/habitat_preset_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("A11_SCENE_FAIL " + message)

func _run() -> void:
	var host: Node = Scene.instantiate()
	host.auto_boot = false
	host.autosave_enabled = false
	host.save_directory = "res://artifacts/runtime/eco-a11-fixtures/scene-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	root.add_child(host)
	await process_frame
	check(host.has_node("HabitatUI/HabitatPanel"), "visible habitat has explicitly named controls")
	check(host.session.controller == null, "unbooted scene does not invent a controller")
	check(not host.show_advanced_tools(true) and host.get_node("HabitatUI/HabitatPanel").visible, "unbooted advanced toggle cannot hide the only panel")
	var manifest := Preset.create(20260912, 64)
	var started: Dictionary = host.new_habitat(manifest)
	check(started.success, "visible scene starts real canonical preset")
	check(host.workbench != null and host.session.controller == host.workbench.controller, "host and accepted Workbench share one controller")
	check(host.workbench.get_script().resource_path == "res://scripts/ecology/workbench/ecology_workbench.gd", "reuses shipped A10.5 Workbench script")
	check(host.has_node("HabitatPresentation"), "camera/light/environment presentation composed")
	check(host.workbench.organism_views.size() == 3, "three canonical organism views")
	check(host.workbench.get_node("OrganismMarkers").get_child_count() == 3, "derived organism nodes instantiated")
	check(not host.workbench.running, "new persistent scene starts paused")
	var genesis_hash: String = host.session.controller.get_snapshot().canonical_state_hash
	check(host.show_advanced_tools(true), "advanced tools explicitly selectable")
	check(host.workbench.get_node("WorkbenchUI").visible and not host.get_node("HabitatUI/HabitatPanel").visible, "exactly one tool panel visible")
	var return_key := InputEventKey.new()
	return_key.keycode = KEY_F2
	return_key.pressed = true
	host._unhandled_key_input(return_key)
	check(host.get_node("HabitatUI/HabitatPanel").visible and not host.workbench.get_node("WorkbenchUI").visible, "F2 restores the named habitat panel")
	check(not host.find_child("AdvancedToolsToggle", true, false).button_pressed, "F2 also resets advanced toggle state")
	check(host.session.controller.get_snapshot().canonical_state_hash == genesis_hash, "panel switching is noncausal")
	var twin := Session.new()
	check(twin.start(manifest).success, "direct comparison controller created")
	check(host.workbench.command_step_n(4), "visible time command runs 4 ticks")
	check(twin.controller.run(4).success, "direct canonical runtime runs same ticks")
	var state_hash: String = host.session.controller.get_snapshot().canonical_state_hash
	check(state_hash == twin.controller.get_snapshot().canonical_state_hash, "scene has no alternate lifecycle semantics")
	host.workbench.set_morphology_enabled(false)
	await process_frame
	check(host.session.controller.get_snapshot().canonical_state_hash == state_hash, "turning generic meshes off is noncausal")
	host.workbench.set_morphology_enabled(true)
	host.workbench.set_morphology_lod("LOW")
	await process_frame
	check(host.session.controller.get_snapshot().canonical_state_hash == state_hash, "generic LOD switch is noncausal")
	host.workbench.select_entity("founder/0000")
	check(host.session.controller.get_snapshot().canonical_state_hash == state_hash, "inspection selection is noncausal")
	var saved: Dictionary = host.save_checkpoint()
	check(saved.success and saved.tick == 4, "visible host writes durable checkpoint")
	if saved.success:
		check(host.workbench.command_step_n(2), "visible branch advances after save")
		var resumed: Dictionary = host.restore_checkpoint(saved.path, saved.sha256)
		check(resumed.success and host.session.controller.tick() == 4, "visible restore returns to exact tick")
		check(host.session.controller == host.workbench.controller, "restore rebinds Workbench to admitted controller")
		check(host.session.controller.get_snapshot().canonical_state_hash == state_hash, "restored visible scene exact hash")
		check(not host.workbench.running, "restore does not silently resume wall-clock ticks")
		var original: Object = host.session.controller
		var bad: Dictionary = host.boot(PackedStringArray(["--eco-habitat-save=" + String(saved.path)]))
		check(not bad.success and host.session.controller == original, "partial startup restore request cannot reset live state")
		bad = host.boot(PackedStringArray(["--eco-habitat-save=" + String(saved.path), "--eco-habitat-sha=" + "0".repeat(64)]))
		check(not bad.success and host.session.controller == original, "corrupt startup restore fails closed without new preset")
		var booted: Dictionary = host.boot(PackedStringArray(["--eco-habitat-save=" + String(saved.path), "--eco-habitat-sha=" + String(saved.sha256)]))
		check(booted.success and host.session.controller.tick() == 4, "real startup arguments restore same persistent session")
		host.autosave_enabled = true
		check(host.workbench.command_step_n(12), "advance to declared autosave interval")
		check(host.last_receipt.has("tick") and int(host.last_receipt.tick) == 16, "autosave after completed tick publishes receipt")
		check(host.session.controller == host.workbench.controller, "autosave does not replace live canonical controller")
		host.autosave_enabled = false
	var folder: String = host.save_directory
	host.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(ProjectSettings.globalize_path(folder)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("EVO_ARCH2_A11_SCENE checks=%d failed=%d" % [checks, failures.size()])
	print("EVO_ARCH2_A11_SCENE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

extends Node3D

## WORLD PACKS gallery (WP0.10) — registry-driven comparison gallery.
##
## Two modes:
##   pads (default): one equally-sized pad per registered pack under a neutral
##     shared environment, so reviewers compare pack identity independently
##     from gameplay and environment settings;
##   focus: `-- --pack=<WP-ID>` renders a single pack with its full
##     environment (sky/lighting/fog) on a single pad.
##
## Asset-free by design; packs are discovered through pack_registry.gd.

const RegistryScript = preload("res://scripts/world_packs/pack_registry.gd")

const PAD_SPACING_X: float = 20.0
const NEUTRAL_SKY: Color = Color(0.05, 0.055, 0.065)
const NEUTRAL_AMBIENT: Color = Color(0.35, 0.37, 0.4)

var _focus_pack: String = ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			_focus_pack = arg.substr("--pack=".length())

	var pack_ids: PackedStringArray = RegistryScript.ids()
	if not _focus_pack.is_empty():
		if not RegistryScript.has(_focus_pack):
			push_error("WORLD PACKS gallery: unknown pack id %s" % _focus_pack)
			print("WORLD_PACKS_GALLERY_FAILED")
			return
		_build_focus(_focus_pack)
		print("WORLD_PACKS_GALLERY_PACKS=1")
		_build_camera(true)
	else:
		_build_neutral_environment()
		var offset: int = 0
		for pack_id in pack_ids:
			_build_pad(pack_ids.size(), offset, pack_id)
			offset += 1
		print("WORLD_PACKS_GALLERY_PACKS=%d" % pack_ids.size())
		_build_camera(false)
	print("WORLD_PACKS_GALLERY_READY")


## MCP driver entry (WP0.10 graphical capture): rebuild the gallery live in
## focus mode for one pack and report via stdout sentinel.
func focus_pack(pack_id: String) -> bool:
	if not RegistryScript.has(pack_id):
		return false
	for child in get_children():
		remove_child(child)
		child.free()
	_focus_pack = pack_id
	_build_focus(pack_id)
	_build_camera(true)
	print("WORLD_PACKS_GALLERY_FOCUS=%s" % pack_id)
	return true


func _build_focus(pack_id: String) -> void:
	var profile: RefCounted = RegistryScript.make_profile(pack_id)
	profile.apply_environment(self)
	var pad := Node3D.new()
	pad.name = String(pack_id)
	add_child(pad)
	profile.build_pad(pad)
	var manifest: Dictionary = profile.manifest()
	_add_label(Vector3(0.0, 8.5, -5.0), "%s  %s" % [
		String(manifest.get("display_name", pack_id)), String(manifest.get("version", "")),
	])


func _build_neutral_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = NEUTRAL_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = NEUTRAL_AMBIENT
	environment.ambient_light_energy = 0.6
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -22.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)


func _build_pad(count: int, index: int, pack_id: String) -> void:
	var profile: RefCounted = RegistryScript.make_profile(pack_id)
	var pad := Node3D.new()
	pad.name = String(pack_id)
	pad.position.x = (float(index) - float(count - 1) / 2.0) * PAD_SPACING_X
	add_child(pad)
	profile.build_pad(pad)
	var manifest: Dictionary = profile.manifest()
	_add_label(pad.position + Vector3(0.0, 8.5, -5.0), "%s  %s" % [
		String(manifest.get("display_name", pack_id)), String(manifest.get("version", "")),
	])


func _add_label(position: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 32
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = position
	add_child(label)


func _build_camera(focus: bool = false) -> void:
	var camera := Camera3D.new()
	if focus:
		camera.position = Vector3(0.0, 13.0, 20.0)
		camera.look_at_from_position(camera.position, Vector3(0.0, 1.2, 0.0))
	else:
		camera.position = Vector3(0.0, 24.0, 34.0)
		camera.look_at_from_position(camera.position, Vector3(0.0, 0.5, 0.0))
	camera.current = true
	add_child(camera)

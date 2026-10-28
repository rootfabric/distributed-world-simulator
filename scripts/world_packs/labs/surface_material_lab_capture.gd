extends SceneTree

## WP-VIS1 graphical evidence capture.
##
## Loads the lab scene with the default (full) fidelity, renders a few frames
## on the real renderer, captures the viewport to PNG, then switches to
## preview fidelity and captures again. Exit 0 on success.
##
## Run (graphical session, NOT --headless):
##   godot --path . --script res://scripts/world_packs/labs/surface_material_lab_capture.gd -- --out-dir=<abs dir>

const LabScene := preload("res://scenes/labs/world_packs/surface_material_lab.tscn")

const FRAME_WAIT: int = 12

var _lab: Node
var _out_dir: String = "res://docs/world_packs/evidence/"
var _frames: int = 0
var _phase: int = 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			_out_dir = arg.substr("--out-dir=".length())
	_lab = LabScene.instantiate()
	root.add_child(_lab)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < FRAME_WAIT:
		return false
	if _phase == 0:
		if not _capture("WP-VIS1-lab-full-fidelity.png"):
			quit(1)
			return true
		(_lab as Node).call("apply_fidelity", "preview")
		_phase = 1
		_frames = 0
		return false
	if not _capture("WP-VIS1-lab-preview-fidelity.png"):
		quit(1)
		return true
	print("SURFACE_MATERIAL_LAB_CAPTURE=PASS")
	quit(0)
	return true


func _capture(file_name: String) -> bool:
	var image := root.get_viewport().get_texture().get_image()
	var target := _out_dir.path_join(file_name)
	var err := image.save_png(target)
	if err != OK:
		print("SURFACE_MATERIAL_LAB_CAPTURE_PROBLEM=save failed (%d) to %s" % [err, target])
		return false
	print("SURFACE_MATERIAL_LAB_CAPTURE_FILE=%s" % target)
	return true

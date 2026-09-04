extends Node3D

const Extension = preload("res://scripts/research/fabric_bake0/complex2e_modular_machine_extension_v1.gd")

var _result: Dictionary = {}
var _stage := 0
var _nodes: Array[MeshInstance3D] = []
var _status: Label

func _ready() -> void:
	_build_world()
	_result = Extension.run_experiment()
	if not bool(_result.get("success", false)):
		_status.text = "COMPLEX2-E FAILED: %s" % String(_result.get("error_code", "unknown"))
		return
	_apply_stage(0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and bool(_result.get("success", false)):
		_stage = (_stage + 1) % 4
		_apply_stage(_stage)

func _build_world() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.0, 10.0)
	camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	add_child(light)
	for index in range(4):
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.1, 0.45, 0.65)
		node.mesh = mesh
		node.position = Vector3(-2.7 + float(index) * 1.8, 0.0, 0.0)
		add_child(node)
		_nodes.append(node)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_status = Label.new()
	_status.position = Vector2(24, 20)
	_status.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_status)

func _apply_stage(stage: int) -> void:
	var sample: Dictionary
	var label := ""
	match stage:
		0:
			sample = _result["settled"]["samples"][0]
			label = "FIRST IMPACT PEAK"
		1:
			sample = _result["settled"]["samples"][1]
			label = "SETTLED"
		2:
			sample = _result["settled"]["samples"][1]
			label = "REBAKED DYNAMIC_ROM"
		_:
			sample = _result["reimpact"]["samples"][0]
			label = "RE-IMPACT PEAK"
	var q: Array = sample["native_q"]
	_nodes[0].rotation.z = float(q[0])
	_nodes[1].rotation.z = float(q[1])
	_nodes[2].rotation.x = float(q[2])
	_nodes[3].position.x = 2.7 + float(q[3]) * 8.0
	_status.text = "COMPLEX2-E  %s\nenergy=%.6f J  rebake generation=%d\nshoulder=%.3f elbow=%.3f shaft=%.3f carriage=%.3f\nSPACE: impact → settle → rebake → re-impact" % [
		label, float(sample["energy_j"]), int(_result["rebake_generation"]),
		float(q[0]), float(q[1]), float(q[2]), float(q[3]),
	]

extends Node3D

const Extension = preload("res://scripts/research/fabric_bake0/complex2c_modular_machine_extension_v1.gd")

var _result: Dictionary = {}
var _sample_index := 0
var _modules: Array[MeshInstance3D] = []
var _status: Label

func _ready() -> void:
	_build_world()
	_result = Extension.run_experiment()
	if not bool(_result.get("success", false)):
		_status.text = "COMPLEX2-C FAILED: %s" % String(_result.get("error_code", "unknown"))
		return
	_apply_sample(0)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and bool(_result.get("success", false)):
		var samples: Array = _result["coupled"]["samples"]
		_sample_index = (_sample_index + 1) % samples.size()
		_apply_sample(_sample_index)

func _build_world() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.2, 10.5)
	camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.shadow_enabled = true
	add_child(light)
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(10.0, 0.15, 4.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -1.0, 0.0)
	add_child(floor)
	for index in range(4):
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.15, 0.45, 0.65)
		node.mesh = mesh
		node.position = Vector3(-2.7 + float(index) * 1.8, 0.0, 0.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = [Color(0.2, 0.55, 0.95), Color(0.25, 0.8, 0.45), Color(0.95, 0.55, 0.18), Color(0.7, 0.35, 0.9)][index]
		node.material_override = material
		add_child(node)
		_modules.append(node)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_status = Label.new()
	_status.position = Vector2(24, 20)
	_status.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_status)

func _apply_sample(index: int) -> void:
	var sample: Dictionary = _result["coupled"]["samples"][index]
	var q: Array = sample["native_q"]
	_modules[0].rotation.z = float(q[0])
	_modules[1].rotation.z = float(q[1])
	_modules[2].rotation.x = float(q[2])
	_modules[3].position.x = 2.7 + float(q[3]) * 8.0
	var transfer: Dictionary = _result["coupled"]["transfer_probe"]
	_status.text = "COMPLEX2-C  step=%d  evaluator=%s\nshoulder=%.3f rad  elbow=%.3f rad  shaft=%.3f rad  carriage=%.3f m\nenergy=%.5f J  transfer shaft=%.5f m carriage=%.5f m\nSPACE: next evidence sample" % [
		int(sample["step"]), String(sample["evaluator"]), float(q[0]), float(q[1]), float(q[2]), float(q[3]),
		float(sample["energy_j"]), float(transfer["coupled_shaft_peak_m"]), float(transfer["coupled_carriage_peak_m"]),
	]

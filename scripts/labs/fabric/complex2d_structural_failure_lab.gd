extends Node3D

const Extension = preload("res://scripts/research/fabric_bake0/complex2d_modular_machine_extension_v1.gd")

var _result: Dictionary = {}
var _failed := false
var _nodes: Array[MeshInstance3D] = []
var _brace: MeshInstance3D
var _status: Label

func _ready() -> void:
	_build_world()
	_result = Extension.run_experiment()
	if not bool(_result.get("success", false)):
		_status.text = "COMPLEX2-D FAILED: %s" % String(_result.get("error_code", "unknown"))
		return
	_apply_state(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and bool(_result.get("success", false)):
		_failed = not _failed
		_apply_state(_failed)

func _build_world() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 4.0, 10.0)
	camera.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	add_child(light)
	for index in range(5):
		var node := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.85, 0.5, 0.7)
		node.mesh = mesh
		node.position = Vector3(-3.2 + float(index) * 1.6, 0.0, 0.0)
		add_child(node)
		_nodes.append(node)
	_brace = MeshInstance3D.new()
	var brace_mesh := BoxMesh.new()
	brace_mesh.size = Vector3(6.4, 0.10, 0.12)
	_brace.mesh = brace_mesh
	_brace.position = Vector3(0.0, 0.65, 0.0)
	add_child(_brace)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_status = Label.new()
	_status.position = Vector2(24, 20)
	_status.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_status)

func _apply_state(failed: bool) -> void:
	var structural: Dictionary = _result["structural"]
	var state: Dictionary = structural["after"] if failed else structural["before"]
	for index in range(_nodes.size()):
		var node_id := "module/complex2-%02d" % (12 + index)
		_nodes[index].position.y = float(state["displacement_m"][node_id]) * 4.0
	_brace.visible = not failed
	_status.text = "COMPLEX2-D  %s\nbrace force=%.2f N  chain max=%.2f N  tip=%.4f m\ncomponents=%d  functional unchanged=%s\nSPACE: before/after failure" % [
		"AFTER FAILURE" if failed else "BASELINE",
		float(state["brace_force_n"]), float(state["max_chain_force_n"]), float(state["tip_deflection_m"]),
		int(structural["component_count_after"]), str(structural["functional_before_hash"] == structural["functional_after_hash"]),
	]

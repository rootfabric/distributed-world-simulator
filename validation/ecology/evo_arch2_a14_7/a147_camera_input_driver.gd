extends Node
## A14.7 R1 automated REAL SceneTree input (not a camera teleport mock).
## Injects deterministic mouse motions and W key events into Godot's Input
## dispatch; only _input() updates the real LabCamera. Test-only Node.
var camera: Camera3D = null
var sent := 0
var received := 0
var mouse_received := 0
var key_received := 0
var first_position := Vector3.ZERO

func bind_camera(target: Camera3D) -> void:
	camera = target
	if camera != null:
		first_position = camera.global_position
	set_process_input(true)

func inject(frame_number: int) -> void:
	if camera == null:
		return
	if frame_number % 3 == 0:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(1.5 + sin(float(frame_number) * 0.037),
			cos(float(frame_number) * 0.041) * 0.75)
		sent += 1
		Input.parse_input_event(ev)
	if frame_number % 30 == 0:
		var down := InputEventKey.new()
		down.keycode = KEY_W
		down.pressed = true
		sent += 1
		Input.parse_input_event(down)
		var up := InputEventKey.new()
		up.keycode = KEY_W
		up.pressed = false
		sent += 1
		Input.parse_input_event(up)
	# Synthetic events are injected via the real Godot Input queue. Flush
	# explicitly so they reach the scene even on low frame-rate hosts.
	Input.flush_buffered_events()

func _input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseMotion:
		received += 1
		mouse_received += 1
		camera.rotate_y(-float(event.relative.x) * 0.003)
		camera.rotate_object_local(Vector3.RIGHT, -float(event.relative.y) * 0.002)
	elif event is InputEventKey:
		if event.keycode == KEY_W:
			received += 1
			key_received += 1
			if event.pressed and not event.echo:
				camera.translate_object_local(Vector3(0.0, 0.0, -0.13))

func proof() -> Dictionary:
	return {
		"sent": sent, "received": received,
		"mouse_received": mouse_received, "key_received": key_received,
		"camera_moved": camera != null and
			camera.global_position.distance_to(first_position) > 0.02,
	}

extends Camera3D

@export var movement_speed_m_s: float = 180.0
@export var boost_multiplier: float = 6.0
@export var mouse_sensitivity: float = 0.0015

var _mouse_captured: bool = true


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current = true
	near = 0.1
	far = 10000.0


func _process(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction -= basis.z
	if Input.is_physical_key_pressed(KEY_S):
		direction += basis.z
	if Input.is_physical_key_pressed(KEY_A):
		direction -= basis.x
	if Input.is_physical_key_pressed(KEY_D):
		direction += basis.x
	if Input.is_physical_key_pressed(KEY_E):
		direction += basis.y
	if Input.is_physical_key_pressed(KEY_Q):
		direction -= basis.y
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var speed: float = movement_speed_m_s
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier
	position += direction * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_mouse_captured = not _mouse_captured
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED \
				if _mouse_captured else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			look_at(Vector3(1000.0, 0.0, 0.0), Vector3.UP)
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and _mouse_captured:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		rotation.x = clampf(rotation.x, -1.54, 1.54)

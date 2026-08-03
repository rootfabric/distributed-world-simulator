extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed = load("res://scenes/labs/character/character_presentation_lab.tscn")
	if not packed is PackedScene:
		push_error("CH3 graphical: scene failed to load")
		quit(1)
		return
	var lab = (packed as PackedScene).instantiate()
	get_root().add_child(lab)
	for frame in range(12):
		await process_frame
	var camera := _find_first(lab, "Camera3D") as Camera3D
	if camera == null or not camera.current:
		failures += 1
		push_error("CH3 graphical: active camera missing")
	var mesh_count := _count_class(lab, "MeshInstance3D")
	if mesh_count < 18:
		failures += 1
		push_error("CH3 graphical: expected at least 18 meshes, got %d" % mesh_count)
	var image := get_root().get_texture().get_image()
	if image == null or image.get_width() < 640 or image.get_height() < 360:
		failures += 1
		push_error("CH3 graphical: viewport image unavailable")
	else:
		image.save_png("/tmp/ch3-character-lab-smoke.png")
	print("CH3 GRAPHICAL PASS: meshes=%d viewport=%dx%d" % [mesh_count, image.get_width() if image != null else 0, image.get_height() if image != null else 0])
	lab.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func _find_first(root: Node, class_name_value: String) -> Node:
	if root.is_class(class_name_value): return root
	for child in root.get_children():
		var found := _find_first(child, class_name_value)
		if found != null: return found
	return null

func _count_class(root: Node, class_name_value: String) -> int:
	var count := 1 if root.is_class(class_name_value) else 0
	for child in root.get_children(): count += _count_class(child, class_name_value)
	return count

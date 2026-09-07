extends SceneTree
const Scene = preload("res://scenes/research/fabric_composition_r3_observatory.tscn")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		print("FABRIC-COMPOSITION-R3-RENDER: FAIL (rendering display and output directory required)")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var lab = Scene.instantiate()
	root.add_child(lab)
	lab.set_process(false)
	lab.toggle_fidelity()
	for i in range(45): lab.single_step()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := args[0]
	var ok := DirAccess.make_dir_recursive_absolute(path) == OK
	ok = ok and root.get_texture().get_image().save_png(path.path_join("before-fracture.png")) == OK
	for i in range(30): lab.single_step()
	await process_frame
	await RenderingServer.frame_post_draw
	ok = ok and root.get_texture().get_image().save_png(path.path_join("after-fracture.png")) == OK
	ok = ok and lab.last_result.success and lab.bridge.inspect().mechanical_revision == 2
	lab.queue_free()
	await process_frame
	print("FABRIC-COMPOSITION-R3-RENDER: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
